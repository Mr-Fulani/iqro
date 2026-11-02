# Russian admin text is intentional.
# ruff: noqa: RUF001
"""Media of the tajweed course's lessons (docs/tajweed/course.md, «Медиа уроков»)."""

from __future__ import annotations

import copy
from collections.abc import Iterator
from pathlib import Path
from typing import Any
from unittest.mock import patch

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import Client, override_settings
from django.urls import reverse

from quran_backend.modules.accounts.models import User
from quran_backend.modules.courses.lesson_media_admin import MAKE_DRAFT_HINT, OPEN_LESSON_HINT
from quran_backend.modules.tajweed.course import (
    TajweedCourseError,
    load_course_snapshot,
    validate_course_snapshot,
)
from quran_backend.modules.tajweed.course_publication import (
    copy_tajweed_course,
    import_tajweed_course,
    mark_tajweed_watched,
    new_videos,
    publish_tajweed_course,
    sign_tajweed_course,
)
from quran_backend.modules.tajweed.models import TajweedCourseDocument, TajweedCourseVersion
from tests.test_courses_video import KeepingUploader, media, storage  # noqa: F401 - fixtures

MEDIA = "https://media.iqro.forum"
LESSON = "izhar"


def picture(stem: str) -> dict[str, Any]:
    return {
        "object_key": f"courses/slides/{stem}.webp",
        "small_object_key": f"courses/slides/{stem}-800.webp",
        "width": 1600,
        "height": 900,
        "sha256": stem.ljust(64, "0"),
    }


def video(sha: str = "a") -> dict[str, Any]:
    return {
        "sha256": sha * 64,
        "object_key": f"courses/videos/{sha * 20}.mp4",
        "bytes": 41943040,
        "duration_ms": 245000,
        "width": 1280,
        "height": 720,
        "fps": 30.0,
        "spoken_language": "ru",
        "poster": {
            "object_key": f"courses/posters/{sha * 20}-1280.webp",
            "small_object_key": f"courses/posters/{sha * 20}-640.webp",
            "width": 1280,
            "height": 720,
        },
        "dubs": {
            "en": {
                "sha256": "e" * 64,
                "object_key": f"courses/videos/{sha * 20}-en-eeeeeeeeeeee.mp4",
                "bytes": 40000000,
                "duration_ms": 245000,
            }
        },
    }


def with_media(snapshot: dict[str, Any], blocks: list[dict[str, Any]]) -> dict[str, Any]:
    result = copy.deepcopy(snapshot)
    next(lesson for lesson in result["lessons"] if lesson["slug"] == LESSON)["media"] = blocks
    return result


SLIDES = {
    "id": "slides000001",
    "type": "slides",
    "slides": [
        {
            "id": "slide0000001",
            "image": picture("a"),
            "images": {"ar": picture("ar")},
            "caption": {"ru": "Горловые буквы", "ar": "حروف الحلق"},
            "alt": {},
        }
    ],
}


@pytest.fixture
def owner(db: None) -> User:
    return User.objects.create_superuser(email="tajweed-owner@example.com", password="pw-123456789")


@pytest.fixture
def draft(db: None) -> TajweedCourseVersion:
    return import_tajweed_course(copy.deepcopy(load_course_snapshot()))


def _publish(version: TajweedCourseVersion, owner: User) -> TajweedCourseVersion:
    with patch("quran_backend.modules.tajweed.course_publication.enqueue_tajweed_content_change"):
        for sha256 in new_videos(version):
            mark_tajweed_watched(version, sha256=sha256, watched=True)
        version.refresh_from_db()
        sign_tajweed_course(version, owner)
        publish_tajweed_course(version)
    version.refresh_from_db()
    return version


# Snapshot and documents ------------------------------------------------------


@pytest.mark.django_db
@override_settings(PUBLIC_AUDIO_BASE_URL=MEDIA)
def test_documents_show_the_lesson_media_on_each_language() -> None:
    snapshot = with_media(
        load_course_snapshot(), [{"id": "video", "type": "video", "video": video()}, SLIDES]
    )
    version = import_tajweed_course(snapshot)

    def lesson(language: str) -> dict[str, Any]:
        payload = TajweedCourseDocument.objects.get(version=version, language=language).payload
        return next(item for item in payload["lessons"] if item["slug"] == LESSON)

    russian, arabic, english = lesson("ru"), lesson("ar"), lesson("en")
    assert [block["type"] for block in russian["media"]] == ["video", "slides"]
    assert russian["media"][0]["video"]["url"] == f"{MEDIA}/courses/videos/{'a' * 20}.mp4"
    # The English document gets the English dub, the Arabic one its own picture.
    assert english["media"][0]["video"]["url"].endswith("-en-eeeeeeeeeeee.mp4")
    assert english["media"][0]["video"]["spoken_language"] == "en"
    assert arabic["media"][1]["slides"][0] == {
        "image": {
            "url": f"{MEDIA}/courses/slides/ar.webp",
            "small_url": f"{MEDIA}/courses/slides/ar-800.webp",
            "width": 1600,
            "height": 900,
        },
        "caption": "حروف الحلق",
        "alt": "حروف الحلق",
        "dir": "rtl",
    }
    other = next(item for item in russian_lessons(version) if item["slug"] != LESSON)
    assert other["media"] == []


def russian_lessons(version: TajweedCourseVersion) -> list[dict[str, Any]]:
    payload = TajweedCourseDocument.objects.get(version=version, language="ru").payload
    return list(payload["lessons"])


def test_snapshot_refuses_odd_media() -> None:
    snapshot = load_course_snapshot()
    for blocks in (
        [{"id": "x", "type": "gallery"}],
        [{"id": "video", "type": "video"}, {"id": "video", "type": "video"}],
        [{"id": "x", "type": "slides"}],
        "slides",
    ):
        with pytest.raises(TajweedCourseError, match="media"):
            validate_course_snapshot(with_media(snapshot, blocks))  # type: ignore[arg-type]


@pytest.mark.django_db
def test_a_new_draft_copies_the_media(draft: TajweedCourseVersion) -> None:
    draft.snapshot = with_media(draft.snapshot, [SLIDES])
    draft.save(update_fields=["snapshot"])
    copied = copy_tajweed_course(draft, "2026-11-01")
    lesson = next(item for item in copied.snapshot["lessons"] if item["slug"] == LESSON)
    assert lesson["media"] == [SLIDES]


# Watched marks and sign-off ----------------------------------------------------------


@pytest.mark.django_db
def test_sign_off_needs_every_new_video_and_dub_watched(owner: User) -> None:
    version = import_tajweed_course(
        with_media(load_course_snapshot(), [{"id": "video", "type": "video", "video": video()}])
    )
    assert new_videos(version) == {"a" * 64, "e" * 64}
    with pytest.raises(TajweedCourseError, match="Просмотрено"):
        sign_tajweed_course(version, owner)
    mark_tajweed_watched(version, sha256="a" * 64, watched=True)
    with pytest.raises(TajweedCourseError, match="нет среди новых"):
        mark_tajweed_watched(version, sha256="f" * 64, watched=True)
    version.refresh_from_db()
    with pytest.raises(TajweedCourseError, match="Просмотрено"):
        sign_tajweed_course(version, owner)
    published = _publish(version, owner)
    assert published.status == "published"

    # The next draft shows the same files: nothing new to watch, a new dub is.
    later = copy_tajweed_course(published, "2026-11-01")
    assert new_videos(later) == set()
    changed = video()
    changed["dubs"]["tr"] = {**changed["dubs"]["en"], "sha256": "d" * 64}
    later.snapshot = with_media(
        later.snapshot, [{"id": "video", "type": "video", "video": changed}]
    )
    later.save(update_fields=["snapshot"])
    assert new_videos(later) == {"d" * 64}


# Admin -------------------------------------------------------------------------


def _client(user: User) -> Client:
    client = Client()
    client.force_login(user)
    return client


def _url(name: str, version: TajweedCourseVersion, *args: str) -> str:
    return reverse(f"admin:tajweed_tajweedcourseversion_{name}", args=[version.pk, *args])


@pytest.fixture
def stored() -> Iterator[list[str]]:
    names: list[str] = []

    def fake(uploaded: Any, *, kind: str, prefix: str) -> dict[str, Any]:
        names.append(f"{prefix}/{kind}/{uploaded.name}")
        return picture(Path(uploaded.name).stem)

    with patch("quran_backend.modules.courses.lesson_media_admin.store_media_image", fake):
        yield names


def _file(name: str) -> SimpleUploadedFile:
    return SimpleUploadedFile(name, b"\x89PNG\r\n\x1a\n", content_type="image/png")


@pytest.mark.django_db
@override_settings(PUBLIC_AUDIO_BASE_URL=MEDIA)
def test_editor_adds_slides_to_a_draft_lesson(
    draft: TajweedCourseVersion, owner: User, stored: list[str]
) -> None:
    client = _client(owner)
    editor = _url("editor", draft) + f"?node=lesson:{LESSON}"
    page = client.get(editor).content.decode()
    assert "Медиа пока нет." in page
    assert "lesson_media/admin/media.js" in page

    address = _url("media", draft, LESSON)
    added = client.post(
        address, {"action": "add", "kind": "slides", "file": [_file("one.png"), _file("two.png")]}
    )
    assert added.status_code == 200
    assert "Слайд 2" in added.json()["html"]
    assert stored == ["courses/slides/one.png", "courses/slides/two.png"]
    draft.refresh_from_db()
    lesson = next(item for item in draft.snapshot["lessons"] if item["slug"] == LESSON)
    (block,) = lesson["media"]
    texts = client.post(
        address,
        {"action": "texts", "block": block["id"], "slide": block["slides"][0]["id"],
         "language": "ru", "caption": "Изхар", "alt": ""},
    )  # fmt: skip
    assert texts.json() == {"ok": True}
    document = TajweedCourseDocument.objects.get(version=draft, language="ru").payload
    shown = next(item for item in document["lessons"] if item["slug"] == LESSON)["media"]
    assert shown[0]["slides"][0]["caption"] == "Изхар"
    # The lesson's texts saved from the form keep the media.
    client.post(editor, {"node": f"lesson:{LESSON}", "minutes": "5", "letters": "ء ه"})
    draft.refresh_from_db()
    lesson = next(item for item in draft.snapshot["lessons"] if item["slug"] == LESSON)
    assert lesson["media"][0]["slides"][0]["caption"] == {"ru": "Изхар"}


@pytest.mark.django_db
def test_signed_and_published_versions_keep_their_media(
    draft: TajweedCourseVersion, owner: User, stored: list[str]
) -> None:
    published = _publish(draft, owner)
    client = _client(owner)
    answer = client.post(
        _url("media", published, LESSON),
        {"action": "add", "kind": "slides", "file": _file("a.png")},
    )
    assert answer.status_code == 403
    assert stored == []
    assert client.post(_url("media", published, "no-such-lesson")).status_code == 404


@pytest.mark.django_db
@override_settings(PUBLIC_AUDIO_BASE_URL=MEDIA)
def test_the_editor_shows_the_way_to_the_media_buttons(
    draft: TajweedCourseVersion, owner: User
) -> None:
    client = _client(owner)
    course = client.get(_url("editor", draft)).content.decode()
    assert OPEN_LESSON_HINT in course
    assert "data-lesson-media" not in course
    lesson = client.get(_url("editor", draft) + f"?node=lesson:{LESSON}").content.decode()
    assert OPEN_LESSON_HINT not in lesson
    assert MAKE_DRAFT_HINT not in lesson
    assert "data-media-add" in lesson

    published = _publish(draft, owner)
    copy_url = _url("new_draft", published)
    for address in (
        _url("editor", published),
        _url("editor", published) + f"?node=lesson:{LESSON}",
    ):
        page = client.get(address).content.decode()
        assert MAKE_DRAFT_HINT in page
        assert f'<a class="button default" href="{copy_url}">' in page


@pytest.mark.django_db
@override_settings(PUBLIC_AUDIO_BASE_URL=MEDIA)
def test_editor_uploads_a_video_and_a_dub_into_the_draft(
    media: dict[str, Path],  # noqa: F811 - the fixture of the video tests
    storage: KeepingUploader,  # noqa: F811
    draft: TajweedCourseVersion,
    owner: User,
) -> None:
    client = _client(owner)
    with media["handbrake"].open("rb") as file:
        uploaded = client.post(
            _url("video", draft, LESSON, "upload"), {"file": file, "spoken_language": "ru"}
        )
    assert uploaded.status_code == 200, uploaded.content
    assert "Язык речи" in uploaded.json()["html"]
    draft.refresh_from_db()
    lesson = next(item for item in draft.snapshot["lessons"] if item["slug"] == LESSON)
    stored_video = lesson["media"][0]["video"]
    assert stored_video["object_key"].startswith("courses/videos/")
    assert stored_video["original_name"] == "lecture.mp4"

    with media["dub_mp3"].open("rb") as file:
        dubbed = client.post(
            _url("dub", draft, LESSON, "en", "upload"),
            {"file": file, "video": stored_video["sha256"]},
        )
    assert dubbed.status_code == 200, dubbed.content
    stale = client.post(
        _url("video", draft, LESSON, "language"), {"video": "0" * 64, "spoken_language": "ar"}
    )
    assert stale.status_code == 409
    draft.refresh_from_db()
    lesson = next(item for item in draft.snapshot["lessons"] if item["slug"] == LESSON)
    assert set(lesson["media"][0]["video"]["dubs"]) == {"en"}
    assert len(new_videos(draft)) == 2
    page = client.get(_url("editor", draft) + f"?node=lesson:{LESSON}").content.decode()
    assert "Новые видео и озвучки" in page

    removed = client.post(_url("video", draft, LESSON, "remove"), {"video": stored_video["sha256"]})
    assert removed.status_code == 200
    draft.refresh_from_db()
    assert new_videos(draft) == set()
