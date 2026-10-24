# Russian admin text is intentional.
# ruff: noqa: RUF001
from __future__ import annotations

import shutil
import subprocess
from pathlib import Path
from typing import Any
from unittest.mock import patch

import pytest
from django.contrib.admin.models import LogEntry
from django.contrib.auth.models import Group, Permission
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import Client

from quran_backend.modules.accounts.models import User
from quran_backend.modules.core.object_storage import ImmutableObjectSpec, StoredObject
from quran_backend.modules.courses.models import (
    COURSE_LANGUAGES,
    Course,
    CourseLesson,
    CourseRelease,
    CourseReleaseStatus,
)
from quran_backend.modules.courses.services import (
    prepare_release,
    publish_release,
    sign_release,
)

UPLOADER = "quran_backend.modules.courses.media.player_background_uploader"
needs_ffmpeg = pytest.mark.skipif(shutil.which("ffmpeg") is None, reason="ffmpeg is not installed")


class FakeUploader:
    def __init__(self) -> None:
        self.specs: list[ImmutableObjectSpec] = []

    def upload_path(self, _source_path: Path, spec: ImmutableObjectSpec) -> StoredObject:
        self.specs.append(spec)
        return StoredObject(key=spec.key, etag='"etag"', created=True)


def _client(user: User) -> Client:
    client = Client()
    client.force_login(user)
    return client


def _staff(email: str, *codenames: str) -> User:
    user = User.objects.create_user(email=email, status="active", is_staff=True)
    user.user_permissions.set(
        Permission.objects.filter(content_type__app_label="courses", codename__in=codenames)
    )
    return user


@pytest.fixture
def owner(db: None) -> User:
    return User.objects.create_user(
        email="courses-admin-owner@example.test",
        status="active",
        is_staff=True,
        is_superuser=True,
    )


@pytest.fixture
def owner_client(owner: User) -> Client:
    return _client(owner)


@pytest.fixture
def course(db: None) -> Course:
    course = Course.objects.create(slug="ramadan", title_ru="Рамадан", summary_ru="Пост и таравих.")
    CourseLesson.objects.create(
        course=course,
        slug="smysl-posta",
        title_ru="Смысл поста",
        notes_ru="## Что такое пост\nПост (الصوم) — **обязанность**.",
    )
    CourseLesson.objects.create(
        course=course, slug="namerenie", title_ru="Намерение", notes_ru="Решение сердца."
    )
    return course


def _course_form(course: Course, **changes: Any) -> dict[str, Any]:
    course.refresh_from_db()
    data: dict[str, Any] = {
        "slug": course.slug,
        "position": course.position,
        "revision": course.revision,
        **{
            f"{field}_{language}": course.text(field, language)
            for field in ("title", "summary", "source")
            for language in COURSE_LANGUAGES
        },
    }
    lessons = list(course.lessons.all())
    data.update(
        {
            "lessons-TOTAL_FORMS": len(lessons),
            "lessons-INITIAL_FORMS": len(lessons),
            "lessons-MIN_NUM_FORMS": 0,
            "lessons-MAX_NUM_FORMS": 1000,
        }
    )
    for index, lesson in enumerate(lessons):
        data.update(
            {
                f"lessons-{index}-id": lesson.pk,
                f"lessons-{index}-course": course.pk,
                f"lessons-{index}-position": lesson.position,
                f"lessons-{index}-title_ru": lesson.title_ru,
                f"lessons-{index}-slug": lesson.slug,
                f"lessons-{index}-minutes": lesson.minutes or "",
                f"lessons-{index}-revision": lesson.revision,
            }
        )
    data.update(changes)
    return data


def _lesson_form(lesson: CourseLesson, **changes: Any) -> dict[str, Any]:
    lesson.refresh_from_db()
    data: dict[str, Any] = {
        "position": lesson.position,
        "slug": lesson.slug,
        "minutes": lesson.minutes or "",
        "revision": lesson.revision,
        **{
            f"{field}_{language}": lesson.text(field, language)
            for field in ("title", "summary", "notes", "sources")
            for language in COURSE_LANGUAGES
        },
        "_continue": "1",
    }
    data.update(changes)
    return data


def _published(course: Course, owner: User) -> CourseRelease:
    release = prepare_release(course, owner, languages=["ru"], change_note="Первый выпуск")
    sign_release(release, owner)
    return publish_release(release, owner)


# Pages ------------------------------------------------------------------


@pytest.mark.django_db
def test_owner_creates_a_course_with_lessons(owner_client: Client) -> None:
    page = owner_client.get("/admin/courses/course/add/")
    assert page.status_code == 200
    assert "Адрес в ссылке" in page.content.decode()

    data = {
        "slug": "ramadan",
        "position": 100,
        "revision": 1,
        "title_ru": "Рамадан",
        "summary_ru": "Пост",
        "lessons-TOTAL_FORMS": 1,
        "lessons-INITIAL_FORMS": 0,
        "lessons-MIN_NUM_FORMS": 0,
        "lessons-MAX_NUM_FORMS": 1000,
        "lessons-0-title_ru": "Смысл поста",
        "lessons-0-slug": "smysl-posta",
        "lessons-0-position": "",
        "lessons-0-revision": 1,
        "_continue": "1",
    }
    response = owner_client.post("/admin/courses/course/add/", data)

    assert response.status_code == 302
    course = Course.objects.get(slug="ramadan")
    assert course.created_by is not None
    assert course.lessons.get().position == 1


@pytest.mark.django_db
def test_reserved_slug_is_refused_in_the_form(owner_client: Client) -> None:
    response = owner_client.post(
        "/admin/courses/course/add/",
        {
            "slug": "salah",
            "position": 100,
            "revision": 1,
            "title_ru": "Намаз",
            "lessons-TOTAL_FORMS": 0,
            "lessons-INITIAL_FORMS": 0,
        },
    )

    assert response.status_code == 200
    assert "занят разделом сайта" in response.content.decode()
    assert not Course.objects.exists()


@pytest.mark.django_db
def test_course_page_shows_readiness_and_changes_after_release(
    course: Course, owner: User, owner_client: Client
) -> None:
    page = owner_client.get(f"/admin/courses/course/{course.pk}/change/").content.decode()
    assert "Курса ещё нет на сайте" in page
    assert "Подготовить выпуск" in page
    assert "Нет названия курса." in page  # English is not written yet
    assert 'dir="rtl"' in page  # Arabic fields
    assert "RU ✓ · العربية — · EN — · TR —" in page

    _published(course, owner)
    CourseLesson.objects.filter(slug="namerenie").update(notes_ru="Новое.")
    page = owner_client.get(f"/admin/courses/course/{course.pk}/change/").content.decode()
    assert "На сайте выпуск 1" in page
    assert "Правки увидят после выпуска 2" in page
    assert "Тема 2: изменён конспект (ru)" in page
    assert "Скрыть с сайта" in page
    # The address is fixed once a release exists.
    assert 'name="slug"' not in page.split("lessons-TOTAL_FORMS")[0]


@pytest.mark.django_db
def test_lesson_page_has_arrows_preview_and_fixed_slug_after_release(
    course: Course, owner: User, owner_client: Client
) -> None:
    first, second = course.lessons.all()
    page = owner_client.get(f"/admin/courses/courselesson/{first.pk}/change/").content.decode()
    assert "Следующая тема →" in page
    assert "← Предыдущая тема" not in page
    assert "Тема 1 из 2" in page
    assert "Пустая строка — новый абзац" in page

    _published(course, owner)
    page = owner_client.get(f"/admin/courses/courselesson/{second.pk}/change/").content.decode()
    assert "← Предыдущая тема" in page
    assert "Тема уже была в выпуске: адрес не меняется." in page
    response = owner_client.post(
        f"/admin/courses/courselesson/{second.pk}/change/", _lesson_form(second, slug="drugoy")
    )
    assert response.status_code == 302
    second.refresh_from_db()
    assert second.slug == "namerenie"


@pytest.mark.django_db
def test_concurrent_lesson_edit_is_refused_and_text_stays(
    course: Course, owner_client: Client
) -> None:
    lesson = course.lessons.first()
    assert lesson is not None
    stale = _lesson_form(lesson)
    first = owner_client.post(
        f"/admin/courses/courselesson/{lesson.pk}/change/",
        {**stale, "notes_ru": "Правка из первой вкладки."},
    )
    assert first.status_code == 302
    lesson.refresh_from_db()
    assert lesson.revision == 2

    second = owner_client.post(
        f"/admin/courses/courselesson/{lesson.pk}/change/",
        {**stale, "notes_ru": "Мой длинный текст из второй вкладки."},
    )

    assert second.status_code == 200
    body = second.content.decode()
    assert "Ничего не сохранено: тему изменили в другой вкладке." in body
    assert "Мой длинный текст из второй вкладки." in body
    lesson.refresh_from_db()
    assert lesson.notes_ru == "Правка из первой вкладки."


@pytest.mark.django_db
def test_concurrent_course_edit_is_refused(course: Course, owner_client: Client) -> None:
    stale = _course_form(course)
    assert (
        owner_client.post(
            f"/admin/courses/course/{course.pk}/change/", {**stale, "summary_ru": "Первая"}
        ).status_code
        == 302
    )

    response = owner_client.post(
        f"/admin/courses/course/{course.pk}/change/", {**stale, "summary_ru": "Вторая"}
    )

    assert response.status_code == 200
    assert "Ничего не сохранено: курс изменили в другой вкладке." in response.content.decode()
    course.refresh_from_db()
    assert course.summary_ru == "Первая"


@pytest.mark.django_db
def test_saving_the_course_form_keeps_the_live_release(
    course: Course, owner: User, owner_client: Client
) -> None:
    form = _course_form(course)
    release = _published(course, owner)

    response = owner_client.post(
        f"/admin/courses/course/{course.pk}/change/", {**form, "position": 5}
    )

    assert response.status_code == 302
    course.refresh_from_db()
    assert course.live_release == release
    assert course.position == 5


@pytest.mark.django_db
def test_preview_draws_blocks_on_every_language(course: Course, owner_client: Client) -> None:
    page = owner_client.get(f"/admin/courses/course/{course.pk}/preview/").content.decode()
    assert "Что такое пост" in page
    assert '<bdi lang="ar" class="cv-ar">الصوم</bdi>' in page
    assert "<strong>обязанность</strong>" in page
    assert "العربية" in page

    english = owner_client.get(f"/admin/courses/course/{course.pk}/preview/?language=en")
    assert "На этом языке курс ещё не готов к выпуску" in english.content.decode()

    lesson = course.lessons.get(slug="namerenie")
    page = owner_client.get(
        f"/admin/courses/courselesson/{lesson.pk}/preview/?language=ar"
    ).content.decode()
    assert 'dir="rtl"' in page
    assert "Что такое пост" not in page


@pytest.mark.django_db
def test_prepare_page_lists_languages_and_creates_the_release(
    course: Course, owner_client: Client
) -> None:
    url = f"/admin/courses/course/{course.pk}/submit/"
    page = owner_client.get(url).content.decode()
    assert 'value="ru" checked' in page
    assert 'value="en" disabled' in page

    refused = owner_client.post(url, {"languages": ["ru"], "change_note": ""})
    assert refused.status_code == 400
    assert "Напишите, что изменилось." in refused.content.decode()

    response = owner_client.post(url, {"languages": ["ru"], "change_note": "Первый выпуск"})
    assert response.status_code == 302
    release = CourseRelease.objects.get()
    assert release.status == CourseReleaseStatus.IN_REVIEW
    assert LogEntry.objects.filter(change_message__startswith="Подготовлен выпуск 1").exists()


@pytest.mark.django_db
def test_review_page_signs_and_publishes(course: Course, owner: User, owner_client: Client) -> None:
    _published(course, owner)
    CourseLesson.objects.filter(slug="namerenie").update(notes_ru="Решение сердца.\nНовая строка.")
    release = prepare_release(course, owner, languages=["ru"], change_note="Вторая строка")

    page = owner_client.get(f"/admin/courses/courserelease/{release.pk}/change/").content.decode()
    assert "Тема 2: изменён конспект (ru)" in page
    assert '<div class="is-add">+ Новая строка.</div>' in page
    assert "Подписать" in page
    assert "Вернуть на доработку" in page
    preview = owner_client.get(f"/admin/courses/courserelease/{release.pk}/preview/?language=ru")
    assert "Новая строка." in preview.content.decode()

    review = f"/admin/courses/courserelease/{release.pk}/review/"
    assert owner_client.post(f"{review}sign/", {"text": ""}).status_code == 302
    assert owner_client.post(f"{review}publish/").status_code == 302
    course.refresh_from_db()
    assert course.live_release == release
    assert (
        LogEntry.objects.filter(change_message="Опубликован выпуск 2 вместо выпуска 1.").count()
        == 2
    )


@pytest.mark.django_db
def test_return_comment_is_shown_on_the_course_page(
    course: Course, owner: User, owner_client: Client
) -> None:
    release = prepare_release(course, owner, languages=["ru"], change_note="Первый")
    response = owner_client.post(
        f"/admin/courses/courserelease/{release.pk}/review/return/",
        {"text": "Уточните источник в теме 1."},
    )
    assert response.status_code == 302

    page = owner_client.get(f"/admin/courses/course/{course.pk}/change/").content.decode()
    assert "Выпуск 1 возвращён на доработку." in page
    assert "Уточните источник в теме 1." in page


@pytest.mark.django_db
def test_hide_show_and_rollback_from_the_panel(
    course: Course, owner: User, owner_client: Client
) -> None:
    first = _published(course, owner)
    CourseLesson.objects.filter(slug="namerenie").update(notes_ru="Ошибка.")
    _published(course, owner)
    base = f"/admin/courses/course/{course.pk}"

    assert owner_client.post(f"{base}/hide/", {"reason": ""}).status_code == 302
    course.refresh_from_db()
    assert course.hidden_at is None
    owner_client.post(f"{base}/hide/", {"reason": "Ошибка в теме 2"})
    course.refresh_from_db()
    assert course.hidden_reason == "Ошибка в теме 2"
    assert "Скрыт с сайта" in owner_client.get(f"{base}/change/").content.decode()
    owner_client.post(f"{base}/show/")
    course.refresh_from_db()
    assert course.hidden_at is None

    page = owner_client.get(f"{base}/change/").content.decode()
    assert "Вернуть выпуск 1" in page
    owner_client.post(f"{base}/rollback/{first.pk}/", {"reason": "Ошибка", "faulty": "on"})
    course.refresh_from_db()
    assert course.live_release == first
    assert CourseRelease.objects.get(number=2).status == CourseReleaseStatus.WITHDRAWN
    assert owner_client.get(f"{base}/hide/").status_code == 405


# Rights ------------------------------------------------------------------


@pytest.mark.django_db
def test_view_only_staff_gets_403_on_every_action(course: Course, owner: User) -> None:
    first = _published(course, owner)
    CourseLesson.objects.filter(slug="namerenie").update(notes_ru="Правка.")
    _published(course, owner)
    CourseLesson.objects.filter(slug="namerenie").update(notes_ru="Ещё правка.")
    release = prepare_release(course, owner, languages=["ru"], change_note="Третий")
    viewer = _client(
        _staff(
            "courses-viewer@example.test",
            "view_course",
            "view_courselesson",
            "view_courserelease",
            "view_coursedocument",
        )
    )
    base = f"/admin/courses/course/{course.pk}"
    review = f"/admin/courses/courserelease/{release.pk}/review"

    assert viewer.get(f"{base}/change/").status_code == 200
    assert viewer.get(f"{base}/preview/").status_code == 200
    for url, data in (
        (f"{base}/change/", _course_form(course, summary_ru="Чужая правка")),
        (f"{base}/submit/", {"languages": ["ru"], "change_note": "x"}),
        (f"{base}/hide/", {"reason": "x"}),
        (f"{base}/show/", {}),
        (f"{base}/rollback/{first.pk}/", {"reason": "x"}),
        (f"{review}/withdraw/", {}),
        (f"{review}/return/", {"text": "x"}),
        (f"{review}/sign/", {}),
        (f"{review}/publish/", {}),
    ):
        assert viewer.post(url, data).status_code == 403, url
    assert viewer.get(f"{base}/submit/").status_code == 403

    page = viewer.get(f"{base}/change/").content.decode()
    assert "Подготовить выпуск" not in page
    assert "Скрыть с сайта" not in page
    review_page = viewer.get(f"/admin/courses/courserelease/{release.pk}/change/").content.decode()
    assert "Подписать" not in review_page
    changelist = viewer.get("/admin/courses/courserelease/").content.decode()
    assert "sign_selected" not in changelist
    assert "publish_selected" not in changelist
    release.refresh_from_db()
    assert release.status == CourseReleaseStatus.IN_REVIEW


@pytest.mark.django_db
def test_list_actions_need_their_own_rights(course: Course, owner: User) -> None:
    release = prepare_release(course, owner, languages=["ru"], change_note="Первый")
    reviewer = _client(_staff("courses-reviewer@example.test", "view_courserelease", "sign_course"))
    changelist = reviewer.get("/admin/courses/courserelease/").content.decode()
    assert "sign_selected" in changelist
    assert "publish_selected" not in changelist

    reviewer.post(
        "/admin/courses/courserelease/",
        {"action": "publish_selected", "_selected_action": [release.pk]},
    )
    release.refresh_from_db()
    assert release.status == CourseReleaseStatus.IN_REVIEW
    reviewer.post(
        "/admin/courses/courserelease/",
        {"action": "sign_selected", "_selected_action": [release.pk]},
    )
    release.refresh_from_db()
    assert release.status == CourseReleaseStatus.SIGNED

    publisher = _client(
        _staff("courses-publisher@example.test", "view_courserelease", "publish_course")
    )
    publisher.post(
        "/admin/courses/courserelease/",
        {"action": "publish_selected", "_selected_action": [release.pk]},
    )
    release.refresh_from_db()
    assert release.status == CourseReleaseStatus.PUBLISHED


@pytest.mark.django_db
def test_editor_prepares_but_cannot_sign_or_publish(course: Course) -> None:
    editor = _staff("courses-editor@example.test", "view_course", "change_course")
    client = _client(editor)
    client.post(
        f"/admin/courses/course/{course.pk}/submit/",
        {"languages": ["ru"], "change_note": "Первый"},
    )
    release = CourseRelease.objects.get()
    review = f"/admin/courses/courserelease/{release.pk}/review"
    assert client.post(f"{review}/sign/").status_code == 403
    assert client.post(f"{review}/return/", {"text": "x"}).status_code == 403
    # The author may take their own release back.
    assert client.post(f"{review}/withdraw/").status_code == 403  # no view right on releases
    editor.user_permissions.add(Permission.objects.get(codename="view_courserelease"))
    assert _client(editor).post(f"{review}/withdraw/").status_code == 302
    release.refresh_from_db()
    assert release.status == CourseReleaseStatus.RETURNED


@pytest.mark.django_db
def test_working_groups_exist_with_their_rights() -> None:
    def codenames(name: str) -> set[str]:
        return set(Group.objects.get(name=name).permissions.values_list("codename", flat=True))

    assert "change_courselesson" in codenames("Редактор курсов")
    assert "sign_course" not in codenames("Редактор курсов")
    assert "sign_course" in codenames("Религиозный рецензент")
    assert "publish_course" not in codenames("Религиозный рецензент")
    assert "publish_course" in codenames("Публикатор")


@pytest.mark.django_db
def test_course_with_releases_cannot_be_deleted(
    course: Course, owner: User, owner_client: Client
) -> None:
    _published(course, owner)
    assert owner_client.get(f"/admin/courses/course/{course.pk}/delete/").status_code == 403


# Cover -------------------------------------------------------------------


@needs_ffmpeg
@pytest.mark.django_db
def test_cover_becomes_two_webp_pictures(
    course: Course, owner_client: Client, tmp_path: Path
) -> None:
    source = tmp_path / "cover.png"
    subprocess.run(  # noqa: S603 - a test picture
        [
            shutil.which("ffmpeg") or "ffmpeg", "-nostdin", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "color=c=0x2e7d32:s=900x900", "-frames:v", "1", str(source),
        ],
        check=True,
    )  # fmt: skip
    uploader = FakeUploader()
    upload = SimpleUploadedFile("cover.png", source.read_bytes(), content_type="image/png")
    with patch(UPLOADER, return_value=uploader):
        response = owner_client.post(
            f"/admin/courses/course/{course.pk}/change/",
            _course_form(course, cover_upload=upload),
        )

    assert response.status_code == 302
    course.refresh_from_db()
    assert course.cover_object_key.startswith("courses/covers/")
    assert course.cover_thumb_object_key == course.cover_object_key.replace(".webp", "-640.webp")
    assert (course.cover_width, course.cover_height) == (1280, 720)
    assert [spec.content_type for spec in uploader.specs] == ["image/webp", "image/webp"]
    assert uploader.specs[1].size_bytes <= 50 * 1024

    response = owner_client.post(
        f"/admin/courses/course/{course.pk}/change/", _course_form(course, remove_cover="on")
    )
    course.refresh_from_db()
    assert course.cover_object_key == ""


@pytest.mark.django_db
def test_cover_must_be_a_picture(course: Course, owner_client: Client) -> None:
    upload = SimpleUploadedFile("cover.png", b"not a picture", content_type="image/png")
    response = owner_client.post(
        f"/admin/courses/course/{course.pk}/change/", _course_form(course, cover_upload=upload)
    )

    assert response.status_code == 200
    assert "Нужна картинка JPEG, PNG или WebP." in response.content.decode()
