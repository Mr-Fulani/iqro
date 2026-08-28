from __future__ import annotations

import html
import re

from django.utils.html import strip_tags

_SUP_PATTERN = re.compile(r"<sup\b[^>]*>(.*?)</sup>", re.IGNORECASE | re.DOTALL)
_UNSAFE_BLOCK_PATTERN = re.compile(
    r"<(script|style)\b[^>]*>.*?</\1>",
    re.IGNORECASE | re.DOTALL,
)
_BREAK_PATTERN = re.compile(r"<(?:br\s*/?|/p|/li)>\s*", re.IGNORECASE)
_SPACE_PATTERN = re.compile(r"[\t\r\f\v ]+")
_NEWLINE_PATTERN = re.compile(r"\s*\n\s*")


def provider_plain_text(value: str) -> str:
    """Convert provider HTML to stable, non-executable plain text."""

    without_unsafe_blocks = _UNSAFE_BLOCK_PATTERN.sub("", value)
    with_footnote_markers = _SUP_PATTERN.sub(
        lambda match: f" [{strip_tags(html.unescape(match.group(1))).strip()}] ",
        without_unsafe_blocks,
    )
    with_breaks = _BREAK_PATTERN.sub("\n", with_footnote_markers)
    decoded = html.unescape(strip_tags(with_breaks)).replace("\xa0", " ")
    compact_lines = _NEWLINE_PATTERN.sub("\n", _SPACE_PATTERN.sub(" ", decoded))
    return compact_lines.strip()
