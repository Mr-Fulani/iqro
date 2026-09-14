from __future__ import annotations

from copy import deepcopy

import pytest

from quran_backend.modules.quran.qul_layout import PROFILE_NAMES, apply_qul_layout, load_profile


@pytest.mark.parametrize("name", sorted(set(PROFILE_NAMES.values())))
def test_profiles_cover_every_word_once_and_explicit_surah_rows(name: str) -> None:
    profile = load_profile(name)
    all_words = []
    surahs = []
    for page, rows in profile["pages"].items():
        numbers = [row["line_number"] for row in rows]
        assert numbers == list(range(1, len(rows) + 1)), (page, numbers)
        assert max(numbers) <= profile["lines_per_page"]
        for row in rows:
            assert row["line_type"] in {"ayah", "basmallah", "surah_name"}
            assert isinstance(row["is_centered"], bool)
            all_words.extend(row["word_ids"])
            if row["line_type"] == "surah_name":
                surahs.append(row["surah_number"])
                if row["surah_number"] == 9:
                    assert rows[numbers.index(row["line_number"]) + 1]["line_type"] == "ayah"
    assert len(all_words) == len(set(all_words)) == 83665
    assert surahs == list(range(1, 115))


@pytest.mark.parametrize("source", sorted(PROFILE_NAMES))
def test_layout_orders_words_without_changing_text_verse_or_source(source: int) -> None:
    rows = load_profile(PROFILE_NAMES[source])["pages"]["1"]
    ids = [word for row in rows for word in row["word_ids"]]
    words = [
        {
            "word_id": word,
            "text": f"glyph-{word}",
            "verse_key": "1:1",
            "line_number": 15,
            "position_in_page": index + 1,
        }
        for index, word in enumerate(reversed(ids))
    ]
    original = deepcopy(words)
    result, layout = apply_qul_layout(source, 1, words)
    assert words == original
    assert [word["word_id"] for word in result] == ids
    assert [word["position_in_page"] for word in result] == list(range(1, len(ids) + 1))
    assert all(word["source_line_number"] == 15 for word in result)
    assert all(word["text"] == f"glyph-{word['word_id']}" for word in result)
    assert all(word["verse_key"] == "1:1" for word in result)
    assert layout
    assert layout["lines"][0]["surah_number"] == 1
    assert all(row["is_centered"] for row in layout["lines"])


@pytest.mark.parametrize("mutation", ["missing", "duplicate", "extra", "unknown"])
def test_future_incompatible_snapshot_is_never_partially_rearranged(mutation: str) -> None:
    rows = load_profile(PROFILE_NAMES[1])["pages"]["1"]
    words = [{"word_id": word} for row in rows for word in row["word_ids"]]
    if mutation == "missing":
        words.pop()
    elif mutation == "duplicate":
        words[-1] = words[0]
    elif mutation == "extra":
        words.append({"word_id": -1})
    else:
        words[-1] = {"word_id": -1}
    result, layout = apply_qul_layout(1, 1, words)
    assert result is words
    assert layout is None
