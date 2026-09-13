"""Official font/word-image contracts shared by web and native clients.

Assets: Quran.Foundation font guide, Quran.com src/utils/cdn.ts and QUL font 462.
Source text and physical lines always come from the corresponding snapshot.
"""

from __future__ import annotations

import re
from html.parser import HTMLParser
from typing import Any

FONT_ROOT = "https://verses.quran.foundation/fonts/quran/hafs/"
NASTALEEQ_FONT = "https://static-cdn.tarteel.ai/qul/fonts/nastaleeq/KFGQPCNastaleeq-Regular.ttf"
IMAGE_ROOT = "https://static.qurancdn.com/images/"
SUPPORTED_MUSHAF_IDS = (1, 2, 4, 5, 6, 7, 10, 11, 12, 14, 15, 16, 19)
PAGE_FONTS = {1: "v2", 2: "v1", 19: "v4/colrv1"}
UNICODE_FONTS = {
    4: "me_quran/me_quran-2",
    5: "uthmanic_hafs/UthmanicHafs1Ver18",
    6: "nastaleeq/indopak/indopak-nastaleeq-waqf-lazim-v4.2.1",
    7: "nastaleeq/indopak/indopak-nastaleeq-waqf-lazim-v4.2.1",
    16: "uthmanic_hafs/UthmanicHafs1Ver18",
}
IMAGE_PREFIXES = {10: "qa-color", 11: "rq-color", 12: "qa-black"}

# Semantic rules are data, never executable HTML or arbitrary CSS.
TAJWEED_COLORS = {
    "ham_wasl": "#aaaaaa",
    "laam_shamsiyah": "#aaaaaa",
    "slnt": "#aaaaaa",
    "madda_normal": "#537fff",
    "madda_permissible": "#4050ff",
    "madda_obligatory_mottasel": "#2144c1",
    "madda_obligatory_monfasel": "#2144c1",
    "madda_necessary": "#000ebc",
    "qalaqah": "#dd0008",
    "ghunnah": "#ff7e1e",
    "ikhafa": "#9400a8",
    "ikhafa_shafawi": "#d500b7",
    "idgham_ghunnah": "#169200",
    "idgham_shafawi": "#58b800",
    "idgham_wo_ghunnah": "#169200",
    "iqlab": "#26bffd",
    "idgham_mutajanisayn": "#a1a1a1",
    "idgham_mutaqaribayn": "#a1a1a1",
}


def quran_foundation_rendering(
    source_id: int,
    *,
    page_number: int | None = None,
) -> dict[str, object]:
    """Return a public rendering contract, without API credentials."""
    result: dict[str, object] = {"available": True, "version": 2}
    if source_id in PAGE_FONTS:
        root = FONT_ROOT + PAGE_FONTS[source_id]
        result.update(
            mode="page-font",
            font_format="woff2",
            font_url_template=root + "/woff2/p{page}.woff2",
            native_font_url_template=root + "/ttf/p{page}.ttf",
        )
        if page_number is not None:
            result.update(
                font_url=f"{root}/woff2/p{page_number}.woff2",
                native_font_url=f"{root}/ttf/p{page_number}.ttf",
            )
        if source_id == 19:
            result["color_format"] = "COLRv1"
    elif source_id in UNICODE_FONTS:
        root = FONT_ROOT + UNICODE_FONTS[source_id]
        result.update(
            mode="unicode-font",
            font_format="woff2",
            font_url=root + ".woff2",
            native_font_url=root + ".ttf",
        )
        if source_id == 16:
            result["tajweed"] = True
    elif source_id in (14, 15):
        result.update(
            mode="unicode-font",
            font_format="truetype",
            font_url=NASTALEEQ_FONT,
            native_font_url=NASTALEEQ_FONT,
        )
    elif source_id in IMAGE_PREFIXES:
        result.update(mode="word-images", image_base_url=IMAGE_ROOT, image_version="1")
    else:
        return {"available": False, "mode": "unknown", "reason": "unsupported_mushaf"}
    return result


def verse_keys_from_mapping(mapping: dict[str, Any]) -> list[str]:
    keys: list[str] = []
    for chapter, ranges in sorted(mapping.items(), key=lambda pair: int(pair[0])):
        if not 1 <= int(chapter) <= 114:
            raise ValueError("Invalid Mushaf chapter")
        for part in str(ranges).split(","):
            match = re.fullmatch(r"(\d+)(?:-(\d+))?", part.strip())
            if match is None:
                raise ValueError("Invalid Mushaf verse range")
            start, end = int(match[1]), int(match[2] or match[1])
            if not 1 <= start <= end <= 286:
                raise ValueError("Invalid Mushaf verse range")
            keys.extend(f"{chapter}:{verse}" for verse in range(start, end + 1))
    return keys


class _TajweedParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.rules: list[str] = []
        self.runs: list[dict[str, str]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag != "rule":
            raise ValueError("Unexpected element in Quran text")
        rule = dict(attrs).get("class") or ""
        if rule not in TAJWEED_COLORS and rule != "custom-alef-maksora":
            raise ValueError("Unknown Quran tajweed rule")
        self.rules.append(rule)

    def handle_endtag(self, tag: str) -> None:
        if tag != "rule" or not self.rules:
            raise ValueError("Unbalanced Quran tajweed rule")
        self.rules.pop()

    def handle_data(self, data: str) -> None:
        run = {"text": data}
        if self.rules:
            run["rule"] = self.rules[-1]
            if color := TAJWEED_COLORS.get(self.rules[-1]):
                run["color"] = color
        self.runs.append(run)


def renderable_words(
    source_id: int,
    words: list[dict[str, Any]],
    mapping: dict[str, Any],
) -> list[dict[str, Any]]:
    """Keep original text intact; expose safe rendering runs separately."""
    keys = verse_keys_from_mapping(mapping)
    verse_ids = list(dict.fromkeys(word["verse_id"] for word in words if word.get("verse_id")))
    references = dict(zip(verse_ids, keys, strict=False)) if len(verse_ids) == len(keys) else {}
    result = []
    for original in words:
        word = {
            **original,
            "verse_key": original.get("verse_key") or references.get(original.get("verse_id")),
        }
        if source_id in IMAGE_PREFIXES:
            prefix = IMAGE_PREFIXES[source_id]
            pattern = rf"w/(?:{prefix}/[1-9]\d*/[1-9]\d*/[1-9]\d*|common/[1-9]\d*)\.png"
            if not re.fullmatch(pattern, word["text"]):
                raise ValueError("Invalid Quran word image path")
            word["image_url"] = IMAGE_ROOT + word["text"] + "?v=1"
        elif source_id == 16:
            parser = _TajweedParser()
            parser.feed(word["text"])
            parser.close()
            if parser.rules:
                raise ValueError("Unclosed Quran tajweed rule")
            word["text_runs"] = parser.runs
        result.append(word)
    return result
