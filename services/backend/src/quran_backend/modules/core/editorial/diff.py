"""Line comparison of two texts for a reviewer who reads only what changed."""

from __future__ import annotations

import difflib

GAP = "…"


def line_diff(old: str, new: str, *, context: int = 1) -> list[tuple[str, str]]:
    """(mark, line) pairs: `-` removed, `+` added, ` ` context, `…` skipped lines."""
    rows: list[tuple[str, str]] = []
    lines = list(difflib.unified_diff(old.splitlines(), new.splitlines(), n=context, lineterm=""))
    # The first two lines name the files.
    for line in lines[2:]:
        if line.startswith("@@"):
            if rows:
                rows.append((GAP, ""))
            continue
        rows.append((line[:1], line[1:]))
    return rows
