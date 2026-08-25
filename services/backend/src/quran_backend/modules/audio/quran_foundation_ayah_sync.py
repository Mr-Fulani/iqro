from __future__ import annotations

import hashlib
import json
import re
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Protocol

from django.db import transaction
from django.utils import timezone

from quran_backend.modules.audio.models import (
    QuranFoundationAyahRecitation,
    QuranFoundationAyahRecitationChapter,
)
from quran_backend.modules.audio.quran_foundation import (
    QuranFoundationClient,
    QuranFoundationEnvironment,
    QuranFoundationError,
)
from quran_backend.modules.quran.models import Ayah, QuranEditionVersion

VERSE_KEY_PATTERN = re.compile(r"^(?P<surah>[1-9][0-9]{0,2}):(?P<ayah>[1-9][0-9]{0,2})$")


class QuranFoundationAyahAudioSource(Protocol):
    environment: QuranFoundationEnvironment

    def list_ayah_recitations(self, *, language: str = "en") -> list[dict[str, Any]]: ...

    def get_ayah_recitation_audio(self, recitation_id: int) -> dict[str, Any]: ...

    def normalize_ayah_audio_url(self, value: object) -> str: ...

    def get_external_ayah_audio_size(self, url: str) -> int: ...


@dataclass(frozen=True, slots=True)
class QuranFoundationAyahCatalogSyncSummary:
    selected: int
    available: int
    created: int
    updated: int
    unchanged: int
    chapters: int
    audio_files: int
    delivery_samples: int
    failures: tuple[tuple[int, str], ...]


@dataclass(frozen=True, slots=True)
class _PreparedAyahRecitation:
    source_id: int
    name_ar: str
    name_en: str
    name_ru: str
    style: str
    audio_file_count: int
    checksum: str
    chapters: tuple[tuple[int, tuple[dict[str, object], ...]], ...]
    delivery_samples: int


def sync_quran_foundation_ayah_recitations(
    *,
    quran_version: QuranEditionVersion,
    client: QuranFoundationAyahAudioSource | None = None,
    now: datetime | None = None,
    verify_delivery: bool = True,
) -> QuranFoundationAyahCatalogSyncSummary:
    _ensure_hafs_version(quran_version)
    sync_client = client or QuranFoundationClient.from_environment()
    current = now or timezone.now()
    expected = _expected_verse_keys(quran_version)
    catalogs = {
        language: sync_client.list_ayah_recitations(language=language)
        for language in ("en", "ar", "ru")
    }
    localized = _localized_catalogs(catalogs)
    selected_ids = set(localized["en"])

    created = 0
    updated = 0
    unchanged = 0
    delivery_samples = 0
    failures: list[tuple[int, str]] = []
    for source_id in sorted(selected_ids):
        try:
            prepared = _prepare_recitation(
                sync_client,
                source_id=source_id,
                localized=localized,
                expected=expected,
                verify_delivery=verify_delivery,
            )
            was_created, was_changed = _apply_recitation(
                environment=sync_client.environment.name,
                quran_version=quran_version,
                prepared=prepared,
                current=current,
            )
        except QuranFoundationError as exc:
            failures.append((source_id, str(exc)))
            QuranFoundationAyahRecitation.objects.filter(
                environment=sync_client.environment.name,
                source_id=source_id,
                quran_edition_version=quran_version,
            ).update(is_available=False, last_synced_at=current)
            continue
        created += int(was_created)
        updated += int(was_changed and not was_created)
        unchanged += int(not was_changed)
        delivery_samples += prepared.delivery_samples

    QuranFoundationAyahRecitation.objects.filter(
        environment=sync_client.environment.name,
        quran_edition_version=quran_version,
    ).exclude(source_id__in=selected_ids).update(is_available=False, last_synced_at=current)
    public = QuranFoundationAyahRecitation.objects.filter(
        environment=sync_client.environment.name,
        quran_edition_version=quran_version,
        is_available=True,
    )
    chapters = QuranFoundationAyahRecitationChapter.objects.filter(
        recitation__in=public,
    )
    return QuranFoundationAyahCatalogSyncSummary(
        selected=len(selected_ids),
        available=public.count(),
        created=created,
        updated=updated,
        unchanged=unchanged,
        chapters=chapters.count(),
        audio_files=sum(chapters.values_list("ayah_count", flat=True)),
        delivery_samples=delivery_samples,
        failures=tuple(failures),
    )


def _localized_catalogs(
    catalogs: dict[str, list[dict[str, Any]]],
) -> dict[str, dict[int, dict[str, Any]]]:
    result: dict[str, dict[int, dict[str, Any]]] = {}
    expected_ids: set[int] | None = None
    for language in ("en", "ar", "ru"):
        rows = catalogs.get(language)
        if rows is None:
            raise QuranFoundationError("Localized ayah recitation catalogs are incomplete.")
        by_id: dict[int, dict[str, Any]] = {}
        for row in rows:
            source_id = _positive_int(row.get("id"), "ayah recitation ID")
            if source_id in by_id:
                raise QuranFoundationError(
                    "Quran.Foundation returned duplicate ayah recitation IDs."
                )
            by_id[source_id] = row
        if expected_ids is None:
            expected_ids = set(by_id)
        elif set(by_id) != expected_ids:
            raise QuranFoundationError("Localized ayah recitation catalogs do not match.")
        result[language] = by_id
    if not expected_ids:
        raise QuranFoundationError("Quran.Foundation returned an empty ayah recitation catalog.")
    return result


def _expected_verse_keys(
    quran_version: QuranEditionVersion,
) -> dict[str, tuple[int, int]]:
    expected = {
        f"{surah_number}:{ayah_number}": (surah_number, ayah_number)
        for surah_number, ayah_number in Ayah.objects.filter(
            surah__edition_version=quran_version,
        ).values_list("surah__number", "number")
    }
    chapters = {surah for surah, _ayah in expected.values()}
    if len(chapters) != 114 or not expected:
        raise QuranFoundationError("The selected Quran edition is incomplete.")
    return expected


def _prepare_recitation(
    client: QuranFoundationAyahAudioSource,
    *,
    source_id: int,
    localized: dict[str, dict[int, dict[str, Any]]],
    expected: dict[str, tuple[int, int]],
    verify_delivery: bool,
) -> _PreparedAyahRecitation:
    payload = client.get_ayah_recitation_audio(source_id)
    raw_files = payload.get("audio_files")
    if not isinstance(raw_files, list):
        raise QuranFoundationError("Quran.Foundation returned no ayah audio files.")
    grouped: defaultdict[int, list[dict[str, object]]] = defaultdict(list)
    seen: set[str] = set()
    for row in raw_files:
        if not isinstance(row, dict):
            raise QuranFoundationError("Quran.Foundation returned an invalid ayah audio row.")
        verse_key = row.get("verse_key")
        if not isinstance(verse_key, str) or VERSE_KEY_PATTERN.fullmatch(verse_key) is None:
            raise QuranFoundationError("Quran.Foundation returned an invalid verse key.")
        identity = expected.get(verse_key)
        if identity is None or verse_key in seen:
            raise QuranFoundationError("Quran.Foundation returned duplicate or unrelated audio.")
        seen.add(verse_key)
        surah_number, ayah_number = identity
        grouped[surah_number].append(
            {
                "ayah_number": ayah_number,
                "verse_key": verse_key,
                "url": client.normalize_ayah_audio_url(row.get("url")),
            }
        )
    if seen != set(expected):
        raise QuranFoundationError("Quran.Foundation ayah recitation is incomplete.")
    chapters: list[tuple[int, tuple[dict[str, object], ...]]] = []
    for chapter_number in range(1, 115):
        files = sorted(grouped[chapter_number], key=_audio_file_ayah_number)
        chapters.append((chapter_number, tuple(files)))

    sample_count = 0
    if verify_delivery:
        sample_urls = {
            str(chapters[0][1][0]["url"]),
            str(chapters[-1][1][-1]["url"]),
        }
        for url in sorted(sample_urls):
            client.get_external_ayah_audio_size(url)
            sample_count += 1

    name_ar = _localized_name(localized["ar"][source_id])
    name_en = _localized_name(localized["en"][source_id])
    name_ru = _localized_name(localized["ru"][source_id])
    style = _style(localized["en"][source_id])
    checksum = hashlib.sha256(
        json.dumps(
            {
                "source_id": source_id,
                "name_ar": name_ar,
                "name_en": name_en,
                "name_ru": name_ru,
                "style": style,
                "chapters": chapters,
            },
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode()
    ).hexdigest()
    return _PreparedAyahRecitation(
        source_id=source_id,
        name_ar=name_ar,
        name_en=name_en,
        name_ru=name_ru,
        style=style,
        audio_file_count=len(seen),
        checksum=checksum,
        chapters=tuple(chapters),
        delivery_samples=sample_count,
    )


@transaction.atomic
def _apply_recitation(
    *,
    environment: str,
    quran_version: QuranEditionVersion,
    prepared: _PreparedAyahRecitation,
    current: datetime,
) -> tuple[bool, bool]:
    recitation = (
        QuranFoundationAyahRecitation.objects.select_for_update()
        .filter(
            environment=environment,
            source_id=prepared.source_id,
            quran_edition_version=quran_version,
        )
        .first()
    )
    if (
        recitation is not None
        and recitation.source_checksum_sha256 == prepared.checksum
        and recitation.chapters.count() == 114
    ):
        recitation.is_available = True
        recitation.last_synced_at = current
        recitation.save(update_fields=["is_available", "last_synced_at", "updated_at"])
        return False, False

    was_created = recitation is None
    recitation, _ = QuranFoundationAyahRecitation.objects.update_or_create(
        environment=environment,
        source_id=prepared.source_id,
        quran_edition_version=quran_version,
        defaults={
            "name_ar": prepared.name_ar,
            "name_en": prepared.name_en,
            "name_ru": prepared.name_ru,
            "style": prepared.style,
            "audio_file_count": prepared.audio_file_count,
            "source_checksum_sha256": prepared.checksum,
            "is_available": True,
            "last_synced_at": current,
        },
    )
    recitation.chapters.all().delete()
    QuranFoundationAyahRecitationChapter.objects.bulk_create(
        [
            QuranFoundationAyahRecitationChapter(
                recitation=recitation,
                chapter_number=chapter_number,
                ayah_count=len(files),
                audio_files=list(files),
            )
            for chapter_number, files in prepared.chapters
        ],
        batch_size=114,
    )
    return was_created, True


def _localized_name(row: dict[str, Any]) -> str:
    translated = row.get("translated_name")
    if isinstance(translated, dict):
        value = translated.get("name")
        if isinstance(value, str) and value.strip():
            return value.strip()
    value = row.get("reciter_name")
    if not isinstance(value, str) or not value.strip():
        raise QuranFoundationError("Quran.Foundation returned an invalid reciter name.")
    return value.strip()


def _audio_file_ayah_number(row: dict[str, object]) -> int:
    value = row.get("ayah_number")
    if not isinstance(value, int):
        raise QuranFoundationError("Prepared ayah audio has an invalid position.")
    return value


def _style(row: dict[str, Any]) -> str:
    value = row.get("style")
    if value is None:
        return ""
    if not isinstance(value, str):
        raise QuranFoundationError("Quran.Foundation returned an invalid recitation style.")
    return value.strip()


def _positive_int(value: object, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, str)):
        raise QuranFoundationError(f"Quran.Foundation returned an invalid {label}.")
    try:
        parsed = int(value)
    except ValueError as exc:
        raise QuranFoundationError(f"Quran.Foundation returned an invalid {label}.") from exc
    if parsed <= 0:
        raise QuranFoundationError(f"Quran.Foundation returned an invalid {label}.")
    return parsed


def _ensure_hafs_version(quran_version: QuranEditionVersion) -> None:
    riwayah = quran_version.edition.riwayah.casefold()
    if "hafs" not in riwayah and "ḥafṣ" not in riwayah:
        raise QuranFoundationError(
            "Quran.Foundation ayah recitations are not qira'ah-tagged; only a Hafs edition is safe."
        )
