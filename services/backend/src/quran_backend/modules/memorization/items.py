"""The memorization list: one active range, a queue and memorized ranges.

The active item is always the plan's range, so the existing plan and session
endpoints keep working. Every list change bumps the plan revision, which is the
offline-sync token for the whole memorization state.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import NotFound, ValidationError

from quran_backend.modules.accounts.models import User
from quran_backend.modules.audio.models import RecitationEdition
from quran_backend.modules.memorization.models import (
    MemorizationItem,
    MemorizationItemStatus,
    MemorizationPlan,
)
from quran_backend.modules.memorization.services import (
    MemorizationPlanRevisionConflictError,
    _device_for_user,
    _full_clean,
    _published_recitation,
    item_snapshot,
    list_snapshot,
    plan_snapshot,
)
from quran_backend.modules.quran.models import Ayah, QuranEdition, Surah

DEFAULT_DAILY_REPETITIONS = 5
DEFAULT_PAUSE_SECONDS = 2

ACTIVE = MemorizationItemStatus.ACTIVE
QUEUED = MemorizationItemStatus.QUEUED
MEMORIZED = MemorizationItemStatus.MEMORIZED


class AddMode:
    QUEUE = "queue"
    NOW = "now"
    EXTEND = "extend"
    CHOICES = (QUEUE, NOW, EXTEND)


class MemorizationItemNotFoundError(NotFound):
    default_detail = "A memorization list item was not found."
    default_code = "memorization_item_not_found"


@dataclass(frozen=True)
class Span:
    """An inclusive ayah range inside one surah."""

    surah: int
    start: int
    end: int

    def overlaps(self, other: Span) -> bool:
        return self.surah == other.surah and self.start <= other.end and other.start <= self.end

    def touches(self, other: Span) -> bool:
        return (
            self.surah == other.surah
            and self.start <= other.end + 1
            and other.start <= self.end + 1
        )

    def contains(self, other: Span) -> bool:
        return self.surah == other.surah and self.start <= other.start and other.end <= self.end


def _span_snapshot(span: Span) -> dict[str, int]:
    return {
        "surah_number": span.surah,
        "start_ayah_number": span.start,
        "end_ayah_number": span.end,
    }


def _span(item: MemorizationItem) -> Span:
    return Span(item.start_ayah.surah.number, item.start_ayah.number, item.end_ayah.number)


def _subtract(pieces: list[Span], taken: list[Span]) -> list[Span]:
    remaining = pieces
    for block in taken:
        next_pieces: list[Span] = []
        for piece in remaining:
            if not piece.overlaps(block):
                next_pieces.append(piece)
                continue
            if piece.start < block.start:
                next_pieces.append(Span(piece.surah, piece.start, block.start - 1))
            if block.end < piece.end:
                next_pieces.append(Span(piece.surah, block.end + 1, piece.end))
        remaining = next_pieces
    return remaining


@dataclass
class _ListState:
    user: User
    plan: MemorizationPlan | None
    items: list[MemorizationItem]
    version_id: uuid.UUID | None

    @property
    def active(self) -> MemorizationItem | None:
        return next((item for item in self.items if item.status == ACTIVE), None)

    @property
    def queued(self) -> list[MemorizationItem]:
        return sorted(
            (item for item in self.items if item.status == QUEUED),
            key=lambda item: (item.position, item.created_at),
        )

    @property
    def revision(self) -> int:
        return self.plan.revision if self.plan is not None else 0


def _items_queryset(user: User) -> Any:
    return MemorizationItem.objects.filter(user=user).select_related(
        "start_ayah__surah", "end_ayah__surah"
    )


def _load_state(user: User, *, lock: bool) -> _ListState:
    plans = MemorizationPlan.objects.filter(user=user).select_related(
        "start_ayah__surah__edition_version__edition",
        "end_ayah__surah__edition_version__edition",
        "recitation__reciter",
        "device",
    )
    items = _items_queryset(user)
    if lock:
        plans = plans.select_for_update(of=("self",))
        items = items.select_for_update(of=("self",))
    plan = plans.first()
    return _ListState(
        user=user,
        plan=plan,
        items=list(items),
        version_id=plan.start_ayah.surah.edition_version_id if plan is not None else None,
    )


def _edition_version_id(edition_code: str) -> uuid.UUID:
    edition = QuranEdition.objects.filter(code=edition_code).first()
    if edition is None or edition.active_version_id is None:
        raise ValidationError({"edition_code": "A published Quran edition was not found."})
    return edition.active_version_id


def _selection_pieces(
    version_id: uuid.UUID,
    *,
    start: tuple[int, int],
    end: tuple[int, int],
) -> list[Span]:
    """Split a Mushaf selection into one span per surah."""
    if start > end:
        raise ValidationError({"ayah_range": "The start ayah must not be after the end ayah."})
    surahs = {
        surah.number: surah.ayah_count
        for surah in Surah.objects.filter(
            edition_version_id=version_id,
            number__gte=start[0],
            number__lte=end[0],
        ).only("number", "ayah_count")
    }
    pieces: list[Span] = []
    for number in range(start[0], end[0] + 1):
        ayah_count = surahs.get(number)
        if ayah_count is None:
            raise ValidationError({"ayah_range": "One or more surahs were not found."})
        first = start[1] if number == start[0] else 1
        last = end[1] if number == end[0] else ayah_count
        if first < 1 or last > ayah_count or first > last:
            raise ValidationError({"ayah_range": "One or more ayahs were not found."})
        pieces.append(Span(number, first, last))
    return pieces


def _ayahs_for(version_id: uuid.UUID, spans: list[Span]) -> dict[tuple[int, int], Ayah]:
    keys = {(span.surah, number) for span in spans for number in (span.start, span.end)}
    ayahs = Ayah.objects.filter(
        surah__edition_version_id=version_id,
        surah__number__in={key[0] for key in keys},
        number__in={key[1] for key in keys},
    ).select_related("surah")
    return {(ayah.surah.number, ayah.number): ayah for ayah in ayahs}


def _set_span(item: MemorizationItem, span: Span, ayahs: dict[tuple[int, int], Ayah]) -> None:
    item.start_ayah = ayahs[(span.surah, span.start)]
    item.end_ayah = ayahs[(span.surah, span.end)]


def _covering_item(state: _ListState, piece: Span) -> MemorizationItem | None:
    point = Span(piece.surah, piece.start, piece.start)
    return next((item for item in state.items if _span(item).contains(point)), None)


def _extend_target(state: _ListState, pieces: list[Span]) -> Span | None:
    """The widened active range when the new ayahs start right after it."""
    active = state.active
    if active is None or not pieces:
        return None
    current = _span(active)
    first = pieces[0]
    if first.surah != current.surah or first.start != current.end + 1:
        return None
    return Span(current.surah, current.start, first.end)


def preview_memorization_selection(
    user: User,
    *,
    edition_code: str,
    start: tuple[int, int],
    end: tuple[int, int],
) -> dict[str, Any]:
    """Tell the Mushaf menu which choice to offer for a selection."""
    state = _load_state(user, lock=False)
    version_id = state.version_id or _edition_version_id(edition_code)
    pieces = _selection_pieces(version_id, start=start, end=end)
    taken = [_span(item) for item in state.items]
    if not _subtract(pieces, taken):
        duplicate = _covering_item(state, pieces[0])
        return {
            "state": "duplicate",
            "revision": state.revision,
            "item": item_snapshot(duplicate) if duplicate else None,
            "extend_to": None,
        }
    if state.active is None and not state.queued:
        return {"state": "empty", "revision": state.revision, "item": None, "extend_to": None}
    fresh = _subtract(pieces, [_span(item) for item in state.items if item.status != QUEUED])
    target = _extend_target(state, fresh)
    return {
        "state": "extendable" if target else "choose",
        "revision": state.revision,
        "item": item_snapshot(state.active) if state.active else None,
        "extend_to": _span_snapshot(target) if target else None,
    }


@transaction.atomic
def add_memorization_selection(  # noqa: PLR0913
    *,
    user: User,
    edition_code: str,
    start: tuple[int, int],
    end: tuple[int, int],
    mode: str,
    source: str,
    base_revision: int,
    client_updated_at: datetime,
    timezone_name: str,
    recitation_id: uuid.UUID | None = None,
    device_id: uuid.UUID | None = None,
) -> dict[str, Any]:
    User.objects.select_for_update().only("id").get(id=user.id)
    state = _load_state(user, lock=True)
    _check_revision(state, base_revision)
    version_id = state.version_id or _edition_version_id(edition_code)
    pieces = _selection_pieces(version_id, start=start, end=end)
    if not _subtract(pieces, [_span(item) for item in state.items]):
        duplicate = _covering_item(state, pieces[0])
        return _mutation_response(state, result="duplicate", item=duplicate, plan=state.plan)
    fresh = _subtract(pieces, [_span(item) for item in state.items if item.status != QUEUED])
    if state.active is None and not state.queued:
        mode = AddMode.NOW
        result = "started"
    else:
        result = {AddMode.QUEUE: "queued", AddMode.NOW: "now", AddMode.EXTEND: "extended"}[mode]
    spans = [*fresh, *(_span(item) for item in state.items)]
    target = _extend_target(state, fresh) if mode == AddMode.EXTEND else None
    if target is not None:
        spans.append(target)
    ayahs = _ayahs_for(version_id, spans)

    if mode == AddMode.EXTEND:
        if target is None:
            raise ValidationError({"mode": "The selection does not continue the current range."})
        active = state.active
        assert active is not None  # _extend_target found it.
        main = _absorb_overlapping_queued(state, active, target, ayahs)
        _queue_pieces(state, fresh[1:], source=source, ayahs=ayahs)
    elif mode == AddMode.NOW:
        previous = state.active
        if previous is not None:
            previous.status = QUEUED
            previous.save(update_fields=["status", "updated_at"])
        main = MemorizationItem(user=user, status=ACTIVE, source=source)
        main = _absorb_overlapping_queued(state, main, fresh[0], ayahs)
        state.items.append(main)
        _queue_pieces(state, fresh[1:], source=source, ayahs=ayahs)
        if previous is not None:
            _move_to_front(state, previous)
    else:
        main, merged = _queue_pieces(state, fresh, source=source, ayahs=ayahs)[0]
        if merged:
            result = "merged"
    plan = _sync_plan(
        state,
        timezone_name=timezone_name,
        recitation_id=recitation_id,
        client_updated_at=client_updated_at,
        device_id=device_id,
    )
    return _mutation_response(state, result=result, item=main, plan=plan)


@transaction.atomic
def update_memorization_item(  # noqa: PLR0913
    *,
    user: User,
    item_id: uuid.UUID,
    status: str,
    base_revision: int,
    client_updated_at: datetime,
    device_id: uuid.UUID | None = None,
) -> dict[str, Any]:
    """Start a queued item now, or mark an item as memorized."""
    User.objects.select_for_update().only("id").get(id=user.id)
    state = _load_state(user, lock=True)
    _check_revision(state, base_revision)
    item = _find_item(state, item_id)
    if status == ACTIVE:
        if item.status != QUEUED:
            raise ValidationError({"status": "Only a queued item can be started."})
        previous = state.active
        if previous is not None:
            previous.status = QUEUED
            previous.save(update_fields=["status", "updated_at"])
        item.status = ACTIVE
        item.save(update_fields=["status", "updated_at"])
        if previous is not None:
            _move_to_front(state, previous)
        else:
            _renumber(state.queued)
        result = "started"
    elif status == MEMORIZED:
        if item.status == MEMORIZED:
            raise ValidationError({"status": "The item is already memorized."})
        item.status = MEMORIZED
        item.memorized_at = timezone.now()
        item.save(update_fields=["status", "memorized_at", "updated_at"])
        _renumber(state.queued)
        result = "memorized"
    else:
        raise ValidationError({"status": "Use active or memorized."})
    plan = _sync_plan(state, client_updated_at=client_updated_at, device_id=device_id)
    return _mutation_response(state, result=result, item=item, plan=plan)


@transaction.atomic
def delete_memorization_item(
    *,
    user: User,
    item_id: uuid.UUID,
    base_revision: int,
) -> dict[str, Any]:
    """Remove a queued or memorized item; the active one is changed, not removed."""
    User.objects.select_for_update().only("id").get(id=user.id)
    state = _load_state(user, lock=True)
    _check_revision(state, base_revision)
    item = _find_item(state, item_id)
    if item.status == ACTIVE:
        raise ValidationError({"item": "The current item cannot be removed."})
    item.delete()
    state.items = [entry for entry in state.items if entry.pk != item_id]
    _renumber(state.queued)
    plan = _sync_plan(state, client_updated_at=timezone.now())
    return _mutation_response(state, result="removed", item=None, plan=plan)


def _check_revision(state: _ListState, base_revision: int) -> None:
    if state.revision != base_revision:
        raise MemorizationPlanRevisionConflictError


def _find_item(state: _ListState, item_id: uuid.UUID) -> MemorizationItem:
    item = next((entry for entry in state.items if entry.pk == item_id), None)
    if item is None:
        raise MemorizationItemNotFoundError
    return item


def _absorb_overlapping_queued(
    state: _ListState,
    item: MemorizationItem,
    span: Span,
    ayahs: dict[tuple[int, int], Ayah],
) -> MemorizationItem:
    """Give ``item`` the span, swallowing queued items that overlap it."""
    merged = span
    for queued in state.queued:
        current = _span(queued)
        if current.overlaps(merged):
            merged = Span(
                merged.surah, min(merged.start, current.start), max(merged.end, current.end)
            )
            queued.delete()
            state.items.remove(queued)
    _set_span(item, merged, ayahs)
    _full_clean(item)
    item.save()
    return item


def _queue_pieces(
    state: _ListState,
    pieces: list[Span],
    *,
    source: str,
    ayahs: dict[tuple[int, int], Ayah],
) -> list[tuple[MemorizationItem, bool]]:
    """Queue each piece, gluing it to overlapping or neighbouring queued ranges."""
    results: list[tuple[MemorizationItem, bool]] = []
    for piece in pieces:
        group = [item for item in state.queued if _span(item).touches(piece)]
        if not group:
            last = max((item.position for item in state.queued), default=-1)
            item = MemorizationItem(
                user=state.user,
                status=QUEUED,
                position=last + 1,
                source=source,
            )
            _set_span(item, piece, ayahs)
            _full_clean(item)
            item.save(force_insert=True)
            state.items.append(item)
            results.append((item, False))
            continue
        keeper = group[0]
        merged = Span(
            piece.surah,
            min([piece.start, *(_span(item).start for item in group)]),
            max([piece.end, *(_span(item).end for item in group)]),
        )
        for extra in group[1:]:
            extra.delete()
            state.items.remove(extra)
        _set_span(keeper, merged, ayahs)
        _full_clean(keeper)
        keeper.save()
        results.append((keeper, True))
    _renumber(state.queued)
    return results


def _move_to_front(state: _ListState, item: MemorizationItem) -> None:
    _renumber([item, *(entry for entry in state.queued if entry.pk != item.pk)])


def _renumber(items: list[MemorizationItem]) -> None:
    changed = []
    for position, item in enumerate(items):
        if item.position != position:
            item.position = position
            changed.append(item)
    if changed:
        MemorizationItem.objects.bulk_update(changed, ["position"])


def _sync_plan(
    state: _ListState,
    *,
    client_updated_at: datetime,
    timezone_name: str | None = None,
    recitation_id: uuid.UUID | None = None,
    device_id: uuid.UUID | None = None,
) -> MemorizationPlan | None:
    """Point the plan at the active item and bump the shared revision."""
    active = state.active
    plan = state.plan
    device = _device_for_user(state.user, device_id)
    if plan is None:
        if active is None:
            return None
        plan = MemorizationPlan(
            user=state.user,
            start_ayah=active.start_ayah,
            end_ayah=active.end_ayah,
            recitation=_covering_recitation(recitation_id, active),
            daily_repetitions=DEFAULT_DAILY_REPETITIONS,
            pause_seconds=DEFAULT_PAUSE_SECONDS,
            timezone_name=timezone_name or state.user.timezone or "UTC",
            client_updated_at=client_updated_at,
            device=device,
        )
        _full_clean(plan)
        plan.save(force_insert=True)
        return plan
    if active is not None and (
        plan.start_ayah_id != active.start_ayah_id or plan.end_ayah_id != active.end_ayah_id
    ):
        plan.start_ayah = active.start_ayah
        plan.end_ayah = active.end_ayah
        plan.recitation = _covering_recitation(plan.recitation_id, active)
    plan.client_updated_at = client_updated_at
    if device is not None:
        plan.device = device
    plan.revision += 1
    _full_clean(plan)
    plan.save()
    return plan


def _covering_recitation(
    recitation_id: uuid.UUID | None,
    item: MemorizationItem,
) -> RecitationEdition | None:
    """Keep a recitation only while it has timings for the whole range."""
    try:
        return _published_recitation(
            recitation_id,
            edition_version_id=item.start_ayah.surah.edition_version_id,
            start_ayah=item.start_ayah,
            end_ayah=item.end_ayah,
        )
    except ValidationError:
        return None


def _mutation_response(
    state: _ListState,
    *,
    result: str,
    item: MemorizationItem | None,
    plan: MemorizationPlan | None,
) -> dict[str, Any]:
    queued = state.queued
    return {
        "result": result,
        "item": item_snapshot(item) if item is not None else None,
        "next": item_snapshot(queued[0]) if queued and state.active is None else None,
        "plan": plan_snapshot(plan) if plan is not None else None,
        **list_snapshot(state.user, plan=plan),
    }
