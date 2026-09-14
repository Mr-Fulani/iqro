"""QUL structure with the selected Quran.Foundation edition's original words.

Profiles change line placement, never text, glyphs, verse identity or pagination.
If a future snapshot changes page membership, retain it without applying a stale
profile. Both clients receive the same explicit line roles and reading order.
"""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

PROFILE_NAMES = {
    1: "qpc-v2-15-lines",
    2: "qpc-v1-15-lines",
    4: "qpc-v2-15-lines",
    5: "qpc-v2-15-lines",
    6: "qudratullah-indopak-15-lines",
    7: "taj-indopak-16-lines",
    10: "qpc-v1-15-lines",
    11: "qpc-v1-15-lines",
    12: "qpc-v1-15-lines",
    14: "qudratullah-indopak-15-lines",
    15: "taj-indopak-16-lines",
    16: "qpc-v2-15-lines",
    19: "qpc-v4-tajweed-15-lines",
}


@lru_cache(maxsize=5)
def load_profile(name: str) -> dict[str, Any]:
    return json.loads((Path(__file__).parent / "qul_layouts" / f"{name}.json").read_text())  # type: ignore[no-any-return]


def apply_qul_layout(
    source_id: int,
    page_number: int,
    words: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], dict[str, Any] | None]:
    name = PROFILE_NAMES.get(source_id)
    if name is None:
        return words, None
    profile = load_profile(name)
    rows = profile["pages"].get(str(page_number))
    if not rows:
        return words, None
    expected = [word_id for row in rows for word_id in row["word_ids"]]
    by_id = {word.get("word_id"): word for word in words}
    if (
        len(expected) != len(set(expected))
        or len(by_id) != len(words)
        or set(expected) != set(by_id)
    ):
        return words, None
    ordered: list[dict[str, Any]] = []
    for row in rows:
        for position, word_id in enumerate(row["word_ids"], start=1):
            word = by_id[word_id]
            ordered.append(
                {
                    **word,
                    "source_line_number": word["line_number"],
                    "source_position_in_page": word["position_in_page"],
                    "line_number": row["line_number"],
                    "position_in_line": position,
                    "position_in_page": len(ordered) + 1,
                }
            )
    return ordered, {
        "version": 1,
        "name": profile["name"],
        "source_url": profile["source_url"],
        "source_sha256": profile["source_sha256"],
        "lines_per_page": profile["lines_per_page"],
        "decoration_font_url": "https://verses.quran.foundation/fonts/quran/hafs/uthmanic_hafs/UthmanicHafs1Ver18.woff2",
        "native_decoration_font_url": "https://verses.quran.foundation/fonts/quran/hafs/uthmanic_hafs/UthmanicHafs1Ver18.ttf",
        # The live QUL preview centers the opening spread, including rows whose
        # older SQLite export still has is_centered=0 (e.g. Qudratullah p1).
        "lines": [
            {
                **{key: value for key, value in row.items() if key != "word_ids"},
                "is_centered": page_number <= 2 or row["is_centered"],
            }
            for row in rows
        ],
    }
