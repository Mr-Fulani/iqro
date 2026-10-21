"""Resolves the course's formula references into text, translation and audio.

Formulas are referenced, not copied: a du'a from the published Hisn al-Muslim,
ayahs of the published Mushaf text, or an inline formula of the snapshot.
This runs when a version is compiled (import, publication), never per request,
and loads everything in a few bulk queries.
"""

from __future__ import annotations

import re
from collections import defaultdict
from collections.abc import Mapping, Sequence
from typing import Any

from django.conf import settings

from quran_backend.modules.audio.selectors import (
    ordered_renditions,
    public_recitations,
    public_surah_tracks,
    verified_audio_segments,
)
from quran_backend.modules.audio.serializers import audio_asset_payload, public_audio_url
from quran_backend.modules.dua.models import DuaAudioAsset, DuaCollection, DuaEntry
from quran_backend.modules.quran.models import Ayah, QuranEdition
from quran_backend.modules.salah.snapshot import audio_media_key
from quran_backend.modules.translations.models import AyahTranslation
from quran_backend.modules.translations.selectors import published_translation_editions

QURAN_EDITION_CODE = "madani-hafs"
_ARABIC_DIGITS = str.maketrans("0123456789", "٠١٢٣٤٥٦٧٨٩")


class SalahFormulaError(ValueError):
    pass


# Hisn al-Muslim wraps the recited words in ((…)) and adds notes outside them
# («ثلاث مرَّاتٍ», «- 3 раза», «(three times)»); a step's counter shows the count.
_COUNT_NOTE = re.compile(
    r"[\s\"”’'.]*(?:[-–—]\s*\d+\s*раз[а]?|\((?:\w+\s)?times\)+|\(\s*\d+\s*(?:раз[а]?|kez|defa)\s*\))[.\s]*$",  # noqa: RUF001
    re.IGNORECASE,
)


def clean_recited_arabic(text: str) -> str:
    """The words to recite: the ((…)) part when the source marks it."""
    match = re.match(r"\s*\(\((.+?)\)\)", text, re.DOTALL)
    return match.group(1).strip() if match else text.strip()


def clean_note(text: str) -> str:
    """A translation or transliteration without a trailing «N times» note."""
    cleaned = _COUNT_NOTE.sub("", text).strip(" \"”’'")  # noqa: RUF001
    if cleaned.startswith("(") and cleaned.count("(") > cleaned.count(")"):
        cleaned = cleaned[1:].lstrip()
    return cleaned


def _ayah_marker(number: int) -> str:
    return f"﴿{str(number).translate(_ARABIC_DIGITS)}﴾"  # noqa: RUF001


class FormulaResolver:
    """Loads every referenced source once; `resolve(language)` is then cheap."""

    def __init__(
        self, formulas: Sequence[Mapping[str, Any]], media: Mapping[str, Mapping[str, Any]]
    ):
        self._formulas = list(formulas)
        self._media = media
        self._dua: dict[tuple[str, int], dict[str, Any]] = {}
        self._quran_ayahs: dict[int, dict[int, str]] = {}
        self._quran_audio: dict[tuple[int, int, int], dict[str, Any]] = {}
        self._quran_translations: dict[str, dict[tuple[int, int], str]] = defaultdict(dict)
        self._load()

    # Loading

    def _load(self) -> None:
        dua_numbers: dict[str, set[int]] = defaultdict(set)
        quran_refs: list[tuple[int, int, int]] = []
        for formula in self._formulas:
            source = formula["source"]
            if source["kind"] == "dua":
                dua_numbers[source["collection"]].add(int(source["source_number"]))
            elif source["kind"] == "quran":
                quran_refs.append((source["surah"], source["ayah_from"], source["ayah_to"]))
        for collection, numbers in dua_numbers.items():
            self._load_dua(collection, numbers)
        if quran_refs:
            self._load_quran(quran_refs)

    def _load_dua(self, collection_slug: str, numbers: set[int]) -> None:
        collection = (
            DuaCollection.objects.filter(slug=collection_slug)
            .select_related("active_version")
            .first()
        )
        if collection is None or collection.active_version is None:
            raise SalahFormulaError(f"Нет опубликованного сборника дуа «{collection_slug}».")
        version = collection.active_version
        entries = (
            DuaEntry.objects.filter(collection_version=version, source_number__in=numbers)
            .prefetch_related("translations")
            .only("id", "source_number", "arabic_text", "repetitions")
        )
        audio: dict[int, str] = {}
        for asset in DuaAudioAsset.objects.filter(
            collection_version=version,
            source_number__in=numbers,
            is_active=True,
            language_code="ar",
        ).order_by("source_number", "id"):
            url = public_audio_url(asset.object_key) if asset.object_key else asset.external_url
            if url:
                audio.setdefault(asset.source_number, url)
        found = set()
        for entry in entries:
            found.add(entry.source_number)
            self._dua[(collection_slug, entry.source_number)] = {
                "arabic": entry.arabic_text,
                "repetitions": entry.repetitions,
                "translations": {
                    row.language_code: (row.meaning_text, row.transliteration)
                    for row in entry.translations.all()
                },
                "audio": audio.get(entry.source_number),
            }
        missing = sorted(numbers - found)
        if missing:
            raise SalahFormulaError(f"Сборник «{collection_slug}» не содержит записей {missing}.")

    def _load_quran(self, refs: list[tuple[int, int, int]]) -> None:
        edition = (
            QuranEdition.objects.filter(code=QURAN_EDITION_CODE)
            .select_related("active_version")
            .first()
        )
        if edition is None or edition.active_version is None:
            raise SalahFormulaError(f"Нет опубликованного издания Корана «{QURAN_EDITION_CODE}».")
        surahs = {surah for surah, _, _ in refs}
        for ayah in (
            Ayah.objects.filter(
                surah__edition_version=edition.active_version, surah__number__in=surahs
            )
            .select_related("surah")
            .only("number", "text_uthmani", "surah__number")
        ):
            self._quran_ayahs.setdefault(ayah.surah.number, {})[ayah.number] = ayah.text_uthmani
        for surah, start, end in refs:
            available = self._quran_ayahs.get(surah, {})
            if any(number not in available for number in range(start, end + 1)):
                raise SalahFormulaError(f"Нет аятов {surah}:{start}-{end} в опубликованном тексте.")
        self._load_quran_translations(surahs)
        for ref in refs:
            audio = self._quran_audio_for(*ref)
            if audio:
                self._quran_audio[ref] = audio

    def _load_quran_translations(self, surahs: set[int]) -> None:
        environment = settings.QURAN_QF_ENV
        preferred: Mapping[str, int] = getattr(settings, "SALAH_QURAN_TRANSLATIONS", {})
        for language in ("ru", "en", "tr"):
            editions = published_translation_editions(environment, language_code=language).order_by(
                "source_id"
            )
            if language in preferred:
                editions = editions.filter(source_id=preferred[language])
            edition = editions.first()
            if edition is None:
                continue
            for row in AyahTranslation.objects.filter(
                edition_version=edition.active_version, surah_number__in=surahs
            ).only("surah_number", "ayah_number", "text"):
                self._quran_translations[language][(row.surah_number, row.ayah_number)] = row.text

    def _quran_audio_for(self, surah: int, start: int, end: int) -> dict[str, Any] | None:
        """The first public recitation with verified timings for every ayah."""
        for recitation in public_recitations()[:20]:
            track = public_surah_tracks(recitation.id, surah).first()
            if track is None:
                continue
            segments = list(
                verified_audio_segments()
                .filter(track=track, ayah__number__gte=start, ayah__number__lte=end)
                .select_related("ayah")
                .only("start_ms", "end_ms", "ayah__number")
            )
            if len(segments) != end - start + 1:
                continue
            rendition = ordered_renditions().filter(track=track, is_default=True).first()
            if rendition is None:
                continue
            return {
                "url": audio_asset_payload(rendition)["url"],
                "start_ms": segments[0].start_ms,
                "end_ms": segments[-1].end_ms,
                "segments": [
                    {
                        "ayah": segment.ayah.number,
                        "start_ms": segment.start_ms,
                        "end_ms": segment.end_ms,
                    }
                    for segment in segments
                ],
            }
        return None

    # Resolution

    def resolve(self, language: str) -> dict[str, dict[str, Any]]:
        return {formula["id"]: self._resolve(formula, language) for formula in self._formulas}

    def _resolve(self, formula: Mapping[str, Any], language: str) -> dict[str, Any]:
        result = self._resolve_one(formula, language)
        # A recording uploaded for the course replaces the source's one.
        own = self._media.get(audio_media_key(formula["source"], language) or "")
        if own:
            result["audio"] = {"url": own["url"]}
        return result

    def _resolve_one(self, formula: Mapping[str, Any], language: str) -> dict[str, Any]:
        source = formula["source"]
        kind = source["kind"]
        if kind == "dua":
            dua = self._dua[(source["collection"], int(source["source_number"]))]
            meaning, transliteration = dua["translations"].get(language, ("", ""))
            # The snapshot may override any text; references and audio stay.
            override = source.get("translations", {}).get(language, {})
            meaning = override.get("meaning") or clean_note(meaning)
            transliteration = override.get("transliteration") or clean_note(transliteration)
            result: dict[str, Any] = {
                "arabic": source.get("arabic") or clean_recited_arabic(dua["arabic"]),
                "translation": meaning,
                "repetitions": dua["repetitions"],
                "source": {
                    "kind": "dua",
                    "collection": source["collection"],
                    "source_number": int(source["source_number"]),
                },
            }
            if transliteration:
                result["transliteration"] = transliteration
            if dua["audio"]:
                result["audio"] = {"url": dua["audio"]}
            return result
        if kind == "quran":
            surah, start, end = source["surah"], source["ayah_from"], source["ayah_to"]
            ayahs = self._quran_ayahs[surah]
            translations = self._quran_translations.get(language, {})
            result = {
                "arabic": " ".join(f"{ayahs[n]} {_ayah_marker(n)}" for n in range(start, end + 1)),
                "translation": " ".join(
                    translations[(surah, n)]
                    for n in range(start, end + 1)
                    if (surah, n) in translations
                ),
                "repetitions": 1,
                "source": {"kind": "quran", "surah": surah, "ayah_from": start, "ayah_to": end},
            }
            audio = self._quran_audio.get((surah, start, end))
            if audio:
                result["audio"] = audio
            return result
        translations = source.get("translations", {}).get(language, {})
        result = {
            "arabic": source["arabic"],
            "translation": translations.get("meaning", ""),
            "repetitions": int(source.get("repetitions", 1)),
            "source": {"kind": "inline"},
        }
        if translations.get("transliteration"):
            result["transliteration"] = translations["transliteration"]
        return result
