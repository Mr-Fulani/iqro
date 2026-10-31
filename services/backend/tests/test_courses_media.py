# Russian admin text is intentional.
"""Media of a lesson: video, slides and banners (docs/courses/README.md, «Медиа темы»)."""

from __future__ import annotations

import shutil
import subprocess
from collections.abc import Iterator
from pathlib import Path
from typing import Any
from unittest.mock import patch

import pytest
from django.contrib.admin.models import LogEntry
from django.contrib.auth.models import Permission
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import Client, override_settings

from quran_backend.modules.accounts.models import User
from quran_backend.modules.core.object_storage import ImmutableObjectSpec, StoredObject
from quran_backend.modules.courses.document import build_document, build_snapshot, changes
from quran_backend.modules.courses.lesson_media import (
    LessonMediaError,
    add_block,
    add_images,
    media_changes,
    media_payload,
    media_snapshot,
    move_blocks,
    move_slides,
    remove_slide,
    set_language_image,
    set_texts,
    store_media_image,
)
from quran_backend.modules.courses.lesson_media_admin import (
    MAKE_DRAFT_HINT,
    NEW_LESSON_HINT,
    NO_DRAFT_HINT,
    OPEN_LESSON_HINT,
    media_hint,
)
from quran_backend.modules.courses.models import (
    Course,
    CourseDocument,
    CourseLesson,
    CourseVideo,
)
from quran_backend.modules.courses.services import prepare_release, publish_release, sign_release
from quran_backend.modules.salah.importer import webp_size

MEDIA = "https://media.iqro.forum"
LANGUAGES = ("ar", "en", "ru", "tr")
needs_ffmpeg = pytest.mark.skipif(shutil.which("ffmpeg") is None, reason="ffmpeg is not installed")


def picture(stem: str, width: int = 1600, height: int = 900) -> dict[str, Any]:
    return {
        "object_key": f"courses/slides/{stem}.webp",
        "small_object_key": f"courses/slides/{stem}-800.webp",
        "width": width,
        "height": height,
        "sha256": stem.ljust(64, "0"),
    }


def url(key: str) -> str:
    return f"{MEDIA}/{key}"


class Keeping:
    def __init__(self, folder: Path) -> None:
        self.folder = folder
        self.specs: list[ImmutableObjectSpec] = []

    def upload_path(self, source_path: Path, spec: ImmutableObjectSpec) -> StoredObject:
        self.specs.append(spec)
        target = self.folder / spec.key
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source_path, target)
        return StoredObject(key=spec.key, etag='"etag"', created=True)


def _image(folder: Path, name: str, size: str) -> SimpleUploadedFile:
    path = folder / name
    subprocess.run(  # noqa: S603
        ["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", f"testsrc2=size={size}",  # noqa: S607
         "-frames:v", "1", str(path)],
        check=True,
        capture_output=True,
    )  # fmt: skip
    return SimpleUploadedFile(name, path.read_bytes(), content_type="image/png")


# Pictures ----------------------------------------------------------------


@needs_ffmpeg
def test_slide_keeps_its_shape_and_is_never_enlarged(tmp_path: Path) -> None:
    uploader = Keeping(tmp_path / "r2")
    wide = store_media_image(
        _image(tmp_path, "wide.png", "2400x1200"),
        kind="slides",
        prefix="courses",
        uploader=uploader,
    )
    assert (wide["width"], wide["height"]) == (1600, 800)
    assert wide["object_key"] == f"courses/slides/{wide['sha256'][:20]}.webp"
    assert wide["small_object_key"] == f"courses/slides/{wide['sha256'][:20]}-800.webp"
    small = (tmp_path / "r2" / wide["small_object_key"]).read_bytes()
    assert webp_size(small) == (800, 400)
    assert [spec.content_type for spec in uploader.specs] == ["image/webp", "image/webp"]

    tiny = store_media_image(
        _image(tmp_path, "tiny.png", "640x480"), kind="slides", prefix="courses", uploader=uploader
    )
    assert (tiny["width"], tiny["height"]) == (640, 480)


@needs_ffmpeg
def test_banner_is_cropped_to_16_by_9(tmp_path: Path) -> None:
    uploader = Keeping(tmp_path / "r2")
    banner = store_media_image(
        _image(tmp_path, "square.png", "1000x1000"),
        kind="banner",
        prefix="tajweed",
        uploader=uploader,
    )
    assert (banner["width"], banner["height"]) == (1600, 900)
    assert banner["object_key"].startswith("tajweed/banners/")
    assert webp_size((tmp_path / "r2" / banner["small_object_key"]).read_bytes()) == (800, 450)


@needs_ffmpeg
def test_odd_pictures_are_refused(tmp_path: Path) -> None:
    uploader = Keeping(tmp_path / "r2")
    with pytest.raises(LessonMediaError, match="слишком вытянута"):
        store_media_image(
            _image(tmp_path, "strip.png", "2000x400"),
            kind="slides",
            prefix="courses",
            uploader=uploader,
        )
    with pytest.raises(LessonMediaError, match="нужна картинка JPEG, PNG или WebP"):
        store_media_image(
            SimpleUploadedFile("notes.txt", b"not a picture"), kind="slides", prefix="courses"
        )
    assert uploader.specs == []


# The editor's list ---------------------------------------------------------


def test_blocks_are_added_moved_and_their_slides_edited() -> None:
    media, slides = add_block([], "slides", has_video=True)
    # A video uploaded before the list existed stands first.
    assert [block["type"] for block in media] == ["video", "slides"]
    media = add_images(media, slides["id"], [picture("a"), picture("b")], has_video=True)
    media, banner = add_block(media, "banner", has_video=True)
    media = add_images(media, banner["id"], [picture("c")], has_video=True)
    media = move_blocks(media, [banner["id"], "video", slides["id"]], has_video=True)
    assert [block["type"] for block in media] == ["banner", "video", "slides"]

    first, second = (slide["id"] for slide in media[2]["slides"])
    media = move_slides(media, slides["id"], [second, first], has_video=True)
    media = set_texts(
        media, slides["id"], first, "ru", caption="  Подпись  ", alt="", has_video=True
    )
    media = set_language_image(media, slides["id"], first, "ar", picture("d"), has_video=True)
    media = remove_slide(media, slides["id"], second, has_video=True)
    (slide,) = media[2]["slides"]
    assert slide["caption"] == {"ru": "Подпись"}
    assert slide["images"]["ar"]["object_key"] == "courses/slides/d.webp"
    # A banner keeps one picture: a new one replaces it.
    media = add_images(media, banner["id"], [picture("e")], has_video=True)
    assert [slide["image"]["object_key"] for slide in media[0]["slides"]] == [
        "courses/slides/e.webp"
    ]


def test_editor_refuses_what_does_not_fit() -> None:
    media, _ = add_block([], "video", has_video=False)
    with pytest.raises(LessonMediaError, match="одно видео"):
        add_block(media, "video", has_video=False)
    media, block = add_block(media, "slides", has_video=False)
    with pytest.raises(LessonMediaError, match="не больше 30 слайдов"):
        add_images(media, block["id"], [picture(str(n)) for n in range(31)], has_video=False)
    with pytest.raises(LessonMediaError, match="другой вкладке") as stale:
        move_blocks(media, [block["id"]], has_video=False)
    assert stale.value.status == 409
    media = add_images(media, block["id"], [picture("a")], has_video=False)
    slide_id = media[1]["slides"][0]["id"]
    with pytest.raises(LessonMediaError, match="не больше 300 знаков"):
        set_texts(media, block["id"], slide_id, "ru", caption="я" * 301, alt="", has_video=False)
    with pytest.raises(LessonMediaError, match="Общая картинка нужна"):
        set_language_image(media, block["id"], slide_id, "", None, has_video=False)


def test_snapshot_drops_empty_blocks_and_a_missing_video() -> None:
    media, empty = add_block([{"id": "video", "type": "video"}], "slides", has_video=False)
    media, banner = add_block(media, "banner", has_video=False)
    media = add_images(media, banner["id"], [picture("b")], has_video=False)
    snapshot = media_snapshot(media, has_video=False, languages=LANGUAGES)
    assert [block["id"] for block in snapshot] == [banner["id"]]
    assert empty["id"] not in str(snapshot)
    assert snapshot[0]["slides"][0]["caption"] == dict.fromkeys(LANGUAGES, "")


def test_payload_takes_the_language_picture_and_falls_back_on_the_caption() -> None:
    media, block = add_block([], "slides", has_video=False)
    media = add_images(media, block["id"], [picture("a")], has_video=False)
    slide_id = media[0]["slides"][0]["id"]
    media = set_language_image(media, block["id"], slide_id, "ar", picture("ar"), has_video=False)
    media = set_texts(media, block["id"], slide_id, "ar", caption="نية", alt="", has_video=False)
    media = set_texts(media, block["id"], slide_id, "ru", caption="", alt="Схема", has_video=False)
    snapshot = media_snapshot(media, has_video=False, languages=LANGUAGES)

    def first(language: str) -> dict[str, Any]:
        (result,) = media_payload(snapshot, language=language, video=None, public_url=url)
        return dict(result["slides"][0])

    assert first("ar") == {
        "image": {
            "url": f"{MEDIA}/courses/slides/ar.webp",
            "small_url": f"{MEDIA}/courses/slides/ar-800.webp",
            "width": 1600,
            "height": 900,
        },
        "caption": "نية",
        "alt": "نية",
        "dir": "rtl",
    }
    russian = first("ru")
    assert russian["image"]["url"] == f"{MEDIA}/courses/slides/a.webp"
    assert (russian["caption"], russian["alt"], russian["dir"]) == ("", "Схема", "ltr")


def test_changes_name_added_changed_removed_and_moved_blocks() -> None:
    old, slides = add_block([], "slides", has_video=True)
    old = add_images(old, slides["id"], [picture("a"), picture("b")], has_video=True)
    old, banner = add_block(old, "banner", has_video=True)
    old = add_images(old, banner["id"], [picture("c")], has_video=True)
    before = media_snapshot(old, has_video=True, languages=LANGUAGES)

    new = move_blocks(old, [slides["id"], "video", banner["id"]], has_video=True)
    first = new[0]["slides"][0]["id"]
    new = set_texts(new, slides["id"], first, "en", caption="Intention", alt="", has_video=True)
    new = add_images(new, slides["id"], [picture("d")], has_video=True)
    new = set_language_image(new, slides["id"], first, "ar", picture("e"), has_video=True)
    new = [block for block in new if block["id"] != banner["id"]]
    new, _ = add_block(new, "banner", has_video=True)
    new = add_images(new, new[-1]["id"], [picture("f")], has_video=True)
    after = media_snapshot(new, has_video=True, languages=LANGUAGES)

    assert media_changes(before, after, ["ru", "ar", "en", "tr"]) == [
        "слайды: добавлено слайдов: 1, заменены картинки, изменены подписи (en)",
        "добавлен баннер",
        "удалён баннер",
        "изменён порядок медиа",
    ]


# The lesson, its release and its documents ------------------------------------


@pytest.fixture
def owner(db: None) -> User:
    return User.objects.create_user(
        email="media-owner@example.test", status="active", is_staff=True, is_superuser=True
    )


@pytest.fixture
def lesson(db: None) -> CourseLesson:
    course = Course.objects.create(slug="ramadan", title_ru="Рамадан", summary_ru="Пост.")
    return CourseLesson.objects.create(
        course=course, slug="namerenie", title_ru="Намерение", notes_ru="Решение сердца."
    )


def _video(lesson: CourseLesson) -> CourseVideo:
    video = CourseVideo.objects.create(
        course=lesson.course,
        object_key="courses/videos/aaaaaaaaaaaaaaaaaaaa.mp4",
        sha256="a" * 64,
        bytes=1000,
        duration_ms=125_000,
        width=1280,
        height=720,
        fps=30,
        bitrate_kbps=1500,
        video_codec="h264",
        audio_codec="aac",
        has_audio=True,
        poster_object_key="courses/posters/a-1280.webp",
        poster_small_object_key="courses/posters/a-640.webp",
        poster_width=1280,
        poster_height=720,
    )
    lesson.video = video
    lesson.save(update_fields=["video"])
    return video


@pytest.mark.django_db
def test_a_lesson_without_slides_keeps_its_snapshot(lesson: CourseLesson) -> None:
    _video(lesson)
    plain = build_snapshot(lesson.course)
    lesson.media = [{"id": "video", "type": "video"}, {"id": "x", "type": "slides", "slides": []}]
    lesson.save(update_fields=["media"])
    # Only the place of the video and an empty block: students see the same.
    assert build_snapshot(lesson.course) == plain
    assert "media" not in plain["lessons"][0]


@pytest.mark.django_db
@override_settings(PUBLIC_AUDIO_BASE_URL=MEDIA)
def test_document_puts_the_video_where_the_author_did(lesson: CourseLesson) -> None:
    _video(lesson)
    media, block = add_block([], "slides", has_video=True)
    lesson.media = add_images(media, block["id"], [picture("a")], has_video=True)[::-1]
    lesson.save(update_fields=["media"])
    document = build_document(
        build_snapshot(lesson.course), language="ru", version="1", languages=["ru"]
    )
    (item,) = document["lessons"]
    assert [entry["type"] for entry in item["media"]] == ["slides", "video"]
    assert item["media"][1]["video"] == item["video"]


@pytest.mark.django_db
@override_settings(PUBLIC_AUDIO_BASE_URL=MEDIA)
def test_release_names_slides_in_changes_and_shows_them_to_the_reviewer(
    lesson: CourseLesson, owner: User
) -> None:
    first = prepare_release(lesson.course, owner, languages=["ru"], change_note="Первый")
    publish_release(sign_release(first, owner), owner)
    media, block = add_block([], "slides", has_video=False)
    lesson.media = add_images(media, block["id"], [picture("a"), picture("b")], has_video=False)
    lesson.save(update_fields=["media"])

    assert changes(first.snapshot, build_snapshot(lesson.course)) == [
        "Тема 1: добавлены слайды (2)"
    ]
    second = prepare_release(lesson.course, owner, languages=["ru"], change_note="Слайды")
    payload = CourseDocument.objects.get(release=second).payload
    assert len(payload["lessons"][0]["media"][0]["slides"]) == 2
    page = _client(owner).get(f"/admin/courses/courserelease/{second.pk}/change/").content.decode()
    assert "Слайды: новый блок" in page
    assert f'src="{MEDIA}/courses/slides/b-800.webp"' in page
    preview = (
        _client(owner).get(f"/admin/courses/courserelease/{second.pk}/preview/").content.decode()
    )
    assert "1 / 2" in preview


@pytest.mark.django_db
@override_settings(PUBLIC_AUDIO_BASE_URL=MEDIA)
def test_release_document_before_media_is_previewed_with_its_video(
    lesson: CourseLesson, owner: User
) -> None:
    _video(lesson)
    release = prepare_release(lesson.course, owner, languages=["ru"], change_note="Видео")
    document = CourseDocument.objects.get(release=release)
    del document.payload["lessons"][0]["media"]
    document.save(update_fields=["payload"])
    preview = (
        _client(owner).get(f"/admin/courses/courserelease/{release.pk}/preview/").content.decode()
    )
    assert f'src="{MEDIA}/courses/videos/aaaaaaaaaaaaaaaaaaaa.mp4"' in preview


# Admin ---------------------------------------------------------------------


def _client(user: User) -> Client:
    client = Client()
    client.force_login(user)
    return client


@pytest.fixture
def stored() -> Iterator[list[str]]:
    """Pictures are not processed: each upload gets a picture named after the file."""
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
def test_admin_media_block_edits_the_list(
    lesson: CourseLesson, owner: User, stored: list[str]
) -> None:
    client = _client(owner)
    address = f"/admin/courses/courselesson/{lesson.pk}/media/"
    assert client.get(address).status_code == 405

    added = client.post(
        address, {"action": "add", "kind": "slides", "file": [_file("one.png"), _file("two.png")]}
    )
    assert added.status_code == 200
    html = added.json()["html"]
    assert "Слайд 2" in html
    assert f'src="{MEDIA}/courses/slides/two-800.webp"' in html
    assert stored == ["courses/slides/one.png", "courses/slides/two.png"]

    lesson.refresh_from_db()
    (block,) = lesson.media
    one, two = (slide["id"] for slide in block["slides"])
    texts = client.post(
        address,
        {"action": "texts", "block": block["id"], "slide": one, "language": "ar",
         "caption": "نية", "alt": "صورة"},
    )  # fmt: skip
    assert texts.json() == {"ok": True}
    client.post(address, {"action": "slide_order", "block": block["id"], "order": [two, one]})
    client.post(
        address,
        {"action": "language_image", "block": block["id"], "slide": one, "language": "en",
         "file": _file("english.png")},
    )  # fmt: skip
    banner = client.post(address, {"action": "add", "kind": "banner", "file": _file("wide.png")})
    assert "Баннер" in banner.json()["html"]

    lesson.refresh_from_db()
    slides, banner_block = lesson.media
    assert [slide["id"] for slide in slides["slides"]] == [two, one]
    assert slides["slides"][1]["caption"] == {"ar": "نية"}
    assert slides["slides"][1]["images"]["en"]["object_key"] == "courses/slides/english.webp"
    assert banner_block["type"] == "banner"
    assert lesson.updated_by == owner
    logged = [
        entry.get_change_message() for entry in LogEntry.objects.filter(object_id=str(lesson.pk))
    ]
    assert any("Медиа: подпись слайда (ar)" in message for message in logged)

    stale = client.post(address, {"action": "order", "order": [banner_block["id"]]})
    assert stale.status_code == 409
    assert "другой вкладке" in stale.json()["error"]
    removed = client.post(address, {"action": "remove", "block": slides["id"]})
    assert "Слайд 1" not in removed.json()["html"]


@pytest.mark.django_db
@override_settings(PUBLIC_AUDIO_BASE_URL=MEDIA)
def test_removing_the_video_block_takes_the_video_out(lesson: CourseLesson, owner: User) -> None:
    _video(lesson)
    client = _client(owner)
    page = client.get(f"/admin/courses/courselesson/{lesson.pk}/change/").content.decode()
    assert "1. Видео" in page
    assert "Взять кадр на" in page
    answer = client.post(
        f"/admin/courses/courselesson/{lesson.pk}/media/", {"action": "remove", "block": "video"}
    )
    assert answer.status_code == 200
    lesson.refresh_from_db()
    assert lesson.video_id is None
    assert lesson.media == []


@pytest.mark.django_db
def test_admin_media_needs_the_right_to_change_the_lesson(
    lesson: CourseLesson, stored: list[str]
) -> None:
    viewer = User.objects.create_user(email="viewer@example.test", status="active", is_staff=True)
    viewer.user_permissions.set(Permission.objects.filter(codename="view_courselesson"))
    answer = _client(viewer).post(
        f"/admin/courses/courselesson/{lesson.pk}/media/",
        {"action": "add", "kind": "slides", "file": _file("one.png")},
    )
    assert answer.status_code == 403
    assert stored == []


@pytest.mark.django_db
def test_a_new_theme_says_when_media_can_be_added(owner: User) -> None:
    page = _client(owner).get("/admin/courses/courselesson/add/").content.decode()
    assert NEW_LESSON_HINT in page


@pytest.mark.parametrize(
    ("on_lesson", "editable", "draft_url", "hint"),
    [
        (True, True, "", ""),
        (False, True, "", OPEN_LESSON_HINT),
        (True, False, "/copy/", MAKE_DRAFT_HINT),
        (False, False, "/copy/", MAKE_DRAFT_HINT),
        (True, False, "", NO_DRAFT_HINT),
    ],
)
def test_media_hint_leads_to_the_buttons(
    on_lesson: bool, editable: bool, draft_url: str, hint: str
) -> None:
    assert media_hint(on_lesson=on_lesson, editable=editable, draft_url=draft_url) == hint
