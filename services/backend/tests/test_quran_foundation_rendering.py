from __future__ import annotations

import pytest

from quran_backend.modules.quran.quran_foundation_rendering import (
    SUPPORTED_MUSHAF_IDS,
    quran_foundation_rendering,
    renderable_words,
    verse_keys_from_mapping,
)


@pytest.mark.parametrize("source_id", SUPPORTED_MUSHAF_IDS)
def test_every_layout_has_web_and_native_assets(source_id: int) -> None:
    contract = quran_foundation_rendering(source_id, page_number=42)
    assert contract["available"]
    if contract["mode"] != "word-images":
        assert str(contract["font_url"]).startswith("https://")
        assert str(contract["native_font_url"]).endswith(".ttf")
    if source_id in (1, 2, 19):
        assert "/p42." in str(contract["native_font_url"])
    if source_id == 19:
        assert contract["color_format"] == "COLRv1"


@pytest.mark.parametrize(
    ("source_id", "prefix"), [(10, "qa-color"), (11, "rq-color"), (12, "qa-black")]
)
def test_word_images_and_verse_markers(source_id: int, prefix: str) -> None:
    words = [
        {"verse_id": 1, "text": f"w/{prefix}/1/1/1.png"},
        {"verse_id": 1, "text": "w/common/1.png"},
    ]
    result = renderable_words(source_id, words, {"1": "1"})
    assert result[0]["image_url"] == f"https://static.qurancdn.com/images/w/{prefix}/1/1/1.png?v=1"
    assert result[1]["image_url"].endswith("/w/common/1.png?v=1")
    assert all(word["verse_key"] == "1:1" for word in result)
    assert "image_url" not in words[0]


@pytest.mark.parametrize(
    "path",
    [
        "https://evil.test/a.png",
        "w/rq-color/../../1.png",
        "w/qa-black/1/1/1.png",
        "w/rq-color/1/1/1.png?x=1",
    ],
)
def test_image_path_cannot_escape_source(path: str) -> None:
    with pytest.raises(ValueError, match="image path"):
        renderable_words(11, [{"verse_id": 1, "text": path}], {"1": "1"})


def test_tajweed_preserves_arabic_and_exposes_only_semantic_colors() -> None:
    text = "<rule class=ham_wasl>ٱ</rule>للَّهِ"
    result = renderable_words(16, [{"verse_id": 1, "text": text}], {"1": "1"})[0]
    assert result["text"] == text
    assert result["text_runs"] == [
        {"text": "ٱ", "rule": "ham_wasl", "color": "#aaaaaa"},
        {"text": "للَّهِ"},
    ]
    assert "".join(run["text"] for run in result["text_runs"]) == "ٱللَّهِ"


@pytest.mark.parametrize(
    "text",
    [
        "<script>alert(1)</script>",
        "<img src=x onerror=alert(1)>",
        "<rule class=unknown>ب</rule>",
        "<rule class=ham_wasl>ب",
    ],
)
def test_unexpected_markup_is_not_published(text: str) -> None:
    with pytest.raises(ValueError, match=r"Unexpected|Unknown|Unclosed"):
        renderable_words(16, [{"verse_id": 1, "text": text}], {"1": "1"})


def test_disjoint_ranges_and_verified_boundary_references() -> None:
    assert verse_keys_from_mapping({"2": "1, 3-4", "1": "7"}) == ["1:7", "2:1", "2:3", "2:4"]
    result = renderable_words(
        15,
        [
            {"verse_id": 1127, "verse_key": "7:173", "text": "أَوۡ"},
            {"verse_id": 1136, "verse_key": "7:182", "text": "وَٱلَّذِينَ"},
        ],
        {"7": "173-181"},
    )
    assert [word["verse_key"] for word in result] == ["7:173", "7:182"]


def test_unknown_source_is_not_substituted() -> None:
    assert quran_foundation_rendering(999)["available"] is False
