from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Protocol

from django.db import models, transaction
from django.utils import timezone

from quran_backend.modules.audio.quran_foundation import (
    QuranFoundationClient,
    QuranFoundationEnvironment,
    QuranFoundationError,
    QuranFoundationTafsirSyncResult,
)
from quran_backend.modules.core.provider_text import provider_plain_text
from quran_backend.modules.quran.models import Ayah, PublicationStatus
from quran_backend.modules.tafsirs.models import (
    AyahTafsir,
    QuranFoundationTafsirSyncState,
    TafsirEdition,
    TafsirEditionVersion,
    TafsirPublicationStatus,
)

PROVIDER = "quran_foundation"
SOURCE_NAME = "Quran.Foundation Content API"
SOURCE_URL = "https://api-docs.quran.foundation/docs/content_apis_versioned/4.0.0/tafsirs/"
LICENSE_NAME = "Quran.Foundation Developer Terms"
LICENSE_URL = "https://api-docs.quran.foundation/legal/developer-terms/"
ATTRIBUTION = "Quran data provided by Quran Foundation."
LANGUAGE_CODES = {"arabic": "ar", "english": "en", "russian": "ru"}
RELOAD_MUTATIONS = {
    "RESOURCE_CREATE",
    "RESOURCE_INVALIDATE",
    "RESOURCE_UPDATE",
    "ROW_CREATE",
    "ROW_UPDATE",
    "ROW_DELETE",
}


class QuranFoundationTafsirSource(Protocol):
    environment: QuranFoundationEnvironment

    def list_tafsirs(self, *, language: str = "en") -> list[dict[str, Any]]: ...

    def sync_tafsir_catalog(
        self,
        resource_ids: tuple[int, ...],
        *,
        sync_token: str = "",
    ) -> QuranFoundationTafsirSyncResult: ...

    def get_tafsir_snapshot(self, resource_id: int) -> dict[str, Any]: ...


@dataclass(frozen=True, slots=True)
class TafsirSyncSummary:
    editions: int
    versions_created: int
    records_imported: int
    removed: int
    changed: bool
    sync_sequence: int


def tafsir_resources_filter(resource_ids: tuple[int, ...]) -> str:
    normalized = tuple(sorted(set(resource_ids)))
    if not normalized or any(resource_id <= 0 for resource_id in normalized):
        raise QuranFoundationError("Tafsir resource IDs must be positive.")
    return "tafsirs:" + ",".join(str(resource_id) for resource_id in normalized)


def sync_quran_foundation_tafsirs(
    *,
    resource_ids: tuple[int, ...],
    client: QuranFoundationTafsirSource | None = None,
    force: bool = False,
    now: datetime | None = None,
    expected_verse_keys: set[str] | None = None,
) -> TafsirSyncSummary:
    normalized_ids = tuple(sorted(set(resource_ids)))
    tafsir_resources_filter(normalized_ids)
    sync_client = client or QuranFoundationClient.from_environment()
    current = now or timezone.now()
    catalog = _catalog_by_id(sync_client.list_tafsirs(), normalized_ids)
    summaries = [
        _sync_tafsir_resource(
            resource_id=resource_id,
            metadata=catalog.get(resource_id),
            client=sync_client,
            force=force,
            current=current,
            expected_verse_keys=expected_verse_keys,
        )
        for resource_id in normalized_ids
    ]
    return TafsirSyncSummary(
        editions=TafsirEdition.objects.filter(
            environment=sync_client.environment.name,
            provider=PROVIDER,
            is_available=True,
            active_version__isnull=False,
        ).count(),
        versions_created=sum(summary.versions_created for summary in summaries),
        records_imported=sum(summary.records_imported for summary in summaries),
        removed=sum(summary.removed for summary in summaries),
        changed=any(summary.changed for summary in summaries),
        sync_sequence=max(summary.sync_sequence for summary in summaries),
    )


def _sync_tafsir_resource(  # noqa: PLR0913
    *,
    resource_id: int,
    metadata: dict[str, Any] | None,
    client: QuranFoundationTafsirSource,
    force: bool,
    current: datetime,
    expected_verse_keys: set[str] | None,
) -> TafsirSyncSummary:
    resources_filter = tafsir_resources_filter((resource_id,))
    state, _ = QuranFoundationTafsirSyncState.objects.get_or_create(
        environment=client.environment.name,
        resources_filter=resources_filter,
    )
    state.last_attempt_at = current
    state.save(update_fields=["last_attempt_at", "updated_at"])

    try:
        result = client.sync_tafsir_catalog(
            (resource_id,),
            sync_token="" if force else state.sync_token,
        )
        reload_ids, deleted_ids = _catalog_actions(result.mutations)
        has_local_publication = TafsirEdition.objects.filter(
            environment=client.environment.name,
            provider=PROVIDER,
            source_id=resource_id,
            is_available=True,
            active_version__isnull=False,
        ).exists()
        if not has_local_publication and resource_id not in deleted_ids:
            reload_ids.add(resource_id)
        snapshots = {
            changed_resource_id: client.get_tafsir_snapshot(changed_resource_id)
            for changed_resource_id in sorted(reload_ids)
        }
        if snapshots and metadata is None:
            raise QuranFoundationError(
                "Quran.Foundation Tafsir catalog omitted a changed resource."
            )
        verse_keys = expected_verse_keys
        if snapshots and verse_keys is None:
            verse_keys = _published_quran_verse_keys()
        editions, versions, records = _apply_catalog(
            environment=client.environment.name,
            resources_filter=resources_filter,
            catalog={resource_id: metadata} if metadata is not None else {},
            snapshots=snapshots,
            deleted_ids=deleted_ids,
            result=result,
            expected_verse_keys=verse_keys or set(),
            current=current,
        )
    except QuranFoundationError:
        state.consecutive_failures += 1
        state.last_error_code = "quran_foundation_error"
        state.save(update_fields=["consecutive_failures", "last_error_code", "updated_at"])
        raise
    return TafsirSyncSummary(
        editions=editions,
        versions_created=versions,
        records_imported=records,
        removed=len(deleted_ids),
        changed=bool(snapshots or deleted_ids),
        sync_sequence=result.sync_until_sequence,
    )


def _catalog_by_id(
    rows: list[dict[str, Any]],
    resource_ids: tuple[int, ...],
) -> dict[int, dict[str, Any]]:
    catalog: dict[int, dict[str, Any]] = {}
    requested = set(resource_ids)
    for row in rows:
        try:
            resource_id = int(row.get("id", 0))
        except TypeError, ValueError:
            continue
        if resource_id in requested:
            catalog[resource_id] = row
    return catalog


def _catalog_actions(
    mutations: tuple[dict[str, Any], ...],
) -> tuple[set[int], set[int]]:
    reload_ids: set[int] = set()
    deleted_ids: set[int] = set()
    for mutation in mutations:
        resource_id = _positive_int(mutation.get("resource_id"), "Tafsir resource ID")
        mutation_type = str(mutation.get("type", ""))
        if mutation_type == "RESOURCE_DELETE":
            deleted_ids.add(resource_id)
            reload_ids.discard(resource_id)
        elif mutation_type in RELOAD_MUTATIONS:
            reload_ids.add(resource_id)
            deleted_ids.discard(resource_id)
    return reload_ids, deleted_ids


@transaction.atomic
def _apply_catalog(  # noqa: PLR0913
    *,
    environment: str,
    resources_filter: str,
    catalog: dict[int, dict[str, Any]],
    snapshots: dict[int, dict[str, Any]],
    deleted_ids: set[int],
    result: QuranFoundationTafsirSyncResult,
    expected_verse_keys: set[str],
    current: datetime,
) -> tuple[int, int, int]:
    TafsirEdition.objects.filter(
        environment=environment,
        provider=PROVIDER,
        source_id__in=deleted_ids,
    ).update(is_available=False, active_version=None)

    versions_created = 0
    records_imported = 0
    for resource_id, snapshot in snapshots.items():
        created, record_count = _replace_snapshot(
            environment=environment,
            metadata=catalog[resource_id],
            snapshot=snapshot,
            expected_verse_keys=expected_verse_keys,
            current=current,
        )
        versions_created += int(created)
        records_imported += record_count if created else 0

    state = QuranFoundationTafsirSyncState.objects.select_for_update().get(
        environment=environment,
        resources_filter=resources_filter,
    )
    state.sync_token = result.next_sync_token
    state.last_sync_sequence = result.sync_until_sequence
    state.last_success_at = current
    state.consecutive_failures = 0
    state.last_error_code = ""
    state.save(
        update_fields=[
            "sync_token",
            "last_sync_sequence",
            "last_success_at",
            "consecutive_failures",
            "last_error_code",
            "updated_at",
        ]
    )
    editions = TafsirEdition.objects.filter(
        environment=environment,
        provider=PROVIDER,
        is_available=True,
        active_version__isnull=False,
    ).count()
    return editions, versions_created, records_imported


def _replace_snapshot(
    *,
    environment: str,
    metadata: dict[str, Any],
    snapshot: dict[str, Any],
    expected_verse_keys: set[str],
    current: datetime,
) -> tuple[bool, int]:
    resource_id = _positive_int(metadata.get("id"), "Tafsir ID")
    if _positive_int(snapshot.get("resource_id"), "snapshot resource ID") != resource_id:
        raise QuranFoundationError("Quran.Foundation Tafsir snapshot ID does not match.")
    records = snapshot.get("records")
    if not isinstance(records, list) or not records:
        raise QuranFoundationError("Quran.Foundation Tafsir snapshot has no records.")
    if not expected_verse_keys:
        raise QuranFoundationError("No published Quran is available for Tafsir validation.")

    ordered_keys = sorted(expected_verse_keys, key=_parse_verse_key)
    verse_rank = {key: index for index, key in enumerate(ordered_keys, start=1)}
    normalized: list[dict[str, Any]] = []
    seen_verse_keys: set[str] = set()
    covered_ranks: set[int] = set()
    for record in records:
        row = _normalize_tafsir_record(record, resource_id, verse_rank)
        if row["verse_key"] in seen_verse_keys:
            raise QuranFoundationError("Quran.Foundation returned a duplicate Tafsir verse.")
        seen_verse_keys.add(row["verse_key"])
        covered_ranks.update(range(row["start_verse_id"], row["end_verse_id"] + 1))
        normalized.append(row)
    _validate_grouped_tafsir_texts(normalized)
    language_name = _required_string(metadata.get("language_name"), "Tafsir language")
    language_code = LANGUAGE_CODES.get(language_name.lower())
    if language_code is None:
        raise QuranFoundationError("Configured Tafsir language is not supported.")
    edition, _ = TafsirEdition.objects.update_or_create(
        environment=environment,
        provider=PROVIDER,
        source_id=resource_id,
        defaults={
            "slug": _required_string(metadata.get("slug"), "Tafsir slug"),
            "language_code": language_code,
            "language_name": language_name,
            "name": _required_string(metadata.get("name"), "Tafsir name"),
            "author_name": _required_string(
                metadata.get("author_name") or metadata.get("name"),
                "Tafsir author",
            ),
            "source_name": SOURCE_NAME,
            "source_url": SOURCE_URL,
            "license_name": LICENSE_NAME,
            "license_url": LICENSE_URL,
            "attribution": ATTRIBUTION,
            "is_available": True,
        },
    )
    sync_sequence = _non_negative_int(snapshot.get("sync_sequence"), "snapshot sequence")
    checksum = hashlib.sha256(
        json.dumps(
            snapshot,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode()
    ).hexdigest()
    version = TafsirEditionVersion.objects.filter(
        edition=edition,
        sync_sequence=sync_sequence,
    ).first()
    created = version is None
    if version is None:
        version = TafsirEditionVersion.objects.create(
            edition=edition,
            sync_sequence=sync_sequence,
            schema_version=str(snapshot.get("schema_version", "")),
            checksum_sha256=checksum,
            status=TafsirPublicationStatus.PUBLISHED,
            record_count=len(normalized),
            covered_ayah_count=len(covered_ranks),
            published_at=current,
        )
        AyahTafsir.objects.bulk_create(
            [AyahTafsir(edition_version=version, **row) for row in normalized],
            batch_size=250,
        )
    elif version.checksum_sha256 != checksum:
        raise QuranFoundationError(
            "Quran.Foundation reused a Tafsir sequence with different content."
        )
    elif version.status != TafsirPublicationStatus.PUBLISHED:
        raise QuranFoundationError("An existing Tafsir version is not published.")
    edition.active_version = version
    edition.is_available = True
    edition.save(update_fields=["active_version", "is_available", "updated_at"])
    return created, len(normalized)


def _normalize_tafsir_record(
    record: object,
    resource_id: int,
    verse_rank: dict[str, int],
) -> dict[str, Any]:
    if not isinstance(record, dict):
        raise QuranFoundationError("Quran.Foundation returned an invalid Tafsir record.")
    if _positive_int(record.get("resource_id"), "record resource ID") != resource_id:
        raise QuranFoundationError("Quran.Foundation returned an unrelated Tafsir record.")

    verse_key = _required_string(record.get("verse_key"), "verse key")
    surah_number, ayah_number = _parse_verse_key(verse_key)
    rank = verse_rank.get(verse_key)
    if rank is None:
        raise QuranFoundationError("Quran.Foundation Tafsir references an unknown verse.")
    start_verse_key = _optional_string(record.get("group_verse_key_from")) or verse_key
    end_verse_key = _optional_string(record.get("group_verse_key_to")) or verse_key
    start_rank = verse_rank.get(start_verse_key)
    end_rank = verse_rank.get(end_verse_key)
    if start_rank is None or end_rank is None or not (start_rank <= rank <= end_rank):
        raise QuranFoundationError("Quran.Foundation returned an invalid Tafsir verse range.")

    source_verse_id = _positive_int(record.get("verse_id"), "Tafsir verse ID")
    start_verse_id = _positive_int(
        record.get("start_verse_id") or source_verse_id,
        "Tafsir start verse ID",
    )
    end_verse_id = _positive_int(
        record.get("end_verse_id") or source_verse_id,
        "Tafsir end verse ID",
    )
    if source_verse_id != rank or start_verse_id != start_rank or end_verse_id != end_rank:
        raise QuranFoundationError("Quran.Foundation Tafsir verse IDs do not match the Quran.")

    start_surah_number, start_ayah_number = _parse_verse_key(start_verse_key)
    end_surah_number, end_ayah_number = _parse_verse_key(end_verse_key)
    group_verses_count = _positive_int(
        record.get("group_verses_count") or end_rank - start_rank + 1,
        "Tafsir group verse count",
    )
    if group_verses_count != end_rank - start_rank + 1:
        raise QuranFoundationError("Quran.Foundation returned an invalid Tafsir group size.")

    raw_source_text = record.get("text")
    if not isinstance(raw_source_text, str):
        raise QuranFoundationError("Quran.Foundation returned an invalid Tafsir text.")
    source_text = raw_source_text.strip()
    text = provider_plain_text(source_text)
    raw_group_id = record.get("group_tafsir_id")
    provider_group_id = (
        None if raw_group_id in (None, "") else _positive_int(raw_group_id, "Tafsir group ID")
    )
    return {
        "source_id": _positive_int(record.get("id"), "Tafsir row ID"),
        "provider_group_id": provider_group_id,
        "verse_key": verse_key,
        "surah_number": surah_number,
        "ayah_number": ayah_number,
        "start_verse_id": start_verse_id,
        "end_verse_id": end_verse_id,
        "start_verse_key": start_verse_key,
        "end_verse_key": end_verse_key,
        "start_surah_number": start_surah_number,
        "start_ayah_number": start_ayah_number,
        "end_surah_number": end_surah_number,
        "end_ayah_number": end_ayah_number,
        "group_verses_count": group_verses_count,
        "text": text,
        "source_text": source_text,
    }


def _validate_grouped_tafsir_texts(rows: list[dict[str, Any]]) -> None:
    """Validate provider rows that reference one shared Tafsir range text."""

    rows_by_source_id = {row["source_id"]: row for row in rows}
    for row in rows:
        if row["text"]:
            continue
        group_id = row["provider_group_id"]
        source = rows_by_source_id.get(group_id)
        if (
            group_id is None
            or source is None
            or not source["text"]
            or source["start_verse_key"] != row["start_verse_key"]
            or source["end_verse_key"] != row["end_verse_key"]
        ):
            raise QuranFoundationError(
                "Quran.Foundation returned an unresolved grouped Tafsir text."
            )


def _published_quran_verse_keys() -> set[str]:
    coordinates = Ayah.objects.filter(
        surah__edition_version__status=PublicationStatus.PUBLISHED,
        surah__edition_version__edition__active_version=models.F("surah__edition_version"),
    ).values_list("surah__number", "number")
    verse_keys = {f"{surah}:{ayah}" for surah, ayah in coordinates}
    if not verse_keys:
        raise QuranFoundationError("No published Quran is available for Tafsir validation.")
    return verse_keys


def _parse_verse_key(value: str) -> tuple[int, int]:
    parts = value.split(":")
    if len(parts) != 2:
        raise QuranFoundationError("Quran.Foundation returned an invalid verse key.")
    surah_number = _positive_int(parts[0], "surah number")
    ayah_number = _positive_int(parts[1], "ayah number")
    if surah_number > 114:
        raise QuranFoundationError("Quran.Foundation returned an invalid surah number.")
    return surah_number, ayah_number


def _required_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise QuranFoundationError(f"Quran.Foundation returned an invalid {label}.")
    return value.strip()


def _optional_string(value: object) -> str:
    return value.strip() if isinstance(value, str) else ""


def _positive_int(value: object, label: str) -> int:
    parsed = _non_negative_int(value, label)
    if parsed <= 0:
        raise QuranFoundationError(f"Quran.Foundation returned an invalid {label}.")
    return parsed


def _non_negative_int(value: object, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, str)):
        raise QuranFoundationError(f"Quran.Foundation returned an invalid {label}.")
    try:
        parsed = int(value)
    except (TypeError, ValueError) as exc:
        raise QuranFoundationError(f"Quran.Foundation returned an invalid {label}.") from exc
    if parsed < 0:
        raise QuranFoundationError(f"Quran.Foundation returned an invalid {label}.")
    return parsed
