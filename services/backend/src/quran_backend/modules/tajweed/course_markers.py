# ruff: noqa: RUF001
"""Where a course target occurs in an ayah.

A target is what one lesson teaches. Most targets are Quran.Foundation classes
and come straight from the markup. Five are not QF classes, so they are read
from the letters of the same QF text (docs/tajweed/course.md, «Цели уроков»):

- izhar: noon with sukun or tanween before a throat letter;
- izhar_shafawi: meem with sukun before a letter other than meem and beh;
- laam_qamariyah: the lam of the article with sukun;
- madd_muttasil / madd_munfasil: QF `madda_obligatory` split by where the hamza is.

QF marks the noon, meem and lam of these cases with an explicit sukun and never
marks them with a class, so the derived targets do not overlap the QF ones.
"""

from __future__ import annotations

import unicodedata
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from quran_backend.modules.tajweed.markup import (
    TajweedMarkupError,
    TajweedWord,
    parse_tajweed_verse,
)
from quran_backend.modules.tajweed.rules import RULES_BY_CODE

SUKUN = "ْ"
TANWEEN = frozenset("ًٌٍ")
HAMZA_ABOVE = "ٔ"
TATWEEL = "ـ"
ALEF_WASLA = "ٱ"
HAMZA_LETTERS = frozenset("ءأإؤئآ")
THROAT_LETTERS = HAMZA_LETTERS | frozenset("هعحغخ")
# Fathatan is written before a final alef (or alef maksura) that is not read.
TANWEEN_SEATS = frozenset("اى")
# «يَـٰٓأَيُّهَا», «هَـٰٓؤُلَآءِ»: a vocative or attention particle written into the
# next word. The madd is separated (munfasil hukmi) although the hamza is in the word.
JOINED_PARTICLES = (("ي",), ("ه",), ("و", "ي"), ("و", "ه"), ("ف", "ه"))

# Derived target -> the QF class it refines (None: read from letters only).
DERIVED_TARGETS: Mapping[str, str | None] = {
    "izhar": None,
    "izhar_shafawi": None,
    "laam_qamariyah": None,
    "madd_muttasil": "madda_obligatory",
    "madd_munfasil": "madda_obligatory",
}
TARGETS = frozenset(RULES_BY_CODE) | frozenset(DERIVED_TARGETS)


@dataclass(frozen=True, slots=True)
class OccurrencePart:
    position: int
    start: int
    end: int

    def as_dict(self) -> dict[str, int]:
        return {"position": self.position, "start": self.start, "end": self.end}


@dataclass(frozen=True, slots=True)
class Occurrence:
    """One place of a target: letters of one word, or of two when it crosses words."""

    parts: tuple[OccurrencePart, ...]
    variant: str = ""

    @property
    def positions(self) -> tuple[int, ...]:
        return tuple(part.position for part in self.parts)

    def as_dict(self) -> dict[str, Any]:
        result: dict[str, Any] = {"parts": [part.as_dict() for part in self.parts]}
        if self.variant:
            result["variant"] = self.variant
        return result


@dataclass(frozen=True, slots=True)
class _Letter:
    start: int
    end: int
    base: str
    marks: str


def is_mark(char: str) -> bool:
    return unicodedata.category(char) in {"Mn", "Cf"}


def letters(text: str) -> list[_Letter]:
    """Base letters with the marks that follow them; tatweel + hamza above is a hamza."""
    result: list[_Letter] = []
    index = 0
    while index < len(text):
        if is_mark(text[index]):
            index += 1
            continue
        end = index + 1
        while end < len(text) and is_mark(text[end]):
            end += 1
        marks = text[index + 1 : end]
        base = "ء" if text[index] == TATWEEL and HAMZA_ABOVE in marks else text[index]
        result.append(_Letter(index, end, base, marks))
        index = end
    return result


def parse_course_words(
    verse_key: str, source_text: str, stored_words: Sequence[Mapping[str, Any]]
) -> tuple[TajweedWord, ...] | None:
    """Every word of the ayah, or None when it cannot be trusted.

    The stored row keeps only words with rules, bound to QF word positions with
    the Mushaf word list. Without that list a text token is a word, which is
    wrong for a few ayahs spaced differently in the two QF texts; such an ayah
    no longer matches its stored words and is left out of the course.
    """
    try:
        words = parse_tajweed_verse(verse_key, source_text)
    except TajweedMarkupError:
        return None
    for stored in stored_words:
        position = int(stored.get("position", 0))
        if not 1 <= position <= len(words):
            return None
        word = words[position - 1]
        if word.text != stored.get("text") or [
            fragment.as_dict() for fragment in word.fragments
        ] != list(stored.get("rules", [])):
            return None
    return words


def occurrences(words: Sequence[TajweedWord], target: str) -> list[Occurrence]:
    """The target's places in reading order."""
    if target in RULES_BY_CODE:
        return _fragment_occurrences(words, target)
    if target in {"madd_muttasil", "madd_munfasil"}:
        return [
            occurrence
            for occurrence in _fragment_occurrences(words, "madda_obligatory")
            if _madd_kind(words, occurrence) == target
        ]
    if target == "izhar":
        return _izhar(words)
    if target == "izhar_shafawi":
        return _izhar_shafawi(words)
    if target == "laam_qamariyah":
        return _laam_qamariyah(words)
    raise ValueError(f"Unknown tajweed course target {target!r}.")


def present_targets(words: Sequence[TajweedWord], targets: Iterable[str]) -> list[str]:
    return [target for target in targets if occurrences(words, target)]


def _fragment_occurrences(words: Sequence[TajweedWord], code: str) -> list[Occurrence]:
    """QF fragments of one class; a fragment that continues into the next word is one place."""
    result: list[Occurrence] = []
    for index, word in enumerate(words):
        for fragment in word.fragments:
            if fragment.code != code or fragment.joins_previous:
                continue
            parts = [OccurrencePart(word.position, fragment.start, fragment.end)]
            current, following = fragment, index + 1
            while current.joins_next and following < len(words):
                continued = next(
                    (
                        item
                        for item in words[following].fragments
                        if item.code == code and item.joins_previous
                    ),
                    None,
                )
                if continued is None:
                    break
                parts.append(
                    OccurrencePart(words[following].position, continued.start, continued.end)
                )
                current, following = continued, following + 1
            result.append(Occurrence(tuple(parts), fragment.variant))
    return result


def _madd_kind(words: Sequence[TajweedWord], occurrence: Occurrence) -> str:
    """Connected when the hamza follows in the same word, separated when it starts the next."""
    if len(occurrence.parts) > 1 or occurrence.variant == "silah_kubra":
        return "madd_munfasil"
    part = occurrence.parts[0]
    text = words[part.position - 1].text
    before = tuple(item.base for item in letters(text[: part.start]) if item.base != TATWEEL)
    following = [item.base for item in letters(text[part.end :]) if item.base != TATWEEL]
    # A final alef after a waw of the plural is not read («ءَامَنُوٓاْ»).
    if following == ["ا"]:
        following = []
    if following and following[0] in HAMZA_LETTERS and before not in JOINED_PARTICLES:
        return "madd_muttasil"
    return "madd_munfasil"


def _next_letter(
    words: Sequence[TajweedWord], index: int, letter_index: int
) -> tuple[int, _Letter] | None:
    """The letter read after this one: later in the word or the first of the next word."""
    word_letters = letters(words[index].text)
    if letter_index + 1 < len(word_letters):
        return index, word_letters[letter_index + 1]
    if index + 1 < len(words):
        following = letters(words[index + 1].text)
        if following:
            return index + 1, following[0]
    return None


def _with_next(
    words: Sequence[TajweedWord], index: int, letter: _Letter, following: tuple[int, _Letter]
) -> Occurrence:
    """The letter that carries the rule and the letter that causes it."""
    next_index, next_letter = following
    if next_index == index:
        return Occurrence((OccurrencePart(words[index].position, letter.start, next_letter.end),))
    return Occurrence(
        (
            OccurrencePart(words[index].position, letter.start, letter.end),
            OccurrencePart(words[next_index].position, next_letter.start, next_letter.end),
        )
    )


def _izhar(words: Sequence[TajweedWord]) -> list[Occurrence]:
    result: list[Occurrence] = []
    for index, word in enumerate(words):
        word_letters = letters(word.text)
        for letter_index, letter in enumerate(word_letters):
            if letter.base == "ن" and SUKUN in letter.marks:
                following = _next_letter(words, index, letter_index)
            elif TANWEEN.intersection(letter.marks) and all(
                item.base in TANWEEN_SEATS for item in word_letters[letter_index + 1 :]
            ):
                # Tanween is a noon at the end of the word: only the next word can follow.
                following = _next_letter(words, index, len(word_letters) - 1)
                if following is not None and following[0] == index:
                    following = None
            else:
                continue
            if following is not None and following[1].base in THROAT_LETTERS:
                result.append(_with_next(words, index, letter, following))
    return result


def _izhar_shafawi(words: Sequence[TajweedWord]) -> list[Occurrence]:
    result: list[Occurrence] = []
    for index, word in enumerate(words):
        for letter_index, letter in enumerate(letters(word.text)):
            if letter.base != "م" or SUKUN not in letter.marks:
                continue
            following = _next_letter(words, index, letter_index)
            if following is not None and following[1].base not in {"م", "ب"}:
                result.append(_with_next(words, index, letter, following))
    return result


def _laam_qamariyah(words: Sequence[TajweedWord]) -> list[Occurrence]:
    result: list[Occurrence] = []
    for word in words:
        word_letters = letters(word.text)
        for letter_index, letter in enumerate(word_letters[1:], start=1):
            # QF classes the lam of «ٱلْتَقَى» (a verb, not the article) as laam_shamsiyah.
            if (
                letter.base == "ل"
                and SUKUN in letter.marks
                and word_letters[letter_index - 1].base == ALEF_WASLA
                and not any(item.start <= letter.start < item.end for item in word.fragments)
            ):
                result.append(
                    Occurrence((OccurrencePart(word.position, letter.start, letter.end),))
                )
    return result
