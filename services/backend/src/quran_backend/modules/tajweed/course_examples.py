"""Lesson examples picked from the tajweed markup of the whole Quran.

An example is one ayah with every word and every place of the lesson's target.
Order: the lesson's own ayahs, then short well-known ones (al-Fatiha, juz ʿAmma,
Ayat al-Kursi), then the rest from the shortest. The order is fixed, so an
offset pages through it («show more examples»).
"""

from __future__ import annotations

from collections.abc import Iterator, Mapping, Sequence
from typing import Any

from django.db.models import Case, IntegerField, Q, QuerySet, Value, When
from django.db.models.functions import Length

from quran_backend.modules.tajweed.course_markers import (
    DERIVED_TARGETS,
    Occurrence,
    occurrences,
    parse_course_words,
)
from quran_backend.modules.tajweed.markup import TajweedWord
from quran_backend.modules.tajweed.models import AyahTajweed

MAX_LIMIT = 8
MAX_OFFSET = 64
DEFAULT_LIMIT = 4
WELL_KNOWN_SURAHS = (1, *range(78, 115))
WELL_KNOWN_AYAHS = ("2:255", "2:285", "2:286")
_FIELDS = ("verse_key", "surah_number", "ayah_number", "page_number", "source_text", "words")


def target_filter(target: str) -> Q:
    """Ayahs that may hold the target, from the markup text; parsing decides."""
    rule = DERIVED_TARGETS.get(target, target)
    if rule is not None:
        return Q(source_text__contains=f"class={rule}>")
    if target == "izhar":
        return Q(source_text__contains="نْ") | Q(source_text__regex="[ً-ٍ]")
    if target == "izhar_shafawi":
        return Q(source_text__contains="مْ")
    return Q(source_text__contains="لْ")  # laam_qamariyah


def course_example(row: Mapping[str, Any], target: str) -> dict[str, Any] | None:
    """The ayah with all its words and the target's places, or None when it has none."""
    words = parse_course_words(row["verse_key"], row["source_text"], row["words"])
    if words is None:
        return None
    found = occurrences(words, target)
    if not found:
        return None
    return example_payload(row, words, found)


def example_payload(
    row: Mapping[str, Any], words: Sequence[TajweedWord], found: Sequence[Occurrence]
) -> dict[str, Any]:
    return {
        "verse_key": row["verse_key"],
        "surah_number": row["surah_number"],
        "ayah_number": row["ayah_number"],
        "page_number": row["page_number"],
        "words": [{"position": word.position, "text": word.text} for word in words],
        "occurrences": [occurrence.as_dict() for occurrence in found],
    }


def _ordered(
    ayahs: QuerySet[AyahTajweed], target: str, preferred: Sequence[str]
) -> Iterator[dict[str, Any]]:
    by_key = {
        row["verse_key"]: row
        for row in ayahs.filter(verse_key__in=list(preferred)).values(*_FIELDS)
    }
    for key in preferred:
        if key in by_key:
            yield by_key[key]
    rest = (
        ayahs.filter(target_filter(target))
        .exclude(verse_key__in=list(preferred))
        .annotate(
            tier=Case(
                When(
                    Q(surah_number__in=WELL_KNOWN_SURAHS) | Q(verse_key__in=WELL_KNOWN_AYAHS),
                    then=Value(0),
                ),
                default=Value(1),
                output_field=IntegerField(),
            ),
            length=Length("source_text"),
        )
        .order_by("tier", "length", "surah_number", "ayah_number")
        .values(*_FIELDS)
    )
    yield from rest.iterator(chunk_size=64)


def lesson_examples(
    ayahs: QuerySet[AyahTajweed],
    *,
    target: str,
    preferred: Sequence[str],
    offset: int,
    limit: int,
) -> dict[str, Any]:
    """Examples `offset`…`offset + limit` in the fixed order, and where the next page starts."""
    examples: list[dict[str, Any]] = []
    seen = 0
    has_more = False
    for row in _ordered(ayahs, target, preferred):
        example = course_example(row, target)
        if example is None:
            continue
        if seen >= offset + limit:
            has_more = True
            break
        if seen >= offset:
            examples.append(example)
        seen += 1
    next_offset = offset + limit if has_more and offset + limit <= MAX_OFFSET else None
    return {"target": target, "offset": offset, "next_offset": next_offset, "examples": examples}
