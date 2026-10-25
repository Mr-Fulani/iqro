# Messages for authors are intentionally Russian.
# ruff: noqa: RUF001
"""Author markup of course notes → typed blocks (docs/courses/README.md, «Конспект»).

The author writes plain text with a few line markers; the server parses it once
when a release is prepared, and the site and the app only draw the blocks. There
is no HTML. A segment may carry a link (`[text](/quran/2:255)`) or be a note icon
(`word[!text]`, `word[?text]`). Parsing never fails: an unknown marker stays
ordinary text; `markup_issues` tells the author what did not become a link or a note.
"""

from __future__ import annotations

import re
import unicodedata
from typing import Any
from urllib.parse import urlsplit

Segment = dict[str, Any]
Block = dict[str, Any]

ARABIC_RANGES = (
    (0x0600, 0x06FF),
    (0x0750, 0x077F),
    (0x08A0, 0x08FF),
    (0xFB50, 0xFDFF),
    (0xFE70, 0xFEFF),
)
ORDERED_ITEM = re.compile(r"\d+\. ")
QUOTE_SOURCE = "— "  # an em dash, as the author types it
BOLD = "**"
# `[!text]` and `[?text]`: a note icon; `[text](address)`: a link. No brackets inside.
INLINE = re.compile(r"\[(?:([!?])([^\[\]]*)\]|([^\[\]]+)\]\(([^()\s]*)\))")
NOTE_KINDS = {"!": "warning", "?": "help"}
# The sections of the site and the app a note may link to (docs/courses/README.md).
INTERNAL_LINK = re.compile(
    r"/(?:quran/\d{1,3}(?::\d{1,3})?"
    r"|courses(?:/[a-z0-9-]+){0,2}"
    r"|dua(?:/[A-Za-z0-9_-]+){0,3}"
    r"|tajweed(?:/[a-z0-9-]+)?)"
)
# Stands for a link or a note while bold pairs are matched around it.
PLACEHOLDER = "\x00"


def parse_notes(text: str) -> list[Block]:
    """Blocks of a note in reading order."""
    blocks: list[Block] = []
    kind = ""
    lines: list[str] = []

    def flush() -> None:
        if lines:
            block = _block(kind, lines)
            if block is not None:
                blocks.append(block)
        lines.clear()

    for raw in _lines(text):
        line = raw.strip()
        if not line:
            flush()
            continue
        line_kind, content = _classify(line)
        if line_kind != kind or line_kind == "heading":
            flush()
            kind = line_kind
        lines.append(content)
    flush()
    return blocks


def is_arabic(character: str) -> bool:
    code = ord(character)
    return any(start <= code <= end for start, end in ARABIC_RANGES)


def segments(text: str, *, inline: bool = True) -> list[Segment]:
    """One line of text: links and notes, bold pairs, then Arabic runs; equal neighbours
    merged. Inside a note (`inline=False`) only bold and Arabic runs."""
    text = text.replace(PLACEHOLDER, "")
    tokens: list[Segment] = []
    masked = ""
    position = 0
    for match in INLINE.finditer(text) if inline else ():
        token = _token(match)
        if token is None:
            continue
        before = text[position : match.start()]
        # The icon stands right after its word: a space before it is dropped.
        masked += before.rstrip() if "note" in token else before
        masked += PLACEHOLDER
        tokens.append(token)
        position = match.end()
    masked += text[position:]
    found = iter(tokens)
    result: list[Segment] = []
    for piece, bold in _bold_pieces(masked):
        for index, part in enumerate(piece.split(PLACEHOLDER)):
            if index:
                token = next(found)
                for segment in token.get("parts", [token]):
                    _append(
                        result, {**segment, "bold": True} if bold and "link" in segment else segment
                    )
            for run, arabic in _script_runs(part):
                segment = {"text": run}
                if bold:
                    segment["bold"] = True
                if arabic:
                    segment["lang"] = "ar"
                _append(result, segment)
    return result


def link_kind(href: str) -> str | None:
    """`internal` for a section of the site and the app, `external` for a web address."""
    if INTERNAL_LINK.fullmatch(href):
        return "internal"
    if not href.lower().startswith(("https://", "http://")):
        return None
    try:
        parts = urlsplit(href)
        port = parts.port
    except ValueError:
        return None
    if not parts.hostname or parts.username is not None or port not in {None, 80, 443}:
        return None
    return "external"


def _token(match: re.Match[str]) -> Segment | None:
    """A note or a link segment; None when the brackets are not one (they stay text)."""
    mark, note, label, href = match.groups()
    if mark is not None:
        content = segments(note.strip(), inline=False)
        if not content:
            return None
        return {"text": "", "note": {"kind": NOTE_KINDS[mark], "text": content}}
    kind = link_kind(href)
    if kind is None or not label.strip():
        return None
    link = {"href": href, "kind": kind}
    # The label may be bold or Arabic in parts: each part carries the link.
    return {"parts": [{**part, "link": link} for part in segments(label, inline=False)]}


def _append(result: list[Segment], segment: Segment) -> None:
    joins = result and "note" not in segment and "note" not in result[-1]
    if joins and _attributes(result[-1]) == _attributes(segment):
        result[-1]["text"] += segment["text"]
        return
    if segment["text"] or "note" in segment:
        result.append(segment)


def direction(texts: list[str]) -> str:
    """`rtl` when the first strong character is right-to-left."""
    for text in texts:
        for character in text:
            kind = unicodedata.bidirectional(character)
            if kind == "L":
                return "ltr"
            if kind in {"R", "AL"}:
                return "rtl"
    return "ltr"


def plain_text(blocks: list[Block]) -> str:
    """The words of the blocks, for the reading-time estimate."""
    parts: list[str] = []
    for block in blocks:
        if block["type"] == "heading":
            rows = [block["text"]]
        else:
            rows = block.get("lines") or block.get("items") or []
        parts += [segment["text"] for row in rows for segment in row]
        if block.get("source"):
            parts.append(block["source"])
    return " ".join(parts)


def plain_markup(text: str) -> str:
    """The text without inline markup, line markers kept: for clients that predate links
    and notes. Links keep their text, notes and bold markers go."""
    rows = []
    for raw in _lines(text):
        line = raw.strip()
        _kind, content = _classify(line)
        prefix = line[: len(line) - len(content)]
        rows.append(prefix + "".join(segment["text"] for segment in segments(content)))
    return "\n".join(rows)


def markup_links(text: str) -> list[dict[str, Any]]:
    """Every link of the text with its line number, for the reviewer and the checks."""
    found = []
    for number, raw in enumerate(_lines(text), start=1):
        for match in INLINE.finditer(_classify(raw.strip())[1]):
            _mark, _note, label, href = match.groups()
            kind = None if label is None else link_kind(href)
            if kind is not None and label.strip():
                text_ = "".join(part["text"] for part in segments(label, inline=False))
                found.append({"line": number, "text": text_, "href": href, "kind": kind})
    return found


def markup_issues(text: str) -> list[tuple[int, str]]:
    """Brackets that did not become a link or a note, as (line number, problem)."""
    issues: list[tuple[int, str]] = []
    for number, raw in enumerate(_lines(text), start=1):
        content = _classify(raw.strip())[1]
        for match in INLINE.finditer(content):
            mark, note, label, href = match.groups()
            if mark is not None:
                if not segments(note.strip(), inline=False):
                    issues.append(
                        (number, f"пустая пометка «{match[0]}»: напишите текст подсказки")
                    )
            elif link_kind(href) is None:
                issues.append(
                    (
                        number,
                        f"«{href}» — не адрес ссылки: внутренняя начинается с /quran/, /courses/, "
                        "/dua или /tajweed, внешняя — с https://",
                    )
                )
            elif not label.strip():
                issues.append((number, f"у ссылки «{href}» нет текста"))
        rest = INLINE.sub("", content)
        if "[!" in rest or "[?" in rest:
            issues.append(
                (
                    number,
                    "незакрытая скобка: пометке «[!…» или «[?…» нужна «]», "
                    "других скобок внутри нет",
                )
            )
        elif "](" in rest:
            issues.append(
                (number, "незакрытая скобка: у ссылки «[текст](адрес)» нет «)» или в адресе пробел")
            )
    return issues


def _lines(text: str) -> list[str]:
    return text.replace("\r\n", "\n").replace("\r", "\n").split("\n")


def _classify(line: str) -> tuple[str, str]:
    if line.startswith("## "):
        return "heading", line[3:]
    if line.startswith("- "):
        return "unordered", line[2:]
    ordered = ORDERED_ITEM.match(line)
    if ordered is not None:
        return "ordered", line[ordered.end() :]
    if line.startswith("> "):
        return "quote", line[2:]
    if line.startswith("! "):
        return "note", line[2:]
    return "paragraph", line


def _block(kind: str, raw_lines: list[str]) -> Block | None:
    source: str | None = None
    if kind == "quote" and len(raw_lines) > 1 and raw_lines[-1].strip().startswith(QUOTE_SOURCE):
        source = raw_lines[-1].strip()[len(QUOTE_SOURCE) :].strip()
        raw_lines = raw_lines[:-1]
    rows = [row for row in (segments(line.strip()) for line in raw_lines) if row]
    if not rows:
        return None
    dir_ = direction([segment["text"] for row in rows for segment in row])
    if kind == "heading":
        return {"type": "heading", "dir": dir_, "text": rows[0]}
    if kind in {"unordered", "ordered"}:
        return {"type": "list", "dir": dir_, "ordered": kind == "ordered", "items": rows}
    if kind == "quote":
        return {"type": "quote", "dir": dir_, "lines": rows, "source": source or None}
    return {"type": kind, "dir": dir_, "lines": rows}


def _bold_pieces(text: str) -> list[tuple[str, bool]]:
    parts = text.split(BOLD)
    if len(parts) % 2 == 0:
        # An odd number of markers: the last one has no pair and stays text.
        parts[-2:] = [parts[-2] + BOLD + parts[-1]]
    return [(part, index % 2 == 1) for index, part in enumerate(parts)]


def _script_runs(text: str) -> list[tuple[str, bool]]:
    """Arabic runs, with the spaces and marks between Arabic words, apart from the rest."""
    runs: list[tuple[str, bool]] = []
    start = 0
    index = 0
    while index < len(text):
        if not is_arabic(text[index]):
            index += 1
            continue
        if index > start:
            runs.append((text[start:index], False))
        end = index + 1
        probe = end
        while probe < len(text):
            if is_arabic(text[probe]):
                end = probe = probe + 1
            elif _neutral(text[probe]):
                probe += 1
            else:
                break
        runs.append((text[index:end], True))
        start = index = end
    if start < len(text):
        runs.append((text[start:], False))
    return runs


def _neutral(character: str) -> bool:
    return unicodedata.bidirectional(character) not in {"L", "R", "AL"}


def _attributes(segment: Segment) -> tuple[bool, str, str]:
    link = segment.get("link") or {}
    return bool(segment.get("bold")), str(segment.get("lang", "")), str(link.get("href", ""))
