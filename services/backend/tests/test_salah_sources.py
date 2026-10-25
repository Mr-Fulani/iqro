# Russian course texts intentionally contain Cyrillic letters.
# ruff: noqa: RUF001
"""«Автор и источники» of the prayer course and «Источники» of its lessons.

Contract: docs/salah/sources.md.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any
from unittest.mock import patch

import pytest
from django.test import Client

from quran_backend.modules.salah import editor
from quran_backend.modules.salah.compiler import compile_document
from quran_backend.modules.salah.models import (
    SALAH_LANGUAGES,
    SalahCourseVersion,
    SalahPublicationStatus,
)
from quran_backend.modules.salah.snapshot import (
    SOURCES_MAX_LENGTH,
    SalahSnapshotError,
    integrity_problems,
    validate_snapshot,
)
from tests.test_salah import COURSE_SNAPSHOT, _example_snapshot, _fake_formulas, _fake_media
from tests.test_salah_editor import (
    LANGUAGES,
    RESOLVER,
    FakeResolver,
    _editor_url,
    _form,
    _post,
    draft,
    owner_client,
)

__all__ = ["draft", "owner_client"]

LESSON = "lesson:fajr"


def _all(text: str) -> dict[str, str]:
    return {language: f"{text} ({language})" for language in SALAH_LANGUAGES}


def _compiled(snapshot: dict[str, Any], language: str = "ru") -> dict[str, Any]:
    return compile_document(
        snapshot,
        language=language,
        course_meta={"slug": "hanbali-umdah", "version": "1", "methodology": "hanbali"},
        formulas=_fake_formulas(snapshot),
        media=_fake_media(snapshot),
    )


def test_a_course_without_sources_still_validates_and_has_no_blocks() -> None:
    snapshot = json.loads(Path(COURSE_SNAPSHOT).read_text(encoding="utf-8"))
    validate_snapshot(snapshot)
    document = _compiled(snapshot)
    assert "source" not in document["course"]
    assert all("sources" not in lesson for lesson in document["lessons"])


def test_sources_compile_line_by_line_in_the_language_of_the_document() -> None:
    snapshot = _example_snapshot()
    snapshot["course"]["source"] = _all("Составитель и проверка")
    snapshot["lessons"][0]["sources"] = {
        language: f"Умдат аль-фикх, {language}\n\n  Аль-Мугни, 1/500  \n"
        for language in SALAH_LANGUAGES
    }
    validate_snapshot(snapshot)

    document = _compiled(snapshot, "en")

    assert document["course"]["source"] == "Составитель и проверка (en)"
    assert document["lessons"][0]["sources"] == ["Умдат аль-фикх, en", "Аль-Мугни, 1/500"]


def test_sources_written_in_one_language_wait_for_the_others_only_at_the_sign_off() -> None:
    snapshot = _example_snapshot()
    snapshot["lessons"][0]["sources"] = {"ru": "Умдат аль-фикх"}

    with pytest.raises(SalahSnapshotError) as error:
        validate_snapshot(snapshot)

    assert "Урок «fajr».sources: нет текста на «en»." in error.value.problems
    # A draft may be translated later: saving it is not refused.
    assert integrity_problems(snapshot) == []
    # The untranslated languages get no block rather than an empty one.
    assert "sources" not in _compiled(snapshot, "en")["lessons"][0]


def test_too_long_or_malformed_sources_are_refused_even_in_a_draft() -> None:
    snapshot = _example_snapshot()
    snapshot["course"]["source"] = "Умдат аль-фикх"
    too_long = "а" * (SOURCES_MAX_LENGTH + 1)
    snapshot["lessons"][0]["sources"] = dict.fromkeys(SALAH_LANGUAGES, too_long)

    assert integrity_problems(snapshot) == [
        "course.source: ожидаются тексты по языкам.",
        *(
            f"Урок «fajr».sources [{language}]: длиннее {SOURCES_MAX_LENGTH} знаков."
            for language in SALAH_LANGUAGES
        ),
    ]


def test_empty_sources_are_complete_and_written_ones_are_counted_until_translated() -> None:
    snapshot = _example_snapshot()
    assert editor.course_missing(snapshot, LANGUAGES) == dict.fromkeys(LANGUAGES, 0)

    snapshot["course"]["source"] = {"ru": "Составитель курса"}

    assert editor.course_missing(snapshot, LANGUAGES) == {
        language: int(language != "ru") for language in LANGUAGES
    }


# The admin ------------------------------------------------------------------


@pytest.mark.django_db
def test_the_editor_writes_the_sources_and_previews_them(
    draft: SalahCourseVersion, owner_client: Client
) -> None:
    course = owner_client.get(_editor_url(draft)).content.decode()
    assert 'name="text-source-ru"' in course
    assert "Автор и источники" in course
    assert "Как увидят ученики" in course
    assert '{"kind": "course"}' in course

    form = _form(draft, "course")
    for language in LANGUAGES:
        form[f"text-source-{language}"] = f"Составитель курса ({language})"
    assert _post(owner_client, draft, "course", form).status_code == 302

    lesson = owner_client.get(_editor_url(draft, LESSON)).content.decode()
    assert 'name="text-sources-ru"' in lesson
    assert "По одному источнику на строку" in lesson
    assert '{"kind": "lesson"}' in lesson
    form = _form(draft, LESSON)
    for language in LANGUAGES:
        form[f"text-sources-{language}"] = f"Умдат аль-фикх\r\nАль-Мугни ({language})"
    assert _post(owner_client, draft, LESSON, form).status_code == 302

    draft.refresh_from_db()
    assert draft.snapshot["lessons"][0]["sources"]["ru"] == "Умдат аль-фикх\nАль-Мугни (ru)"
    document = draft.documents.get(language="ar").payload
    assert document["course"]["source"] == "Составитель курса (ar)"
    assert document["lessons"][0]["sources"] == ["Умдат аль-фикх", "Аль-Мугни (ar)"]

    # Emptied in every language, the field leaves the snapshot and the documents.
    form = _form(draft, LESSON)
    for language in LANGUAGES:
        form[f"text-sources-{language}"] = ""
    assert _post(owner_client, draft, LESSON, form).status_code == 302
    draft.refresh_from_db()
    assert "sources" not in draft.snapshot["lessons"][0]
    assert "sources" not in draft.documents.get(language="ru").payload["lessons"][0]


@pytest.mark.django_db
def test_sources_do_not_block_the_sign_off_but_a_partial_translation_does(
    draft: SalahCourseVersion, owner_client: Client
) -> None:
    form = _form(draft, "course")
    for language in LANGUAGES:
        form[f"text-source-{language}"] = "Составитель курса" if language == "ru" else ""
    assert _post(owner_client, draft, "course", form).status_code == 302

    def sign() -> str:
        with patch(RESOLVER, FakeResolver):
            response = owner_client.post(
                f"/admin/salah/salahcourseversion/{draft.pk}/review/",
                {"action": "sign", "node": "course"},
                follow=True,
            )
        return str(response.content.decode())

    others = ", ".join(f"{language}: 1" for language in LANGUAGES if language != "ru")
    assert f"есть непереведённые тексты ({others})" in sign()
    draft.refresh_from_db()
    assert not draft.is_signed

    form = _form(draft, "course")
    for language in LANGUAGES:
        form[f"text-source-{language}"] = ""
    assert _post(owner_client, draft, "course", form).status_code == 302
    sign()
    draft.refresh_from_db()
    assert draft.is_signed


@pytest.mark.django_db
def test_a_new_draft_keeps_the_sources(draft: SalahCourseVersion, owner_client: Client) -> None:
    snapshot = draft.snapshot
    snapshot["course"]["source"] = _all("Составитель")
    snapshot["lessons"][0]["sources"] = _all("Умдат аль-фикх")
    draft.snapshot = snapshot
    draft.status = SalahPublicationStatus.WITHDRAWN
    draft.save(update_fields=["snapshot", "status"])

    with patch(RESOLVER, FakeResolver):
        owner_client.post(
            f"/admin/salah/salahcourseversion/{draft.pk}/new-draft/", {"version": "2026-10-25"}
        )

    copy_ = SalahCourseVersion.objects.get(version="2026-10-25")
    assert copy_.snapshot["course"]["source"] == _all("Составитель")
    assert copy_.snapshot["lessons"][0]["sources"] == _all("Умдат аль-фикх")
    assert copy_.documents.get(language="tr").payload["lessons"][0]["sources"] == [
        "Умдат аль-фикх (tr)"
    ]
