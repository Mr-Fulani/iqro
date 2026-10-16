from __future__ import annotations

from quran_backend.modules.quran.surah_header import (
    SURAH_HEADER_FONT_SHA256,
    SURAH_HEADER_FONT_URL,
    surah_header,
)


def test_only_surahs_starting_on_the_page_get_heading_glyphs() -> None:
    header = surah_header({"4": "176", "5": "1-2", "9": "1 - 6", "114": "1-6"})
    assert header == {
        "font_url": SURAH_HEADER_FONT_URL,
        "font_sha256": SURAH_HEADER_FONT_SHA256,
        "glyph_ids": {"5": 8, "9": 12, "114": 117},
    }


def test_pages_without_a_surah_opening_have_no_heading() -> None:
    assert surah_header({"2": "6-16"}) is None
    assert surah_header({}) is None


def test_heading_font_is_the_pinned_qul_cdn_file() -> None:
    assert SURAH_HEADER_FONT_URL.startswith("https://static-cdn.tarteel.ai/qul/fonts/")
    assert len(SURAH_HEADER_FONT_SHA256) == 64
