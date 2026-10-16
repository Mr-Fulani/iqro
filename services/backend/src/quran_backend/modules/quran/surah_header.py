"""Printed surah headings from QUL's "Surah header font" (resource 458).

Every glyph of KFGQPC's QCF_SurahHeader font is a whole Mushaf heading: the
ornamental cartouche with the surah name inside. Browsers' and Flutter's text
rasterizers drop parts of these 6000-point outlines, so clients read the glyph
outline from the pinned file and fill it as a vector path. The font is loaded
from the QUL CDN like the other Mushaf fonts and never stored in this project.
"""

from __future__ import annotations

from typing import Any

SURAH_HEADER_FONT_URL = (
    "https://static-cdn.tarteel.ai/qul/fonts/surah-names/surah-header/"
    "QCF_SurahHeader_COLOR-Regular.ttf"
)
# Version 1.000, 8 September 2025. A different file falls back to IQRO's frame
# instead of trusting glyph ids that might point at another surah.
SURAH_HEADER_FONT_SHA256 = "de261a309bdd42262e1a268d5ead56b6ea8366cd59124baedea3903561d7370b"
# Glyphs follow .notdef, uni0000, uni0009 and space in surah order.
FIRST_SURAH_GLYPH_ID = 4


def surah_header(
    verse_mapping: dict[str, str],
    layout: dict[str, Any] | None = None,
) -> dict[str, Any] | None:
    """Heading glyphs for every surah title drawn on this page.

    That is each surah whose first ayah is here, plus any title row of the page
    layout: printed Mushafs often end a page with the next surah's title while
    its first ayah opens the following page.
    """
    titled = {
        int(surah)
        for surah, ranges in verse_mapping.items()
        if str(ranges).split("-")[0].strip() == "1"
    }
    for row in (layout or {}).get("lines") or []:
        if row.get("line_type") == "surah_name" and row.get("surah_number"):
            titled.add(int(row["surah_number"]))
    surahs = sorted(surah for surah in titled if 1 <= surah <= 114)
    if not surahs:
        return None
    return {
        "font_url": SURAH_HEADER_FONT_URL,
        "font_sha256": SURAH_HEADER_FONT_SHA256,
        "glyph_ids": {str(surah): FIRST_SURAH_GLYPH_ID + surah - 1 for surah in surahs},
    }
