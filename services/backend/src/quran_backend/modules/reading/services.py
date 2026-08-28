from __future__ import annotations

import hashlib
import json
import uuid
from datetime import datetime
from typing import Any, cast

from django.conf import settings
from django.core import signing
from django.core.exceptions import ImproperlyConfigured
from django.core.serializers.json import DjangoJSONEncoder
from django.db import IntegrityError, transaction
from django.db.models import QuerySet
from django.utils import timezone
from django.views.decorators.debug import sensitive_variables
from rest_framework import status
from rest_framework.exceptions import APIException, NotFound, ValidationError

from quran_backend.modules.accounts.models import Device, User
from quran_backend.modules.quran.models import (
    Ayah,
    MushafPage,
    PublicationStatus,
    QuranEdition,
)
from quran_backend.modules.reading.change_log import append_sync_change, current_sync_cursor
from quran_backend.modules.reading.models import (
    Bookmark,
    ReadingPosition,
    RetiredBookmarkId,
    SyncAction,
    SyncChange,
    SyncEntityType,
    SyncOperation,
    SyncOutcome,
    UserSyncCursor,
)
from quran_backend.modules.reading.policies import bookmark_id_policy
from quran_backend.modules.reminders.sync_adapter import (
    apply_reminder_sync_operation,
    current_reminder_sync_entity,
    full_resync_reminders,
)


class SyncRevisionConflict(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The entity changed after the client's base revision. Pull and retry."
    default_code = "sync_revision_conflict"


class SyncOperationReuse(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "operation_id was already used with a different request."
    default_code = "sync_operation_reuse"


class SyncCursorAheadError(ValidationError):
    default_detail = "The sync cursor is ahead of the server cursor."
    default_code = "sync_cursor_ahead"


class SyncCursorExpiredError(APIException):
    status_code = status.HTTP_410_GONE
    default_detail = "The sync cursor is no longer retained. Start a full resync."
    default_code = "sync_cursor_expired"

    def __init__(self, *, minimum_valid_cursor: int, current_cursor: int) -> None:
        self.minimum_valid_cursor = minimum_valid_cursor
        self.current_cursor = current_cursor
        super().__init__()


class FullResyncTokenInvalidError(ValidationError):
    default_detail = "The full-resync page token is invalid or expired."
    default_code = "full_resync_token_invalid"


class BookmarkCreateConflictError(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "Bookmark id already represents a different bookmark state."
    default_code = "bookmark_create_conflict"


class BookmarkQuotaExceededError(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The per-user bookmark quota has been reached."
    default_code = "bookmark_quota_exceeded"


class BookmarkIdNotReusableError(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "A new bookmark requires a recent UUIDv7 id. Generate a new id and retry."
    default_code = "bookmark_id_not_reusable"


class ReadingPositionNotFoundError(NotFound):
    default_detail = "Reading position was not found."
    default_code = "reading_position_not_found"


class BookmarkNotFoundError(NotFound):
    default_detail = "Bookmark was not found."
    default_code = "bookmark_not_found"


class QuranEditionNotFoundError(NotFound):
    default_detail = "Published Quran edition was not found."
    default_code = "edition_not_found"


_FULL_RESYNC_PHASES = (
    SyncEntityType.READING_POSITION,
    SyncEntityType.BOOKMARK,
    SyncEntityType.REMINDER,
)
_FULL_RESYNC_REGISTRY_VERSION = "v2:reading_position:bookmark:reminder"
_FULL_RESYNC_SIGNING_CONTEXT = "quran-platform.offline-sync.full-resync.v2"


def reading_position_snapshot(position: ReadingPosition) -> dict[str, Any]:
    ayah: dict[str, Any] | None = None
    position_ayah = position.ayah
    if position_ayah is not None:
        ayah = {
            "id": str(position_ayah.id),
            "surah_number": position_ayah.surah.number,
            "ayah_number": position_ayah.number,
        }
    return {
        "id": str(position.id),
        "entity_type": SyncEntityType.READING_POSITION,
        "edition_code": position.edition.code,
        "page_number": position.page.number,
        "ayah": ayah,
        "intra_page_anchor": position.intra_page_anchor,
        "progress_percent": str(position.progress_percent),
        "last_read_at": position.last_read_at.isoformat(),
        "client_updated_at": position.client_updated_at.isoformat(),
        "revision": position.revision,
        "device_id": str(position.device_id) if position.device_id else None,
        "created_at": position.created_at.isoformat(),
        "updated_at": position.updated_at.isoformat(),
    }


def bookmark_snapshot(bookmark: Bookmark) -> dict[str, Any]:
    ayah: dict[str, Any] | None = None
    bookmark_ayah = bookmark.ayah
    if bookmark_ayah is not None:
        ayah = {
            "id": str(bookmark_ayah.id),
            "surah_number": bookmark_ayah.surah.number,
            "ayah_number": bookmark_ayah.number,
            "surah_name_ar": bookmark_ayah.surah.name_ar,
            "surah_name_en": bookmark_ayah.surah.name_en,
            "surah_name_ru": bookmark_ayah.surah.name_ru,
        }
    bookmark_page = bookmark.page
    return {
        "id": str(bookmark.id),
        "entity_type": SyncEntityType.BOOKMARK,
        "edition_code": bookmark.edition.code,
        "page_number": bookmark_page.number if bookmark_page is not None else None,
        "ayah": ayah,
        "label": bookmark.label,
        "color_key": bookmark.color_key,
        "note": bookmark.note,
        "client_updated_at": bookmark.client_updated_at.isoformat(),
        "revision": bookmark.revision,
        "deleted_at": bookmark.deleted_at.isoformat() if bookmark.deleted_at else None,
        "device_id": str(bookmark.device_id) if bookmark.device_id else None,
        "created_at": bookmark.created_at.isoformat(),
        "updated_at": bookmark.updated_at.isoformat(),
    }


def get_reading_position(user: User, edition_code: str) -> ReadingPosition:
    try:
        return _position_queryset().get(user=user, edition__code=edition_code)
    except ReadingPosition.DoesNotExist as exc:
        raise ReadingPositionNotFoundError from exc


def list_bookmarks(user: User, *, include_deleted: bool = False) -> QuerySet[Bookmark]:
    queryset = _bookmark_queryset().filter(user=user)
    if not include_deleted:
        queryset = queryset.filter(deleted_at__isnull=True)
    return queryset


def get_bookmark(user: User, bookmark_id: uuid.UUID) -> Bookmark:
    try:
        return _bookmark_queryset().get(user=user, id=bookmark_id)
    except Bookmark.DoesNotExist as exc:
        raise BookmarkNotFoundError from exc


@transaction.atomic
def upsert_reading_position_direct(
    user: User,
    data: dict[str, Any],
) -> dict[str, Any]:
    User.objects.select_for_update().only("id").get(id=user.id)
    edition = _active_edition(data["edition_code"])
    current = ReadingPosition.objects.select_for_update().filter(user=user, edition=edition).first()
    entity_id = current.id if current else uuid.uuid7()
    result = _mutate_reading_position(
        user=user,
        entity_id=entity_id,
        base_revision=data["base_revision"],
        client_updated_at=data["client_updated_at"],
        device_id=data.get("device_id"),
        payload=data,
        locked_position=current,
    )
    _raise_direct_conflict(result)
    return cast(dict[str, Any], result["entity"])


@transaction.atomic
def create_bookmark_direct(user: User, data: dict[str, Any]) -> tuple[dict[str, Any], bool]:
    User.objects.select_for_update().only("id").get(id=user.id)
    entity_id = cast(uuid.UUID, data["id"])
    existing = _bookmark_queryset(for_update=True).filter(id=entity_id).first()
    if existing is not None:
        if existing.user_id != user.id or not _matches_bookmark_create(existing, data):
            raise BookmarkCreateConflictError
        return bookmark_snapshot(existing), False
    if not _new_bookmark_id_is_acceptable(entity_id, now=timezone.now()):
        raise BookmarkIdNotReusableError
    if RetiredBookmarkId.objects.filter(user=user, bookmark_id=entity_id).exists():
        raise BookmarkIdNotReusableError
    if Bookmark.objects.filter(user=user).count() >= _positive_setting(
        "QURAN_BOOKMARK_MAX_PER_USER",
        5_000,
    ):
        raise BookmarkQuotaExceededError

    result = _mutate_bookmark(
        user=user,
        entity_id=entity_id,
        action=SyncAction.UPSERT,
        base_revision=0,
        client_updated_at=data["client_updated_at"],
        device_id=data.get("device_id"),
        payload=data,
    )
    _raise_direct_conflict(result)
    return cast(dict[str, Any], result["entity"]), True


@transaction.atomic
def update_bookmark_direct(
    user: User,
    bookmark_id: uuid.UUID,
    data: dict[str, Any],
) -> dict[str, Any]:
    User.objects.select_for_update().only("id").get(id=user.id)
    result = _mutate_bookmark(
        user=user,
        entity_id=bookmark_id,
        action=SyncAction.UPSERT,
        base_revision=data["base_revision"],
        client_updated_at=data["client_updated_at"],
        device_id=data.get("device_id"),
        payload=data,
    )
    _raise_direct_conflict(result)
    return cast(dict[str, Any], result["entity"])


@transaction.atomic
def delete_bookmark_direct(
    user: User,
    bookmark_id: uuid.UUID,
    data: dict[str, Any],
) -> dict[str, Any]:
    User.objects.select_for_update().only("id").get(id=user.id)
    if not Bookmark.objects.filter(user=user, id=bookmark_id).exists():
        raise BookmarkNotFoundError
    result = _mutate_bookmark(
        user=user,
        entity_id=bookmark_id,
        action=SyncAction.DELETE,
        base_revision=data["base_revision"],
        client_updated_at=data["client_updated_at"],
        device_id=data.get("device_id"),
        payload={},
    )
    _raise_direct_conflict(result)
    return cast(dict[str, Any], result["entity"])


@sensitive_variables("operations")
@transaction.atomic
def apply_sync_batch(
    user: User,
    operations: list[dict[str, Any]],
    *,
    authenticated_device: Device | None = None,
) -> dict[str, Any]:
    """Apply a batch atomically while preserving stored per-operation conflict results."""

    results = [
        _apply_sync_operation(
            user,
            operation,
            authenticated_device=authenticated_device,
        )
        for operation in operations
    ]
    return {"results": results, "cursor": current_sync_cursor(user)}


@sensitive_variables("operation")
@transaction.atomic
def _apply_sync_operation(
    user: User,
    operation: dict[str, Any],
    *,
    authenticated_device: Device | None,
) -> dict[str, Any]:
    # Serialize a user's operation log so concurrent retries cannot apply twice
    # before the operation_id uniqueness constraint is observed.
    User.objects.select_for_update().only("id").get(id=user.id)
    entity_type = operation["entity_type"]
    request_hash = _operation_hash(
        operation,
        bound_device_id=(
            authenticated_device.id
            if entity_type == SyncEntityType.REMINDER and authenticated_device
            else None
        ),
    )
    existing = (
        SyncOperation.objects.select_for_update()
        .filter(user=user, operation_id=operation["operation_id"])
        .first()
    )
    if existing:
        if existing.request_hash != request_hash:
            raise SyncOperationReuse()
        replayed_response = dict(existing.response)
        if existing.entity_type == SyncEntityType.REMINDER:
            entity_was_present = bool(replayed_response.pop("_entity_was_present", False))
            replayed_response["entity"] = (
                current_reminder_sync_entity(user, existing.entity_id)
                if entity_was_present
                else None
            )
        replayed_response["replayed"] = True
        return replayed_response

    if entity_type == SyncEntityType.READING_POSITION:
        mutation = _mutate_reading_position(
            user=user,
            entity_id=operation["entity_id"],
            base_revision=operation["base_revision"],
            client_updated_at=operation["client_updated_at"],
            device_id=operation.get("device_id"),
            payload=operation["payload"],
        )
    elif entity_type == SyncEntityType.BOOKMARK:
        mutation = _mutate_bookmark(
            user=user,
            entity_id=operation["entity_id"],
            action=operation["action"],
            base_revision=operation["base_revision"],
            client_updated_at=operation["client_updated_at"],
            device_id=operation.get("device_id"),
            payload=operation["payload"],
        )
    elif entity_type == SyncEntityType.REMINDER:
        mutation = apply_reminder_sync_operation(
            user=user,
            device=authenticated_device,
            operation=operation,
        )
    else:  # pragma: no cover - serializer and model choices are fail-closed.
        raise RuntimeError(f"Unsupported sync entity type: {entity_type}")

    response = {
        "operation_id": str(operation["operation_id"]),
        "outcome": mutation["outcome"],
        "replayed": False,
        "entity": mutation.get("entity"),
        "cursor": mutation["cursor"],
    }
    if mutation.get("conflict_reason"):
        response["conflict_reason"] = mutation["conflict_reason"]

    stored_response = response
    if entity_type == SyncEntityType.REMINDER:
        # Reminder operation replay is hydrated from the current domain row.
        # Avoid duplicating schedule, timezone, ayah range, and device data in
        # the long-lived operation ledger.
        stored_response = {
            **response,
            "entity": None,
            "_entity_was_present": response.get("entity") is not None,
        }
    SyncOperation.objects.create(
        user=user,
        operation_id=operation["operation_id"],
        entity_type=entity_type,
        entity_id=operation["entity_id"],
        action=operation["action"],
        request_hash=request_hash,
        outcome=mutation["outcome"],
        response=stored_response,
    )
    return response


@transaction.atomic
def pull_changes(user: User, *, cursor: int, limit: int) -> dict[str, Any]:
    cursor_state = UserSyncCursor.objects.select_for_update().filter(user=user).first()
    server_cursor = cursor_state.value if cursor_state else 0
    minimum_valid_cursor = cursor_state.minimum_valid_cursor if cursor_state else 0
    if cursor < minimum_valid_cursor:
        raise SyncCursorExpiredError(
            minimum_valid_cursor=minimum_valid_cursor,
            current_cursor=server_cursor,
        )
    if cursor > server_cursor:
        raise SyncCursorAheadError()
    changes = list(
        SyncChange.objects.filter(user=user, sequence__gt=cursor).order_by("sequence")[: limit + 1]
    )
    has_more = len(changes) > limit
    changes = changes[:limit]
    next_cursor = changes[-1].sequence if changes else server_cursor
    return {
        "mode": "incremental",
        "changes": [
            {
                "cursor": change.sequence,
                "entity_type": change.entity_type,
                "entity_id": str(change.entity_id),
                "action": change.action,
                "revision": change.revision,
                "entity": change.snapshot,
                "server_updated_at": change.updated_at.isoformat(),
            }
            for change in changes
        ],
        "next_cursor": next_cursor,
        "has_more": has_more,
    }


@transaction.atomic
def full_resync_page(
    user: User,
    *,
    limit: int,
    page_token: str | None,
) -> dict[str, Any]:
    cursor_state = UserSyncCursor.objects.select_for_update().filter(user=user).first()
    current_cursor = cursor_state.value if cursor_state else 0
    minimum_valid_cursor = cursor_state.minimum_valid_cursor if cursor_state else 0

    if page_token:
        token = _decode_full_resync_token(page_token, user)
        snapshot_cursor = token["snapshot_cursor"]
        phase = token["phase"]
        after = token["after"]
        if snapshot_cursor < minimum_valid_cursor:
            raise SyncCursorExpiredError(
                minimum_valid_cursor=minimum_valid_cursor,
                current_cursor=current_cursor,
            )
    else:
        snapshot_cursor = current_cursor
        phase = SyncEntityType.READING_POSITION
        after = None

    entities: list[dict[str, Any]] = []
    next_phase: str | None = None
    next_after: uuid.UUID | None = None

    phase_index = _FULL_RESYNC_PHASES.index(phase)
    current_after = after
    while phase_index < len(_FULL_RESYNC_PHASES) and len(entities) < limit:
        current_phase = _FULL_RESYNC_PHASES[phase_index]
        remaining = limit - len(entities)
        page = _full_resync_entities(
            current_phase,
            user=user,
            after=current_after,
            limit=remaining + 1,
        )
        if len(page) > remaining:
            page = page[:remaining]
            entities.extend(page)
            next_phase = current_phase
            next_after = uuid.UUID(page[-1]["id"])
            break
        entities.extend(page)
        phase_index += 1
        current_after = None

    # If a phase ended exactly at the response limit, find the next non-empty
    # phase so has_more never advertises a guaranteed empty page.
    if next_phase is None and len(entities) == limit:
        while phase_index < len(_FULL_RESYNC_PHASES):
            candidate_phase = _FULL_RESYNC_PHASES[phase_index]
            if _full_resync_entities(
                candidate_phase,
                user=user,
                after=None,
                limit=1,
            ):
                next_phase = candidate_phase
                break
            phase_index += 1

    next_page_token = None
    if next_phase:
        next_page_token = _encode_full_resync_token(
            user=user,
            snapshot_cursor=snapshot_cursor,
            phase=next_phase,
            after=next_after,
        )
    return {
        "mode": "full_resync",
        "entities": entities,
        "snapshot_cursor": snapshot_cursor,
        "next_page_token": next_page_token,
        "has_more": next_page_token is not None,
    }


def _matches_bookmark_create(
    existing: Bookmark,
    data: dict[str, Any],
) -> bool:
    page = existing.page
    ayah = existing.ayah
    return (
        existing.revision == 1
        and existing.deleted_at is None
        and existing.edition.code == data["edition_code"]
        and (page.number if page else None) == data.get("page_number")
        and (ayah.surah.number if ayah else None) == data.get("surah_number")
        and (ayah.number if ayah else None) == data.get("ayah_number")
        and existing.label == data.get("label", "")
        and existing.color_key == data.get("color_key", "default")
        and existing.note == data.get("note", "")
        and existing.client_updated_at == data["client_updated_at"]
        and existing.device_id == data.get("device_id")
    )


def _full_resync_positions(
    user: User,
    *,
    after: uuid.UUID | None,
    limit: int,
) -> list[ReadingPosition]:
    queryset = _position_queryset().filter(user=user).order_by("id")
    if after:
        queryset = queryset.filter(id__gt=after)
    return list(queryset[:limit])


def _full_resync_bookmarks(
    user: User,
    *,
    after: uuid.UUID | None,
    limit: int,
) -> list[Bookmark]:
    queryset = _bookmark_queryset().filter(user=user).order_by("id")
    if after:
        queryset = queryset.filter(id__gt=after)
    return list(queryset[:limit])


def _full_resync_entities(
    phase: str,
    *,
    user: User,
    after: uuid.UUID | None,
    limit: int,
) -> list[dict[str, Any]]:
    if phase == SyncEntityType.READING_POSITION:
        return [
            reading_position_snapshot(position)
            for position in _full_resync_positions(user, after=after, limit=limit)
        ]
    if phase == SyncEntityType.BOOKMARK:
        return [
            bookmark_snapshot(bookmark)
            for bookmark in _full_resync_bookmarks(user, after=after, limit=limit)
        ]
    if phase == SyncEntityType.REMINDER:
        return full_resync_reminders(user, after=after, limit=limit)
    raise RuntimeError(f"Unsupported full-resync phase: {phase}")


def _encode_full_resync_token(
    *,
    user: User,
    snapshot_cursor: int,
    phase: str,
    after: uuid.UUID | None,
) -> str:
    return signing.dumps(
        {
            "user_id": str(user.id),
            "snapshot_cursor": snapshot_cursor,
            "registry_version": _FULL_RESYNC_REGISTRY_VERSION,
            "phase": phase,
            "after": str(after) if after else None,
        },
        salt=_FULL_RESYNC_SIGNING_CONTEXT,
        compress=True,
    )


def _decode_full_resync_token(token: str, user: User) -> dict[str, Any]:
    try:
        payload = signing.loads(
            token,
            salt=_FULL_RESYNC_SIGNING_CONTEXT,
            max_age=_positive_setting(
                "QURAN_SYNC_FULL_RESYNC_TOKEN_MAX_AGE_SECONDS",
                24 * 60 * 60,
            ),
        )
        if not isinstance(payload, dict) or payload.get("user_id") != str(user.id):
            raise FullResyncTokenInvalidError
        if payload.get("registry_version") != _FULL_RESYNC_REGISTRY_VERSION:
            raise FullResyncTokenInvalidError
        phase = payload.get("phase")
        if phase not in _FULL_RESYNC_PHASES:
            raise FullResyncTokenInvalidError
        after_value = payload.get("after")
        after = uuid.UUID(after_value) if after_value else None
        snapshot_cursor = int(payload["snapshot_cursor"])
        if snapshot_cursor < 0:
            raise ValueError
    except (signing.BadSignature, KeyError, TypeError, ValueError) as exc:
        raise FullResyncTokenInvalidError from exc
    return {"snapshot_cursor": snapshot_cursor, "phase": phase, "after": after}


def _positive_setting(name: str, default: int) -> int:
    try:
        value = int(getattr(settings, name, default))
    except (TypeError, ValueError) as exc:
        raise ImproperlyConfigured(f"{name} must be a positive integer.") from exc
    if value <= 0:
        raise ImproperlyConfigured(f"{name} must be a positive integer.")
    return value


def _mutate_reading_position(  # noqa: PLR0913
    *,
    user: User,
    entity_id: uuid.UUID,
    base_revision: int,
    client_updated_at: Any,
    device_id: uuid.UUID | None,
    payload: dict[str, Any],
    locked_position: ReadingPosition | None = None,
) -> dict[str, Any]:
    edition = _active_edition(payload["edition_code"])
    page = _page_for_active_edition(edition, payload["page_number"])
    ayah = _ayah_for_active_edition(
        edition,
        payload.get("surah_number"),
        payload.get("ayah_number"),
    )
    _validate_page_ayah(page, ayah)
    device = _device_for_user(user, device_id)
    position = locked_position
    if position is None:
        position = _position_queryset(for_update=True).filter(user=user, edition=edition).first()

    if position is None:
        if base_revision != 0:
            return _conflict(user, "entity_missing", None)
        if ReadingPosition.objects.filter(id=entity_id).exists():
            return _conflict(user, "entity_id_unavailable", None)
        try:
            with transaction.atomic():
                position = ReadingPosition.objects.create(
                    id=entity_id,
                    user=user,
                    edition=edition,
                    page=page,
                    ayah=ayah,
                    intra_page_anchor=payload.get("intra_page_anchor", {}),
                    progress_percent=payload.get("progress_percent", 0),
                    last_read_at=payload["last_read_at"],
                    client_updated_at=client_updated_at,
                    revision=1,
                    device=device,
                )
        except IntegrityError:
            return _conflict(user, "entity_id_unavailable", None)
    else:
        if position.id != entity_id:
            return _conflict(user, "entity_identity_mismatch", reading_position_snapshot(position))
        if position.revision != base_revision:
            return _conflict(user, "revision_mismatch", reading_position_snapshot(position))
        position.page = page
        position.ayah = ayah
        position.intra_page_anchor = payload.get("intra_page_anchor", {})
        position.progress_percent = payload.get("progress_percent", 0)
        position.last_read_at = payload["last_read_at"]
        position.client_updated_at = client_updated_at
        position.device = device
        position.revision += 1
        position.save(
            update_fields=[
                "page",
                "ayah",
                "intra_page_anchor",
                "progress_percent",
                "last_read_at",
                "client_updated_at",
                "device",
                "revision",
                "updated_at",
            ]
        )

    snapshot = reading_position_snapshot(position)
    cursor = append_sync_change(
        user=user,
        entity_type=SyncEntityType.READING_POSITION,
        entity_id=position.id,
        action=SyncAction.UPSERT,
        revision=position.revision,
        snapshot=snapshot,
    )
    return {"outcome": SyncOutcome.ACCEPTED, "entity": snapshot, "cursor": cursor}


def _mutate_bookmark(  # noqa: PLR0911, PLR0912, PLR0913
    *,
    user: User,
    entity_id: uuid.UUID,
    action: str,
    base_revision: int,
    client_updated_at: Any,
    device_id: uuid.UUID | None,
    payload: dict[str, Any],
) -> dict[str, Any]:
    bookmark = _bookmark_queryset(for_update=True).filter(user=user, id=entity_id).first()
    device = _device_for_user(user, device_id)

    if action == SyncAction.DELETE:
        if bookmark is None:
            return _conflict(user, "entity_missing", None)
        if bookmark.revision != base_revision:
            return _conflict(user, "revision_mismatch", bookmark_snapshot(bookmark))
        bookmark.deleted_at = timezone.now()
        bookmark.client_updated_at = client_updated_at
        bookmark.device = device
        bookmark.revision += 1
        bookmark.save(
            update_fields=[
                "deleted_at",
                "client_updated_at",
                "device",
                "revision",
                "updated_at",
            ]
        )
        snapshot = bookmark_snapshot(bookmark)
        cursor = append_sync_change(
            user=user,
            entity_type=SyncEntityType.BOOKMARK,
            entity_id=bookmark.id,
            action=SyncAction.DELETE,
            revision=bookmark.revision,
            snapshot=snapshot,
        )
        return {"outcome": SyncOutcome.ACCEPTED, "entity": snapshot, "cursor": cursor}

    if bookmark is None:
        if base_revision != 0:
            return _conflict(user, "entity_missing", None)
        if Bookmark.objects.filter(id=entity_id).exists():
            return _conflict(user, "entity_id_unavailable", None)
        if RetiredBookmarkId.objects.filter(user=user, bookmark_id=entity_id).exists():
            return _conflict(user, "entity_id_not_reusable", None)
        if not _new_bookmark_id_is_acceptable(entity_id, now=timezone.now()):
            return _conflict(user, "entity_id_not_reusable", None)
        if Bookmark.objects.filter(user=user).count() >= _positive_setting(
            "QURAN_BOOKMARK_MAX_PER_USER",
            5_000,
        ):
            return _conflict(user, "bookmark_quota_exceeded", None)
        edition = _active_edition(payload["edition_code"])
        page, ayah = _bookmark_target(edition, payload, None)
        try:
            with transaction.atomic():
                bookmark = Bookmark.objects.create(
                    id=entity_id,
                    user=user,
                    edition=edition,
                    page=page,
                    ayah=ayah,
                    label=payload.get("label", ""),
                    color_key=payload.get("color_key", "default"),
                    note=payload.get("note", ""),
                    client_updated_at=client_updated_at,
                    revision=1,
                    device=device,
                )
        except IntegrityError:
            return _conflict(user, "entity_id_unavailable", None)
    else:
        if bookmark.revision != base_revision:
            return _conflict(user, "revision_mismatch", bookmark_snapshot(bookmark))
        if payload.get("edition_code", bookmark.edition.code) != bookmark.edition.code:
            raise ValidationError({"edition_code": "A bookmark's edition cannot be changed."})
        page, ayah = _bookmark_target(bookmark.edition, payload, bookmark)
        bookmark.page = page
        bookmark.ayah = ayah
        for field in ("label", "color_key", "note"):
            if field in payload:
                setattr(bookmark, field, payload[field])
        bookmark.client_updated_at = client_updated_at
        bookmark.device = device
        bookmark.deleted_at = None
        bookmark.revision += 1
        bookmark.save(
            update_fields=[
                "page",
                "ayah",
                "label",
                "color_key",
                "note",
                "client_updated_at",
                "device",
                "deleted_at",
                "revision",
                "updated_at",
            ]
        )

    snapshot = bookmark_snapshot(bookmark)
    cursor = append_sync_change(
        user=user,
        entity_type=SyncEntityType.BOOKMARK,
        entity_id=bookmark.id,
        action=SyncAction.UPSERT,
        revision=bookmark.revision,
        snapshot=snapshot,
    )
    return {"outcome": SyncOutcome.ACCEPTED, "entity": snapshot, "cursor": cursor}


def _bookmark_target(
    edition: QuranEdition,
    payload: dict[str, Any],
    bookmark: Bookmark | None,
) -> tuple[MushafPage | None, Ayah | None]:
    if "page_number" in payload:
        page_number = payload["page_number"]
        page = _page_for_active_edition(edition, page_number) if page_number is not None else None
    else:
        page = bookmark.page if bookmark else None

    if "surah_number" in payload or "ayah_number" in payload:
        ayah = _ayah_for_active_edition(
            edition,
            payload.get("surah_number"),
            payload.get("ayah_number"),
        )
    else:
        ayah = bookmark.ayah if bookmark else None

    if page is None and ayah is None:
        raise ValidationError("A bookmark must reference a page or ayah.")
    _validate_page_ayah(page, ayah)
    return page, ayah


def _active_edition(code: str) -> QuranEdition:
    try:
        return QuranEdition.objects.select_related("active_version").get(
            code=code,
            active_version__status=PublicationStatus.PUBLISHED,
        )
    except QuranEdition.DoesNotExist as exc:
        raise QuranEditionNotFoundError from exc


def _page_for_active_edition(edition: QuranEdition, number: int) -> MushafPage:
    try:
        return MushafPage.objects.select_related("edition_version__edition").get(
            edition_version=edition.active_version,
            number=number,
        )
    except MushafPage.DoesNotExist as exc:
        raise ValidationError(
            {"page_number": "Page does not exist in the active edition."}
        ) from exc


def _ayah_for_active_edition(
    edition: QuranEdition,
    surah_number: int | None,
    ayah_number: int | None,
) -> Ayah | None:
    if surah_number is None and ayah_number is None:
        return None
    if surah_number is None or ayah_number is None:
        raise ValidationError("surah_number and ayah_number must be provided together.")
    try:
        return Ayah.objects.select_related("surah__edition_version__edition").get(
            surah__edition_version=edition.active_version,
            surah__number=surah_number,
            number=ayah_number,
        )
    except Ayah.DoesNotExist as exc:
        raise ValidationError(
            {"ayah_number": "Ayah does not exist in the active edition."}
        ) from exc


def _validate_page_ayah(page: MushafPage | None, ayah: Ayah | None) -> None:
    if page and ayah and not ayah.page_regions.filter(page=page).exists():
        raise ValidationError("The selected ayah is not located on the selected page.")


def _device_for_user(user: User, device_id: uuid.UUID | None) -> Device | None:
    if device_id is None:
        return None
    try:
        return Device.objects.get(id=device_id, user=user, revoked_at__isnull=True)
    except Device.DoesNotExist as exc:
        raise ValidationError({"device_id": "Active device was not found for this user."}) from exc


def _position_queryset(*, for_update: bool = False) -> QuerySet[ReadingPosition]:
    queryset = ReadingPosition.objects.select_related(
        "edition",
        "page__edition_version__edition",
        "ayah__surah__edition_version__edition",
        "device",
    )
    # Nullable page/ayah/device relations are loaded with LEFT OUTER JOINs.
    # PostgreSQL rejects a blanket FOR UPDATE in that shape, so lock only the
    # reading_position row that owns the mutable state.
    return queryset.select_for_update(of=("self",)) if for_update else queryset


def _bookmark_queryset(*, for_update: bool = False) -> QuerySet[Bookmark]:
    queryset = Bookmark.objects.select_related(
        "edition",
        "page__edition_version__edition",
        "ayah__surah__edition_version__edition",
        "device",
    )
    return queryset.select_for_update(of=("self",)) if for_update else queryset


def _conflict(
    user: User,
    reason: str,
    entity: dict[str, Any] | None,
) -> dict[str, Any]:
    return {
        "outcome": SyncOutcome.CONFLICT,
        "conflict_reason": reason,
        "entity": entity,
        "cursor": current_sync_cursor(user),
    }


def _raise_direct_conflict(result: dict[str, Any]) -> None:
    if result["outcome"] == SyncOutcome.CONFLICT:
        raise SyncRevisionConflict(f"Sync conflict: {result['conflict_reason']}.")


def _new_bookmark_id_is_acceptable(entity_id: uuid.UUID, *, now: datetime) -> bool:
    """Reject unseen stale IDs so a physically pruned tombstone cannot be resurrected."""

    if entity_id.version != 7:
        return False
    policy = bookmark_id_policy()
    if not policy.is_safe:
        return False
    now_milliseconds = int(now.timestamp() * 1_000)
    max_age_milliseconds = policy.new_id_max_age_days * 86_400_000
    future_skew_milliseconds = policy.future_skew_seconds * 1_000
    return (
        now_milliseconds - max_age_milliseconds
        <= entity_id.time
        <= now_milliseconds + future_skew_milliseconds
    )


def _operation_hash(
    operation: dict[str, Any],
    *,
    bound_device_id: uuid.UUID | None = None,
) -> str:
    try:
        canonical_operation = dict(operation)
        if operation.get("entity_type") == SyncEntityType.REMINDER:
            canonical_operation["_bound_device_id"] = bound_device_id
        serialized = json.dumps(
            canonical_operation,
            cls=DjangoJSONEncoder,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode()
    except (TypeError, ValueError) as exc:
        raise ValidationError("Sync operation is not JSON serializable.") from exc
    return hashlib.sha256(serialized).hexdigest()
