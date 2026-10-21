# ruff: noqa: RUF001
from __future__ import annotations

from io import StringIO
from typing import Any

import pytest
from django.core.management import call_command
from django.core.management.base import CommandError
from django.db import connection
from django.test import override_settings
from django.test.utils import CaptureQueriesContext
from django.utils import timezone
from rest_framework.test import APIClient

from quran_backend.modules.audio.quran_foundation import (
    ENVIRONMENTS,
    QuranFoundationClient,
    QuranFoundationError,
)
from quran_backend.modules.quran.models import QuranFoundationMushaf, QuranFoundationMushafPage
from quran_backend.modules.tajweed.markup import TajweedMarkupError, parse_tajweed_verse
from quran_backend.modules.tajweed.models import (
    AyahTajweed,
    TajweedEdition,
    TajweedEditionVersion,
)
from quran_backend.modules.tajweed.quran_foundation_sync import (
    VerseWords,
    quran_foundation_verse_words,
    sync_quran_foundation_tajweed,
)
from quran_backend.modules.tajweed.rules import LANGUAGES, TAJWEED_RULES

# Real Quran.Foundation `text_uthmani_tajweed` rows and Mushaf 4 word texts.
FATIHA_1 = (
    "بِسْمِ <tajweed class=ham_wasl>ٱ</tajweed>للَّهِ <tajweed class=ham_wasl>ٱ</tajweed>"
    "<tajweed class=laam_shamsiyah>ل</tajweed>رَّحْمَ<tajweed class=madda_normal>ـٰ</tajweed>نِ "
    "<tajweed class=ham_wasl>ٱ</tajweed><tajweed class=laam_shamsiyah>ل</tajweed>رَّح"
    "<tajweed class=madda_permissible>ِي</tajweed>مِ <span class=end>١</span>"
)
FATIHA_1_WORDS = ("بِسْمِ", "ٱللَّهِ", "ٱلرَّحْمَـٰنِ", "ٱلرَّحِيمِ")
FATIHA_2 = (
    "ٱلْحَمْدُ لِلَّهِ رَبِّ <tajweed class=ham_wasl>ٱ</tajweed>لْعَ"
    "<tajweed class=madda_normal>ـٰ</tajweed>لَم<tajweed class=madda_permissible>ِي</tajweed>نَ "
    "<span class=end>٢</span>"
)
FATIHA_2_WORDS = ("ٱلْحَمْدُ", "لِلَّهِ", "رَبِّ", "ٱلْعَـٰلَمِينَ")
IKHLAS_4 = (
    "وَلَمْ يَك<tajweed class=idgham_wo_ghunnah>ُن ل</tajweed>َّهُ"
    "<tajweed class=madda_normal>ۥ</tajweed> كُفُوًا أَحَ<tajweed class=qalaqah>د</tajweed>ُۢ "
    "<span class=end>٤</span>"
)
IKHLAS_4_WORDS = ("وَلَمْ", "يَكُن", "لَّهُۥ", "كُفُوًا", "أَحَدٌۢ")
VERSE_WORDS = {
    "1:1": VerseWords(page_number=1, words=FATIHA_1_WORDS),
    "1:2": VerseWords(page_number=1, words=FATIHA_2_WORDS),
}


class FakeTajweedClient:
    environment = ENVIRONMENTS["production"]

    def __init__(self, verses: list[dict[str, Any]] | None = None) -> None:
        self.verses = verses or [
            {"id": 1, "verse_key": "1:1", "text_uthmani_tajweed": FATIHA_1},
            {"id": 2, "verse_key": "1:2", "text_uthmani_tajweed": FATIHA_2},
        ]

    def get_uthmani_tajweed(self) -> list[dict[str, Any]]:
        return self.verses


def test_every_quran_foundation_rule_has_four_languages_and_a_palette_colour() -> None:
    codes = [rule.code for rule in TAJWEED_RULES]
    assert len(codes) == len(set(codes)) == 17
    for rule in TAJWEED_RULES:
        assert rule.color.startswith("#")
        assert len(rule.color) == 7
        assert rule.arabic_name
        for texts in (rule.name, rule.why, rule.how):
            assert set(texts) == set(LANGUAGES)
            assert all(value.strip() for value in texts.values())
        for variant in rule.variants:
            assert all(set(texts) == set(LANGUAGES) for texts in (variant.name, variant.why))


def test_idgham_crosses_words_and_variants_explain_silah_and_stop() -> None:
    words = parse_tajweed_verse("112:4", IKHLAS_4, IKHLAS_4_WORDS)

    assert [word.as_dict() for word in words] == [
        {"position": 1, "text": "وَلَمْ", "rules": []},
        {
            "position": 2,
            "text": "يَكُن",
            "rules": [{"code": "idgham_wo_ghunnah", "start": 3, "end": 5, "joins_next": True}],
        },
        {
            "position": 3,
            "text": "لَّهُۥ",
            "rules": [
                {"code": "idgham_wo_ghunnah", "start": 0, "end": 1, "joins_previous": True},
                {"code": "madda_normal", "start": 5, "end": 6, "variant": "silah_sughra"},
            ],
        },
        {"position": 4, "text": "كُفُوًا", "rules": []},
        {
            "position": 5,
            "text": "أَحَدُۢ",
            "rules": [{"code": "qalaqah", "start": 4, "end": 5, "variant": "stop"}],
        },
    ]
    assert words[1].text[3:5] == "ُن"


def test_nested_rules_and_pause_marks_stay_inside_one_word() -> None:
    markup = (
        "وَلَا تَعْتَد<tajweed class=madda_obligatory>ُوٓ<tajweed class=slnt>اْ</tajweed>"
        "‌ۚ</tajweed> إِ<tajweed class=ghunnah>نّ</tajweed>َ <span class=end>١٩٠</span>"
    )

    words = parse_tajweed_verse("2:190", markup, ("وَلَا", "تَعْتَدُوٓا۟ ۚ", "إِنَّ"))

    # The pause mark is joined by U+200C (zero-width non-joiner), not a space.
    assert [fragment.as_dict() for fragment in words[1].fragments] == [
        {"code": "madda_obligatory", "start": 7, "end": 14},
        {"code": "slnt", "start": 10, "end": 12},
    ]
    assert words[1].text[10:12] == "اْ"
    assert words[1].text.endswith(chr(0x200C) + "ۚ")


def test_canonical_words_merge_differently_spaced_tokens_and_drop_section_marks() -> None:
    markup = (
        "۞ أَهْوَآءَه<tajweed class=ikhafa_shafawi>ُم ب</tajweed>َعْدَمَا جَآءَكَ "
        "يَسْجُدُونَ ۩ <span class=end>٣٧</span>"
    )
    canonical = ("۞ أَهْوَآءَهُم", "بَعْدَ مَا", "جَآءَكَ", "يَسْجُدُونَ ۩")

    words = parse_tajweed_verse("13:37", markup, canonical)

    assert [word.text for word in words] == ["أَهْوَآءَهُم", "بَعْدَمَا", "جَآءَكَ", "يَسْجُدُونَ"]
    assert words[0].fragments[0].joins_next is True
    assert words[1].fragments[0].joins_previous is True

    spaced = parse_tajweed_verse(
        "8:6",
        "بَعْدَ مَا تَبَيَّنَ <span class=end>٦</span>",
        ("بَعْدَ مَا", "تَبَيَّنَ"),
    )
    assert [word.text for word in spaced] == ["بَعْدَ مَا", "تَبَيَّنَ"]


@pytest.mark.parametrize(
    ("markup", "message"),
    [
        ("<tajweed class=madda_super>ا</tajweed> <span class=end>١</span>", "Unknown tajweed"),
        ("<b>ب</b> <span class=end>١</span>", "Unexpected element"),
        ("<tajweed class=ghunnah>نّ <span class=end>١</span>", "Unclosed"),
        ("نّ</tajweed> <span class=end>١</span>", "Unbalanced"),
        ("بِسْمِ <span class=end>٢</span>", "end marker"),
        ("بِسْمِ <span class=end>١</span> ب", "follows the verse end"),
        ("بِسْمِ  ٱللَّهِ <span class=end>١</span>", "Empty word"),
        ("بِسْمِ ۚ <span class=end>١</span>", "standalone mark"),
        ("بِسْمِ &amp; <span class=end>١</span>", "entity"),
        ("<tajweed class=ghunnah></tajweed>بِسْمِ <span class=end>١</span>", "Empty tajweed"),
    ],
)
def test_malformed_or_unknown_markup_is_rejected(markup: str, message: str) -> None:
    with pytest.raises(TajweedMarkupError, match=message):
        parse_tajweed_verse("1:1", markup)


def test_word_mismatch_with_the_canonical_text_is_rejected() -> None:
    with pytest.raises(TajweedMarkupError, match="Word 2 of 1:1"):
        parse_tajweed_verse("1:1", FATIHA_1, ("بِسْمِ", "رَبِّ", "ٱلرَّحْمَـٰنِ", "ٱلرَّحِيمِ"))
    with pytest.raises(TajweedMarkupError, match="more words"):
        parse_tajweed_verse("1:1", FATIHA_1, FATIHA_1_WORDS[:3])


@pytest.mark.django_db
def test_sync_publishes_a_version_and_is_idempotent() -> None:
    result = sync_quran_foundation_tajweed(
        client=FakeTajweedClient(),
        verse_words=VERSE_WORDS,
        mushaf_checksum="m" * 64,
    )

    edition = TajweedEdition.objects.get()
    assert result.changed is True
    assert result.ayahs == 2
    assert edition.environment == "production"
    assert edition.active_version is not None
    assert edition.active_version.checksum_sha256 == result.checksum_sha256
    ayah = AyahTajweed.objects.get(verse_key="1:1")
    assert ayah.page_number == 1
    assert ayah.rules == ["madda_permissible", "madda_normal", "ham_wasl", "laam_shamsiyah"]
    assert [word["position"] for word in ayah.words] == [2, 3, 4]
    assert ayah.source_text == FATIHA_1

    again = sync_quran_foundation_tajweed(
        client=FakeTajweedClient(),
        verse_words=VERSE_WORDS,
        mushaf_checksum="m" * 64,
    )
    assert again.changed is False
    assert TajweedEditionVersion.objects.count() == 1


@pytest.mark.django_db
def test_changed_markup_publishes_a_new_active_version() -> None:
    sync_quran_foundation_tajweed(client=FakeTajweedClient(), verse_words=VERSE_WORDS)
    changed = FakeTajweedClient(
        [
            {"verse_key": "1:1", "text_uthmani_tajweed": FATIHA_1},
            {"verse_key": "1:2", "text_uthmani_tajweed": FATIHA_2.replace("ham_wasl", "slnt")},
        ]
    )

    result = sync_quran_foundation_tajweed(client=changed, verse_words=VERSE_WORDS)

    edition = TajweedEdition.objects.get()
    assert result.changed is True
    assert TajweedEditionVersion.objects.count() == 2
    assert edition.active_version is not None
    assert edition.active_version.checksum_sha256 == result.checksum_sha256
    assert AyahTajweed.objects.filter(edition_version=edition.active_version).count() == 2


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("verses", "message"),
    [
        (
            [
                {"verse_key": "1:1", "text_uthmani_tajweed": FATIHA_1},
                {"verse_key": "1:2", "text_uthmani_tajweed": FATIHA_2.replace("ham_wasl", "x")},
            ],
            "Unknown tajweed rule",
        ),
        ([{"verse_key": "1:1", "text_uthmani_tajweed": FATIHA_1}], "expected 2"),
        (
            [
                {"verse_key": "1:1", "text_uthmani_tajweed": FATIHA_1},
                {"verse_key": "1:1", "text_uthmani_tajweed": FATIHA_1},
            ],
            "twice",
        ),
        (
            [
                {"verse_key": "1:1", "text_uthmani_tajweed": FATIHA_1},
                {"verse_key": "1:2", "text_uthmani_tajweed": FATIHA_2},
                {"verse_key": "1:3", "text_uthmani_tajweed": FATIHA_2},
            ],
            "unknown verse",
        ),
        (
            [
                {"verse_key": "1:1", "text_uthmani_tajweed": FATIHA_1},
                {"verse_key": "1:2", "text_uthmani_tajweed": "رَبِّ <span class=end>٢</span>"},
            ],
            "does not match the canonical text",
        ),
        ([{"verse_key": 1, "text_uthmani_tajweed": FATIHA_1}], "invalid tajweed verse"),
    ],
)
def test_any_mismatch_aborts_the_import_without_changes(
    verses: list[dict[str, Any]],
    message: str,
) -> None:
    with pytest.raises(QuranFoundationError, match=message):
        sync_quran_foundation_tajweed(client=FakeTajweedClient(verses), verse_words=VERSE_WORDS)

    assert not TajweedEdition.objects.exists()
    assert not AyahTajweed.objects.exists()


@pytest.mark.django_db
def test_dry_run_validates_without_writing() -> None:
    result = sync_quran_foundation_tajweed(
        client=FakeTajweedClient(),
        verse_words=VERSE_WORDS,
        dry_run=True,
    )

    assert result.ayahs == 2
    assert result.changed is False
    assert not TajweedEdition.objects.exists()


@pytest.mark.django_db
def test_word_positions_come_from_quran_foundation_mushafs(
    quran_dataset: dict[str, Any],
) -> None:
    _mushaf(19, [("1:1", 1, "ﱁ"), ("1:1", 2, "ﱂ"), ("1:1", 3, "ﱃ"), ("1:1", 4, "ﱄ")])
    _mushaf(4, [("1:1", position, text) for position, text in enumerate(FATIHA_1_WORDS, 1)])
    with pytest.raises(QuranFoundationError, match="published Quran"):
        quran_foundation_verse_words("production")

    QuranFoundationMushaf.objects.all().delete()
    _mushaf(19, [*_glyphs("1:1", 4), *_glyphs("1:2", 4), ("1:2", 5, "ﱉ")], page=2)
    _mushaf(4, [*_texts("1:1", FATIHA_1_WORDS), *_texts("1:2", (*FATIHA_2_WORDS, "٢"))])

    verse_words, checksum = quran_foundation_verse_words("production")

    assert verse_words["1:1"] == VerseWords(page_number=2, words=FATIHA_1_WORDS)
    # A trailing ayah number labelled as a word (QF 2:181) is not a word.
    assert verse_words["1:2"].words == FATIHA_2_WORDS
    assert len(checksum) == 64
    result = sync_quran_foundation_tajweed(client=FakeTajweedClient())
    assert result.ayahs == 2
    assert AyahTajweed.objects.get(verse_key="1:2").page_number == 2


@pytest.mark.django_db
def test_an_ayah_end_labelled_as_a_word_only_in_v4_is_not_a_word(
    quran_dataset: dict[str, Any],
) -> None:
    # Production QF data: Mushaf 4 marks the 2:181 number as the ayah end,
    # Mushaf 19 still labels the same word id as a word.
    _mushaf(19, [*_glyphs("1:1", 4), *_glyphs("1:2", 4), ("1:2", 5, "ﱉ")])
    _mushaf(4, [*_texts("1:1", FATIHA_1_WORDS), *_texts("1:2", (*FATIHA_2_WORDS, "٢"))])
    QuranFoundationMushafPage.objects.filter(mushaf__source_id=4).update(
        words=[
            {**word, "char_type_name": "end"} if word["text"] == "٢" else word
            for word in QuranFoundationMushafPage.objects.get(mushaf__source_id=4).words
        ]
    )

    verse_words, _ = quran_foundation_verse_words("production")

    assert verse_words["1:2"].words == FATIHA_2_WORDS


@pytest.mark.django_db
def test_missing_mushafs_or_mismatched_word_ids_abort(quran_dataset: dict[str, Any]) -> None:
    with pytest.raises(QuranFoundationError, match="Mushafs 19 and 4"):
        quran_foundation_verse_words("production")

    _mushaf(19, [*_glyphs("1:1", 4), *_glyphs("1:2", 4)])
    _mushaf(4, [*_texts("1:1", FATIHA_1_WORDS), *_texts("1:2", (*FATIHA_2_WORDS, "رَبِّ"))])
    with pytest.raises(QuranFoundationError, match="different QF word positions"):
        quran_foundation_verse_words("production")


@pytest.mark.django_db
@override_settings(QURAN_QF_ENV="production")
def test_public_rules_page_and_ayah_api(api_client: APIClient) -> None:
    sync_quran_foundation_tajweed(
        client=FakeTajweedClient(
            [
                {"verse_key": "1:1", "text_uthmani_tajweed": FATIHA_1},
                {"verse_key": "1:2", "text_uthmani_tajweed": FATIHA_2},
                {"verse_key": "112:4", "text_uthmani_tajweed": IKHLAS_4},
            ]
        ),
        verse_words={
            **VERSE_WORDS,
            "112:4": VerseWords(page_number=604, words=IKHLAS_4_WORDS),
        },
    )

    rules = api_client.get("/api/v1/quran/tajweed/rules")
    with CaptureQueriesContext(connection) as queries:
        page = api_client.get("/api/v1/quran/tajweed/pages/604")
    ayah = api_client.get("/api/v1/quran/tajweed/surahs/1/ayahs/2")

    assert rules.status_code == 200
    assert rules["Cache-Control"].startswith("public")
    assert rules["ETag"].startswith('W/"')
    assert len(rules.json()["rules"]) == 17
    assert rules.json()["review_status"] == "pending_teacher_review"
    assert page.status_code == 200
    assert page["Cache-Control"].startswith("public")
    body = page.json()
    assert body["page_number"] == 604
    assert body["rules"] == ["idgham_wo_ghunnah", "qalaqah", "madda_normal"]
    assert body["source"]["attribution"] == "Quran data provided by Quran Foundation."
    assert body["ayahs"][0]["verse_key"] == "112:4"
    assert body["ayahs"][0]["words"][1] == {
        "position": 3,
        "text": "لَّهُۥ",
        "rules": [
            {"code": "idgham_wo_ghunnah", "start": 0, "end": 1, "joins_previous": True},
            {"code": "madda_normal", "start": 5, "end": 6, "variant": "silah_sughra"},
        ],
    }
    assert "source_text" not in body["ayahs"][0]
    assert not any("source_text" in query["sql"] for query in queries.captured_queries)
    assert ayah.status_code == 200
    assert ayah.json()["verse_key"] == "1:2"
    assert ayah.json()["page_number"] == 1
    cached = api_client.get(
        "/api/v1/quran/tajweed/surahs/1/ayahs/2",
        HTTP_IF_NONE_MATCH=ayah["ETag"],
    )
    assert cached.status_code == 304
    assert api_client.get("/api/v1/quran/tajweed/pages/3").status_code == 404
    assert api_client.get("/api/v1/quran/tajweed/surahs/2/ayahs/1").status_code == 404


@pytest.mark.django_db
@override_settings(QURAN_QF_ENV="prelive")
def test_tajweed_api_is_empty_until_the_environment_is_imported(api_client: APIClient) -> None:
    sync_quran_foundation_tajweed(client=FakeTajweedClient(), verse_words=VERSE_WORDS)

    assert api_client.get("/api/v1/quran/tajweed/pages/1").status_code == 404
    assert api_client.get("/api/v1/quran/tajweed/rules").status_code == 200


@pytest.mark.django_db
def test_management_command_reports_and_wraps_errors(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[bool] = []

    def fake_sync(*, dry_run: bool) -> Any:
        calls.append(dry_run)
        if len(calls) == 2:
            raise QuranFoundationError("Unknown tajweed rule class 'x'.")
        return sync_quran_foundation_tajweed(
            client=FakeTajweedClient(),
            verse_words=VERSE_WORDS,
            dry_run=dry_run,
        )

    monkeypatch.setattr(
        "quran_backend.modules.tajweed.management.commands."
        "sync_quran_foundation_tajweed.sync_quran_foundation_tajweed",
        fake_sync,
    )
    output = StringIO()
    call_command("sync_quran_foundation_tajweed", "--dry-run", stdout=output)
    assert "validated, nothing written: 2 ayahs" in output.getvalue()
    with pytest.raises(CommandError, match="Unknown tajweed rule"):
        call_command("sync_quran_foundation_tajweed")
    assert calls == [True, False]


def _mushaf(source_id: int, words: list[tuple[str, int, str]], *, page: int = 1) -> None:
    mushaf = QuranFoundationMushaf.objects.create(
        environment="production",
        source_id=source_id,
        name=f"Mushaf {source_id}",
        qirat_name="Hafs",
        pages_count=604,
        lines_per_page=15,
        default_font_name="v4-tajweed" if source_id == 19 else "text_uthmani",
        mapping_mode="reference",
        schema_version="1",
        sync_sequence=1,
        source_checksum_sha256=str(source_id % 10) * 64,
        last_synced_at=timezone.now(),
    )
    QuranFoundationMushafPage.objects.create(
        mushaf=mushaf,
        source_id=page,
        page_number=page,
        verse_mapping={"1": "1-2"},
        verses_count=2,
        words=[
            {
                "id": index,
                "word_id": index,
                "verse_key": verse_key,
                "position_in_verse": position,
                "char_type_name": "word",
                "text": text,
            }
            for index, (verse_key, position, text) in enumerate(words, start=1)
        ],
    )


def _glyphs(verse_key: str, count: int) -> list[tuple[str, int, str]]:
    return [(verse_key, position, chr(0xFC40 + position)) for position in range(1, count + 1)]


def _texts(verse_key: str, texts: tuple[str, ...]) -> list[tuple[str, int, str]]:
    return [(verse_key, position, text) for position, text in enumerate(texts, 1)]


def test_word_text_uses_standard_uthmani_characters_with_the_same_offsets() -> None:
    markup = (
        "وَكَذ<tajweed class=madda_normal>َٲ</tajweed>لِكَ فَسَوَّ"
        "<tajweed class=madda_normal>ٮٰ</tajweed>هُنَّ <span class=end>٣٧</span>"
    )

    words = parse_tajweed_verse("13:37", markup, ("وَكَذَٰلِكَ", "فَسَوَّىٰهُنَّ"))

    assert [word.text for word in words] == ["وَكَذَٰلِكَ", "فَسَوَّىٰهُنَّ"]
    assert words[0].text[5:7] == "َٰ"
    assert words[0].fragments[0].as_dict() == {"code": "madda_normal", "start": 5, "end": 7}
    assert words[1].text[7:9] == "ىٰ"


def test_client_reads_every_uthmani_tajweed_verse(monkeypatch: pytest.MonkeyPatch) -> None:
    client = QuranFoundationClient(
        client_id="client",
        client_secret="secret",
        environment=ENVIRONMENTS["prelive"],
    )
    calls: list[tuple[str, dict[str, str]]] = []

    def fake_get_json(path: str, *, query: dict[str, str]) -> dict[str, Any]:
        calls.append((path, query))
        return {"verses": [{"verse_key": "1:1", "text_uthmani_tajweed": FATIHA_1}]}

    monkeypatch.setattr(client, "_get_json", fake_get_json)
    assert client.get_uthmani_tajweed()[0]["verse_key"] == "1:1"
    assert calls == [("/content/api/v4/quran/verses/uthmani_tajweed", {})]

    monkeypatch.setattr(client, "_get_json", lambda *_, **__: {"verses": "1:1"})
    with pytest.raises(QuranFoundationError, match="invalid tajweed verses"):
        client.get_uthmani_tajweed()
