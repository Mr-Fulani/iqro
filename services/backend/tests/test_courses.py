# Russian content and messages are intentional.
# ruff: noqa: RUF001
from __future__ import annotations

import copy
import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import pytest
from django.contrib.auth.models import Permission
from django.core.exceptions import PermissionDenied, ValidationError
from django.db import IntegrityError, transaction
from django.test import override_settings
from rest_framework.test import APIClient

from quran_backend.modules.accounts.models import User
from quran_backend.modules.core.editorial.diff import line_diff
from quran_backend.modules.core.editorial.markup import parse_notes
from quran_backend.modules.core.tasks import notify_web_content_change_task
from quran_backend.modules.courses.document import build_snapshot, changes, readiness
from quran_backend.modules.courses.models import (
    Course,
    CourseDocument,
    CourseLesson,
    CourseRelease,
    CourseReleaseStatus,
    CourseVideo,
)
from quran_backend.modules.courses.services import (
    CourseReleaseError,
    hide_course,
    mark_watched,
    new_videos,
    prepare_release,
    publish_release,
    return_for_rework,
    roll_back,
    show_course,
    sign_release,
    withdraw_from_review,
)

DOCS = Path(__file__).resolve().parents[3] / "docs" / "courses"
MEDIA = "https://media.iqro.forum"
PUBLISHED_AT = datetime(2027, 1, 12, 10, 0, tzinfo=UTC)
VIDEO_SHA = "abcdef0123456789abcd" + "0" * 44


def picture(stem: str, kind: str, width: int, height: int) -> dict[str, Any]:
    return {
        "object_key": f"courses/{kind}/{stem}.webp",
        "small_object_key": f"courses/{kind}/{stem}-800.webp",
        "width": width,
        "height": height,
        "sha256": stem + "0" * 44,
    }


BANNER = {
    "id": "banner000001",
    "type": "banner",
    "slides": [
        {
            "id": "slide0000001",
            "image": picture("2222222222bbbbbbbbbb", "banners", 1600, 900),
            "images": {},
            "caption": {},
            "alt": {"ru": "Полумесяц над минаретом на закате"},
        }
    ],
}
SLIDES = {
    "id": "slides000001",
    "type": "slides",
    "slides": [
        {
            "id": "slide0000002",
            "image": picture("1111111111aaaaaaaaaa", "slides", 1600, 1200),
            "images": {},
            "caption": {"ru": "[Когда делать намерение — схема после проверки]"},
            "alt": {"ru": "Схема: ночь, рассвет и время намерения"},
        },
        {
            "id": "slide0000003",
            "image": picture("3333333333cccccccccc", "slides", 1600, 900),
            # A picture with English text on it: students of other languages see the common one.
            "images": {"en": picture("4444444444dddddddddd", "slides", 1600, 900)},
            "caption": {"ru": "نويت صوم غد"},
            "alt": {},
        },
    ],
}

LESSONS = [
    {
        "slug": "smysl-posta",
        "title_ru": "Смысл поста",
        "summary_ru": "Зачем мусульмане постятся в Рамадан.",
        "minutes": 8,
        "notes_ru": (
            "## Что такое пост\n"
            "Пост (الصوم) — это **[определение поста — текст после проверки]**.\n\n"
            "> نص الآية بعد المراجعة\n"
            "> — Коран, 2:183\n\n"
            "> [смысловой перевод аята — после проверки]"
        ),
        "sources_ru": "[источник 1 — после проверки]",
        "media": [BANNER],
    },
    {
        "slug": "namerenie",
        "title_ru": "Намерение (ният)",
        "summary_ru": "Что такое намерение и когда его делать.",
        "minutes": 12,
        "notes_ru": (
            "## Что такое намерение\n"
            "Намерение — это **решение сердца** совершить пост ради Аллаха.\n"
            "[правило о произнесении намерения по методике курса — после проверки]\n"
            "- Намерение отличает поклонение от привычки.\n"
            "- [второй пункт — после проверки]\n"
            "! [важное правило о времени намерения — после проверки]"
        ),
        "sources_ru": "[источник 1 — после проверки]\n\n  [источник 2 — после проверки]  ",
        "media": [{"id": "video", "type": "video"}, SLIDES],
    },
    {
        "slug": "taraviikh",
        "title_ru": "Таравих",
        "summary_ru": "Ночной намаз Рамадана.",
        "minutes": 10,
        "notes_ru": (
            "## Порядок\n1. [шаг 1 — после проверки]\n2. [шаг 2 — после проверки]\n\n"
            "فقرة عربية بعد المراجعة"
        ),
        "sources_ru": "",
    },
]


def _user(email: str, *codenames: str, superuser: bool = False) -> User:
    user = User.objects.create_user(
        email=email, status="active", is_staff=True, is_superuser=superuser
    )
    user.user_permissions.set(Permission.objects.filter(codename__in=codenames))
    return User.objects.get(pk=user.pk)


@pytest.fixture
def owner(db: None) -> User:
    return _user("courses-owner@example.test", superuser=True)


@pytest.fixture
def ramadan(db: None) -> Course:
    course = Course.objects.create(
        slug="ramadan",
        title_ru="Рамадан",
        summary_ru=(
            "Пост, намерение, таравих, Ночь Предопределения и закят аль-фитр: "
            "что важно знать до начала месяца."
        ),
        source_ru="[автор и источники — после проверки]",
        cover_object_key="courses/covers/0123456789abcdef0123.webp",
        cover_thumb_object_key="courses/covers/0123456789abcdef0123-640.webp",
        cover_width=1280,
        cover_height=720,
    )
    video = CourseVideo.objects.create(
        course=course,
        object_key="courses/videos/abcdef0123456789abcd.mp4",
        sha256=VIDEO_SHA,
        bytes=113246208,
        duration_ms=588000,
        width=1280,
        height=720,
        fps=30,
        bitrate_kbps=1500,
        video_codec="h264",
        audio_codec="aac",
        has_audio=True,
        spoken_language="ru",
        poster_object_key="courses/posters/abcdef0123456789abcd-0123456789ab-1280.webp",
        poster_small_object_key="courses/posters/abcdef0123456789abcd-0123456789ab-640.webp",
        poster_width=1280,
        poster_height=720,
    )
    for lesson in LESSONS:
        CourseLesson.objects.create(
            course=course, video=video if lesson["slug"] == "namerenie" else None, **lesson
        )
    return course


def release_course(course: Course, user: User, note: str = "Первый выпуск") -> CourseRelease:
    release = prepare_release(course, user, languages=["ru"], change_note=note)
    watch_all(release, user)
    sign_release(release, user)
    return publish_release(release, user)


def watch_all(release: CourseRelease, user: User) -> None:
    for sha256 in new_videos(release):
        mark_watched(release, user, sha256=sha256, watched=True)


def _example(name: str) -> dict[str, Any]:
    return json.loads((DOCS / name).read_text(encoding="utf-8"))


# Markup ------------------------------------------------------------------


@pytest.mark.parametrize(
    "case",
    json.loads((DOCS / "notes-markup.cases.json").read_text(encoding="utf-8"))["cases"],
    ids=lambda case: case["name"],
)
def test_notes_markup_matches_the_shared_cases(case: dict[str, Any]) -> None:
    assert parse_notes(case["input"]) == case["blocks"]


def test_markup_never_fails_and_keeps_odd_markers_as_text() -> None:
    blocks = parse_notes("**a** b **c\n> — только источник\n****\n!нет пробела")

    assert blocks == [
        {
            "type": "paragraph",
            "dir": "ltr",
            "lines": [
                [{"text": "a", "bold": True}, {"text": " b **c"}],
            ],
        },
        {"type": "quote", "dir": "ltr", "lines": [[{"text": "— только источник"}]], "source": None},
        {"type": "paragraph", "dir": "ltr", "lines": [[{"text": "!нет пробела"}]]},
    ]


def test_line_diff_marks_changed_lines_with_context() -> None:
    old = "один\nдва\nтри\nчетыре\nпять\nшесть"
    new = "один\nДВА\nтри\nчетыре\nпять\nшесть\nсемь"

    assert line_diff(old, new) == [
        (" ", "один"),
        ("-", "два"),
        ("+", "ДВА"),
        (" ", "три"),
        ("…", ""),
        (" ", "шесть"),
        ("+", "семь"),
    ]
    assert line_diff("same", "same") == []


# Models -----------------------------------------------------------------


@pytest.mark.django_db
def test_reserved_slugs_are_refused() -> None:
    for slug in ("salah", "tajweed", "quiz", "courses", "new", "preview", "events"):
        with pytest.raises(ValidationError) as error:
            Course(slug=slug, title_ru="Курс").full_clean()
        assert "slug" in error.value.message_dict
    Course(slug="ramadan", title_ru="Курс").full_clean()


@pytest.mark.django_db
def test_lesson_slug_is_unique_in_a_course_and_position_goes_last(ramadan: Course) -> None:
    lesson = CourseLesson.objects.create(course=ramadan, slug="zakyat", title_ru="Закят")
    assert lesson.position == 4
    other = Course.objects.create(slug="hajj", title_ru="Хадж")
    CourseLesson.objects.create(course=other, slug="zakyat")
    with pytest.raises(IntegrityError), transaction.atomic():
        CourseLesson.objects.create(course=ramadan, slug="zakyat")


@pytest.mark.django_db
def test_release_constraints(ramadan: Course, owner: User) -> None:
    release = prepare_release(ramadan, owner, languages=["ru"], change_note="Первый")
    with pytest.raises(IntegrityError), transaction.atomic():
        CourseRelease.objects.filter(pk=release.pk).update(status=CourseReleaseStatus.PUBLISHED)
    with pytest.raises(IntegrityError), transaction.atomic():
        CourseRelease.objects.create(
            course=ramadan,
            number=2,
            snapshot={},
            checksum_sha256="0" * 64,
            change_note="Второй на проверке",
            submitted_at=PUBLISHED_AT,
        )
    with pytest.raises(IntegrityError), transaction.atomic():
        CourseRelease.objects.create(
            course=ramadan,
            number=1,
            status=CourseReleaseStatus.RETURNED,
            checksum_sha256="0" * 64,
            change_note="Тот же номер",
            submitted_at=PUBLISHED_AT,
        )


# Release cycle -----------------------------------------------------------


@pytest.mark.django_db
def test_readiness_names_what_each_language_lacks(ramadan: Course) -> None:
    CourseLesson.objects.filter(slug="namerenie").update(notes_ru="")
    missing = readiness(build_snapshot(ramadan))

    assert [problem.text for problem in missing["ru"]] == [
        "Тема 2 «Намерение (ният)»: нет конспекта."
    ]
    assert missing["ru"][0].lesson == str(CourseLesson.objects.get(slug="namerenie").pk)
    assert "Нет названия курса." in [problem.text for problem in missing["en"]]


@pytest.mark.django_db
def test_prepare_refuses_unready_languages_and_empty_note(ramadan: Course, owner: User) -> None:
    with pytest.raises(CourseReleaseError) as error:
        prepare_release(ramadan, owner, languages=["ru", "en"], change_note=" ")

    assert "Напишите, что изменилось." in error.value.problems
    assert "en: Нет названия курса." in error.value.problems
    assert not CourseRelease.objects.exists()


@pytest.mark.django_db
def test_full_cycle_publishes_and_supersedes(ramadan: Course, owner: User) -> None:
    first = release_course(ramadan, owner)
    ramadan.refresh_from_db()
    assert ramadan.live_release == first
    assert first.status == CourseReleaseStatus.PUBLISHED
    assert first.reviewed_by == owner
    assert first.published_by == owner

    with pytest.raises(CourseReleaseError, match="Нет изменений с выпуска 1"):
        prepare_release(ramadan, owner, languages=["ru"], change_note="Пусто")

    CourseLesson.objects.filter(slug="namerenie").update(notes_ru="Новый текст.")
    second = prepare_release(ramadan, owner, languages=["ru"], change_note="Правка темы 2")
    assert second.number == 2
    assert second.based_on == first
    assert changes(first.snapshot, second.snapshot) == ["Тема 2: изменён конспект (ru)"]
    with pytest.raises(CourseReleaseError, match="Выпуск 2 уже на проверке"):
        prepare_release(ramadan, owner, languages=["ru"], change_note="Ещё")

    sign_release(second, owner)
    publish_release(second, owner)
    first.refresh_from_db()
    ramadan.refresh_from_db()
    assert first.status == CourseReleaseStatus.SUPERSEDED
    assert first.end_reason == "Заменён выпуском 2."
    assert ramadan.live_release_id == second.pk


@pytest.mark.django_db
def test_return_and_withdraw_go_back_to_the_author(ramadan: Course, owner: User) -> None:
    author = _user("author@example.test", "change_course", "view_course")
    release = prepare_release(ramadan, author, languages=["ru"], change_note="Первый")
    with pytest.raises(CourseReleaseError, match="Напишите, что исправить"):
        return_for_rework(release, owner, comment="")
    return_for_rework(release, owner, comment="Проверьте аят в теме 1.")
    release.refresh_from_db()
    assert release.status == CourseReleaseStatus.RETURNED
    assert release.review_note == "Проверьте аят в теме 1."
    with pytest.raises(CourseReleaseError):
        sign_release(release, owner)

    again = prepare_release(ramadan, author, languages=["ru"], change_note="Исправлено")
    assert again.number == 2
    withdraw_from_review(again, author)
    assert CourseRelease.objects.get(pk=again.pk).status == CourseReleaseStatus.RETURNED


@pytest.mark.django_db
def test_every_operation_checks_the_right_on_the_server(ramadan: Course, owner: User) -> None:
    viewer = _user("viewer@example.test", "view_course", "view_courserelease")
    editor = _user("editor@example.test", "view_course", "change_course")
    reviewer = _user("reviewer@example.test", "view_course", "sign_course")

    with pytest.raises(PermissionDenied):
        prepare_release(ramadan, viewer, languages=["ru"], change_note="x")
    release = prepare_release(ramadan, editor, languages=["ru"], change_note="Первый")
    for operation in (
        lambda: withdraw_from_review(release, viewer),
        lambda: return_for_rework(release, editor, comment="x"),
        lambda: sign_release(release, editor),
        lambda: mark_watched(release, editor, sha256=VIDEO_SHA, watched=True),
    ):
        with pytest.raises(PermissionDenied):
            operation()
    watch_all(release, reviewer)
    sign_release(release, reviewer)
    with pytest.raises(PermissionDenied):
        publish_release(release, reviewer)
    publish_release(release, owner)
    for operation in (
        lambda: hide_course(ramadan, reviewer, reason="x"),
        lambda: show_course(ramadan, editor),
    ):
        with pytest.raises(PermissionDenied):
            operation()


@pytest.mark.django_db
@override_settings(COURSES_STRICT_REVIEW=True)
def test_strict_review_refuses_the_author_as_signer(ramadan: Course, owner: User) -> None:
    release = prepare_release(ramadan, owner, languages=["ru"], change_note="Первый")
    watch_all(release, owner)
    with pytest.raises(CourseReleaseError, match="Строгий режим"):
        sign_release(release, owner)
    reviewer = _user("second-reviewer@example.test", "sign_course")
    sign_release(release, reviewer)
    assert CourseRelease.objects.get(pk=release.pk).reviewed_by == reviewer


@pytest.mark.django_db
def test_strict_review_is_off_by_default(ramadan: Course, owner: User) -> None:
    release = prepare_release(ramadan, owner, languages=["ru"], change_note="Первый")
    watch_all(release, owner)
    sign_release(release, owner)
    assert CourseRelease.objects.get(pk=release.pk).status == CourseReleaseStatus.SIGNED


@pytest.mark.django_db
def test_hide_show_and_roll_back(ramadan: Course, owner: User) -> None:
    first = release_course(ramadan, owner)
    CourseLesson.objects.filter(slug="taraviikh").update(title_ru="Таравих и витр")
    second = release_course(ramadan, owner, "Тема 3")

    with pytest.raises(CourseReleaseError, match="Укажите причину"):
        hide_course(ramadan, owner, reason=" ")
    hide_course(ramadan, owner, reason="Ошибка в теме 3")
    ramadan.refresh_from_db()
    assert ramadan.hidden_reason == "Ошибка в теме 3"
    with pytest.raises(CourseReleaseError, match="уже скрыт"):
        hide_course(ramadan, owner, reason="Ещё раз")
    show_course(ramadan, owner)
    ramadan.refresh_from_db()
    assert ramadan.hidden_at is None

    with pytest.raises(CourseReleaseError, match="только заменённый"):
        roll_back(ramadan, second, owner, reason="x")
    roll_back(ramadan, first, owner, reason="Ошибка в теме 3", faulty=True)
    ramadan.refresh_from_db()
    second.refresh_from_db()
    first.refresh_from_db()
    assert ramadan.live_release == first
    assert first.status == CourseReleaseStatus.PUBLISHED
    assert second.status == CourseReleaseStatus.WITHDRAWN
    assert second.end_reason == "Ошибка в теме 3"
    # A faulty release never comes back.
    with pytest.raises(CourseReleaseError, match="Ошибочный выпуск не возвращается"):
        roll_back(ramadan, second, owner, reason="Передумали")


@pytest.mark.django_db
def test_signed_older_release_cannot_replace_a_newer_one(ramadan: Course, owner: User) -> None:
    release_course(ramadan, owner)
    CourseLesson.objects.filter(slug="taraviikh").update(title_ru="Таравих 2")
    old = prepare_release(ramadan, owner, languages=["ru"], change_note="2")
    sign_release(old, owner)
    CourseLesson.objects.filter(slug="taraviikh").update(title_ru="Таравих 3")
    newer = prepare_release(ramadan, owner, languages=["ru"], change_note="3")
    sign_release(newer, owner)
    publish_release(newer, owner)

    with pytest.raises(CourseReleaseError, match="более новый выпуск 3"):
        publish_release(old, owner)


@pytest.mark.django_db
def test_oversized_document_is_not_built(
    ramadan: Course, owner: User, monkeypatch: pytest.MonkeyPatch
) -> None:
    # The three lessons of the example take about 4 KiB.
    monkeypatch.setattr("quran_backend.modules.courses.services.MAX_DOCUMENT_BYTES", 1024)

    with pytest.raises(CourseReleaseError, match="больше 2 МиБ"):
        prepare_release(ramadan, owner, languages=["ru"], change_note="Большой")
    assert not CourseRelease.objects.exists()


# Revalidation events ----------------------------------------------------


@pytest.mark.django_db
@override_settings(WEB_CONTENT_REVALIDATION_URL="http://web:3000/api/internal/content-revalidation")
def test_course_changes_send_events_after_commit(
    ramadan: Course,
    owner: User,
    django_capture_on_commit_callbacks: Any,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    queued: list[dict[str, str]] = []
    monkeypatch.setattr(notify_web_content_change_task, "delay", queued.append)

    with django_capture_on_commit_callbacks(execute=True):
        first = release_course(ramadan, owner)
        assert queued == []
    with django_capture_on_commit_callbacks(execute=True):
        hide_course(ramadan, owner, reason="Проверка")
    with django_capture_on_commit_callbacks(execute=True):
        show_course(ramadan, owner)
    CourseLesson.objects.filter(slug="taraviikh").update(title_ru="Таравих 2")
    with django_capture_on_commit_callbacks(execute=True):
        release_course(ramadan, owner, "Тема 3")
    with django_capture_on_commit_callbacks(execute=True):
        roll_back(ramadan, first, owner, reason="Назад")

    event = {"type": "courses.course.changed", "course": "ramadan"}
    assert queued == [
        {**event, "action": "activated", "version": "1"},
        {**event, "action": "withdrawn", "version": "1"},
        {**event, "action": "activated", "version": "1"},
        {**event, "action": "activated", "version": "2"},
        {**event, "action": "activated", "version": "1"},
    ]


@pytest.mark.django_db
@override_settings(WEB_CONTENT_REVALIDATION_URL="http://web:3000/api/internal/content-revalidation")
def test_failed_operation_sends_no_event(
    ramadan: Course,
    owner: User,
    django_capture_on_commit_callbacks: Any,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    queued: list[dict[str, str]] = []
    monkeypatch.setattr(notify_web_content_change_task, "delay", queued.append)
    with django_capture_on_commit_callbacks(execute=True), pytest.raises(CourseReleaseError):
        hide_course(ramadan, owner, reason="Курса ещё нет на сайте")
    assert queued == []


# API ---------------------------------------------------------------------


def _published(course: Course, owner: User) -> CourseRelease:
    release = release_course(course, owner)
    CourseRelease.objects.filter(pk=release.pk).update(published_at=PUBLISHED_AT)
    return release


@pytest.mark.django_db
@override_settings(PUBLIC_AUDIO_BASE_URL=MEDIA)
def test_course_document_matches_the_contract_example(
    ramadan: Course, owner: User, api_client: APIClient
) -> None:
    _published(ramadan, owner)
    response = api_client.get("/api/v1/courses/ramadan")

    assert response.status_code == 200
    assert response["Cache-Control"] == "public, max-age=300, stale-while-revalidate=86400"
    body = response.json()
    document = CourseDocument.objects.get(language="ru")
    assert body["course"]["checksum_sha256"] == document.checksum_sha256
    expected = copy.deepcopy(_example("course-document.example.json"))
    expected["course"]["checksum_sha256"] = document.checksum_sha256
    assert body == expected

    cached = api_client.get("/api/v1/courses/ramadan", HTTP_IF_NONE_MATCH=response["ETag"])
    assert cached.status_code == 304


@pytest.mark.django_db
@override_settings(PUBLIC_AUDIO_BASE_URL=MEDIA)
def test_course_list_matches_the_contract_example(
    ramadan: Course, owner: User, api_client: APIClient
) -> None:
    _published(ramadan, owner)
    draft = Course.objects.create(slug="hajj", title_ru="Хадж", summary_ru="Скоро")
    CourseLesson.objects.create(course=draft, slug="ihram", title_ru="Ихрам", notes_ru="Текст")

    response = api_client.get("/api/v1/courses?language=ru")

    assert response.status_code == 200
    assert response.json() == _example("course-list.example.json")


@pytest.mark.django_db
def test_course_list_orders_by_position_then_title(owner: User, api_client: APIClient) -> None:
    for slug, title, position in (("b", "Бета", 5), ("a", "Альфа", 5), ("z", "Яблоко", 1)):
        course = Course.objects.create(slug=slug, title_ru=title, summary_ru="…", position=position)
        CourseLesson.objects.create(course=course, slug="one", title_ru="Тема", notes_ru="Текст.")
        release_course(course, owner)

    response = api_client.get("/api/v1/courses")

    assert [course["slug"] for course in response.json()["courses"]] == ["z", "a", "b"]
    assert response.json()["courses"][0]["cover"] is None
    assert response.json()["courses"][0]["minutes"] == 1


@pytest.mark.django_db
def test_course_is_visible_only_on_released_languages_and_while_shown(
    ramadan: Course, owner: User, api_client: APIClient
) -> None:
    assert api_client.get("/api/v1/courses/ramadan").json()["detail"] == "Такого курса нет."
    release_course(ramadan, owner)

    english = api_client.get("/api/v1/courses/ramadan?language=en")
    assert english.status_code == 404
    assert english.json()["detail"] == "Такого курса нет."
    assert api_client.get("/api/v1/courses?language=en").json() == {
        "language": "en",
        "courses": [],
    }
    bad = api_client.get("/api/v1/courses?language=de")
    assert bad.status_code == 400
    # Problem details of the project, as in salah/api.py.
    assert bad.json()["field_errors"] == {"language": ["Поддерживаются: ar, en, ru, tr."]}
    assert api_client.get("/api/v1/courses/ramadan?language=de").status_code == 400

    hide_course(ramadan, owner, reason="Проверка")
    assert api_client.get("/api/v1/courses/ramadan").status_code == 404
    assert api_client.get("/api/v1/courses").json()["courses"] == []
    show_course(ramadan, owner)
    assert api_client.get("/api/v1/courses/ramadan").status_code == 200
    assert api_client.get("/api/v1/courses/unknown").status_code == 404


@pytest.mark.django_db
def test_students_see_the_live_release_until_the_next_is_published(
    ramadan: Course, owner: User, api_client: APIClient
) -> None:
    release_course(ramadan, owner)
    Course.objects.filter(pk=ramadan.pk).update(title_ru="Рамадан 1448")
    CourseLesson.objects.filter(slug="taraviikh").delete()
    release = prepare_release(ramadan, owner, languages=["ru"], change_note="Без таравиха")
    sign_release(release, owner)

    before = api_client.get("/api/v1/courses/ramadan").json()
    assert before["course"]["title"] == "Рамадан"
    assert before["course"]["version"] == "1"
    assert len(before["lessons"]) == 3

    publish_release(release, owner)
    after = api_client.get("/api/v1/courses/ramadan").json()
    assert after["course"]["title"] == "Рамадан 1448"
    assert after["course"]["version"] == "2"
    assert [lesson["slug"] for lesson in after["lessons"]] == ["smysl-posta", "namerenie"]


@pytest.mark.django_db
def test_lesson_minutes_are_estimated_from_the_notes(ramadan: Course, owner: User) -> None:
    CourseLesson.objects.filter(slug="smysl-posta").update(
        minutes=None, notes_ru=" ".join(["слово"] * 361)
    )
    release_course(ramadan, owner)

    payload = CourseDocument.objects.get(language="ru").payload
    assert payload["lessons"][0]["minutes"] == 3


@pytest.mark.django_db
def test_two_languages_make_two_documents(ramadan: Course, owner: User) -> None:
    Course.objects.filter(pk=ramadan.pk).update(title_ar="رمضان", summary_ar="الصيام")
    for lesson in CourseLesson.objects.all():
        lesson.title_ar = "درس"
        lesson.notes_ar = "بسم الله"
        lesson.save()
    release = prepare_release(ramadan, owner, languages=["ar", "ru"], change_note="Два языка")

    assert release.languages == ["ar", "ru"]
    arabic = CourseDocument.objects.get(release=release, language="ar").payload
    assert arabic["course"]["languages"] == ["ar", "ru"]
    assert arabic["course"]["title"] == "رمضان"
    assert arabic["lessons"][0]["notes"] == [
        {"type": "paragraph", "dir": "rtl", "lines": [[{"text": "بسم الله", "lang": "ar"}]]}
    ]
