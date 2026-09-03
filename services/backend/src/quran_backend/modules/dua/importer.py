from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from django.db import models, transaction
from django.utils import timezone

from quran_backend.modules.core.content_revalidation import enqueue_dua_content_change
from quran_backend.modules.dua.models import (
    DuaAudioAsset,
    DuaCategory,
    DuaCategoryTranslation,
    DuaCollection,
    DuaCollectionVersion,
    DuaEntry,
    DuaEntryTranslation,
    DuaEvidence,
    DuaPublicationStatus,
    DuaRightsBasis,
    DuaSourceEdition,
)

SUPPORTED_DUA_LANGUAGES = frozenset({"ar", "en", "ru", "tr"})
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")


class DuaSnapshotError(ValueError):
    """The snapshot cannot be safely imported."""


@dataclass(frozen=True, slots=True)
class DuaImportResult:
    version_id: str
    version: str
    checksum_sha256: str
    category_count: int
    entry_count: int
    audio_count: int
    created: bool
    published: bool


def bundled_starter_snapshot_path() -> Path:
    return Path(__file__).with_name("data") / "hisn_al_muslim_starter_v1.json"


def bundled_full_snapshot_path() -> Path:
    return Path(__file__).with_name("data") / "hisn_al_muslim_full_v1.json"


def bundled_quran_supplications_snapshot_path() -> Path:
    return Path(__file__).with_name("data") / "supplications_from_quran_jmapps_v1.json"


def load_dua_snapshot(path: str | Path) -> dict[str, Any]:
    try:
        payload = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise DuaSnapshotError(f"Unable to read Dua snapshot: {exc}") from exc
    if not isinstance(payload, dict):
        raise DuaSnapshotError("The Dua snapshot root must be an object.")
    return payload


def snapshot_checksum(snapshot: dict[str, Any]) -> str:
    canonical = json.dumps(
        snapshot,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode()
    return hashlib.sha256(canonical).hexdigest()


def _require_non_empty_string(container: dict[str, Any], key: str) -> str:
    value = container.get(key)
    if not isinstance(value, str) or not value.strip():
        raise DuaSnapshotError(f"{key} must be a non-empty string.")
    return value.strip()


def _validate_translations(
    translations: Any,
    *,
    owner: str,
    text_key: str,
) -> list[dict[str, Any]]:
    if not isinstance(translations, list):
        raise DuaSnapshotError(f"{owner}.translations must be a list.")
    by_language: dict[str, dict[str, Any]] = {}
    for translation in translations:
        if not isinstance(translation, dict):
            raise DuaSnapshotError(f"{owner}.translations contains a non-object value.")
        language = _require_non_empty_string(translation, "language")
        if language not in SUPPORTED_DUA_LANGUAGES:
            raise DuaSnapshotError(f"Unsupported Dua language: {language}.")
        _require_non_empty_string(translation, text_key)
        if language in by_language:
            raise DuaSnapshotError(f"{owner} contains duplicate language {language}.")
        by_language[language] = translation
    missing = SUPPORTED_DUA_LANGUAGES.difference(by_language)
    if missing:
        raise DuaSnapshotError(f"{owner} is missing translations: {', '.join(sorted(missing))}.")
    return list(by_language.values())


def _validate_sources(sources: Any) -> None:
    if not isinstance(sources, list):
        raise DuaSnapshotError("sources must be a list.")
    source_languages: set[str] = set()
    for source in sources:
        if not isinstance(source, dict):
            raise DuaSnapshotError("sources contains a non-object value.")
        language = _require_non_empty_string(source, "language")
        if language not in SUPPORTED_DUA_LANGUAGES or language in source_languages:
            raise DuaSnapshotError(f"Invalid or duplicate source language: {language}.")
        source_languages.add(language)
        for key in (
            "provider",
            "source_item_id",
            "title",
            "source_url",
            "source_version",
        ):
            _require_non_empty_string(source, key)
        for optional_key in ("author", "translator", "reviewer", "rights_url"):
            value = source.get(optional_key, "")
            if not isinstance(value, str):
                raise DuaSnapshotError(f"sources.{optional_key} must be a string.")
        rights_basis = source.get("rights_basis", DuaRightsBasis.SOURCE_DOCUMENTED)
        if rights_basis not in DuaRightsBasis.values:
            raise DuaSnapshotError(f"Invalid source rights_basis: {rights_basis}.")
        if not source.get("rights_url", "").strip() and rights_basis != (
            DuaRightsBasis.IQRO_OWNER_ATTESTED
        ):
            raise DuaSnapshotError(
                "A blank source rights_url requires rights_basis=iqro_owner_attested."
            )
    if source_languages != SUPPORTED_DUA_LANGUAGES:
        raise DuaSnapshotError("A source edition is required for ar, en, ru and tr.")


def _validate_categories(categories: Any) -> set[int]:
    if not isinstance(categories, list) or not categories:
        raise DuaSnapshotError("categories must be a non-empty list.")
    category_numbers: set[int] = set()
    for category in categories:
        if not isinstance(category, dict):
            raise DuaSnapshotError("categories contains a non-object value.")
        source_number = category.get("source_number")
        if (
            not isinstance(source_number, int)
            or source_number < 1
            or source_number in category_numbers
        ):
            raise DuaSnapshotError("Category source numbers must be unique positive integers.")
        category_numbers.add(source_number)
        _require_non_empty_string(category, "slug")
        _validate_translations(
            category.get("translations"),
            owner=f"category {source_number}",
            text_key="title",
        )
    return category_numbers


def _validate_entries(entries: Any, *, category_numbers: set[int]) -> set[int]:
    if not isinstance(entries, list) or not entries:
        raise DuaSnapshotError("entries must be a non-empty list.")
    entry_numbers: set[int] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            raise DuaSnapshotError("entries contains a non-object value.")
        source_number = entry.get("source_number")
        if (
            not isinstance(source_number, int)
            or source_number < 1
            or source_number in entry_numbers
        ):
            raise DuaSnapshotError("Entry source numbers must be unique positive integers.")
        entry_numbers.add(source_number)
        if entry.get("category_source_number") not in category_numbers:
            raise DuaSnapshotError(f"Entry {source_number} references an unknown category.")
        repetitions = entry.get("repetitions", 1)
        if not isinstance(repetitions, int) or repetitions < 1:
            raise DuaSnapshotError(f"Entry {source_number} has invalid repetitions.")
        repetition_label = entry.get("repetition_label", "")
        if not isinstance(repetition_label, str) or len(repetition_label) > 32:
            raise DuaSnapshotError(f"Entry {source_number} has an invalid repetition label.")
        _require_non_empty_string(entry, "slug")
        _require_non_empty_string(entry, "arabic_text")
        _validate_translations(
            entry.get("translations"),
            owner=f"entry {source_number}",
            text_key="meaning_text",
        )
        evidence_items = entry.get("evidence", [])
        if not isinstance(evidence_items, list):
            raise DuaSnapshotError(f"Entry {source_number} evidence must be a list.")
        for evidence in evidence_items:
            if not isinstance(evidence, dict):
                raise DuaSnapshotError(f"Entry {source_number} evidence contains a non-object.")
            for key in ("kind", "provider", "source_name", "source_reference"):
                _require_non_empty_string(evidence, key)
    return entry_numbers


def _validate_audio(audio_items: Any, *, entry_numbers: set[int]) -> None:
    if audio_items is None:
        return
    if not isinstance(audio_items, list):
        raise DuaSnapshotError("audio must be a list.")
    identities: set[tuple[int, int]] = set()
    for audio in audio_items:
        if not isinstance(audio, dict):
            raise DuaSnapshotError("audio contains a non-object value.")
        source_number = audio.get("source_number")
        sort_order = audio.get("sort_order", 1)
        if source_number not in entry_numbers:
            raise DuaSnapshotError("Dua audio references an unknown entry source number.")
        if not isinstance(sort_order, int) or sort_order < 1:
            raise DuaSnapshotError(f"Dua audio {source_number} has invalid sort_order.")
        identity = (source_number, sort_order)
        if identity in identities:
            raise DuaSnapshotError(
                f"Dua audio {source_number} contains duplicate sort_order {sort_order}."
            )
        identities.add(identity)
        _validate_audio_source(audio, source_number=source_number)


def _validate_audio_source(audio: dict[str, Any], *, source_number: int) -> None:
    language = _require_non_empty_string(audio, "language_code")
    if language not in SUPPORTED_DUA_LANGUAGES:
        raise DuaSnapshotError(f"Unsupported Dua audio language: {language}.")
    for key in ("provider", "external_url", "source_url", "source_version"):
        _require_non_empty_string(audio, key)
    for optional_key in ("reader_name", "reader_name_ar", "rights_url"):
        value = audio.get(optional_key, "")
        if not isinstance(value, str):
            raise DuaSnapshotError(f"audio.{optional_key} must be a string.")
    rights_basis = audio.get("rights_basis", DuaRightsBasis.SOURCE_DOCUMENTED)
    if rights_basis not in DuaRightsBasis.values:
        raise DuaSnapshotError(f"Invalid audio rights_basis: {rights_basis}.")
    if not audio.get("rights_url", "").strip() and rights_basis != (
        DuaRightsBasis.IQRO_OWNER_ATTESTED
    ):
        raise DuaSnapshotError(
            "A blank audio rights_url requires rights_basis=iqro_owner_attested."
        )
    checksum = audio.get("checksum_sha256", "")
    if not isinstance(checksum, str) or (checksum and SHA256_RE.fullmatch(checksum) is None):
        raise DuaSnapshotError(f"Dua audio {source_number} has invalid checksum_sha256.")
    size_bytes = audio.get("size_bytes", 0)
    if not isinstance(size_bytes, int) or size_bytes < 0:
        raise DuaSnapshotError(f"Dua audio {source_number} has invalid size_bytes.")
    if not isinstance(audio.get("is_active", True), bool):
        raise DuaSnapshotError(f"Dua audio {source_number} has invalid is_active.")


def validate_dua_snapshot(snapshot: dict[str, Any]) -> None:
    if snapshot.get("schema_version") != 1:
        raise DuaSnapshotError("Only Dua snapshot schema_version=1 is supported.")
    _require_non_empty_string(snapshot, "version")
    collection = snapshot.get("collection")
    if not isinstance(collection, dict):
        raise DuaSnapshotError("collection must be an object.")
    _require_non_empty_string(collection, "slug")
    _validate_sources(snapshot.get("sources"))
    category_numbers = _validate_categories(snapshot.get("categories"))
    entry_numbers = _validate_entries(snapshot.get("entries"), category_numbers=category_numbers)
    _validate_audio(snapshot.get("audio"), entry_numbers=entry_numbers)


def _publish_version(version: DuaCollectionVersion) -> None:
    unverified_managed_audio = version.audio_assets.filter(
        is_active=True,
        object_key__isnull=False,
    ).filter(
        models.Q(checksum_sha256="")
        | models.Q(size_bytes=0)
        | models.Q(origin_etag="")
        | models.Q(etag="")
        | models.Q(cdn_contract_verified_at__isnull=True)
    )
    if unverified_managed_audio.exists():
        raise DuaSnapshotError(
            "Managed Dua audio must have verified origin and CDN evidence before publication."
        )
    collection = version.collection
    previous = collection.active_version
    if previous and previous.pk != version.pk:
        previous.status = DuaPublicationStatus.WITHDRAWN
        previous.full_clean()
        previous.save(update_fields=("status", "updated_at"))
    if version.status != DuaPublicationStatus.PUBLISHED:
        version.status = DuaPublicationStatus.PUBLISHED
        version.published_at = timezone.now()
        version.full_clean()
        version.save(update_fields=("status", "published_at", "updated_at"))
    collection.active_version = version
    collection.full_clean()
    collection.save(update_fields=("active_version", "updated_at"))
    enqueue_dua_content_change(
        action="activated",
        collection=collection.slug,
        version=version.version,
    )


@transaction.atomic
def import_dua_snapshot(snapshot: dict[str, Any], *, publish: bool = False) -> DuaImportResult:
    validate_dua_snapshot(snapshot)
    checksum = snapshot_checksum(snapshot)
    collection_payload = snapshot["collection"]
    collection, _ = DuaCollection.objects.get_or_create(slug=collection_payload["slug"])
    version_name = snapshot["version"]
    existing = DuaCollectionVersion.objects.filter(
        collection=collection,
        version=version_name,
    ).first()
    if existing:
        if existing.checksum_sha256 != checksum:
            raise DuaSnapshotError(
                "A snapshot with this collection version already exists with a different checksum."
            )
        if publish:
            _publish_version(existing)
        return DuaImportResult(
            version_id=str(existing.pk),
            version=existing.version,
            checksum_sha256=checksum,
            category_count=existing.category_count,
            entry_count=existing.entry_count,
            audio_count=existing.audio_assets.count(),
            created=False,
            published=existing.status == DuaPublicationStatus.PUBLISHED,
        )

    categories_payload = snapshot["categories"]
    entries_payload = snapshot["entries"]
    version = DuaCollectionVersion.objects.create(
        collection=collection,
        version=version_name,
        schema_version=snapshot["schema_version"],
        checksum_sha256=checksum,
        category_count=len(categories_payload),
        entry_count=len(entries_payload),
    )

    for source in snapshot["sources"]:
        DuaSourceEdition.objects.create(
            collection_version=version,
            language_code=source["language"],
            provider=source["provider"],
            source_item_id=source["source_item_id"],
            title=source["title"],
            author=source.get("author", ""),
            translator=source.get("translator", ""),
            reviewer=source.get("reviewer", ""),
            source_url=source["source_url"],
            rights_url=source.get("rights_url", ""),
            rights_basis=source.get("rights_basis", DuaRightsBasis.SOURCE_DOCUMENTED),
            source_version=source["source_version"],
        )

    categories: dict[int, DuaCategory] = {}
    for sort_order, category_payload in enumerate(categories_payload, start=1):
        category = DuaCategory.objects.create(
            collection_version=version,
            source_number=category_payload["source_number"],
            slug=category_payload["slug"],
            sort_order=sort_order,
        )
        categories[category.source_number] = category
        for translation in category_payload["translations"]:
            DuaCategoryTranslation.objects.create(
                category=category,
                language_code=translation["language"],
                title=translation["title"],
            )

    for audio in snapshot.get("audio", []):
        DuaAudioAsset.objects.create(
            collection_version=version,
            source_number=audio["source_number"],
            language_code=audio["language_code"],
            provider=audio["provider"],
            reader_name=audio.get("reader_name", ""),
            reader_name_ar=audio.get("reader_name_ar", ""),
            external_url=audio["external_url"],
            object_key=None,
            content_type=audio.get("content_type", "audio/mpeg"),
            size_bytes=audio.get("size_bytes", 0),
            checksum_sha256=audio.get("checksum_sha256", ""),
            source_url=audio["source_url"],
            rights_url=audio.get("rights_url", ""),
            rights_basis=audio.get("rights_basis", DuaRightsBasis.SOURCE_DOCUMENTED),
            source_version=audio["source_version"],
            sort_order=audio.get("sort_order", 1),
            is_active=audio.get("is_active", True),
        )

    for sort_order, entry_payload in enumerate(entries_payload, start=1):
        entry = DuaEntry.objects.create(
            collection_version=version,
            category=categories[entry_payload["category_source_number"]],
            source_number=entry_payload["source_number"],
            slug=entry_payload["slug"],
            arabic_text=entry_payload["arabic_text"],
            repetitions=entry_payload.get("repetitions", 1),
            repetition_label=entry_payload.get("repetition_label", ""),
            sort_order=sort_order,
        )
        for translation in entry_payload["translations"]:
            DuaEntryTranslation.objects.create(
                entry=entry,
                language_code=translation["language"],
                meaning_text=translation["meaning_text"],
                transliteration=translation.get("transliteration", ""),
            )
        for evidence_order, evidence in enumerate(entry_payload.get("evidence", []), start=1):
            DuaEvidence.objects.create(
                entry=entry,
                kind=evidence["kind"],
                provider=evidence["provider"],
                source_name=evidence["source_name"],
                source_reference=evidence["source_reference"],
                source_url=evidence.get("source_url", ""),
                grade=evidence.get("grade", ""),
                external_id=evidence.get("external_id", ""),
                verification_status=evidence.get("verification_status", "source_only"),
                sort_order=evidence_order,
            )

    if publish:
        _publish_version(version)
    return DuaImportResult(
        version_id=str(version.pk),
        version=version.version,
        checksum_sha256=checksum,
        category_count=version.category_count,
        entry_count=version.entry_count,
        audio_count=version.audio_assets.count(),
        created=True,
        published=version.status == DuaPublicationStatus.PUBLISHED,
    )
