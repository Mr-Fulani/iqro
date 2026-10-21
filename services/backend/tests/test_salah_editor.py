"""The course editor in the admin: who may edit what, saving, notes, recordings."""

from __future__ import annotations

# Russian interface strings intentionally contain characters that resemble Latin glyphs.
# ruff: noqa: RUF001
import copy
import json
import shutil
import subprocess
from pathlib import Path
from typing import Any
from unittest.mock import patch

import pytest
from django.conf import settings
from django.contrib.auth.models import Permission
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import Client

from quran_backend.modules.accounts.models import User
from quran_backend.modules.salah import editor
from quran_backend.modules.salah.compiler import compile_document
from quran_backend.modules.salah.importer import import_salah_snapshot
from quran_backend.modules.salah.models import (
    SALAH_LANGUAGES,
    SalahCourseVersion,
    SalahMediaAsset,
    SalahPublicationStatus,
)
from quran_backend.modules.salah.snapshot import SalahSnapshotError, validate_snapshot
from tests.test_salah import (
    COURSE_SNAPSHOT,
    FakeResolver,
    FakeUploader,
    _example_snapshot,
    _fake_formulas,
    _fake_media,
    _write_media,
)

FFMPEG = shutil.which("ffmpeg") or "ffmpeg"
needs_ffmpeg = pytest.mark.skipif(
    shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None,
    reason="ffmpeg and ffprobe are not installed",
)
LANGUAGES = editor.editor_languages(SALAH_LANGUAGES)
RUKU = "step:fajr.r1.ruku"
RESOLVER = "quran_backend.modules.salah.importer.FormulaResolver"
UPLOADER = "quran_backend.modules.salah.editor_admin.player_background_uploader"


def _editor_url(version: SalahCourseVersion, node: str = "course") -> str:
    return f"/admin/salah/salahcourseversion/{version.pk}/editor/?node={node}"


@pytest.fixture
def draft(tmp_path: Path) -> SalahCourseVersion:
    snapshot = _example_snapshot()
    _write_media(tmp_path, snapshot)
    with patch(RESOLVER, FakeResolver):
        return import_salah_snapshot(snapshot, data_dir=tmp_path, uploader=FakeUploader())


@pytest.fixture
def owner_client() -> Client:
    owner = User.objects.create_user(
        email="owner@example.test", status="active", is_staff=True, is_superuser=True
    )
    client = Client()
    client.force_login(owner)
    return client


def _staff_client(*codenames: str) -> Client:
    user = User.objects.create_user(
        email=f"staff-{'-'.join(codenames) or 'none'}@example.test", status="active", is_staff=True
    )
    user.user_permissions.set(Permission.objects.filter(codename__in=codenames))
    client = Client()
    client.force_login(user)
    return client


def _form(version: SalahCourseVersion, node_id: str) -> dict[str, Any]:
    """What the editor page sends unchanged for a place of the course."""
    snapshot = copy.deepcopy(version.snapshot)
    node = editor.find_node(snapshot, node_id)
    data: dict[str, Any] = {"node_revision": editor.node_revision(snapshot, node)}
    for text_field in node.fields:
        stored = node.data.get(text_field.name) or {}
        for language in LANGUAGES:
            data[f"text-{text_field.name}-{language}"] = stored.get(language, "")
    if node.has_notes:
        notes = node.data.get("notes", [])
        data["notes_order"] = ",".join(f"n{number}" for number in range(1, len(notes) + 1))
        for number, note in enumerate(notes, start=1):
            data[f"note-n{number}-kind"] = note["kind"]
            for language in LANGUAGES:
                data[f"note-n{number}-text-{language}"] = note["text"].get(language, "")
    return data


def _post(client: Client, version: SalahCourseVersion, node_id: str, data: dict[str, Any]) -> Any:
    with patch(RESOLVER, FakeResolver):
        return client.post(_editor_url(version, node_id), data)


def _audio(tmp_path: Path, name: str, *, seconds: float = 1.0) -> SimpleUploadedFile:
    path = tmp_path / name
    codec = "libmp3lame" if name.endswith(".mp3") else "aac"
    subprocess.run(  # noqa: S603 - test fixture, fixed arguments
        [
            FFMPEG, "-nostdin", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", f"sine=frequency=440:duration={seconds}",
            "-c:a", codec, "-b:a", "32k", str(path),
        ],
        check=True,
    )  # fmt: skip
    return SimpleUploadedFile(name, path.read_bytes(), content_type="audio/mpeg")


def _renamed(upload: SimpleUploadedFile, name: str) -> SimpleUploadedFile:
    return SimpleUploadedFile(name, upload.read(), content_type="audio/mpeg")


# The tree and the edits, without a database ---------------------------------


def _snapshot_with_variants() -> dict[str, Any]:
    """The example course plus a second prayer template whose ruku' differs."""
    snapshot = _example_snapshot()
    fard = snapshot["templates"][0]
    nafl_ruku = copy.deepcopy(fard["steps"][1])
    nafl_ruku["instruction"] = {language: f"other [{language}]" for language in LANGUAGES}
    nafl_ruku.pop("notes")
    snapshot["templates"].append(
        {"id": "nafl", "steps": [copy.deepcopy(fard["steps"][0]), nafl_ruku]}
    )
    # Ruku' of rak'ahs 2+ is a variant of the same step with the same words.
    second = copy.deepcopy(fard["steps"][1])
    fard["steps"][1]["when"] = {"rakat": 1}
    second["when"] = {"rakat": [2, 3, 4]}
    fard["steps"].insert(2, second)
    return snapshot


def test_the_tree_shows_each_lesson_step_and_finds_its_template_step() -> None:
    snapshot = _example_snapshot()
    tree = editor.editor_tree(snapshot, LANGUAGES)

    assert editor.flat_ids(tree) == [
        "course",
        "section:five-prayers",
        "lesson:fajr",
        "step:fajr.r1.takbir",
        "step:fajr.r1.ruku",
        "step:fajr.r2.ruku",
        "step:fajr.r2.tashahhud",
        "formula:takbir",
        "formula:fatiha",
        "formula:ruku-tasbih",
        "formula:tashahhud",
    ]
    lesson = tree[1].children[0]
    assert [child.label for child in lesson.children][1] == "2. Р1 · Руку'"
    assert lesson.children[1].notes == 2
    assert lesson.children[1].audio is True
    # Both rak'ahs show one template step: an edit changes both.
    first = editor.find_node(snapshot, "step:fajr.r1.ruku")
    second = editor.find_node(snapshot, "step:fajr.r2.ruku")
    assert first.data is second.data
    assert (first.template_id, first.template_index, first.rakat) == ("fard-prayer", 1, 1)
    assert editor.template_step_usage(snapshot, first) == [("Фаджр", "ракааты 1, 2")]
    assert editor.describe_when({"recitation": "sirr", "rakat": [2, 3, 4]}) == (
        "чтение про себя · ракааты 2, 3, 4"
    )
    with pytest.raises(editor.EditorNodeNotFoundError):
        editor.find_node(snapshot, "step:fajr.r9.ruku")


def test_languages_come_from_the_settings_with_the_source_language_first() -> None:
    assert set(LANGUAGES) == {code for code, _name in settings.LANGUAGES}
    assert LANGUAGES[0] == "ru"
    assert editor.editor_languages(["ar", "en", "ru", "tr", "uz"]) == ["ru", "ar", "en", "tr", "uz"]


def test_untranslated_texts_are_counted_and_an_empty_optional_one_is_complete() -> None:
    snapshot = _example_snapshot()
    node = editor.find_node(snapshot, RUKU)
    assert editor.node_missing(node, LANGUAGES) == dict.fromkeys(LANGUAGES, 0)

    node.data["title"]["en"] = " "
    node.data["details"] = {"ru": "Только по-русски", "en": "", "ar": "", "tr": ""}
    node.data["notes"][0]["text"]["tr"] = ""
    assert editor.node_missing(node, LANGUAGES) == {"ru": 0, "ar": 1, "en": 2, "tr": 2}
    assert editor.course_missing(snapshot, LANGUAGES)["en"] == 2
    node.data["details"] = dict.fromkeys(LANGUAGES, "")
    assert editor.node_missing(node, LANGUAGES)["ar"] == 0


def test_an_edit_reaches_variants_only_where_their_text_was_identical() -> None:
    snapshot = _snapshot_with_variants()
    node = editor.find_node(snapshot, "step:fajr.r1.ruku")
    assert len(editor.variant_descriptions(snapshot, node)) == 2
    form = {
        **{f"text-title-{language}": f"Ruku [{language}]" for language in LANGUAGES},
        **{
            f"text-instruction-{language}": node.data["instruction"][language]
            for language in LANGUAGES
        },
        "notes_order": "a",
        "note-a-kind": "warning",
        "note-a-text-ru": "Новая заметка",
    }
    edit = editor.parse_node_form(node, form, LANGUAGES)
    assert edit.errors == {}

    synced = editor.apply_node_edit(snapshot, node, edit, LANGUAGES, sync_variants=True)

    fard, nafl = snapshot["templates"]
    assert synced == 2
    assert fard["steps"][2]["title"]["en"] == "Ruku [en]"
    assert nafl["steps"][1]["title"]["en"] == "Ruku [en]"
    # The rak'ah 2+ variant shows the same words, so it takes the notes too;
    # nafl's ruku' says something else and keeps its own (none).
    assert fard["steps"][2]["notes"] == [
        {"kind": "warning", "text": {"ru": "Новая заметка", "ar": "", "en": "", "tr": ""}}
    ]
    assert "notes" not in nafl["steps"][1]
    # Details were left empty in every language: the optional text is removed.
    assert "details" not in node.data


def test_without_sync_only_the_edited_variant_changes() -> None:
    snapshot = _snapshot_with_variants()
    node = editor.find_node(snapshot, "step:fajr.r1.ruku")
    form = _form_from_snapshot(snapshot, node)
    form["text-title-ru"] = "Только здесь"
    edit = editor.parse_node_form(node, form, LANGUAGES)

    assert editor.apply_node_edit(snapshot, node, edit, LANGUAGES, sync_variants=False) == 0
    assert snapshot["templates"][0]["steps"][2]["title"]["ru"] == "Руку'"


def _form_from_snapshot(snapshot: dict[str, Any], node: editor.EditorNode) -> dict[str, Any]:
    data = {
        f"text-{text_field.name}-{language}": (node.data.get(text_field.name) or {}).get(
            language, ""
        )
        for text_field in node.fields
        for language in LANGUAGES
    }
    notes = node.data.get("notes", [])
    data["notes_order"] = ",".join(str(number) for number in range(len(notes)))
    for number, note in enumerate(notes):
        data[f"note-{number}-kind"] = note["kind"]
        data.update(
            {f"note-{number}-text-{language}": note["text"][language] for language in LANGUAGES}
        )
    return data


def test_form_problems_are_keyed_by_the_field_that_has_them() -> None:
    snapshot = _example_snapshot()
    node = editor.find_node(snapshot, RUKU)
    form = _form_from_snapshot(snapshot, node)
    form["text-title-ar"] = "ا" * 121
    form["notes_order"] = "0,1,blank"
    form["note-1-kind"] = "tip"
    form["note-blank-kind"] = "help"

    edit = editor.parse_node_form(node, form, LANGUAGES)

    assert edit.errors == {
        "text-title-ar": "Слишком длинно: 121 знаков, допустимо до 120.",
        "note-1-kind": "Выберите тип заметки: справка «?» или важно «!».",
    }
    # An added note left empty is simply not kept.
    assert [note["uid"] for note in edit.notes or []] == ["0", "1"]


# The snapshot schema: notes and recordings ----------------------------------


def test_snapshot_validation_checks_notes_and_recordings() -> None:
    snapshot = _example_snapshot()
    ruku = snapshot["templates"][0]["steps"][1]
    ruku["notes"][1]["kind"] = "tip"
    ruku["notes"][0]["text"].pop("ar")
    ruku["audio_media"] = "position-ruku"
    ruku["audio_media_languages"] = {"de": "audio-ruku-ru", "en": "missing"}
    snapshot["formulas"][0]["source"]["audio_media_languages"] = {"ru": "nowhere"}

    with pytest.raises(SalahSnapshotError) as error:
        validate_snapshot(snapshot)

    problems = "\n".join(error.value.problems)
    assert "Шаг «fajr.r1.ruku», заметка 2: тип должен быть help или warning." in problems
    assert "Шаг «fajr.r1.ruku», заметка 1: нет текста на «ar»." in problems
    # A picture is not a recording.
    assert "Шаг «fajr.r1.ruku»: нет записи «position-ruku» в media." in problems
    assert "Шаг «fajr.r1.ruku»: запись на неизвестном языке «de»." in problems
    assert "Шаг «fajr.r1.ruku»: нет записи «missing» в media." in problems
    assert "Формула «takbir»: нет записи «nowhere» в media." in problems


def test_compiled_steps_carry_notes_and_the_recording_of_their_language() -> None:
    snapshot = _example_snapshot()
    ruku = snapshot["templates"][0]["steps"][1]
    ruku["audio_media"] = "audio-takbir"
    ruku["notes"][1]["text"]["en"] = ""
    media = _fake_media(snapshot)
    documents = {
        language: compile_document(
            snapshot,
            language=language,
            course_meta={"slug": "hanbali-umdah", "version": "v", "methodology": "hanbali"},
            formulas=_fake_formulas(snapshot),
            media=media,
        )
        for language in LANGUAGES
    }

    ru_step = documents["ru"]["lessons"][0]["steps"][1]
    assert ru_step["notes"] == [
        {"kind": "help", "text": ruku["notes"][0]["text"]["ru"]},
        {"kind": "warning", "text": ruku["notes"][1]["text"]["ru"]},
    ]
    # The Russian voice-over wins over the recording for every language.
    assert ru_step["audio"] == {"url": media["audio-ruku-ru"]["url"]}
    en_step = documents["en"]["lessons"][0]["steps"][1]
    assert en_step["audio"] == {"url": media["audio-takbir"]["url"]}
    # An untranslated draft note is left out of that language.
    assert [note["kind"] for note in en_step["notes"]] == ["help"]
    # Recordings never enter the pictures map the clients read.
    assert "audio-ruku-ru" not in documents["ru"]["media"]
    assert "notes" not in documents["ru"]["lessons"][0]["steps"][0]


@pytest.mark.parametrize("version", ["2026-10-18", "2026-10-21"])
def test_published_course_versions_still_validate_and_compile(version: str) -> None:
    """The course as published: no notes, no step recordings; 10-18 also had no 3D stills."""
    snapshot = json.loads(COURSE_SNAPSHOT.read_text(encoding="utf-8"))
    snapshot["course"]["version"] = version
    if version == "2026-10-18":
        for asset in snapshot["media"]:
            asset.pop("scene", None)
    validate_snapshot(snapshot)
    for language in LANGUAGES:
        document = compile_document(
            snapshot,
            language=language,
            course_meta={"slug": "hanbali-umdah", "version": version, "methodology": "hanbali"},
            formulas=_fake_formulas(snapshot),
            media=_fake_media(snapshot),
        )
        steps = [step for lesson in document["lessons"] for step in lesson["steps"]]
        assert all("notes" not in step and "audio" not in step for step in steps)
        assert all(step["title"] and step["instruction"] for step in steps)


# The admin ------------------------------------------------------------------


@pytest.mark.django_db
def test_the_draft_editor_saves_texts_and_notes_in_order(
    draft: SalahCourseVersion, owner_client: Client
) -> None:
    page = owner_client.get(_editor_url(draft, RUKU))
    content = page.content.decode()
    assert page.status_code == 200
    assert "Этот шаг общий." in content
    assert 'name="text-instruction-ar"' in content
    assert 'lang="ar" dir="rtl"' in content
    assert "Заметки «?» и «!»" in content
    assert 'id="se-preview-data"' in content
    checksum = draft.checksum_sha256

    form = _form(draft, RUKU)
    form["text-title-ru"] = "Руку' — поясной поклон"
    form["text-title-en"] = ""
    form["notes_order"] = "n2,n1,new1"
    form["note-new1-kind"] = "help"
    form["note-new1-text-ru"] = "Пальцы ладоней раскрыты."
    response = _post(owner_client, draft, RUKU, {**form, "save_next": "1"})

    assert response.status_code == 302
    assert response["Location"].endswith("?node=step%3Afajr.r2.ruku")
    draft.refresh_from_db()
    ruku = draft.snapshot["templates"][0]["steps"][1]
    assert ruku["title"]["ru"] == "Руку' — поясной поклон"
    # Untranslated is fine in a draft: it is counted, not refused.
    assert ruku["title"]["en"] == ""
    assert [note["kind"] for note in ruku["notes"]] == ["warning", "help", "help"]
    assert draft.checksum_sha256 != checksum
    document = draft.documents.get(language="ru").payload
    compiled = document["lessons"][0]["steps"][1]
    assert compiled["title"] == "Руку' — поясной поклон"
    assert compiled["notes"][2] == {"kind": "help", "text": "Пальцы ладоней раскрыты."}

    page = owner_client.get(response["Location"])
    content = page.content.decode()
    assert "Сохранено. Здесь не переведено полей: 4." in content
    assert "Во всём курсе не переведено:" in content


@pytest.mark.django_db
def test_a_stale_form_is_refused_and_keeps_what_was_typed(
    draft: SalahCourseVersion, owner_client: Client
) -> None:
    form = _form(draft, RUKU)
    first = {**form, "text-title-tr": "Rükû (ilk)"}
    assert _post(owner_client, draft, RUKU, first).status_code == 302

    second = {**form, "text-title-tr": "Başka sekmeden"}
    response = _post(owner_client, draft, RUKU, second)

    assert response.status_code == 409
    content = response.content.decode()
    assert "пока форма была открыта, это место курса изменили" in content
    assert "Başka sekmeden" in content
    draft.refresh_from_db()
    assert draft.snapshot["templates"][0]["steps"][1]["title"]["tr"] == "Rükû (ilk)"


@pytest.mark.django_db
def test_form_errors_are_shown_in_place_and_nothing_is_saved(
    draft: SalahCourseVersion, owner_client: Client
) -> None:
    checksum = draft.checksum_sha256
    form = _form(draft, "lesson:fajr")
    form["text-summary-ru"] = "Очень длинно. " * 40
    form["text-title-en"] = "Dawn prayer"

    response = _post(owner_client, draft, "lesson:fajr", form)

    assert response.status_code == 400
    content = response.content.decode()
    assert "Ничего не сохранено: исправьте отмеченные поля." in content
    assert "допустимо до 400." in content
    assert "Dawn prayer" in content
    draft.refresh_from_db()
    assert draft.checksum_sha256 == checksum


@pytest.mark.django_db
def test_signed_and_published_versions_are_read_only_with_a_copy_button(
    draft: SalahCourseVersion, owner_client: Client
) -> None:
    owner = User.objects.get(email="owner@example.test")
    form = _form(draft, RUKU)
    with patch(RESOLVER, FakeResolver):
        response = owner_client.post(
            f"/admin/salah/salahcourseversion/{draft.pk}/review/",
            {"action": "sign", "node": RUKU},
        )
    assert response.status_code == 302
    draft.refresh_from_db()
    assert draft.reviewed_by == owner

    page = owner_client.get(_editor_url(draft, RUKU)).content.decode()
    assert "Только чтение." in page
    assert "Черновик подписан и ждёт публикации" in page
    assert "Создать черновик из этой версии" in page
    assert "readonly" in page
    assert 'name="save"' not in page
    assert _post(owner_client, draft, RUKU, form).status_code == 403

    with (
        patch(RESOLVER, FakeResolver),
        patch("quran_backend.modules.salah.importer.enqueue_salah_content_change"),
    ):
        owner_client.post(
            f"/admin/salah/salahcourseversion/{draft.pk}/review/", {"action": "publish"}
        )
    draft.refresh_from_db()
    assert draft.status == SalahPublicationStatus.PUBLISHED
    page = owner_client.get(_editor_url(draft, RUKU)).content.decode()
    assert "Версия опубликована" in page
    assert _post(owner_client, draft, RUKU, form).status_code == 403
    change = owner_client.get(f"/admin/salah/salahcourseversion/{draft.pk}/change/")
    assert "Создать черновик из этой версии" in change.content.decode()


@pytest.mark.django_db
def test_signing_needs_every_translation(draft: SalahCourseVersion, owner_client: Client) -> None:
    form = _form(draft, RUKU)
    form["note-n1-text-tr"] = ""
    assert _post(owner_client, draft, RUKU, form).status_code == 302

    response = owner_client.post(
        f"/admin/salah/salahcourseversion/{draft.pk}/review/",
        {"action": "sign", "node": RUKU},
        follow=True,
    )

    assert "Подписать пока нельзя: есть непереведённые тексты (tr: 1)." in response.content.decode()
    draft.refresh_from_db()
    assert not draft.is_signed


@pytest.mark.django_db
def test_view_permission_reads_the_course_and_change_permission_edits_it(
    draft: SalahCourseVersion,
) -> None:
    form = _form(draft, RUKU)
    nobody = _staff_client()
    assert nobody.get(_editor_url(draft, RUKU)).status_code == 403

    reader = _staff_client("view_salahcourseversion")
    page = reader.get(_editor_url(draft, RUKU)).content.decode()
    assert "У вас право только на просмотр курса." in page
    assert "Создать черновик из этой версии" not in page
    assert _post(reader, draft, RUKU, form).status_code == 403
    assert reader.get(f"/admin/salah/salahcourseversion/{draft.pk}/new-draft/").status_code == 403

    editor_client = _staff_client("view_salahcourseversion", "change_salahcourseversion")
    assert _post(editor_client, draft, RUKU, form).status_code == 302


@pytest.mark.django_db
def test_a_new_draft_copies_the_content_and_files_and_leaves_the_source(
    draft: SalahCourseVersion, owner_client: Client
) -> None:
    draft.status = SalahPublicationStatus.WITHDRAWN
    draft.save(update_fields=["status"])
    url = f"/admin/salah/salahcourseversion/{draft.pk}/new-draft/"
    page = owner_client.get(url).content.decode()
    assert "полная копия версии <b>2026-10-18</b>" in page

    assert owner_client.post(url, {"version": "2026-10-18"}).status_code == 400
    assert owner_client.post(url, {"version": "bad name"}).status_code == 400
    with patch(RESOLVER, FakeResolver):
        response = owner_client.post(url, {"version": "2026-10-22"})

    copy_ = SalahCourseVersion.objects.get(version="2026-10-22")
    assert response.status_code == 302
    assert response["Location"] == _editor_url(copy_)
    assert copy_.status == SalahPublicationStatus.DRAFT
    assert not copy_.is_signed
    assert copy_.snapshot["course"]["version"] == "2026-10-22"
    assert copy_.snapshot["lessons"] == draft.snapshot["lessons"]
    assert sorted(copy_.media.values_list("key", "object_key")) == sorted(
        draft.media.values_list("key", "object_key")
    )
    assert copy_.documents.count() == len(SALAH_LANGUAGES)
    draft.refresh_from_db()
    assert draft.snapshot["course"]["version"] == "2026-10-18"


@pytest.mark.django_db
def test_the_snapshot_downloads_as_json(draft: SalahCourseVersion, owner_client: Client) -> None:
    response = owner_client.get(f"/admin/salah/salahcourseversion/{draft.pk}/snapshot.json")

    assert response.status_code == 200
    assert response["Content-Disposition"] == 'attachment; filename="hanbali-umdah-2026-10-18.json"'
    assert json.loads(response.content) == draft.snapshot


@needs_ffmpeg
@pytest.mark.django_db
def test_recordings_upload_per_language_replace_and_delete(
    draft: SalahCourseVersion, owner_client: Client, tmp_path: Path
) -> None:
    uploader = FakeUploader()
    form = _form(draft, RUKU)
    with patch(UPLOADER, return_value=uploader):
        response = _post(
            owner_client,
            draft,
            RUKU,
            {
                **form,
                "audio__step__en": _audio(tmp_path, "ruku-en.mp3"),
                "audio__formula.ruku-tasbih__all": _audio(tmp_path, "tasbih.m4a"),
            },
        )

    assert response.status_code == 302
    draft.refresh_from_db()
    ruku = draft.snapshot["templates"][0]["steps"][1]
    en_key = ruku["audio_media_languages"]["en"]
    assert ruku["audio_media_languages"]["ru"] == "audio-ruku-ru"
    assert en_key.startswith("audio-step-fajr-r1-ruku-en-")
    tasbih = next(f for f in draft.snapshot["formulas"] if f["id"] == "ruku-tasbih")
    formula_key = tasbih["source"]["audio_media"]
    assert {"key": en_key, "file": f"media/{en_key}.mp3"} in draft.snapshot["media"]
    asset = draft.media.get(key=en_key)
    assert asset.content_type == "audio/mpeg"
    assert 900 <= (asset.duration_ms or 0) <= 1200
    assert draft.media.get(key=formula_key).content_type == "audio/mp4"
    en = draft.documents.get(language="en").payload
    assert en["lessons"][0]["steps"][1]["audio"]["url"].endswith(asset.object_key)
    page = owner_client.get(_editor_url(draft, RUKU)).content.decode()
    assert "0:01 · " in page

    form = _form(draft, RUKU)
    with patch(UPLOADER, return_value=uploader):
        _post(owner_client, draft, RUKU, {**form, "audio__step__en": _audio(tmp_path, "new.mp3")})
    draft.refresh_from_db()
    replaced = draft.snapshot["templates"][0]["steps"][1]["audio_media_languages"]["en"]
    assert replaced != en_key
    assert not draft.media.filter(key=en_key).exists()
    assert all(asset["key"] != en_key for asset in draft.snapshot["media"])

    form = _form(draft, RUKU)
    _post(owner_client, draft, RUKU, {**form, "audio_delete__step__en": "on"})
    draft.refresh_from_db()
    ruku = draft.snapshot["templates"][0]["steps"][1]
    assert ruku["audio_media_languages"] == {"ru": "audio-ruku-ru"}
    assert not draft.media.filter(key=replaced).exists()
    validate_snapshot(draft.snapshot)


@needs_ffmpeg
@pytest.mark.django_db
def test_a_file_that_is_not_a_short_m4a_or_mp3_is_refused(
    draft: SalahCourseVersion, owner_client: Client, tmp_path: Path
) -> None:
    checksum = draft.checksum_sha256

    def refused(upload: SimpleUploadedFile) -> str:
        form = {**_form(draft, RUKU), "text-title-ru": "Не потеряется", "audio__step__ru": upload}
        with patch(UPLOADER, return_value=FakeUploader()):
            response = _post(owner_client, draft, RUKU, form)
        assert response.status_code == 400
        content = response.content.decode()
        assert "Не потеряется" in content
        return content

    assert "Нужна запись в формате .m4a или .mp3." in refused(
        SimpleUploadedFile("voice.wav", b"RIFF....WAVE")
    )
    assert "Файл не похож на запись MP3." in refused(
        SimpleUploadedFile("voice.mp3", b"<html>not audio</html>")
    )
    assert "Файл не похож на запись MP3." in refused(
        _renamed(_audio(tmp_path, "real.m4a"), "voice.mp3")
    )
    assert "Файл не похож на запись M4A." in refused(
        _renamed(_audio(tmp_path, "real.mp3"), "voice.m4a")
    )
    assert "Запись длится 3:20, допустимо до 3 минут." in refused(
        _audio(tmp_path, "long.mp3", seconds=200)
    )
    with patch("quran_backend.modules.salah.media_upload.MAX_AUDIO_BYTES", 1024):
        assert "Файл должен быть не больше" in refused(_audio(tmp_path, "big.mp3", seconds=5))
    draft.refresh_from_db()
    assert draft.checksum_sha256 == checksum
    assert not SalahMediaAsset.objects.filter(key__startswith="audio-step-").exists()


@pytest.mark.django_db
def test_the_course_page_explains_the_editor_and_edits_the_source_title(
    draft: SalahCourseVersion, owner_client: Client
) -> None:
    page = owner_client.get(_editor_url(draft)).content.decode()
    assert "Как пользоваться редактором" in page
    assert (
        "Открыть редактор курса"
        in owner_client.get(f"/admin/salah/salahcourseversion/{draft.pk}/change/").content.decode()
    )

    form = _form(draft, "course")
    form["text-source_title-en"] = "Umdat al-Fiqh, revised"
    assert _post(owner_client, draft, "course", form).status_code == 302
    draft.refresh_from_db()
    assert draft.source_title["en"] == "Umdat al-Fiqh, revised"
    assert draft.documents.get(language="en").payload["course"]["source_title"] == (
        "Umdat al-Fiqh, revised"
    )
