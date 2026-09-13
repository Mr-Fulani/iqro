"""Import canonical text and logical navigation, without PDF or image assets."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

from django.conf import settings
from django.db import transaction

from quran_backend.modules.quran.corpus_metadata import CORPUS_SHA256, RUSSIAN_SURAH_NAMES
from quran_backend.modules.quran.importer import (
    _create_ayahs,
    _create_hizb,
    _create_juz,
    _create_rub_el_hizb,
    _create_surahs,
)
from quran_backend.modules.quran.models import (
    Ayah,
    AyahPageMapping,
    MushafPage,
    PublicationStatus,
    QuranEdition,
    QuranEditionVersion,
    QuranFoundationMushaf,
    SourceManifest,
)
from quran_backend.modules.quran.publication import (
    _validate_complete_version,
    publish_quran_version,
)


def require(condition: object, message: str) -> None:
    if not condition:
        raise ValueError(message)


def corpus_rows(path: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    raw = path.read_bytes()
    require(hashlib.sha256(raw).hexdigest() == CORPUS_SHA256, "Canonical corpus checksum differs")
    data = json.loads(raw)
    surahs: list[dict[str, Any]] = []
    ayahs: list[dict[str, Any]] = []
    for source in data["surahs"]:
        number = source["number"]
        require(type(number) is int and 1 <= number <= 114, "Invalid surah number")
        surahs.append(
            {
                "number": number,
                "name_ar": source["name_arabic"],
                "name_en": source["name_transliteration"],
                "name_ru": RUSSIAN_SURAH_NAMES[number - 1],
                "revelation_type": source["revelation"]["type"].lower(),
                "ayah_count": len(source["ayahs"]),
            }
        )
        ayahs.extend(
            {
                "surah": number,
                "number": verse["number"],
                "text_uthmani": verse["text"],
                "juz": verse["juz"],
                "hizb": verse["hizb"],
                "rub_el_hizb": verse["hizb_quarter"],
            }
            for verse in source["ayahs"]
        )
        require(
            [v["number"] for v in source["ayahs"]] == list(range(1, len(source["ayahs"]) + 1)),
            "Canonical ayah sequence differs",
        )
    require(
        [s["number"] for s in surahs] == list(range(1, 115)) and len(ayahs) == 6236,
        "Canonical corpus is incomplete",
    )
    return surahs, ayahs


def page_mapping(
    source: QuranFoundationMushaf, ayahs: list[dict[str, Any]]
) -> dict[int, set[tuple[int, int]]]:
    require(
        source.source_id == 5 and source.pages_count == 604 and source.qirat_name == "Hafs",
        "Canonical navigation requires complete QF KFGQPC Hafs source 5",
    )
    known = {(v["surah"], v["number"]) for v in ayahs}
    order = {key: index for index, key in enumerate(sorted(known))}
    result = {}
    for page in source.cached_pages.order_by("page_number"):
        keys = set()
        for surah, ranges in page.verse_mapping.items():
            for interval in ranges.split(","):
                bounds = [int(value) for value in interval.strip().split("-")]
                require(
                    1 <= len(bounds) <= 2 and 1 <= bounds[0] <= bounds[-1] <= 286,
                    "Invalid verse range",
                )
                for number in range(bounds[0], bounds[-1] + 1):
                    key = (int(surah), number)
                    require(key in known and key not in keys, "Unknown or duplicate page verse")
                    keys.add(key)
        require(keys, "Empty canonical page")
        positions = sorted(order[key] for key in keys)
        require(positions == list(range(positions[0], positions[-1] + 1)), "Non-contiguous page")
        result[page.page_number] = keys
    require(list(result) == list(range(1, 605)), "Canonical page coverage is incomplete")
    require(set().union(*result.values()) == known, "Canonical verse coverage is incomplete")
    previous = -1
    for keys in result.values():
        first, last = min(order[k] for k in keys), max(order[k] for k in keys)
        require(first in {previous, previous + 1} and last >= previous, "Page order differs")
        previous = last
    return result


def divisions(ayahs: list[dict[str, Any]], field: str, count: int) -> list[dict[str, Any]]:
    numbers = [v[field] for v in ayahs]
    require(
        numbers == sorted(numbers) and set(numbers) == set(range(1, count + 1)),
        f"Incomplete {field} boundaries",
    )
    result = []
    for number in range(1, count + 1):
        members = [v for v in ayahs if v[field] == number]
        first, last = members[0], members[-1]
        result.append(
            {
                "number": number,
                "start": {"surah": first["surah"], "ayah": first["number"]},
                "end": {"surah": last["surah"], "ayah": last["number"]},
            }
        )
    return result


@transaction.atomic
def import_canonical_corpus(path: Path) -> QuranEditionVersion:
    surahs, ayahs = corpus_rows(path)
    source = QuranFoundationMushaf.objects.select_for_update().get(
        environment=settings.QURAN_QF_ENV,
        source_id=5,
        is_available=True,
    )
    mapping = page_mapping(source, ayahs)
    juz, hizb, rub = (
        divisions(ayahs, field, count)
        for field, count in (("juz", 30), ("hizb", 60), ("rub_el_hizb", 240))
    )
    mapping_sha = hashlib.sha256(
        json.dumps(
            {number: sorted(keys) for number, keys in mapping.items()},
            sort_keys=True,
        ).encode()
    ).hexdigest()
    checksum = hashlib.sha256(f"{CORPUS_SHA256}:{mapping_sha}".encode()).hexdigest()
    edition, _ = QuranEdition.objects.get_or_create(
        code="madani-hafs",
        defaults={
            "name_ar": "القرآن الكريم",
            "name_en": "Quran · Hafs",
            "name_ru": "Коран · Хафс",
            "riwayah": "Hafs 'an Asim",
            "source_name": "Tanzil",
            "source_url": "https://tanzil.net",
            "license_name": "CC BY 3.0",
            "license_url": "https://tanzil.net/docs/Text_License",
        },
    )
    edition = QuranEdition.objects.select_for_update().get(pk=edition.pk)
    if edition.active_version_id is not None:
        # Never replace canonical UUIDs, user references or a differing active corpus.
        version = edition.active_version
        assert version is not None
        actual = list(
            Ayah.objects.filter(surah__edition_version=version)
            .order_by("surah__number", "number")
            .values_list(
                "surah__number",
                "number",
                "text_uthmani",
                "juz_number",
                "hizb_number",
                "rub_el_hizb_number",
            )
        )
        expected = [
            (a["surah"], a["number"], a["text_uthmani"], a["juz"], a["hizb"], a["rub_el_hizb"])
            for a in ayahs
        ]
        require(
            version.status == PublicationStatus.PUBLISHED and actual == expected,
            "Existing canonical corpus differs; explicit reviewed migration is required",
        )
        existing = {
            (p, s, a)
            for p, s, a in AyahPageMapping.objects.filter(
                page__edition_version=version,
            ).values_list("page__number", "ayah__surah__number", "ayah__number")
        }
        require(
            existing == {(p, s, a) for p, keys in mapping.items() for s, a in keys},
            "Existing page mapping differs; reading positions were preserved",
        )
        _validate_complete_version(version)
        return version
    version = QuranEditionVersion.objects.create(
        edition=edition,
        version=f"text-v1-{checksum[:16]}",
        checksum_sha256=checksum,
        page_count=604,
        surah_count=114,
        juz_count=30,
        hizb_count=60,
        rub_el_hizb_count=240,
    )
    references = _create_ayahs(_create_surahs(version, surahs), ayahs)
    MushafPage.objects.bulk_create(
        [MushafPage(edition_version=version, number=number) for number in mapping]
    )
    pages = {p.number: p for p in version.pages.all()}
    AyahPageMapping.objects.bulk_create(
        [
            AyahPageMapping(page=pages[number], ayah=references[key])
            for number, keys in mapping.items()
            for key in sorted(keys)
        ],
        batch_size=1000,
    )
    _create_juz(version, references, juz)
    hizbs = _create_hizb(version, references, hizb)
    _create_rub_el_hizb(version, references, hizbs, rub)
    SourceManifest.objects.create(
        edition_version=version,
        source_version="tanzil-qf-navigation-v1",
        checksum_sha256=checksum,
        expected_surahs=114,
        expected_ayahs=6236,
        expected_pages=604,
        payload={
            "kind": "canonical-text",
            "corpus_sha256": CORPUS_SHA256,
            "mapping_sha256": mapping_sha,
            "qf_source_sha256": source.source_checksum_sha256,
        },
    )
    publish_quran_version(edition_code=edition.code, version_value=version.version, activate=True)
    return version
