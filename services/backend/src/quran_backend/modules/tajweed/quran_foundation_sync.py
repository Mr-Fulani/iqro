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
)
from quran_backend.modules.quran.models import Ayah, PublicationStatus, QuranFoundationMushaf
from quran_backend.modules.tajweed.markup import (
    ARABIC_INDIC_DIGITS,
    TajweedMarkupError,
    has_letter,
    parse_tajweed_verse,
)
from quran_backend.modules.tajweed.models import (
    AyahTajweed,
    TajweedEdition,
    TajweedEditionVersion,
    TajweedPublicationStatus,
)
from quran_backend.modules.tajweed.rules import RULE_ORDER

PROVIDER = "quran_foundation"
EDITION_CODE = "uthmani-tajweed"
EDITION_NAME = "Quran.Foundation Uthmani Tajweed"
SCHEMA_VERSION = "qf-uthmani-tajweed-v1"
SOURCE_NAME = "Quran.Foundation Content API"
SOURCE_URL = (
    "https://api-docs.quran.foundation/docs/content_apis_versioned/4.0.0/uthmani-tajweed-script/"
)
LICENSE_NAME = "Quran.Foundation Developer Terms"
LICENSE_URL = "https://api-docs.quran.foundation/legal/developer-terms/"
ATTRIBUTION = "Quran data provided by Quran Foundation."
V4_MUSHAF_ID = 19  # QCF V4 tajweed page fonts: word positions and page numbers
UNICODE_MUSHAF_ID = 4  # the same QF word ids as Unicode text, for word matching


class QuranFoundationTajweedSource(Protocol):
    environment: QuranFoundationEnvironment

    def get_uthmani_tajweed(self) -> list[dict[str, Any]]: ...


@dataclass(frozen=True, slots=True)
class VerseWords:
    page_number: int
    words: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class TajweedSyncSummary:
    ayahs: int
    words: int
    fragments: int
    changed: bool
    checksum_sha256: str


def sync_quran_foundation_tajweed(
    *,
    client: QuranFoundationTajweedSource | None = None,
    verse_words: dict[str, VerseWords] | None = None,
    mushaf_checksum: str = "",
    dry_run: bool = False,
    now: datetime | None = None,
) -> TajweedSyncSummary:
    """Import QF tajweed markup bound to QF word positions, or fail without changes."""
    sync_client = client or QuranFoundationClient.from_environment()
    environment = sync_client.environment.name
    if verse_words is None:
        verse_words, mushaf_checksum = quran_foundation_verse_words(environment)
    rows = normalize_tajweed_verses(sync_client.get_uthmani_tajweed(), verse_words)
    checksum = hashlib.sha256(
        json.dumps(
            {"schema": SCHEMA_VERSION, "mushaf": mushaf_checksum, "ayahs": rows},
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode()
    ).hexdigest()
    words = sum(len(row["words"]) for row in rows)
    fragments = sum(len(word["rules"]) for row in rows for word in row["words"])
    changed = False
    if not dry_run:
        changed = _publish(
            environment=environment,
            rows=rows,
            checksum=checksum,
            mushaf_checksum=mushaf_checksum,
            words=words,
            fragments=fragments,
            current=now or timezone.now(),
        )
    return TajweedSyncSummary(
        ayahs=len(rows),
        words=words,
        fragments=fragments,
        changed=changed,
        checksum_sha256=checksum,
    )


def quran_foundation_verse_words(environment: str) -> tuple[dict[str, VerseWords], str]:
    """Return each verse's QF words (as in the V4 font) and its V4 page number."""
    mushafs = {
        mushaf.source_id: mushaf
        for mushaf in QuranFoundationMushaf.objects.filter(
            environment=environment,
            source_id__in=(V4_MUSHAF_ID, UNICODE_MUSHAF_ID),
            is_available=True,
        )
    }
    if set(mushafs) != {V4_MUSHAF_ID, UNICODE_MUSHAF_ID}:
        raise QuranFoundationError(
            "Synchronize Quran.Foundation Mushafs 19 and 4 before importing tajweed."
        )
    v4_words = _verse_word_ids(mushafs[V4_MUSHAF_ID])
    unicode_words = _verse_word_ids(mushafs[UNICODE_MUSHAF_ID])
    if set(v4_words) != set(unicode_words) or set(v4_words) != _published_verse_keys():
        raise QuranFoundationError(
            "Quran.Foundation Mushaf verses do not match the published Quran."
        )

    result: dict[str, VerseWords] = {}
    for verse_key, unicode_rows in unicode_words.items():
        page_numbers = {page for page, _, _ in v4_words[verse_key]}
        if len(page_numbers) != 1:
            raise QuranFoundationError(f"Verse {verse_key} spans several V4 pages.")
        texts = [text for _, _, text in unicode_rows]
        # QF labels the ayah number of 2:181 as a word in both Mushafs; only a
        # final number equal to the verse number is accepted as that marker.
        if texts and texts[-1].translate(ARABIC_INDIC_DIGITS) == verse_key.partition(":")[2]:
            texts.pop()
        if not texts or not all(has_letter(text) for text in texts):
            raise QuranFoundationError(f"Verse {verse_key} has a word without letters.")
        if [row[1] for row in v4_words[verse_key]] != [row[1] for row in unicode_rows]:
            raise QuranFoundationError(f"Verse {verse_key} has different QF word positions.")
        result[verse_key] = VerseWords(page_number=page_numbers.pop(), words=tuple(texts))
    checksum = hashlib.sha256(
        f"{mushafs[V4_MUSHAF_ID].source_checksum_sha256}:"
        f"{mushafs[UNICODE_MUSHAF_ID].source_checksum_sha256}".encode()
    ).hexdigest()
    return result, checksum


def _verse_word_ids(mushaf: QuranFoundationMushaf) -> dict[str, list[tuple[int, int, str]]]:
    verses: dict[str, dict[int, tuple[int, int, str]]] = {}
    for page_number, words in mushaf.cached_pages.order_by("page_number").values_list(
        "page_number", "words"
    ):
        for word in words:
            if word.get("char_type_name") != "word":
                continue
            verse_key = word.get("verse_key")
            position = word.get("position_in_verse")
            if not isinstance(verse_key, str) or not isinstance(position, int):
                raise QuranFoundationError("A Quran.Foundation Mushaf word has no position.")
            positions = verses.setdefault(verse_key, {})
            if position in positions:
                raise QuranFoundationError(f"Duplicate word position in {verse_key}.")
            positions[position] = (page_number, int(word.get("word_id") or 0), str(word["text"]))
    result: dict[str, list[tuple[int, int, str]]] = {}
    for verse_key, positions in verses.items():
        if sorted(positions) != list(range(1, len(positions) + 1)):
            raise QuranFoundationError(f"Word positions of {verse_key} are not contiguous.")
        result[verse_key] = [positions[position] for position in sorted(positions)]
    return result


def normalize_tajweed_verses(
    verses: list[dict[str, Any]],
    verse_words: dict[str, VerseWords],
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    seen: set[str] = set()
    for verse in verses:
        verse_key = verse.get("verse_key")
        markup = verse.get("text_uthmani_tajweed")
        if not isinstance(verse_key, str) or not isinstance(markup, str):
            raise QuranFoundationError("Quran.Foundation returned an invalid tajweed verse.")
        if verse_key in seen:
            raise QuranFoundationError(f"Quran.Foundation returned {verse_key} twice.")
        seen.add(verse_key)
        layout = verse_words.get(verse_key)
        if layout is None:
            raise QuranFoundationError(f"Quran.Foundation returned an unknown verse {verse_key}.")
        try:
            words = parse_tajweed_verse(verse_key, markup, layout.words)
        except TajweedMarkupError as exc:
            raise QuranFoundationError(f"Tajweed markup rejected: {exc}") from exc
        surah, ayah = (int(part) for part in verse_key.split(":"))
        ruled = [word.as_dict() for word in words if word.fragments]
        codes = {fragment.code for word in words for fragment in word.fragments}
        rows.append(
            {
                "verse_key": verse_key,
                "surah_number": surah,
                "ayah_number": ayah,
                "page_number": layout.page_number,
                "source_text": markup,
                "words": ruled,
                "rules": sorted(codes, key=RULE_ORDER.__getitem__),
            }
        )
    if seen != set(verse_words):
        raise QuranFoundationError(
            f"Quran.Foundation returned {len(seen)} tajweed verses, expected {len(verse_words)}."
        )
    rows.sort(key=lambda row: (row["surah_number"], row["ayah_number"]))
    return rows


@transaction.atomic
def _publish(  # noqa: PLR0913
    *,
    environment: str,
    rows: list[dict[str, Any]],
    checksum: str,
    mushaf_checksum: str,
    words: int,
    fragments: int,
    current: datetime,
) -> bool:
    edition, _ = TajweedEdition.objects.select_for_update().update_or_create(
        environment=environment,
        provider=PROVIDER,
        code=EDITION_CODE,
        defaults={
            "name": EDITION_NAME,
            "source_name": SOURCE_NAME,
            "source_url": SOURCE_URL,
            "license_name": LICENSE_NAME,
            "license_url": LICENSE_URL,
            "attribution": ATTRIBUTION,
        },
    )
    active = edition.active_version
    if active is not None and active.checksum_sha256 == checksum:
        return False
    version = TajweedEditionVersion.objects.filter(
        edition=edition, checksum_sha256=checksum
    ).first()
    if version is None:
        version = TajweedEditionVersion.objects.create(
            edition=edition,
            checksum_sha256=checksum,
            schema_version=SCHEMA_VERSION,
            status=TajweedPublicationStatus.PUBLISHED,
            ayah_count=len(rows),
            word_count=words,
            fragment_count=fragments,
            mushaf_source_checksum_sha256=mushaf_checksum,
            published_at=current,
        )
        AyahTajweed.objects.bulk_create(
            [AyahTajweed(edition_version=version, **row) for row in rows],
            batch_size=500,
        )
    elif version.status != TajweedPublicationStatus.PUBLISHED:
        raise QuranFoundationError("An existing tajweed version is not published.")
    edition.active_version = version
    edition.save(update_fields=["active_version", "updated_at"])
    return True


def _published_verse_keys() -> set[str]:
    coordinates = Ayah.objects.filter(
        surah__edition_version__status=PublicationStatus.PUBLISHED,
        surah__edition_version__edition__active_version=models.F("surah__edition_version"),
    ).values_list("surah__number", "number")
    return {f"{surah}:{ayah}" for surah, ayah in coordinates}
