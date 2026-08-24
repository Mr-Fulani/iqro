from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import timedelta
from typing import Any

from django.conf import settings
from django.db import transaction
from django.db.models import Count, Q
from django.utils import timezone
from django.utils.text import slugify

from quran_backend.modules.audio.models import (
    QuranFoundationSyncState,
    RecitationEdition,
    RecitationPublicationStatus,
)
from quran_backend.modules.audio.quran_foundation import (
    QuranFoundationClient,
    QuranFoundationError,
    QuranFoundationSyncResult,
)
from quran_backend.modules.audio.quran_foundation_importer import (
    import_quran_foundation_recitation,
    prepare_quran_foundation_recitation,
)
from quran_backend.modules.core.content_revalidation import enqueue_audio_content_change

SOURCE_ID_PATTERN = re.compile(r"^qf-(?P<source_id>[1-9][0-9]*)-")


@dataclass(frozen=True, slots=True)
class QuranFoundationRefreshResult:
    checked: int
    changed: int
    withdrawn: int
    skipped_fresh: int
    failures: int


@dataclass(frozen=True, slots=True)
class _RefreshContext:
    client: QuranFoundationClient
    ayah_catalog: list[dict[str, Any]]
    current_time: Any
    environment: str


def refresh_quran_foundation_audio(
    *,
    client: QuranFoundationClient | None = None,
    force: bool = False,
    now: Any | None = None,
) -> QuranFoundationRefreshResult:
    """Keep transformed QF audio metadata fresh without mutating published versions."""

    sync_client = client or QuranFoundationClient.from_environment()
    current_time = now or timezone.now()
    environment = sync_client.environment.name
    refresh_days = int(settings.QURAN_QF_AUDIO_REFRESH_DAYS)
    freshness_cutoff = current_time - timedelta(days=refresh_days)

    recitations = latest_complete_qf_recitations(environment)
    due: list[tuple[int, RecitationEdition, QuranFoundationSyncState]] = []
    skipped_fresh = 0
    for source_id, recitation in recitations:
        state, _ = QuranFoundationSyncState.objects.get_or_create(
            environment=environment,
            source_reciter_id=source_id,
        )
        if force or state.last_success_at is None or state.last_success_at <= freshness_cutoff:
            due.append((source_id, recitation, state))
        else:
            skipped_fresh += 1

    if not due:
        return QuranFoundationRefreshResult(0, 0, 0, skipped_fresh, 0)

    ayah_catalog = sync_client.list_ayah_recitations(language="en")
    context = _RefreshContext(sync_client, ayah_catalog, current_time, environment)
    checked = 0
    changed = 0
    withdrawn = 0
    failures = 0
    for source_id, recitation, state in due:
        state.last_attempt_at = current_time
        state.save(update_fields=["last_attempt_at", "updated_at"])
        try:
            recitation_changed, recitation_withdrawn = _refresh_one(
                context,
                source_id=source_id,
                recitation=recitation,
                state=state,
            )
            checked += 1
            changed += int(recitation_changed)
            withdrawn += int(recitation_withdrawn)
        except QuranFoundationError:
            failures += 1
            state.consecutive_failures += 1
            state.last_error_code = "quran_foundation_error"
            state.save(update_fields=["consecutive_failures", "last_error_code", "updated_at"])

    if failures:
        raise QuranFoundationError(
            f"Quran.Foundation refresh failed for {failures} chapter reciter(s)."
        )
    return QuranFoundationRefreshResult(
        checked=checked,
        changed=changed,
        withdrawn=withdrawn,
        skipped_fresh=skipped_fresh,
        failures=0,
    )


def _refresh_one(
    context: _RefreshContext,
    *,
    source_id: int,
    recitation: RecitationEdition,
    state: QuranFoundationSyncState,
) -> tuple[bool, bool]:
    resource_id = _matching_content_sync_resource(recitation, context.ayah_catalog)
    if state.content_sync_resource_id != resource_id:
        state.content_sync_resource_id = resource_id
        state.sync_token = ""
        state.last_sync_sequence = None

    should_refresh = resource_id is None
    resource_deleted = False
    if resource_id is not None:
        try:
            sync_result = _sync_resource(
                context.client,
                resource_id=resource_id,
                sync_token=state.sync_token,
            )
        except QuranFoundationError as exc:
            if "HTTP 403" not in str(exc) and "HTTP 404" not in str(exc):
                raise
            # Content Sync can require a permission separate from Content API access.
            # A complete chapter-catalog comparison remains a compliant safe fallback.
            state.content_sync_resource_id = None
            state.sync_token = ""
            state.last_sync_sequence = None
            should_refresh = True
        else:
            state.sync_token = sync_result.next_sync_token
            state.last_sync_sequence = sync_result.sync_until_sequence
            should_refresh = bool(sync_result.mutations)
            resource_deleted = any(
                mutation["type"] == "RESOURCE_DELETE" for mutation in sync_result.mutations
            )

    recitation_changed = False
    recitation_withdrawn = False
    if resource_deleted:
        recitation_withdrawn = _withdraw_recitation(recitation)
    elif should_refresh:
        recitation_changed = _refresh_recitation_version(
            context.client,
            source_id=source_id,
            recitation=recitation,
            current_time=context.current_time,
            environment=context.environment,
        )

    state.last_success_at = context.current_time
    if should_refresh or resource_deleted:
        state.last_change_at = context.current_time
    state.consecutive_failures = 0
    state.last_error_code = ""
    state.save(
        update_fields=[
            "content_sync_resource_id",
            "sync_token",
            "last_sync_sequence",
            "last_success_at",
            "last_change_at",
            "consecutive_failures",
            "last_error_code",
            "updated_at",
        ]
    )
    return recitation_changed, recitation_withdrawn


def _sync_resource(
    client: QuranFoundationClient,
    *,
    resource_id: int,
    sync_token: str,
) -> QuranFoundationSyncResult:
    try:
        return client.sync_recitation_content(resource_id, sync_token=sync_token)
    except QuranFoundationError as exc:
        if not sync_token or "HTTP 410" not in str(exc):
            raise
        # QF expires stale checkpoints; bootstrap a fresh checkpoint once.
        return client.sync_recitation_content(resource_id, sync_token="")


def latest_complete_qf_recitations(environment: str) -> list[tuple[int, RecitationEdition]]:
    queryset = (
        RecitationEdition.objects.filter(
            source_name="Quran.Foundation Content API",
            source_version=f"content-api-v4-{environment}",
            status=RecitationPublicationStatus.PUBLISHED,
        )
        .annotate(
            complete_surahs=Count(
                "tracks__surah_number",
                filter=Q(tracks__scope="surah"),
                distinct=True,
            )
        )
        .filter(complete_surahs=114)
        .select_related("reciter", "quran_edition_version")
        .order_by("code", "quran_edition_version_id", "-published_at", "-created_at")
    )
    seen: set[tuple[str, Any]] = set()
    result: list[tuple[int, RecitationEdition]] = []
    for recitation in queryset:
        key = (recitation.code, recitation.quran_edition_version_id)
        if key in seen:
            continue
        seen.add(key)
        match = SOURCE_ID_PATTERN.match(recitation.code)
        if match is None:
            continue
        result.append((int(match.group("source_id")), recitation))
    return result


def _matching_content_sync_resource(
    recitation: RecitationEdition,
    catalog: list[dict[str, Any]],
) -> int | None:
    expected_name = slugify(recitation.reciter.name_en)
    expected_style = recitation.style
    matches: list[int] = []
    for row in catalog:
        if slugify(str(row.get("reciter_name", ""))) != expected_name:
            continue
        row_style = slugify(str(row.get("style") or "murattal"))
        if row_style != expected_style:
            continue
        try:
            resource_id = int(row["id"])
        except KeyError, TypeError, ValueError:
            continue
        if resource_id > 0:
            matches.append(resource_id)
    return matches[0] if len(matches) == 1 else None


def _refresh_recitation_version(
    client: QuranFoundationClient,
    *,
    source_id: int,
    recitation: RecitationEdition,
    current_time: Any,
    environment: str,
) -> bool:
    prepared = prepare_quran_foundation_recitation(
        client,
        reciter_id=source_id,
        surah_numbers=list(range(1, 115)),
        quran_version=recitation.quran_edition_version,
    )
    current_timing_checksum = (
        recitation.timing_versions.order_by("-created_at")
        .values_list("source_checksum_sha256", flat=True)
        .first()
    )
    if (
        prepared.source_checksum_sha256 == recitation.source_checksum_sha256
        and prepared.timing_checksum_sha256 == current_timing_checksum
    ):
        return False

    content_version = f"{current_time:%Y.%m.%d-%H%M%S}-{environment}"
    with transaction.atomic():
        result = import_quran_foundation_recitation(
            prepared,
            quran_version=recitation.quran_edition_version,
            content_version=content_version,
            environment_name=environment,
            publish=True,
        )
        if not result.created:
            raise QuranFoundationError("Quran.Foundation refresh version already exists.")
        locked = RecitationEdition.objects.select_for_update().get(pk=recitation.pk)
        locked.withdraw()
        locked.save(update_fields=["status", "updated_at"])
        enqueue_audio_content_change(
            action="withdrawn",
            recitation_id=locked.id,
            reciter_id=locked.reciter_id,
            version=locked.version,
        )
    return True


def _withdraw_recitation(recitation: RecitationEdition) -> bool:
    with transaction.atomic():
        locked = RecitationEdition.objects.select_for_update().get(pk=recitation.pk)
        if locked.status != RecitationPublicationStatus.PUBLISHED:
            return False
        locked.withdraw()
        locked.save(update_fields=["status", "updated_at"])
        enqueue_audio_content_change(
            action="withdrawn",
            recitation_id=locked.id,
            reciter_id=locked.reciter_id,
            version=locked.version,
        )
    return True
