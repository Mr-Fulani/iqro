"""Strict parser for Quran.Foundation `text_uthmani_tajweed` markup.

A verse is plain Uthmani text with `<tajweed class=...>` spans and a trailing
`<span class=end>N</span>`. Tokens are separated by U+0020; a span may cross one
word boundary (idgham, ikhfa, iqlab) and may nest once (madd + silent letter).
Ranges are code-point offsets into the word text (all characters are in the BMP,
so they equal UTF-16 offsets on the web and in Dart).
"""

from __future__ import annotations

import unicodedata
from collections.abc import Sequence
from dataclasses import dataclass
from html.parser import HTMLParser

from quran_backend.modules.tajweed.rules import RULES_BY_CODE

# Rub el hizb and sajdah signs are separate text tokens, but the V4 page font
# draws them inside the neighbouring word; they never carry a rule.
STANDALONE_MARKS = frozenset({chr(0x06DE), chr(0x06E9)})
# The tajweed and plain QF texts spell alef and hamza seats differently
# (e.g. U+0672 for a dagger alif); word matching compares the other consonants.
SKELETON_IGNORED = frozenset("اأإآٱٲىٮئ")
# The tajweed text writes a dagger alif as U+0672 and an alef maksura seat as a
# dotless beh; clients get the standard Uthmani characters. One character maps
# to one character, so rule ranges are unchanged.
DISPLAY_LETTERS = str.maketrans({"\u0672": "\u0670", "\u066e": "\u0649"})
SKELETON_LETTERS = {"ؤ": "و"}  # waw with hamza -> waw
ARABIC_INDIC_DIGITS = str.maketrans("٠١٢٣٤٥٦٧٨٩", "0123456789")
PRONOUN_HA = chr(0x0647)
SILAH_LETTERS = frozenset({chr(0x06E5), chr(0x06E6)})  # small waw, small yeh
SILAH_VARIANTS = {"madda_normal": "silah_sughra", "madda_obligatory": "silah_kubra"}
SUKUN = chr(0x0652)
# Fathatan..kasra and the open tanween forms.
VOWELS = frozenset(map(chr, (*range(0x064B, 0x0651), *range(0x08F0, 0x08F3))))

_Char = tuple[str, tuple[int, ...]]  # a character and the tajweed spans covering it


class TajweedMarkupError(ValueError):
    """The provider markup cannot be mapped to words safely."""


@dataclass(frozen=True, slots=True)
class TajweedFragment:
    code: str
    start: int
    end: int
    joins_previous: bool = False
    joins_next: bool = False
    variant: str = ""

    def as_dict(self) -> dict[str, object]:
        result: dict[str, object] = {"code": self.code, "start": self.start, "end": self.end}
        if self.joins_previous:
            result["joins_previous"] = True
        if self.joins_next:
            result["joins_next"] = True
        if self.variant:
            result["variant"] = self.variant
        return result


@dataclass(frozen=True, slots=True)
class TajweedWord:
    position: int
    text: str
    fragments: tuple[TajweedFragment, ...]

    def as_dict(self) -> dict[str, object]:
        return {
            "position": self.position,
            "text": self.text,
            "rules": [fragment.as_dict() for fragment in self.fragments],
        }


class _MarkupParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=False)
        self.chars: list[_Char] = []
        self.span_codes: list[str] = []
        self.end_marker: str | None = None
        self.open_spans: list[int] = []
        self.in_end = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if self.end_marker is not None:
            raise TajweedMarkupError("Markup continues after the verse end marker.")
        if tag == "span" and values == {"class": "end"}:
            self.in_end = True
            self.end_marker = ""
            return
        if tag != "tajweed" or set(values) != {"class"}:
            raise TajweedMarkupError(f"Unexpected element <{tag}> in tajweed markup.")
        code = values["class"] or ""
        if code not in RULES_BY_CODE:
            raise TajweedMarkupError(f"Unknown tajweed rule class {code!r}.")
        self.span_codes.append(code)
        self.open_spans.append(len(self.span_codes) - 1)

    def handle_endtag(self, tag: str) -> None:
        if tag == "span" and self.in_end:
            self.in_end = False
            return
        if tag != "tajweed" or not self.open_spans:
            raise TajweedMarkupError("Unbalanced tajweed markup.")
        self.open_spans.pop()

    def handle_data(self, data: str) -> None:
        if self.in_end:
            self.end_marker = (self.end_marker or "") + data
        elif self.end_marker is not None:
            if data.strip():
                raise TajweedMarkupError("Text follows the verse end marker.")
        else:
            spans = tuple(self.open_spans)
            self.chars.extend((char, spans) for char in data)

    def handle_entityref(self, name: str) -> None:
        raise TajweedMarkupError(f"Unexpected entity &{name}; in tajweed markup.")

    def handle_charref(self, name: str) -> None:
        raise TajweedMarkupError(f"Unexpected character reference &#{name}; in tajweed markup.")

    def handle_comment(self, data: str) -> None:  # noqa: ARG002
        raise TajweedMarkupError("Unexpected comment in tajweed markup.")


def parse_tajweed_verse(
    verse_key: str,
    markup: str,
    canonical_words: Sequence[str] | None = None,
) -> tuple[TajweedWord, ...]:
    """Split one verse into Quran.Foundation word positions with rule ranges.

    `canonical_words` are the Unicode texts of the verse's QF words in position
    order (the same word ids as the QCF V4 font). Text tokens are assigned to
    them by consonant skeleton, because the two QF texts space a few words
    differently («بَعْدَمَا» / «بَعْدَ مَا»). Without them every token is a word.
    """
    parser = _MarkupParser()
    parser.feed(markup)
    parser.close()
    if parser.open_spans or parser.in_end:
        raise TajweedMarkupError(f"Unclosed tajweed markup in {verse_key}.")
    end_marker = (parser.end_marker or "").strip().translate(ARABIC_INDIC_DIGITS)
    if end_marker != verse_key.partition(":")[2]:
        raise TajweedMarkupError(f"Verse end marker does not match {verse_key}.")

    tokens, separators = _tokens(verse_key, parser.chars)
    groups = _word_groups(verse_key, tokens, canonical_words)
    words: list[list[_Char]] = []
    for group in groups:
        word: list[_Char] = []
        for index in group:
            if word:
                word.append(separators[index - 1])
            word.extend(tokens[index])
        words.append(word)

    span_words: dict[int, list[int]] = {}
    for index, word in enumerate(words):
        for span in {span for _, spans in word for span in spans}:
            span_words.setdefault(span, []).append(index)
    for span in range(len(parser.span_codes)):
        indexes = span_words.get(span)
        if not indexes:
            raise TajweedMarkupError(f"Empty tajweed span in {verse_key}.")
        if indexes != list(range(indexes[0], indexes[0] + len(indexes))):
            raise TajweedMarkupError(f"Discontinuous tajweed span in {verse_key}.")

    return tuple(
        TajweedWord(
            position=index + 1,
            text=_text(word).translate(DISPLAY_LETTERS),
            fragments=_fragments(verse_key, index, word, parser.span_codes, span_words),
        )
        for index, word in enumerate(words)
    )


def _tokens(verse_key: str, chars: list[_Char]) -> tuple[list[list[_Char]], list[_Char]]:
    tokens: list[list[_Char]] = [[]]
    separators: list[_Char] = []
    while chars and chars[-1][0] == " " and not chars[-1][1]:
        chars = chars[:-1]
    for char, spans in chars:
        if char == " ":
            tokens.append([])
            separators.append((char, spans))
        elif char.isspace():
            raise TajweedMarkupError(f"Unexpected whitespace in {verse_key}.")
        else:
            tokens[-1].append((char, spans))
    for token in tokens:
        text = _text(token)
        if not text:
            raise TajweedMarkupError(f"Empty word in {verse_key}.")
        if not has_letter(text) and (
            text not in STANDALONE_MARKS or any(spans for _, spans in token)
        ):
            raise TajweedMarkupError(f"Unexpected standalone mark {text!r} in {verse_key}.")
    return tokens, separators


def _word_groups(
    verse_key: str,
    tokens: list[list[_Char]],
    canonical_words: Sequence[str] | None,
) -> list[list[int]]:
    letter_tokens = [index for index, token in enumerate(tokens) if has_letter(_text(token))]
    if canonical_words is None:
        return [[index] for index in letter_tokens]
    groups: list[list[int]] = []
    cursor = 0
    for position, canonical in enumerate(canonical_words, start=1):
        target = _skeleton(canonical)
        group: list[int] = []
        skeleton = ""
        while cursor < len(letter_tokens) and (not group or skeleton != target):
            group.append(letter_tokens[cursor])
            skeleton += _skeleton(_text(tokens[letter_tokens[cursor]]))
            cursor += 1
            if not target.startswith(skeleton):
                break
        if not group or skeleton != target:
            raise TajweedMarkupError(
                f"Word {position} of {verse_key} does not match the canonical text."
            )
        groups.append(group)
    if cursor != len(letter_tokens):
        raise TajweedMarkupError(f"{verse_key} has more words than the canonical text.")
    return groups


def _fragments(
    verse_key: str,
    index: int,
    word: list[_Char],
    span_codes: list[str],
    span_words: dict[int, list[int]],
) -> tuple[TajweedFragment, ...]:
    text = _text(word)
    fragments: list[TajweedFragment] = []
    for span in sorted({span for _, spans in word for span in spans}):
        offsets = [offset for offset, (_, spans) in enumerate(word) if span in spans]
        start, end = offsets[0], offsets[-1] + 1
        if offsets != list(range(start, end)):
            raise TajweedMarkupError(f"Split tajweed span inside a word in {verse_key}.")
        code = span_codes[span]
        fragments.append(
            TajweedFragment(
                code=code,
                start=start,
                end=end,
                joins_previous=span_words[span][0] < index,
                joins_next=span_words[span][-1] > index,
                variant=_variant(code, text, start, end),
            )
        )
    fragments.sort(key=lambda item: (item.start, item.end, item.code))
    return tuple(fragments)


def _variant(code: str, text: str, start: int, end: int) -> str:
    if code in SILAH_VARIANTS:
        letters = [char for char in text[start:end] if not _is_mark(char)]
        before = [char for char in text[:start] if not _is_mark(char)]
        if letters and letters[0] in SILAH_LETTERS and before and before[-1] == PRONOUN_HA:
            return SILAH_VARIANTS[code]
    if code == "qalaqah":
        # A voweled qalqalah letter at the end of a word only bounces when stopping.
        word_final = all(unicodedata.category(char) in {"Mn", "Cf"} for char in text[end:])
        marks = set(text[start:])
        if word_final and SUKUN not in marks and VOWELS.intersection(marks):
            return "stop"
    return ""


def _skeleton(text: str) -> str:
    return "".join(
        SKELETON_LETTERS.get(char, char)
        for char in text
        if unicodedata.category(char) == "Lo" and char not in SKELETON_IGNORED
    )


def _text(token: list[_Char]) -> str:
    return "".join(char for char, _ in token)


def has_letter(text: str) -> bool:
    return any(unicodedata.category(char) == "Lo" for char in text)


def _is_mark(char: str) -> bool:
    return unicodedata.category(char) == "Mn"
