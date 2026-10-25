# Russian course texts intentionally contain Cyrillic letters.
# ruff: noqa: RUF001
"""«Автор и источники» of the tajweed course and «Источники» of its lessons.

Contract: docs/tajweed/course.md, «Источники».
"""

from __future__ import annotations

from typing import Any

import pytest
from django.urls import reverse

from quran_backend.modules.accounts.models import User
from quran_backend.modules.tajweed.course import (
    SOURCE_MAX_LENGTH,
    TajweedCourseError,
    compile_course_document,
    missing_texts,
    validate_course_snapshot,
)
from quran_backend.modules.tajweed.course_publication import (
    copy_tajweed_course,
    import_tajweed_course,
    sign_tajweed_course,
)
from quran_backend.modules.tajweed.models import TAJWEED_COURSE_LANGUAGES
from tests.test_tajweed_course import _izhar, _snapshot, owner

__all__ = ["owner"]


def _all(text: str) -> dict[str, str]:
    return {language: f"{text} ({language})" for language in TAJWEED_COURSE_LANGUAGES}


def _document(snapshot: dict[str, Any], language: str = "ru") -> dict[str, Any]:
    return compile_course_document(snapshot, language=language, course_meta={})


def test_a_course_without_sources_still_validates_and_gives_empty_blocks() -> None:
    snapshot = _snapshot()
    validate_course_snapshot(snapshot)
    assert missing_texts(snapshot) == dict.fromkeys(TAJWEED_COURSE_LANGUAGES, 0)
    document = _document(snapshot)
    assert document["course"]["source"] == ""
    assert all(lesson["sources"] == [] for lesson in document["lessons"])


def test_sources_compile_line_by_line_in_the_language_of_the_document() -> None:
    snapshot = _snapshot()
    snapshot["course"]["source"] = _all("Составитель и проверка")
    _izhar(snapshot)["sources"] = {
        language: f"Хидаят аль-мустафид, {language}\n\n  Тухфат аль-атфаль, бейт 27  \n"
        for language in TAJWEED_COURSE_LANGUAGES
    }
    validate_course_snapshot(snapshot)

    document = _document(snapshot, "tr")

    assert document["course"]["source"] == "Составитель и проверка (tr)"
    assert _izhar(document)["sources"] == ["Хидаят аль-мустафид, tr", "Тухфат аль-атфаль, бейт 27"]


def test_sources_written_in_one_language_are_counted_and_wait_for_the_sign_off() -> None:
    snapshot = _snapshot()
    _izhar(snapshot)["sources"] = {"ru": "Тухфат аль-атфаль"}

    assert missing_texts(snapshot) == {
        language: int(language != "ru") for language in TAJWEED_COURSE_LANGUAGES
    }
    # A draft is saved with them; the sign-off needs every language.
    validate_course_snapshot(snapshot, complete=False)
    with pytest.raises(TajweedCourseError) as error:
        validate_course_snapshot(snapshot)
    assert "Урок «izhar»: источники [en]: нет текста." in error.value.problems


def test_too_long_or_malformed_sources_are_refused_even_in_a_draft() -> None:
    snapshot = _snapshot()
    snapshot["course"]["source"] = dict.fromkeys(TAJWEED_COURSE_LANGUAGES, "а" * 301)
    _izhar(snapshot)["sources"] = "Тухфат аль-атфаль"

    with pytest.raises(TajweedCourseError) as error:
        validate_course_snapshot(snapshot, complete=False)

    assert error.value.problems == [
        *(
            f"Курс: автор и источники [{language}]: длиннее {SOURCE_MAX_LENGTH} знаков."
            for language in TAJWEED_COURSE_LANGUAGES
        ),
        "Урок «izhar»: источники: нужен объект с текстами по языкам.",
    ]


@pytest.mark.django_db
def test_the_editor_writes_and_previews_the_sources_and_the_copy_keeps_them(
    client: Any, owner: User
) -> None:
    version = import_tajweed_course(_snapshot())
    client.force_login(owner)
    editor = reverse("admin:tajweed_tajweedcourseversion_editor", args=[version.pk])

    course = client.get(editor, {"node": "course"}).content.decode()
    assert "Автор и источники" in course
    assert 'name="source__ru"' in course
    data: dict[str, Any] = {"node": "course", "review_status": "pending_teacher_review"}
    for field in ("title", "summary"):
        for language, text in version.snapshot["course"][field].items():
            data[f"{field}__{language}"] = text
    for language in TAJWEED_COURSE_LANGUAGES:
        data[f"source__{language}"] = f"Составитель курса ({language})"
    assert client.post(f"{editor}?node=course", data).status_code == 302

    lesson = _izhar(version.snapshot)
    data = {"node": "lesson:izhar", "minutes": str(lesson["minutes"]), "letters": lesson["letters"]}
    for field in ("title", "summary", "explanation", "how"):
        for language, text in lesson[field].items():
            data[f"{field}__{language}"] = text
    for language in TAJWEED_COURSE_LANGUAGES:
        data[f"sources__{language}"] = f"Тухфат аль-атфаль\r\nДжазария ({language})"
    assert client.post(f"{editor}?node=lesson:izhar", data).status_code == 302

    page = client.get(editor, {"node": "lesson:izhar"}).content.decode()
    assert "По одному источнику на строку" in page
    assert "Как увидят ученики" in page
    assert '<li dir="auto">Джазария (ru)</li>' in page

    version.refresh_from_db()
    ar = version.documents.get(language="ar").payload
    assert ar["course"]["source"] == "Составитель курса (ar)"
    assert _izhar(ar)["sources"] == ["Тухфат аль-атфаль", "Джазария (ar)"]
    copied = copy_tajweed_course(version, "2026-10-25")
    assert _izhar(copied.snapshot)["sources"] == _izhar(version.snapshot)["sources"]
    assert copied.snapshot["course"]["source"] == version.snapshot["course"]["source"]

    # Emptied in every language, the field leaves the snapshot; the draft still signs.
    for language in TAJWEED_COURSE_LANGUAGES:
        data[f"sources__{language}"] = ""
    assert client.post(f"{editor}?node=lesson:izhar", data).status_code == 302
    version.refresh_from_db()
    assert "sources" not in _izhar(version.snapshot)
    sign_tajweed_course(version, owner)
    assert version.is_signed
