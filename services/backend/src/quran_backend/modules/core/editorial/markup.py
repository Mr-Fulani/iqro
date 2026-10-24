"""Author markup of course notes → typed blocks (docs/courses/README.md, «Конспект»).

The author writes plain text with a few line markers; the server parses it once
when a release is prepared, and the site and the app only draw the blocks. There
is no HTML and no links: every segment is text. Parsing never fails: an unknown
marker stays ordinary text.
"""

from __future__ import annotations

import re
import unicodedata
from typing import Any

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

    for raw in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
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


def segments(text: str) -> list[Segment]:
    """One line of text: bold pairs, then Arabic runs; equal neighbours merged."""
    result: list[Segment] = []
    for piece, bold in _bold_pieces(text):
        for part, arabic in _script_runs(piece):
            segment: Segment = {"text": part}
            if bold:
                segment["bold"] = True
            if arabic:
                segment["lang"] = "ar"
            if result and _attributes(result[-1]) == _attributes(segment):
                result[-1]["text"] += part
            elif part:
                result.append(segment)
    return result


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


def _attributes(segment: Segment) -> tuple[bool, str]:
    return bool(segment.get("bold")), str(segment.get("lang", ""))
