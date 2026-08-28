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
    QuranFoundationTranslationSyncResult,
)
from quran_backend.modules.core.provider_text import provider_plain_text
from quran_backend.modules.quran.models import Ayah, PublicationStatus
from quran_backend.modules.translations.models import (
    AyahTranslation,
    QuranFoundationTranslationSyncState,
    TranslationEdition,
    TranslationEditionVersion,
    TranslationPublicationStatus,
)

PROVIDER = "quran_foundation"
SOURCE_NAME = "Quran.Foundation Content API"
SOURCE_URL = "https://api-docs.quran.foundation/docs/content_apis_versioned/4.0.0/translations/"
LICENSE_NAME = "Quran.Foundation Developer Terms"
LICENSE_URL = "https://api-docs.quran.foundation/legal/developer-terms/"
ATTRIBUTION = "Quran data provided by Quran Foundation."
LANGUAGE_CODES = {"english": "en", "russian": "ru", "turkish": "tr"}
RELOAD_MUTATIONS = {
    "RESOURCE_CREATE",
    "RESOURCE_INVALIDATE",
    "RESOURCE_UPDATE",
    "ROW_CREATE",
    "ROW_UPDATE",
    "ROW_DELETE",
}


class QuranFoundationTranslationSource(Protocol):
    environment: QuranFoundationEnvironment

    def list_translations(self, *, language: str = "en") -> list[dict[str, Any]]: ...

    def sync_translation_catalog(
        self,
        resource_ids: tuple[int, ...],
        *,
        sync_token: str = "",
    ) -> QuranFoundationTranslationSyncResult: ...

    def get_translation_snapshot(self, resource_id: int) -> dict[str, Any]: ...


@dataclass(frozen=True, slots=True)
class TranslationSyncSummary:
    editions: int
    versions_created: int
    ayahs_imported: int
    removed: int
    changed: bool
    sync_sequence: int


def translation_resources_filter(resource_ids: tuple[int, ...]) -> str:
    normalized = tuple(sorted(set(resource_ids)))
    if not normalized or any(resource_id <= 0 for resource_id in normalized):
        raise QuranFoundationError("Translation resource IDs must be positive.")
    return "translations:" + ",".join(str(resource_id) for resource_id in normalized)


def sync_quran_foundation_translations(
    *,
    resource_ids: tuple[int, ...],
    client: QuranFoundationTranslationSource | None = None,
    force: bool = False,
    now: datetime | None = None,
    expected_verse_keys: set[str] | None = None,
) -> TranslationSyncSummary:
    normalized_ids = tuple(sorted(set(resource_ids)))
    translation_resources_filter(normalized_ids)
    sync_client = client or QuranFoundationClient.from_environment()
    current = now or timezone.now()
    catalog = _catalog_by_id(sync_client.list_translations(), normalized_ids)
    summaries = [
        _sync_translation_resource(
            resource_id=resource_id,
            metadata=catalog.get(resource_id),
            client=sync_client,
            force=force,
            current=current,
            expected_verse_keys=expected_verse_keys,
        )
        for resource_id in normalized_ids
    ]
    return TranslationSyncSummary(
        editions=TranslationEdition.objects.filter(
            environment=sync_client.environment.name,
            provider=PROVIDER,
            is_available=True,
            active_version__isnull=False,
        ).count(),
        versions_created=sum(summary.versions_created for summary in summaries),
        ayahs_imported=sum(summary.ayahs_imported for summary in summaries),
        removed=sum(summary.removed for summary in summaries),
        changed=any(summary.changed for summary in summaries),
        sync_sequence=max(summary.sync_sequence for summary in summaries),
    )


def _sync_translation_resource(  # noqa: PLR0913
    *,
    resource_id: int,
    metadata: dict[str, Any] | None,
    client: QuranFoundationTranslationSource,
    force: bool,
    current: datetime,
    expected_verse_keys: set[str] | None,
) -> TranslationSyncSummary:
    resources_filter = translation_resources_filter((resource_id,))
    state, _ = QuranFoundationTranslationSyncState.objects.get_or_create(
        environment=client.environment.name,
        resources_filter=resources_filter,
    )
    state.last_attempt_at = current
    state.save(update_fields=["last_attempt_at", "updated_at"])

    try:
        result = client.sync_translation_catalog(
            (resource_id,),
            sync_token="" if force else state.sync_token,
        )
        reload_ids, deleted_ids = _catalog_actions(result.mutations)
        has_local_publication = TranslationEdition.objects.filter(
            environment=client.environment.name,
            provider=PROVIDER,
            source_id=resource_id,
            is_available=True,
            active_version__isnull=False,
        ).exists()
        if not has_local_publication and resource_id not in deleted_ids:
            reload_ids.add(resource_id)
        snapshots = {
            changed_resource_id: client.get_translation_snapshot(changed_resource_id)
            for changed_resource_id in sorted(reload_ids)
        }
        if snapshots and metadata is None:
            raise QuranFoundationError(
                "Quran.Foundation translation catalog omitted a changed resource."
            )
        verse_keys = expected_verse_keys
        if snapshots and verse_keys is None:
            verse_keys = _published_quran_verse_keys()
        editions, versions, ayahs = _apply_catalog(
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
    return TranslationSyncSummary(
        editions=editions,
        versions_created=versions,
        ayahs_imported=ayahs,
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
        resource_id = _positive_int(mutation.get("resource_id"), "translation resource ID")
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
    result: QuranFoundationTranslationSyncResult,
    expected_verse_keys: set[str],
    current: datetime,
) -> tuple[int, int, int]:
    TranslationEdition.objects.filter(
        environment=environment,
        provider=PROVIDER,
        source_id__in=deleted_ids,
    ).update(is_available=False, active_version=None)

    versions_created = 0
    ayahs_imported = 0
    for resource_id, snapshot in snapshots.items():
        created, ayah_count = _replace_snapshot(
            environment=environment,
            metadata=catalog[resource_id],
            snapshot=snapshot,
            expected_verse_keys=expected_verse_keys,
            current=current,
        )
        versions_created += int(created)
        ayahs_imported += ayah_count if created else 0

    state = QuranFoundationTranslationSyncState.objects.select_for_update().get(
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
    editions = TranslationEdition.objects.filter(
        environment=environment,
        provider=PROVIDER,
        is_available=True,
        active_version__isnull=False,
    ).count()
    return editions, versions_created, ayahs_imported


def _replace_snapshot(
    *,
    environment: str,
    metadata: dict[str, Any],
    snapshot: dict[str, Any],
    expected_verse_keys: set[str],
    current: datetime,
) -> tuple[bool, int]:
    resource_id = _positive_int(metadata.get("id"), "translation ID")
    if _positive_int(snapshot.get("resource_id"), "snapshot resource ID") != resource_id:
        raise QuranFoundationError("Quran.Foundation translation snapshot ID does not match.")
    records = snapshot.get("records")
    if not isinstance(records, list) or not records:
        raise QuranFoundationError("Quran.Foundation translation snapshot has no records.")

    normalized: list[dict[str, Any]] = []
    verse_keys: set[str] = set()
    for record in records:
        row = _normalize_translation_record(record, resource_id)
        if row["verse_key"] in verse_keys:
            raise QuranFoundationError("Quran.Foundation returned a duplicate translated verse.")
        verse_keys.add(row["verse_key"])
        normalized.append(row)
    if not expected_verse_keys or verse_keys != expected_verse_keys:
        raise QuranFoundationError(
            "Quran.Foundation translation snapshot does not match the published Quran."
        )

    language_name = _required_string(metadata.get("language_name"), "translation language")
    language_code = LANGUAGE_CODES.get(language_name.lower())
    if language_code is None:
        raise QuranFoundationError("Configured translation language is not supported.")
    edition, _ = TranslationEdition.objects.update_or_create(
        environment=environment,
        provider=PROVIDER,
        source_id=resource_id,
        defaults={
            "slug": _provider_slug(metadata.get("slug"), resource_id),
            "language_code": language_code,
            "language_name": language_name,
            "name": _required_string(metadata.get("name"), "translation name"),
            "author_name": _required_string(
                metadata.get("author_name") or metadata.get("name"),
                "translation author",
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
    version = TranslationEditionVersion.objects.filter(
        edition=edition,
        sync_sequence=sync_sequence,
    ).first()
    created = version is None
    if version is None:
        version = TranslationEditionVersion.objects.create(
            edition=edition,
            sync_sequence=sync_sequence,
            schema_version=str(snapshot.get("schema_version", "")),
            checksum_sha256=checksum,
            status=TranslationPublicationStatus.PUBLISHED,
            ayah_count=len(normalized),
            published_at=current,
        )
        AyahTranslation.objects.bulk_create(
            [AyahTranslation(edition_version=version, **row) for row in normalized],
            batch_size=500,
        )
    elif version.checksum_sha256 != checksum:
        raise QuranFoundationError(
            "Quran.Foundation reused a translation sequence with different content."
        )
    elif version.status != TranslationPublicationStatus.PUBLISHED:
        raise QuranFoundationError("An existing translation version is not published.")
    edition.active_version = version
    edition.is_available = True
    edition.save(update_fields=["active_version", "is_available", "updated_at"])
    return created, len(normalized)


def _normalize_translation_record(record: object, resource_id: int) -> dict[str, Any]:
    if not isinstance(record, dict):
        raise QuranFoundationError("Quran.Foundation returned an invalid translation record.")
    if _positive_int(record.get("resource_id"), "record resource ID") != resource_id:
        raise QuranFoundationError("Quran.Foundation returned an unrelated translation record.")
    verse_key = _required_string(record.get("verse_key"), "verse key")
    parts = verse_key.split(":")
    if len(parts) != 2:
        raise QuranFoundationError("Quran.Foundation returned an invalid verse key.")
    surah_number = _positive_int(parts[0], "surah number")
    ayah_number = _positive_int(parts[1], "ayah number")
    if surah_number > 114:
        raise QuranFoundationError("Quran.Foundation returned an invalid surah number.")
    source_text = _required_string(record.get("text"), "translation text")
    text = translation_plain_text(source_text)
    if not text:
        raise QuranFoundationError("Quran.Foundation returned empty translation text.")
    foot_notes = record.get("foot_notes", [])
    if not isinstance(foot_notes, (list, dict)):
        raise QuranFoundationError("Quran.Foundation returned invalid translation footnotes.")
    return {
        "source_id": _positive_int(record.get("id"), "translation row ID"),
        "verse_key": verse_key,
        "surah_number": surah_number,
        "ayah_number": ayah_number,
        "text": text,
        "source_text": source_text,
        "foot_notes": _plain_json(foot_notes),
    }


def translation_plain_text(value: str) -> str:
    return provider_plain_text(value)


def _plain_json(value: Any) -> Any:
    if isinstance(value, str):
        return translation_plain_text(value)
    if isinstance(value, list):
        return [_plain_json(item) for item in value]
    if isinstance(value, dict):
        return {str(key): _plain_json(item) for key, item in value.items()}
    if value is None or isinstance(value, (bool, int, float)):
        return value
    raise QuranFoundationError("Quran.Foundation returned invalid translation footnotes.")


def _published_quran_verse_keys() -> set[str]:
    coordinates = Ayah.objects.filter(
        surah__edition_version__status=PublicationStatus.PUBLISHED,
        surah__edition_version__edition__active_version=models.F("surah__edition_version"),
    ).values_list("surah__number", "number")
    verse_keys = {f"{surah}:{ayah}" for surah, ayah in coordinates}
    if not verse_keys:
        raise QuranFoundationError("No published Quran is available for translation validation.")
    return verse_keys


def _required_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise QuranFoundationError(f"Quran.Foundation returned an invalid {label}.")
    return value.strip()


def _provider_slug(value: object, resource_id: int) -> str:
    if isinstance(value, str) and value.strip():
        return value.strip()
    return f"quran-foundation-translation-{resource_id}"


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
