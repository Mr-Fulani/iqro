"""The structure editor: adding, removing and reordering; the course's own formula texts."""

from __future__ import annotations

# Russian interface strings intentionally contain characters that resemble Latin glyphs.
# ruff: noqa: RUF001
import copy
import json
from typing import Any
from unittest.mock import patch

import pytest
from django.test import Client

from quran_backend.modules.salah import editor
from quran_backend.modules.salah import editor_structure as structure
from quran_backend.modules.salah.compiler import compile_document
from quran_backend.modules.salah.models import SalahCourseVersion
from quran_backend.modules.salah.resolvers import FormulaResolver
from quran_backend.modules.salah.snapshot import (
    SalahSnapshotError,
    integrity_problems,
    validate_snapshot,
)
from tests.test_salah import COURSE_SNAPSHOT, FakeResolver, _example_snapshot, _fake_formulas
from tests.test_salah_editor import (
    LANGUAGES,
    RESOLVER,
    RUKU,
    _editor_url,
    _form,
    _post,
    _staff_client,
    draft,
    owner_client,
)

__all__ = ["draft", "owner_client"]


def _all(text: str) -> dict[str, str]:
    return {language: f"{text} [{language}]" for language in LANGUAGES}


def _course() -> dict[str, Any]:
    snapshot: dict[str, Any] = json.loads(COURSE_SNAPSHOT.read_text(encoding="utf-8"))
    return snapshot


def _step_slugs(snapshot: dict[str, Any], lesson_slug: str) -> list[str]:
    lesson = next(item for item in snapshot["lessons"] if item["slug"] == lesson_slug)
    return [step.id.removeprefix("step:") for step in editor.lesson_steps(snapshot, lesson)]


def _completeness(snapshot: dict[str, Any]) -> list[str]:
    with pytest.raises(SalahSnapshotError) as error:
        validate_snapshot(snapshot)
    return error.value.problems


# The snapshot, without a database -------------------------------------------


def test_a_new_lesson_is_valid_in_a_draft_and_asks_for_steps_at_sign_off() -> None:
    snapshot = _course()
    slug = structure.add_lesson(
        snapshot,
        "special",
        kind="steps",
        title={"ru": "Суджуд ас-сахв", "en": "", "ar": "", "tr": ""},
        summary={"ru": "Земной поклон за ошибку.", "en": "", "ar": "", "tr": ""},
    )
    assert slug == "sudzhud-as-sakhv"
    assert snapshot["sections"][-1]["lessons"][-1] == slug
    assert integrity_problems(snapshot) == []
    problems = _completeness(snapshot)
    assert f"Урок «{slug}»: нет шагов." in problems
    assert any(f"Урок «{slug}».title: нет текста на «en»" in item for item in problems)
    # The editor counts the missing translations at once.
    node = editor.find_node(snapshot, f"lesson:{slug}")
    assert editor.node_missing(node, LANGUAGES) == {"ru": 0, "en": 2, "ar": 2, "tr": 2}

    step_id = structure.add_step(
        snapshot, slug, kind="action", title=_all("Поклон"), instruction=_all("Сделайте поклон")
    )
    assert step_id == f"step:{slug}.poklon-ru"
    assert _completeness(snapshot)
    assert not any("нет шагов" in item for item in _completeness(snapshot))


def test_a_lesson_address_is_checked_and_never_taken_twice() -> None:
    snapshot = _course()
    title, summary = _all("Урок"), _all("Кратко")
    with pytest.raises(structure.StructureError, match="латинские буквы"):
        structure.add_lesson(
            snapshot, "basics", kind="steps", slug="Ночная", title=title, summary=summary
        )
    with pytest.raises(structure.StructureError, match="уже занят"):
        structure.add_lesson(
            snapshot, "basics", kind="article", slug="wudu", title=title, summary=summary
        )
    with pytest.raises(structure.StructureError, match="по шагам"):
        structure.add_lesson(snapshot, "basics", kind="prayer", title=title, summary=summary)
    first = structure.add_lesson(snapshot, "basics", kind="article", title=title, summary=summary)
    second = structure.add_lesson(snapshot, "basics", kind="article", title=title, summary=summary)
    assert (first, second) == ("urok-ru", "urok-ru-2")


def test_a_step_added_to_a_prayer_joins_its_template_in_every_prayer_with_it() -> None:
    snapshot = _course()
    anchor = editor.find_node(snapshot, "step:fajr.r1.ruku")
    with pytest.raises(structure.StructureError, match="после другого шага"):
        structure.add_step(snapshot, "fajr", kind="info", title=_all("x"), instruction=_all("y"))
    node_id = structure.add_step(
        snapshot,
        "fajr",
        kind="info",
        title=_all("Пауза"),
        instruction=_all("Замрите"),
        after=anchor,
    )
    assert node_id == "step:fajr.r1.pauza-ru"
    fajr = _step_slugs(snapshot, "fajr")
    assert fajr[fajr.index("fajr.r1.ruku") + 1] == "fajr.r1.pauza-ru"
    # The same template, the same conditions: Dhuhr has it in its first rak'ah too.
    dhuhr = _step_slugs(snapshot, "dhuhr")
    assert dhuhr[dhuhr.index("dhuhr.r1.ruku") + 1] == "dhuhr.r1.pauza-ru"
    assert "dhuhr.r2.pauza-ru" not in dhuhr
    assert integrity_problems(snapshot) == []


def test_removing_a_shared_step_says_where_it_shows_and_keeps_its_variants() -> None:
    snapshot = _course()
    node = editor.find_node(snapshot, "step:fajr.r1.ruku")
    notes = structure.deletion_notes(snapshot, node)
    assert notes[0].startswith("Шаг общий: он удалится из шаблона и из всех этих мест")
    assert "Фаджр (ракаат 1)" in notes[0]
    assert "Зухр (ракаат 1)" in notes[0]
    assert notes[1].startswith("Другие варианты этого шага останутся")
    removed = structure.delete_step(snapshot, node)
    assert removed == [node.data]
    assert "fajr.r1.ruku" not in _step_slugs(snapshot, "fajr")
    assert "fajr.r2.ruku" in _step_slugs(snapshot, "fajr")
    assert integrity_problems(snapshot) == []


def test_removing_a_section_takes_the_lessons_only_it_lists() -> None:
    snapshot = _course()
    snapshot["sections"][1]["lessons"].append("what-is-salah")
    notes = structure.deletion_notes(snapshot, editor.find_node(snapshot, "section:basics"))
    assert any("останется: он есть и в другом разделе" in item for item in notes)
    removed = structure.delete_section(snapshot, "basics")
    lessons = {lesson["slug"] for lesson in snapshot["lessons"]}
    assert "what-is-salah" in lessons
    assert "conditions" not in lessons
    assert removed
    assert all("slug" in step for step in removed)
    assert integrity_problems(snapshot) == []


def test_removed_steps_recordings_go_once_nothing_plays_them() -> None:
    snapshot = _example_snapshot()
    node = editor.find_node(snapshot, "step:fajr.r1.ruku")
    keys = structure.removed_audio([node.data])
    assert keys == {"audio-ruku-ru"}
    structure.delete_step(snapshot, node)
    assert editor.drop_unused_audio(snapshot, keys) == ["audio-ruku-ru"]
    assert integrity_problems(snapshot) == []


def test_steps_move_within_their_lesson_and_a_prayers_within_its_rakah() -> None:
    snapshot = _course()
    wudu = _step_slugs(snapshot, "wudu")
    structure.move_step(snapshot, editor.find_node(snapshot, "step:wudu.hands"), -1)
    moved = _step_slugs(snapshot, "wudu")
    assert moved.index("wudu.hands") == wudu.index("wudu.hands") - 1
    with pytest.raises(structure.StructureError, match="и так первый в уроке"):
        structure.move_step(snapshot, editor.find_node(snapshot, f"step:{moved[0]}"), -1)

    first = _step_slugs(snapshot, "fajr")
    structure.move_step(snapshot, editor.find_node(snapshot, "step:fajr.r1.ruku"), 1)
    after = _step_slugs(snapshot, "fajr")
    assert after.index("fajr.r1.ruku") == first.index("fajr.r1.ruku") + 1
    with pytest.raises(structure.StructureError, match="внутри своего ракаата"):
        structure.move_step_next_to(
            snapshot,
            editor.find_node(snapshot, "step:fajr.r1.ruku"),
            editor.find_node(snapshot, "step:fajr.r2.ruku"),
            after=True,
        )
    assert integrity_problems(snapshot) == []


def test_lessons_and_sections_reorder_and_a_lesson_changes_section() -> None:
    snapshot = _course()
    structure.move_section(snapshot, "purification", -1)
    assert [section["slug"] for section in snapshot["sections"][:2]] == ["purification", "basics"]
    structure.move_section_next_to(snapshot, "purification", "positions", after=True)
    assert [section["slug"] for section in snapshot["sections"][:3]] == [
        "basics",
        "positions",
        "purification",
    ]
    structure.move_lesson_next_to(snapshot, "qibla", "wudu", after=False)
    purification = next(s for s in snapshot["sections"] if s["slug"] == "purification")
    assert purification["lessons"][purification["lessons"].index("wudu") - 1] == "qibla"
    assert "qibla" not in snapshot["sections"][0]["lessons"]
    structure.move_lesson_to_section(snapshot, "qibla", "basics")
    assert snapshot["sections"][0]["lessons"][-1] == "qibla"
    with pytest.raises(structure.StructureError, match="и так последний в разделе"):
        structure.move_lesson(snapshot, "qibla", 1)
    assert integrity_problems(snapshot) == []


def test_a_save_refuses_a_reference_to_nothing_but_not_a_missing_translation() -> None:
    snapshot = _course()
    snapshot["lessons"][0]["title"]["tr"] = ""
    assert integrity_problems(snapshot) == []
    snapshot["lessons"][0]["steps"][0]["formulas"] = ["no-such-formula"]
    snapshot["lessons"][0]["steps"][0]["media"] = "no-such-picture"
    problems = integrity_problems(snapshot)
    assert len(problems) == 2
    assert all("no-such" in item for item in problems)


def test_the_tree_offers_arrows_only_where_there_is_somewhere_to_go() -> None:
    snapshot = _course()
    tree = editor.editor_tree(snapshot, LANGUAGES)
    sections = [entry for entry in tree if entry.kind == "section"]
    assert not sections[0].can_up
    assert sections[0].can_down
    assert sections[-1].can_up
    assert not sections[-1].can_down
    fajr = next(
        lesson for section in sections for lesson in section.children if lesson.id == "lesson:fajr"
    )
    assert fajr.prayer
    assert fajr.group == "lessons"
    steps = {entry.id: entry for entry in fajr.children}
    # The first step of rak'ah 2 cannot go up into rak'ah 1.
    second_rakah = [entry for entry in fajr.children if entry.group == "lesson:fajr|2"]
    assert not second_rakah[0].can_up
    assert second_rakah[0].can_down
    assert steps["step:fajr.r1.ruku"].can_up
    assert steps["step:fajr.r1.ruku"].can_down


def test_a_draft_with_new_and_moved_places_compiles_for_every_language() -> None:
    snapshot = _course()
    slug = structure.add_lesson(
        snapshot, "basics", kind="steps", title=_all("Новый"), summary=_all("Кратко")
    )
    structure.add_step(snapshot, slug, kind="info", title=_all("Шаг"), instruction=_all("Текст"))
    structure.move_lesson(snapshot, slug, -1)
    validate_snapshot(snapshot)
    for language in LANGUAGES:
        document = compile_document(
            snapshot,
            language=language,
            course_meta={"slug": "hanbali-umdah", "version": "draft", "methodology": "hanbali"},
            formulas=_fake_formulas(snapshot),
            media={},
        )
        basics = next(s for s in document["sections"] if s["slug"] == "basics")
        assert basics["lessons"][-2] == slug
        lesson = next(item for item in document["lessons"] if item["slug"] == slug)
        assert lesson["steps"][0]["title"] == f"Шаг [{language}]"


# Formula texts ----------------------------------------------------------------


def _formula_form(
    snapshot: dict[str, Any], formula_id: str, **texts: dict[str, str]
) -> dict[str, Any]:
    node = editor.find_node(snapshot, f"formula:{formula_id}")
    data: dict[str, Any] = {}
    for text_field in node.fields:
        stored = editor.node_texts(node, text_field.name)
        for language in LANGUAGES:
            value = texts.get(text_field.name, stored).get(language, "")
            data[f"text-{text_field.name}-{language}"] = value
    return data


def test_a_duas_own_wording_lies_over_the_source_and_goes_back_to_it() -> None:
    snapshot = _example_snapshot()
    node = editor.find_node(snapshot, "formula:ruku-tasbih")
    assert [field.name for field in node.fields] == ["meaning", "transliteration", "caption"]
    assert editor.node_missing(node, LANGUAGES) == dict.fromkeys(LANGUAGES, 0)
    data = _formula_form(
        snapshot,
        "ruku-tasbih",
        meaning={"ru": "Пречист мой Господь Великий"},
        caption=_all("Муслим, 772"),
    )
    data["formula-arabic"] = "سُبْحَانَ رَبِّيَ الْعَظِيمِ"
    edit = editor.parse_node_form(node, data, LANGUAGES, snapshot=snapshot)
    editor.apply_node_edit(snapshot, node, edit, LANGUAGES, sync_variants=False)
    source = snapshot["formulas"][2]["source"]
    assert source["translations"] == {"ru": {"meaning": "Пречист мой Господь Великий"}}
    assert source["arabic"] == "سُبْحَانَ رَبِّيَ الْعَظِيمِ"
    assert source["caption"]["tr"] == "Муслим, 772 [tr]"
    assert integrity_problems(snapshot) == []

    node = editor.find_node(snapshot, "formula:ruku-tasbih")
    reverted = editor.parse_node_form(
        node, {**_formula_form(snapshot, "ruku-tasbih"), "revert": "meaning"}, LANGUAGES
    )
    editor.apply_node_edit(snapshot, node, reverted, LANGUAGES, sync_variants=False)
    assert "translations" not in source
    node = editor.find_node(snapshot, "formula:ruku-tasbih")
    back = editor.parse_node_form(
        node,
        {
            **_formula_form(snapshot, "ruku-tasbih"),
            "formula-arabic": source["arabic"],
            "revert": "arabic",
        },
        LANGUAGES,
    )
    editor.apply_node_edit(snapshot, node, back, LANGUAGES, sync_variants=False)
    assert "arabic" not in source
    assert source["caption"]["ru"] == "Муслим, 772 [ru]"


def test_ayahs_arabic_never_changes_and_a_caption_needs_every_language() -> None:
    snapshot = _example_snapshot()
    node = editor.find_node(snapshot, "formula:fatiha")
    assert editor.formula_arabic(node) == ("", False)
    data = _formula_form(snapshot, "fatiha", caption={"ru": "Аль-Фатиха, 1–7"})
    data["formula-arabic"] = "changed"
    edit = editor.parse_node_form(node, data, LANGUAGES, snapshot=snapshot)
    assert edit.arabic is None
    editor.apply_node_edit(snapshot, node, edit, LANGUAGES, sync_variants=False)
    source = snapshot["formulas"][1]["source"]
    assert "arabic" not in source
    assert integrity_problems(snapshot) == []
    assert any("fatiha».caption: нет текста на «en»" in item for item in _completeness(snapshot))
    assert editor.node_missing(editor.find_node(snapshot, "formula:fatiha"), LANGUAGES)["en"] == 1


def test_an_inline_formula_is_written_here_and_counted_when_untranslated() -> None:
    snapshot = _example_snapshot()
    node = editor.find_node(snapshot, "formula:takbir")
    assert editor.formula_arabic(node)[1]
    data = _formula_form(snapshot, "takbir", meaning={**_all("Аллах велик"), "tr": ""})
    data["formula-arabic"] = "اللَّهُ أَكْبَرُ"
    editor.apply_node_edit(
        snapshot,
        node,
        editor.parse_node_form(node, data, LANGUAGES),
        LANGUAGES,
        sync_variants=False,
    )
    node = editor.find_node(snapshot, "formula:takbir")
    assert editor.node_missing(node, LANGUAGES)["tr"] == 1
    assert integrity_problems(snapshot) == []


@pytest.mark.django_db
def test_the_ayahs_keep_the_mushaf_text_under_the_courses_wording(
    quran_dataset: dict[str, Any],
) -> None:
    formula = {
        "id": "fatiha-start",
        "source": {
            "kind": "quran",
            "surah": 1,
            "ayah_from": 1,
            "ayah_to": 2,
            "translations": {"ru": {"meaning": "Свой перевод", "transliteration": "Bismillah"}},
            "caption": {"ru": "Сура 1", "en": "Surah 1"},
        },
    }
    resolver = FormulaResolver([formula], {})
    russian = resolver.resolve("ru")["fatiha-start"]
    assert russian["arabic"] == "بِسْمِ اللَّهِ ﴿١﴾ الْحَمْدُ لِلَّهِ ﴿٢﴾"
    assert russian["translation"] == "Свой перевод"
    assert russian["transliteration"] == "Bismillah"
    assert russian["caption"] == "Сура 1"
    english = resolver.resolve("en")["fatiha-start"]
    assert "transliteration" not in english
    assert english["caption"] == "Surah 1"
    assert "caption" not in resolver.resolve("tr")["fatiha-start"]


# The admin --------------------------------------------------------------------


def _structure_url(version: SalahCourseVersion, **query: str) -> str:
    url = f"/admin/salah/salahcourseversion/{version.pk}/structure/"
    return f"{url}?{'&'.join(f'{key}={value}' for key, value in query.items())}" if query else url


def _texts(field: str, value: dict[str, str]) -> dict[str, str]:
    return {f"text-{field}-{language}": value.get(language, "") for language in LANGUAGES}


def _structure_post(
    client: Client, version: SalahCourseVersion, data: dict[str, Any], **query: str
) -> Any:
    with patch(RESOLVER, FakeResolver):
        return client.post(
            _structure_url(version, **query), {"revision": version.checksum_sha256, **data}
        )


@pytest.mark.django_db
def test_the_owner_adds_a_section_a_lesson_and_a_step_from_the_tree(
    draft: SalahCourseVersion, owner_client: Client
) -> None:
    page = owner_client.get(_editor_url(draft, RUKU))
    assert b"action=add-step&amp;after=step%3Afajr.r1.ruku" in page.content
    assert b"action=delete&amp;node=step%3Afajr.r1.ruku" in page.content

    form = owner_client.get(_structure_url(draft, action="add-section"))
    assert form.status_code == 200
    assert "Новый раздел" in form.content.decode()
    response = _structure_post(
        owner_client,
        draft,
        {"action": "add-section", **_texts("title", {"ru": "Сахв", "en": "Sahw"})},
    )
    assert response.status_code == 302
    assert response["Location"].endswith("node=section%3Asakhv")
    draft.refresh_from_db()
    assert draft.snapshot["sections"][-1] == {
        "slug": "sakhv",
        "title": {"ru": "Сахв", "en": "Sahw", "ar": "", "tr": ""},
        "lessons": [],
    }
    response = _structure_post(
        owner_client,
        draft,
        {
            "action": "add-lesson",
            "section": "sakhv",
            "kind": "steps",
            "slug": "sahw",
            **_texts("title", _all("Сахв")),
            **_texts("summary", _all("Кратко")),
        },
    )
    assert response["Location"].endswith("node=lesson%3Asahw")
    draft.refresh_from_db()
    response = _structure_post(
        owner_client,
        draft,
        {
            "action": "add-step",
            "lesson": "sahw",
            "step_kind": "action",
            **_texts("title", {"ru": "Два поклона"}),
            **_texts("instruction", {}),
        },
    )
    assert response["Location"].endswith("node=step%3Asahw.dva-poklona")
    draft.refresh_from_db()
    assert draft.snapshot["lessons"][-1]["steps"][0]["kind"] == "action"
    page = owner_client.get(_editor_url(draft, "step:sahw.dva-poklona"))
    assert page.context["course_missing_total"] > 0
    assert page.context["properties"]["kind"] == "action"


@pytest.mark.django_db
def test_an_element_needs_a_name_and_a_stale_page_changes_nothing(
    draft: SalahCourseVersion, owner_client: Client
) -> None:
    response = _structure_post(
        owner_client, draft, {"action": "add-section", **_texts("title", {})}
    )
    assert response.status_code == 400
    assert response.context["fields"][0]["values"][0]["error"].startswith("Напишите название")
    before = copy.deepcopy(draft.snapshot)
    with patch(RESOLVER, FakeResolver):
        stale = owner_client.post(
            _structure_url(draft, action="down", node="step:fajr.r1.takbir"),
            {"revision": "0" * 64, "return": "step:fajr.r1.takbir"},
            follow=True,
        )
    assert "курс изменили" in stale.content.decode()
    draft.refresh_from_db()
    assert draft.snapshot == before


@pytest.mark.django_db
def test_arrows_and_drag_reorder_steps_and_lessons(
    draft: SalahCourseVersion, owner_client: Client
) -> None:
    response = _structure_post(
        owner_client, draft, {"return": RUKU}, action="up", node="step:fajr.r1.ruku"
    )
    assert response["Location"].endswith("node=step%3Afajr.r1.ruku")
    draft.refresh_from_db()
    assert _step_slugs(draft.snapshot, "fajr")[:2] == ["fajr.r1.ruku", "fajr.r1.takbir"]
    _structure_post(
        owner_client,
        draft,
        {"action": "move", "node": RUKU, "target": "step:fajr.r1.takbir", "position": "after"},
    )
    draft.refresh_from_db()
    assert _step_slugs(draft.snapshot, "fajr")[:2] == ["fajr.r1.takbir", "fajr.r1.ruku"]
    refused = _structure_post(
        owner_client,
        draft,
        {"action": "move", "node": RUKU, "target": "lesson:fajr", "position": "after"},
    )
    assert refused.status_code == 302
    page = owner_client.get(refused["Location"])
    assert "раздел на раздел, урок на урок, шаг на шаг" in page.content.decode()


@pytest.mark.django_db
def test_removing_asks_first_says_where_and_then_drops_the_recordings(
    draft: SalahCourseVersion, owner_client: Client
) -> None:
    confirm = owner_client.get(_structure_url(draft, action="delete", node=RUKU))
    text = confirm.content.decode()
    assert "Шаг общий: он удалится из шаблона и из всех этих мест — Фаджр (ракааты 1, 2)" in text
    assert "Да, удалить из черновика" in text
    response = _structure_post(owner_client, draft, {"action": "delete", "node": RUKU})
    assert response["Location"].endswith("node=lesson%3Afajr")
    draft.refresh_from_db()
    assert not any("ruku" in slug for slug in _step_slugs(draft.snapshot, "fajr"))
    assert "audio-ruku-ru" not in {asset["key"] for asset in draft.snapshot["media"]}
    assert not draft.media.filter(key="audio-ruku-ru").exists()


@pytest.mark.django_db
def test_a_change_that_would_break_the_course_is_refused(
    draft: SalahCourseVersion, owner_client: Client
) -> None:
    before = copy.deepcopy(draft.snapshot)
    with patch(
        "quran_backend.modules.salah.editor_structure_admin.integrity_problems",
        return_value=["Шаг «x»: нет формулы «y»."],
    ):
        response = _structure_post(
            owner_client, draft, {"return": RUKU}, action="up", node="step:fajr.r1.ruku"
        )
    page = owner_client.get(response["Location"])
    assert "Изменение сломало бы курс: Шаг «x»: нет формулы «y»." in page.content.decode()
    draft.refresh_from_db()
    assert draft.snapshot == before


@pytest.mark.django_db
def test_only_an_editor_of_an_open_draft_changes_the_structure(
    draft: SalahCourseVersion, owner_client: Client
) -> None:
    viewer = _staff_client("view_salahcourseversion")
    assert viewer.get(_structure_url(draft, action="add-section")).status_code == 403
    page = viewer.get(_editor_url(draft, RUKU))
    assert b"se-tree-ops" not in page.content
    with patch(RESOLVER, FakeResolver):
        owner_client.post(
            f"/admin/salah/salahcourseversion/{draft.pk}/review/", {"action": "sign", "node": RUKU}
        )
    draft.refresh_from_db()
    assert draft.is_signed
    assert owner_client.get(_structure_url(draft, action="add-section")).status_code == 403
    response = _structure_post(owner_client, draft, {}, action="up", node=RUKU)
    assert response.status_code == 403


@pytest.mark.django_db
def test_a_steps_properties_save_with_its_texts(
    draft: SalahCourseVersion, owner_client: Client
) -> None:
    data = {
        **_form(draft, RUKU),
        "prop-kind": "action",
        "prop-ruling": "wajib",
        "prop-media": "position-takbir",
        "prop-formula": ["ruku-tasbih", "", "takbir"],
        "prop-repeat": "1",
    }
    assert _post(owner_client, draft, RUKU, data).status_code == 302
    draft.refresh_from_db()
    ruku = draft.snapshot["templates"][0]["steps"][1]
    assert (ruku["kind"], ruku["ruling"], ruku["media"]) == ("action", "wajib", "position-takbir")
    assert ruku["formulas"] == ["ruku-tasbih", "takbir"]
    assert "repeat" not in ruku
    wrong = {**data, "prop-media": "audio-takbir", "prop-repeat": "500"}
    response = _post(owner_client, draft, RUKU, wrong)
    assert response.status_code == 400
    errors = response.context["properties"]["errors"]
    assert set(errors) == {"media", "repeat"}


@pytest.mark.django_db
def test_the_formula_page_edits_a_duas_wording_and_shows_the_source(
    draft: SalahCourseVersion, owner_client: Client
) -> None:
    node = "formula:ruku-tasbih"
    source = {"ru": {"arabic": "سبحان", "translation": "Источник", "transliteration": "Subhana"}}
    with (
        patch(
            "quran_backend.modules.salah.editor_admin.FormulaResolver.__init__", return_value=None
        ),
        patch(
            "quran_backend.modules.salah.editor_admin.FormulaResolver.resolve",
            side_effect=lambda language: {"ruku-tasbih": source.get(language, {})},
        ),
    ):
        page = owner_client.get(_editor_url(draft, node))
    meaning = page.context["fields"][0]
    assert meaning["values"][0]["source"] == "Источник"
    assert not meaning["revertible"]
    assert page.context["formula"]["source_arabic"] == "سبحان"
    assert "Вернуть текст источника" not in page.content.decode()

    data = {
        **_texts("meaning", {"ru": "Свой"}),
        **_texts("transliteration", {}),
        **_texts("caption", _all("Муслим")),
        "formula-arabic": "",
        "node_revision": page.context["revision"],
    }
    assert _post(owner_client, draft, node, data).status_code == 302
    draft.refresh_from_db()
    saved = draft.snapshot["formulas"][2]["source"]
    assert saved["translations"] == {"ru": {"meaning": "Свой"}}
    assert saved["caption"] == _all("Муслим")
    page = owner_client.get(_editor_url(draft, node))
    assert page.context["fields"][0]["revertible"]
    reverted = {**data, "node_revision": page.context["revision"], "revert": "meaning"}
    assert _post(owner_client, draft, node, reverted).status_code == 302
    draft.refresh_from_db()
    assert "translations" not in draft.snapshot["formulas"][2]["source"]


@pytest.mark.django_db
def test_signing_refuses_an_empty_new_lesson(
    draft: SalahCourseVersion, owner_client: Client
) -> None:
    _structure_post(
        owner_client,
        draft,
        {
            "action": "add-lesson",
            "section": "five-prayers",
            "kind": "article",
            **_texts("title", _all("Пусто")),
            **_texts("summary", _all("Кратко")),
        },
    )
    draft.refresh_from_db()
    with patch(RESOLVER, FakeResolver):
        response = owner_client.post(
            f"/admin/salah/salahcourseversion/{draft.pk}/review/",
            {"action": "sign", "node": "course"},
            follow=True,
        )
    assert "нет шагов" in response.content.decode()
    draft.refresh_from_db()
    assert not draft.is_signed
