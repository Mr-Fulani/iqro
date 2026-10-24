# Russian admin text is intentional.
# ruff: noqa: RUF001
"""Lesson videos and dubs (docs/courses/README.md, «Видео и озвучки»).

Media files are made by ffmpeg in a temporary folder, a few seconds long and
a few kilobytes big; nothing large is committed.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from collections.abc import Iterator
from pathlib import Path
from typing import Any
from unittest.mock import patch

import pytest
from django.contrib.admin.models import LogEntry
from django.contrib.auth.models import Group, Permission
from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import Client, override_settings
from django.utils import timezone

from quran_backend.modules.accounts.models import User
from quran_backend.modules.core.object_storage import ImmutableObjectSpec, StoredObject
from quran_backend.modules.courses.document import build_snapshot, changes
from quran_backend.modules.courses.models import (
    Course,
    CourseDocument,
    CourseLesson,
    CourseRelease,
    CourseVideo,
    CourseVideoDub,
)
from quran_backend.modules.courses.services import (
    CourseReleaseError,
    mark_watched,
    new_videos,
    prepare_release,
    publish_release,
    sign_release,
)
from quran_backend.modules.courses.video import (
    UPLOAD_LOCK,
    CourseVideoError,
    delete_video_dub,
    poster_size,
    probe_video,
    set_spoken_language,
    set_video_poster,
    upload_lesson_video,
    upload_slot,
    upload_video_dub,
)
from quran_backend.modules.salah.importer import webp_size

MODULE = "quran_backend.modules.courses.video"
MEDIA = "https://media.iqro.forum"
needs_ffmpeg = pytest.mark.skipif(
    shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None,
    reason="ffmpeg is not installed",
)


def _ffmpeg(*arguments: str) -> None:
    subprocess.run(["ffmpeg", "-v", "error", "-y", *arguments], check=True, capture_output=True)  # noqa: S603, S607


def _probe(path: Path) -> dict[str, Any]:
    completed = subprocess.run(  # noqa: S603
        ["ffprobe", "-v", "error", "-print_format", "json", "-show_format", "-show_streams", path],  # noqa: S607
        check=True,
        capture_output=True,
    )
    return dict(json.loads(completed.stdout))


@pytest.fixture(scope="session")
def media(tmp_path_factory: pytest.TempPathFactory) -> dict[str, Path]:
    """Small files shaped like the real ones: an iPhone MOV, a HandBrake MP4, dubs."""
    if shutil.which("ffmpeg") is None:
        pytest.skip("ffmpeg is not installed")
    folder = tmp_path_factory.mktemp("course-media")
    picture = ["-f", "lavfi", "-i", "testsrc2=size=320x180:rate=30"]
    tone = ["-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000"]
    h264 = ["-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p"]
    base = folder / "base.mov"
    _ffmpeg(*picture, *tone, "-t", "12", *h264, "-c:a", "aac", "-ac", "2", str(base))
    # The phone held upright: the frame is stored turned, with the place and the model.
    iphone = folder / "IMG_0001.MOV"
    phone_tags = [
        "-metadata", "location=+55.7558+037.6173+150.000/",
        "-metadata", "com.apple.quicktime.model=iPhone 13",
        "-timecode", "01:00:00:00",
        "-movflags", "use_metadata_tags", "-f", "mov",
    ]  # fmt: skip
    try:
        _ffmpeg("-display_rotation:v:0", "90", "-i", str(base), "-map", "0", "-c", "copy",
                *phone_tags, str(iphone))  # fmt: skip
    except subprocess.CalledProcessError:  # ffmpeg before 7 has no -display_rotation
        _ffmpeg("-i", str(base), "-map", "0", "-c", "copy", "-metadata:s:v:0", "rotate=90",
                *phone_tags, str(iphone))  # fmt: skip
    handbrake = folder / "lecture.mp4"
    _ffmpeg(*picture, *tone, "-t", "12", *h264, "-c:a", "aac", "-b:a", "160k",
            "-movflags", "+faststart", str(handbrake))  # fmt: skip
    silent = folder / "silent.mp4"
    _ffmpeg(*picture, "-t", "11", *h264, str(silent))
    short = folder / "short.mp4"
    _ffmpeg(*picture, "-t", "5", *h264, str(short))
    files = {
        "iphone": iphone,
        "handbrake": handbrake,
        "silent": silent,
        "short": short,
        "dub_mp3": folder / "dub-en.mp3",
        "dub_flac": folder / "dub-tr.flac",
        "dub_long": folder / "dub-long.wav",
        "picture": folder / "poster.png",
    }
    _ffmpeg(*tone, "-t", "12.5", "-c:a", "libmp3lame", "-b:a", "64k", str(files["dub_mp3"]))
    _ffmpeg(*tone, "-t", "11.2", str(files["dub_flac"]))
    _ffmpeg(*tone, "-t", "26", str(files["dub_long"]))
    _ffmpeg("-f", "lavfi", "-i", "color=c=teal:size=800x800", "-frames:v", "1",
            str(files["picture"]))  # fmt: skip
    if subprocess.run(["ffmpeg", "-hide_banner", "-encoders"], capture_output=True, text=True,  # noqa: S607
                      check=True).stdout.count("libx265"):  # fmt: skip
        files["hevc"] = folder / "IMG_0002.MOV"
        _ffmpeg(*picture, "-t", "11", "-c:v", "libx265", "-tag:v", "hvc1", "-pix_fmt", "yuv420p",
                "-f", "mov", str(files["hevc"]))  # fmt: skip
    return files


class KeepingUploader:
    """Keeps a copy of every stored object, so a dub can read its video back."""

    def __init__(self, folder: Path) -> None:
        self.folder = folder
        self.specs: list[ImmutableObjectSpec] = []

    def upload_path(self, source_path: Path, spec: ImmutableObjectSpec) -> StoredObject:
        self.specs.append(spec)
        target = self.folder / spec.key
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source_path, target)
        return StoredObject(key=spec.key, etag='"etag"', created=True)

    def path(self, key: str) -> Path:
        return self.folder / key


@pytest.fixture
def storage(tmp_path: Path) -> Iterator[KeepingUploader]:
    uploader = KeepingUploader(tmp_path / "r2")
    with (
        patch(f"{MODULE}.player_background_uploader", return_value=uploader),
        patch(f"{MODULE}.verify_public_audio_object") as verify,
        patch(
            f"{MODULE}.video_source", side_effect=lambda video: str(uploader.path(video.object_key))
        ),
    ):
        verify.return_value = '"edge"'
        yield uploader


@pytest.fixture
def owner(db: None) -> User:
    return User.objects.create_user(
        email="video-owner@example.test", status="active", is_staff=True, is_superuser=True
    )


@pytest.fixture
def lesson(db: None) -> CourseLesson:
    course = Course.objects.create(slug="ramadan", title_ru="Рамадан", summary_ru="Пост.")
    return CourseLesson.objects.create(
        course=course, slug="namerenie", title_ru="Намерение", notes_ru="Решение сердца."
    )


def _client(user: User) -> Client:
    client = Client()
    client.force_login(user)
    return client


def _upload(lesson: CourseLesson, path: Path, owner: User, **kwargs: Any) -> CourseVideo:
    return upload_lesson_video(
        lesson,
        path,
        user=owner,
        original_name=path.name,
        spoken_language=kwargs.pop("spoken_language", "ru"),
        **kwargs,
    )


def _dub(lesson: CourseLesson, path: Path, owner: User, language: str) -> CourseVideoDub:
    lesson.refresh_from_db()
    return upload_video_dub(
        lesson, lesson.video_id, language, path, user=owner, original_name=path.name
    )


def _release(course: Course, owner: User, languages: list[str]) -> CourseRelease:
    release = prepare_release(course, owner, languages=languages, change_note="Выпуск")
    for sha256 in new_videos(release):
        mark_watched(release, owner, sha256=sha256, watched=True)
    sign_release(release, owner)
    return publish_release(release, owner)


def _translate(lesson: CourseLesson, *languages: str) -> None:
    lesson.refresh_from_db()
    course = lesson.course
    for language in languages:
        setattr(course, f"title_{language}", f"Course {language}")
        setattr(course, f"summary_{language}", f"Summary {language}")
        setattr(lesson, f"title_{language}", f"Lesson {language}")
        setattr(lesson, f"notes_{language}", f"Notes {language}")
    course.save()
    lesson.save()


# What a file must be -----------------------------------------------------


def _report(**video: Any) -> dict[str, Any]:
    audio = video.pop("audio", {"codec_type": "audio", "codec_name": "aac", "channels": 2})
    streams = [
        {
            "index": 0,
            "codec_type": "video",
            "codec_name": "h264",
            "pix_fmt": "yuv420p",
            "width": 1280,
            "height": 720,
            "avg_frame_rate": "30000/1001",
            **video.pop("stream", {}),
        }
    ]
    if audio:
        streams.append({"index": 1, **audio})
    return {
        "streams": streams,
        "format": {
            "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
            "duration": "588.0",
            "bit_rate": "1500000",
            **video,
        },
    }


@pytest.mark.parametrize(
    ("report", "message"),
    [
        (_report(stream={"codec_name": "hevc"}), "HEVC.*Наиболее совместимые.*HandBrake"),
        (_report(stream={"codec_name": "vp9"}), "Видео в формате VP9"),
        (_report(format_name="matroska,webm"), "WebM не подходит"),
        (_report(stream={"pix_fmt": "yuv420p10le"}), "10-битным цветом"),
        (_report(stream={"width": 3840, "height": 2160}), "Кадр 3840×2160, допустимо до 1920×1080"),
        (_report(stream={"avg_frame_rate": "120/1"}), "120 кадров в секунду"),
        (_report(audio={"codec_type": "audio", "codec_name": "mp3"}), "Звук в формате MP3"),
        (
            _report(audio={"codec_type": "audio", "codec_name": "aac", "channels": 6}),
            "многоканальный",
        ),
        (_report(duration="3700.5"), "Видео длится 61 мин 40 с, допустимо до 60 минут"),
        (_report(duration="9.5"), "короче 10 секунд"),
    ],
)
def test_unsuitable_video_is_explained(report: dict[str, Any], message: str) -> None:
    with (
        patch(f"{MODULE}.ffprobe_report", return_value=report),
        pytest.raises(CourseVideoError, match=message),
    ):
        probe_video(Path("lecture.mp4"))


def test_upright_phone_video_cover_art_and_no_sound_are_accepted() -> None:
    upright = _report(
        stream={"width": 1920, "height": 1080, "side_data_list": [{"rotation": -90}]}, audio=None
    )
    upright["streams"].insert(
        0,
        {
            "index": 2,
            "codec_type": "video",
            "codec_name": "mjpeg",
            "disposition": {"attached_pic": 1},
        },
    )
    with patch(f"{MODULE}.ffprobe_report", return_value=upright):
        probe = probe_video(Path("IMG_0001.MOV"))

    assert (probe.width, probe.height) == (1080, 1920)
    assert probe.video_index == 0
    assert probe.audio_index is None
    assert probe.fps == 29.97
    assert probe.duration_ms == 588_000


def test_poster_keeps_the_frame_shape() -> None:
    assert poster_size(1920, 1080, (1280, 720)) == (1280, 720)
    assert poster_size(1080, 1920, (1280, 720)) == (404, 720)
    assert poster_size(1440, 1080, (640, 360)) == (480, 360)


# Upload, remux, posters ----------------------------------------------------


@needs_ffmpeg
@pytest.mark.django_db
@override_settings(PUBLIC_AUDIO_BASE_URL=MEDIA)
def test_phone_video_is_remuxed_without_its_metadata(
    media: dict[str, Path], lesson: CourseLesson, owner: User, storage: KeepingUploader
) -> None:
    video = _upload(lesson, media["iphone"], owner)

    lesson.refresh_from_db()
    assert lesson.video == video
    assert video.object_key == f"courses/videos/{video.sha256[:20]}.mp4"
    assert (video.width, video.height) == (180, 320)
    assert video.video_codec == "h264"
    assert video.audio_codec == "aac"
    assert video.has_audio
    assert 11_900 <= video.duration_ms <= 12_100
    assert video.original_name == "IMG_0001.MOV"
    stored = _probe(storage.path(video.object_key))
    assert [stream["codec_type"] for stream in stored["streams"]] == ["video", "audio"]
    tags = json.dumps(stored["format"].get("tags", {})) + json.dumps(
        [stream.get("tags", {}) for stream in stored["streams"]]
    )
    assert "55.7558" not in tags
    assert "iPhone" not in tags
    assert "2026" not in tags
    with storage.path(video.object_key).open("rb") as file:
        head = file.read(64 * 1024)
    assert head.index(b"moov") < head.index(b"mdat")  # faststart: the index comes first
    [spec] = [spec for spec in storage.specs if spec.key == video.object_key]
    assert spec.content_type == "video/mp4"
    assert spec.size_bytes == video.bytes

    # Poster: a frame in two sizes, upright like the video.
    assert video.poster_object_key.startswith(f"courses/posters/{video.sha256[:20]}-")
    assert video.poster_object_key.endswith("-1280.webp")
    assert video.poster_small_object_key.endswith("-640.webp")
    assert (video.poster_width, video.poster_height) == (404, 720)
    big = storage.path(video.poster_object_key).read_bytes()
    small = storage.path(video.poster_small_object_key).read_bytes()
    assert webp_size(big) == (404, 720)
    assert webp_size(small) == (202, 360)
    assert len(big) <= 120 * 1024
    assert len(small) <= 50 * 1024


@needs_ffmpeg
@pytest.mark.django_db
def test_same_file_again_reuses_the_row_and_uploads_nothing(
    media: dict[str, Path], lesson: CourseLesson, owner: User, storage: KeepingUploader
) -> None:
    first = _upload(lesson, media["handbrake"], owner)
    stored = len(storage.specs)
    second_lesson = CourseLesson.objects.create(
        course=lesson.course, slug="suhur", title_ru="Сухур"
    )

    again = _upload(second_lesson, media["handbrake"], owner)

    assert again == first
    assert len(storage.specs) == stored == 3
    assert CourseVideo.objects.count() == 1


@needs_ffmpeg
@pytest.mark.django_db
def test_video_without_sound_has_no_speech_by_choice(
    media: dict[str, Path], lesson: CourseLesson, owner: User, storage: KeepingUploader
) -> None:
    video = _upload(lesson, media["silent"], owner, spoken_language="")

    assert not video.has_audio
    assert video.audio_codec == ""
    assert video.spoken_language == ""
    assert [
        stream["codec_type"] for stream in _probe(storage.path(video.object_key))["streams"]
    ] == ["video"]


@needs_ffmpeg
@pytest.mark.django_db
def test_hevc_and_short_videos_are_refused_before_storage(
    media: dict[str, Path], lesson: CourseLesson, owner: User, storage: KeepingUploader
) -> None:
    if "hevc" in media:
        with pytest.raises(CourseVideoError, match="HEVC"):
            _upload(lesson, media["hevc"], owner)
    with pytest.raises(CourseVideoError, match="короче 10 секунд"):
        _upload(lesson, media["short"], owner)
    with pytest.raises(CourseVideoError, match="Выберите язык речи"):
        _upload(lesson, media["handbrake"], owner, spoken_language="de")

    assert storage.specs == []
    assert not CourseVideo.objects.exists()


@needs_ffmpeg
@pytest.mark.django_db
def test_replacing_a_video_drops_the_unreleased_row_and_keeps_a_released_one(
    media: dict[str, Path], lesson: CourseLesson, owner: User, storage: KeepingUploader
) -> None:
    draft = _upload(lesson, media["silent"], owner, spoken_language="")
    released = _upload(lesson, media["handbrake"], owner)
    assert not CourseVideo.objects.filter(pk=draft.pk).exists()

    _release(lesson.course, owner, ["ru"])
    _upload(lesson, media["iphone"], owner)

    assert CourseVideo.objects.filter(pk=released.pk).exists()
    assert CourseVideo.objects.count() == 2


@needs_ffmpeg
@pytest.mark.django_db
def test_poster_from_a_chosen_second_and_from_a_picture(
    media: dict[str, Path], lesson: CourseLesson, owner: User, storage: KeepingUploader
) -> None:
    video = _upload(lesson, media["handbrake"], owner)
    original = video.poster_object_key

    framed = set_video_poster(lesson, video.pk, user=owner, second=7)
    assert framed.poster_object_key != original
    assert webp_size(storage.path(framed.poster_object_key).read_bytes()) == (1280, 720)

    picture = SimpleUploadedFile("poster.png", media["picture"].read_bytes(), "image/png")
    pictured = set_video_poster(lesson, video.pk, user=owner, image=picture)
    # A square picture is cropped to the frame's shape.
    assert webp_size(storage.path(pictured.poster_object_key).read_bytes()) == (1280, 720)

    with pytest.raises(CourseVideoError, match="Укажите секунду от 0 до 11"):
        set_video_poster(lesson, video.pk, user=owner, second=12)
    text = SimpleUploadedFile("poster.png", b"not a picture", "image/png")
    with pytest.raises(CourseVideoError, match="Нужна картинка"):
        set_video_poster(lesson, video.pk, user=owner, image=text)


# Dubs ----------------------------------------------------------------------


@needs_ffmpeg
@pytest.mark.django_db
def test_dub_joins_the_picture_with_new_sound(
    media: dict[str, Path], lesson: CourseLesson, owner: User, storage: KeepingUploader
) -> None:
    video = _upload(lesson, media["handbrake"], owner)

    dub = _dub(lesson, media["dub_mp3"], owner, "en")

    assert dub.object_key == f"courses/videos/{video.sha256[:20]}-en-{dub.sha256[:12]}.mp4"
    assert dub.audio_codec == "mp3"
    assert dub.audio_original_name == "dub-en.mp3"
    joined = _probe(storage.path(dub.object_key))
    picture, sound = joined["streams"]
    original = _probe(storage.path(video.object_key))["streams"][0]
    # The picture is copied: same codec, size and bitrate, not encoded again.
    assert picture["codec_name"] == "h264"
    assert (picture["width"], picture["height"], picture["bit_rate"]) == (
        original["width"],
        original["height"],
        original["bit_rate"],
    )
    assert sound["codec_name"] == "aac"
    assert 100_000 <= int(sound["bit_rate"]) <= 140_000
    # -shortest: the result is no longer than the video.
    assert dub.duration_ms <= video.duration_ms + 100

    flac = _dub(lesson, media["dub_flac"], owner, "tr")
    assert flac.audio_codec == "flac"


@needs_ffmpeg
@pytest.mark.django_db
def test_dub_of_another_length_or_the_main_language_is_refused(
    media: dict[str, Path], lesson: CourseLesson, owner: User, storage: KeepingUploader
) -> None:
    _upload(lesson, media["handbrake"], owner)
    stored = len(storage.specs)

    with pytest.raises(CourseVideoError, match="Озвучка длиннее видео на 14 с"):
        _dub(lesson, media["dub_long"], owner, "en")
    with pytest.raises(CourseVideoError, match="уже на языке «русский»"):
        _dub(lesson, media["dub_mp3"], owner, "ru")
    with pytest.raises(CourseVideoError, match="Нужен звук MP3"):
        _dub(lesson, media["picture"], owner, "en")

    assert len(storage.specs) == stored
    assert not CourseVideoDub.objects.exists()


@needs_ffmpeg
@pytest.mark.django_db
def test_short_dub_names_the_difference(
    media: dict[str, Path],
    lesson: CourseLesson,
    owner: User,
    storage: KeepingUploader,
    tmp_path: Path,
) -> None:
    long_video = tmp_path / "long.mp4"
    _ffmpeg("-f", "lavfi", "-i", "testsrc2=size=320x180:rate=30", "-t", "26.6",
            "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p",
            str(long_video))  # fmt: skip
    _upload(lesson, long_video, owner, spoken_language="")

    with pytest.raises(CourseVideoError, match="Озвучка короче видео на 14 с"):
        _dub(lesson, media["dub_mp3"], owner, "en")


@needs_ffmpeg
@pytest.mark.django_db
def test_replaced_or_deleted_dub_stays_only_if_released(
    media: dict[str, Path], lesson: CourseLesson, owner: User, storage: KeepingUploader
) -> None:
    video = _upload(lesson, media["handbrake"], owner)
    first = _dub(lesson, media["dub_mp3"], owner, "en")
    second = _dub(lesson, media["dub_flac"], owner, "en")
    assert not CourseVideoDub.objects.filter(pk=first.pk).exists()

    _translate(lesson, "en")
    _release(lesson.course, owner, ["ru", "en"])
    delete_video_dub(lesson, video.pk, "en", user=owner)

    second.refresh_from_db()
    assert second.retired_at is not None
    assert not video.dubs.filter(retired_at__isnull=True).exists()
    # The next dub on the language is allowed again.
    _dub(lesson, media["dub_mp3"], owner, "en")
    with pytest.raises(CourseVideoError, match="Этой озвучки уже нет"):
        delete_video_dub(lesson, video.pk, "tr", user=owner)


@needs_ffmpeg
@pytest.mark.django_db
def test_spoken_language_cannot_take_a_dubbed_language(
    media: dict[str, Path], lesson: CourseLesson, owner: User, storage: KeepingUploader
) -> None:
    video = _upload(lesson, media["handbrake"], owner)
    _dub(lesson, media["dub_mp3"], owner, "en")

    with pytest.raises(CourseVideoError, match="Сначала удалите её"):
        set_spoken_language(lesson, video.pk, "en", user=owner)
    set_spoken_language(lesson, video.pk, "ar", user=owner)
    video.refresh_from_db()
    assert video.spoken_language == "ar"


@needs_ffmpeg
@pytest.mark.django_db
def test_stale_page_cannot_change_a_replaced_video(
    media: dict[str, Path], lesson: CourseLesson, owner: User, storage: KeepingUploader
) -> None:
    old = _upload(lesson, media["silent"], owner, spoken_language="")
    _upload(lesson, media["handbrake"], owner)

    with pytest.raises(CourseVideoError, match="другой вкладке") as error:
        upload_video_dub(
            lesson, old.pk, "en", media["dub_mp3"], user=owner, original_name="dub.mp3"
        )
    assert error.value.status == 409


# One upload at a time, disk space -----------------------------------------


@pytest.mark.django_db
def test_second_upload_waits_for_the_first() -> None:
    with upload_slot():
        with pytest.raises(CourseVideoError, match="Сейчас загружается") as error, upload_slot():
            pass
        assert error.value.status == 409
    with upload_slot():
        pass


@pytest.mark.django_db
def test_upload_view_answers_409_while_another_runs_and_400_without_room(
    lesson: CourseLesson, owner: User
) -> None:
    client = _client(owner)
    url = f"/admin/courses/courselesson/{lesson.pk}/video/upload/"
    upload = SimpleUploadedFile("lecture.mp4", b"x" * 2048, "video/mp4")

    cache.add(UPLOAD_LOCK, "another", 60)
    try:
        busy = client.post(url, {"file": upload, "spoken_language": "ru"})
    finally:
        cache.delete(UPLOAD_LOCK)
    assert busy.status_code == 409
    assert "Сейчас загружается другое видео" in busy.json()["error"]

    class Full:
        free = 2 * 1024**3

    upload.seek(0)
    with patch(f"{MODULE}.disk_usage", return_value=Full()):
        # Needs three sizes plus 1 GiB; pretend the file is 400 MB.
        full = client.post(url, {"file": upload}, CONTENT_LENGTH=str(400 * 1024 * 1024))
    assert full.status_code == 400
    assert "мало места" in full.json()["error"]
    assert cache.get(UPLOAD_LOCK) is None
    assert not CourseVideo.objects.exists()


@pytest.mark.django_db
def test_oversized_body_is_refused_before_it_is_read(lesson: CourseLesson, owner: User) -> None:
    response = _client(owner).post(
        f"/admin/courses/courselesson/{lesson.pk}/video/upload/",
        {"file": SimpleUploadedFile("lecture.mp4", b"x", "video/mp4")},
        CONTENT_LENGTH=str(482 * 1024 * 1024),
    )
    assert response.status_code == 400
    assert response.json() == {"error": "Файл больше 480 МБ."}


# The document of each language --------------------------------------------


def _stored_video(lesson: CourseLesson, **fields: Any) -> CourseVideo:
    video = CourseVideo.objects.create(
        course=lesson.course,
        object_key="courses/videos/aaaaaaaaaaaaaaaaaaaa.mp4",
        sha256="a" * 64,
        bytes=100 * 1024 * 1024,
        duration_ms=125_000,
        width=1280,
        height=720,
        fps=30,
        bitrate_kbps=1500,
        video_codec="h264",
        audio_codec="aac",
        has_audio=True,
        spoken_language="ru",
        poster_object_key="courses/posters/aaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbb-1280.webp",
        poster_small_object_key="courses/posters/aaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbb-640.webp",
        poster_width=1280,
        poster_height=720,
        **fields,
    )
    CourseLesson.objects.filter(pk=lesson.pk).update(video=video)
    return video


def _stored_dub(video: CourseVideo, language: str, sha: str, **fields: Any) -> CourseVideoDub:
    return CourseVideoDub.objects.create(
        video=video,
        language=language,
        audio_sha256="c" * 64,
        audio_bytes=1000,
        audio_codec="mp3",
        audio_duration_ms=125_500,
        object_key=f"courses/videos/aaaaaaaaaaaaaaaaaaaa-{language}-{sha[:12]}.mp4",
        sha256=sha,
        bytes=fields.pop("bytes", 99 * 1024 * 1024),
        duration_ms=fields.pop("duration_ms", 124_900),
        **fields,
    )


@pytest.mark.django_db
@override_settings(PUBLIC_AUDIO_BASE_URL=MEDIA)
def test_document_gets_the_dub_of_its_language_or_the_video(
    lesson: CourseLesson, owner: User
) -> None:
    video = _stored_video(lesson)
    _stored_dub(video, "en", "d" * 64)
    _translate(lesson, "en", "tr")

    release = _release(lesson.course, owner, ["ru", "en", "tr"])

    documents = {document.language: document for document in release.documents.all()}
    poster = {
        "url": f"{MEDIA}/courses/posters/aaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbb-1280.webp",
        "small_url": f"{MEDIA}/courses/posters/aaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbb-640.webp",
        "width": 1280,
        "height": 720,
    }
    main = {
        "url": f"{MEDIA}/courses/videos/aaaaaaaaaaaaaaaaaaaa.mp4",
        "bytes": 100 * 1024 * 1024,
        "duration_ms": 125_000,
        "width": 1280,
        "height": 720,
        "spoken_language": "ru",
        "poster": poster,
    }
    assert documents["ru"].payload["lessons"][0]["video"] == main
    # Turkish has no dub: the Russian video, which clients mark «Видео на русском языке».
    assert documents["tr"].payload["lessons"][0]["video"] == main
    assert documents["en"].payload["lessons"][0]["video"] == {
        **main,
        "url": f"{MEDIA}/courses/videos/aaaaaaaaaaaaaaaaaaaa-en-dddddddddddd.mp4",
        "bytes": 99 * 1024 * 1024,
        "duration_ms": 124_900,
        "spoken_language": "en",
    }
    # 125 s rounded up; minutes come from the video and the notes.
    assert documents["ru"].card["video_minutes"] == 3
    assert documents["ru"].payload["lessons"][0]["minutes"] == 3


@pytest.mark.django_db
def test_retired_dub_is_not_in_the_snapshot(lesson: CourseLesson) -> None:
    video = _stored_video(lesson)
    _stored_dub(video, "en", "d" * 64, retired_at=timezone.now())

    assert build_snapshot(lesson.course)["lessons"][0]["video"]["dubs"] == {}


@pytest.mark.django_db
def test_changes_name_what_happened_to_the_video(lesson: CourseLesson) -> None:
    before = build_snapshot(lesson.course)
    video = _stored_video(lesson)
    with_video = build_snapshot(lesson.course)
    assert changes(before, with_video) == ["Тема 1: добавлено видео"]

    _stored_dub(video, "en", "d" * 64)
    _stored_dub(video, "tr", "e" * 64)
    CourseVideo.objects.filter(pk=video.pk).update(spoken_language="ar")
    assert changes(with_video, build_snapshot(lesson.course)) == [
        "Тема 1: изменён язык речи видео; добавлена озвучка (en, tr)"
    ]
    CourseLesson.objects.filter(pk=lesson.pk).update(video=None)
    assert changes(with_video, build_snapshot(lesson.course)) == ["Тема 1: убрано видео"]


# «Просмотрено» and signing --------------------------------------------------


@pytest.mark.django_db
def test_reviewer_marks_the_video_and_each_dub_of_released_languages(
    lesson: CourseLesson, owner: User
) -> None:
    video = _stored_video(lesson)
    _stored_dub(video, "en", "d" * 64)
    _stored_dub(video, "tr", "e" * 64)  # Turkish is not in this release: nobody sees it.
    _translate(lesson, "en")

    release = prepare_release(lesson.course, owner, languages=["ru", "en"], change_note="Видео")
    assert new_videos(release) == {"a" * 64, "d" * 64}
    mark_watched(release, owner, sha256="a" * 64, watched=True)
    with pytest.raises(CourseReleaseError, match="Отметьте «Просмотрено»"):
        sign_release(release, owner)
    with pytest.raises(CourseReleaseError, match="нет среди новых"):
        mark_watched(release, owner, sha256="e" * 64, watched=True)
    mark_watched(release, owner, sha256="d" * 64, watched=True)
    mark_watched(release, owner, sha256="a" * 64, watched=False)
    with pytest.raises(CourseReleaseError, match="Отметьте «Просмотрено»"):
        sign_release(release, owner)
    mark_watched(release, owner, sha256="a" * 64, watched=True)
    sign_release(release, owner)
    published = publish_release(release, owner)

    # The next release asks only for what changed: the new English dub.
    CourseVideoDub.objects.filter(language="en").update(retired_at="2027-01-01T00:00:00Z")
    _stored_dub(video, "en", "f" * 64)
    following = prepare_release(lesson.course, owner, languages=["ru", "en"], change_note="Новая")
    assert following.based_on == published
    assert new_videos(following) == {"f" * 64}


@pytest.mark.django_db
def test_review_page_lists_files_and_keeps_sign_off_until_all_are_watched(
    lesson: CourseLesson, owner: User
) -> None:
    video = _stored_video(lesson)
    _stored_dub(video, "en", "d" * 64)
    _translate(lesson, "en")
    release = prepare_release(lesson.course, owner, languages=["ru", "en"], change_note="Видео")
    client = _client(owner)
    page_url = f"/admin/courses/courserelease/{release.pk}/change/"

    page = client.get(page_url).content.decode()
    assert "Тема 1 «Намерение»: основное видео, русский" in page
    assert "Тема 1 «Намерение»: озвучка, английский" in page
    assert "2:05 · 100 МБ" in page
    assert page.count(">Просмотрено</button>") == 2
    assert 'disabled title="Сначала отметьте' in page

    for sha256 in ("a" * 64, "d" * 64):
        answer = client.post(
            f"/admin/courses/courserelease/{release.pk}/watched/{sha256}/", {"watched": "1"}
        )
        assert answer.status_code == 302
        assert answer["Location"].endswith("#videos")
    page = client.get(page_url).content.decode()
    assert "Снять отметку" in page
    assert 'disabled title="Сначала отметьте' not in page
    release.refresh_from_db()
    assert sorted(release.watched_videos) == ["a" * 64, "d" * 64]
    assert LogEntry.objects.filter(change_message__startswith="Просмотрено").count() == 2


@pytest.mark.django_db
def test_only_a_reviewer_marks_watched(lesson: CourseLesson, owner: User) -> None:
    _stored_video(lesson)
    release = prepare_release(lesson.course, owner, languages=["ru"], change_note="Видео")
    editor = User.objects.create_user(email="editor@example.test", status="active", is_staff=True)
    editor.groups.add(Group.objects.get(name="Редактор курсов"))

    answer = _client(editor).post(
        f"/admin/courses/courserelease/{release.pk}/watched/{'a' * 64}/", {"watched": "1"}
    )

    assert answer.status_code == 403
    release.refresh_from_db()
    assert release.watched_videos == []


# Admin block ---------------------------------------------------------------


@pytest.mark.django_db
@override_settings(PUBLIC_AUDIO_BASE_URL=MEDIA)
def test_lesson_page_shows_the_video_block(lesson: CourseLesson, owner: User) -> None:
    client = _client(owner)
    empty = client.get(f"/admin/courses/courselesson/{lesson.pk}/change/").content.decode()
    assert "Медиа пока нет." in empty
    assert "Перетащите файл сюда" not in empty
    assert "courses/admin/video.js" in empty
    assert "lesson_media/admin/media.js" in empty
    assert "docs/courses/video.md" in empty
    # «Добавить: Видео» puts the place of the video in the list, with the upload box.
    added = client.post(
        f"/admin/courses/courselesson/{lesson.pk}/media/", {"action": "add", "kind": "video"}
    )
    assert added.status_code == 200
    assert "Перетащите файл сюда" in added.json()["html"]

    video = _stored_video(lesson, original_name="lecture.mp4")
    _stored_dub(video, "en", "d" * 64, audio_original_name="english.mp3")
    page = client.get(f"/admin/courses/courselesson/{lesson.pk}/change/").content.decode()
    assert f'src="{MEDIA}/courses/videos/aaaaaaaaaaaaaaaaaaaa.mp4"' in page
    assert "<dd>2:05</dd>" in page
    assert "<dd>100 МБ</dd>" in page
    assert "Взять кадр на" in page
    assert "Загрузить картинку" in page
    assert "Язык речи" in page
    # Tabs for every language but the video's own; English has its dub.
    assert 'id="cvid-tab-ru"' not in page
    assert "EN ✓" in page
    assert "файл «english.mp3»" in page
    assert 'id="cvid-tab-tr"' in page
    assert "Озвучки на языке «турецкий» нет" in page

    course_page = client.get(f"/admin/courses/course/{lesson.course_id}/change/").content.decode()
    assert "2:05 · ru + en" in course_page


@needs_ffmpeg
@pytest.mark.django_db
@override_settings(PUBLIC_AUDIO_BASE_URL=MEDIA)
def test_admin_upload_answers_with_the_redrawn_block(
    media: dict[str, Path], lesson: CourseLesson, owner: User, storage: KeepingUploader
) -> None:
    client = _client(owner)
    base = f"/admin/courses/courselesson/{lesson.pk}/video"

    upload = SimpleUploadedFile("lecture.mp4", media["handbrake"].read_bytes(), "video/mp4")
    answer = client.post(f"{base}/upload/", {"file": upload, "spoken_language": "ru"})

    assert answer.status_code == 200, answer.content
    assert "data-course-video" in answer.json()["html"]
    lesson.refresh_from_db()
    video = lesson.video
    assert video is not None
    entry = LogEntry.objects.get(object_id=str(lesson.pk))
    assert "Видео: загружено «lecture.mp4», 0:12" in entry.get_change_message()

    dub = SimpleUploadedFile("english.mp3", media["dub_mp3"].read_bytes(), "audio/mpeg")
    answer = client.post(f"{base}/dubs/en/upload/", {"file": dub, "video": video.pk})
    assert answer.status_code == 200, answer.content
    assert "EN ✓" in answer.json()["html"]

    wrong = SimpleUploadedFile("long.wav", media["dub_long"].read_bytes(), "audio/wav")
    answer = client.post(f"{base}/dubs/tr/upload/", {"file": wrong, "video": video.pk})
    assert answer.status_code == 400
    assert answer.json()["error"].startswith("Озвучка длиннее видео на 14 с")

    answer = client.post(f"{base}/language/", {"video": video.pk, "spoken_language": "ar"})
    assert answer.status_code == 200
    answer = client.post(f"{base}/poster/", {"video": video.pk, "second": "5"})
    assert answer.status_code == 200
    answer = client.post(f"{base}/dubs/en/delete/", {"video": video.pk})
    assert answer.status_code == 200
    answer = client.post(f"{base}/remove/", {"video": video.pk})
    assert answer.status_code == 200
    lesson.refresh_from_db()
    assert lesson.video is None
    assert not CourseVideo.objects.exists()


@pytest.mark.django_db
def test_storage_failure_is_a_502(lesson: CourseLesson, owner: User) -> None:
    video = _stored_video(lesson)
    with patch("quran_backend.modules.courses.admin.set_video_poster", side_effect=OSError("x")):
        answer = _client(owner).post(
            f"/admin/courses/courselesson/{lesson.pk}/video/poster/",
            {"video": video.pk, "second": "1"},
        )
    assert answer.status_code == 502
    assert answer.json() == {"error": "Хранилище недоступно, повторите."}


@pytest.mark.django_db
def test_video_actions_check_rights_on_the_server(lesson: CourseLesson, owner: User) -> None:
    video = _stored_video(lesson)
    _stored_dub(video, "en", "d" * 64)
    viewer = User.objects.create_user(email="viewer@example.test", status="active", is_staff=True)
    viewer.user_permissions.set(
        Permission.objects.filter(
            content_type__app_label="courses",
            codename__in=("view_course", "view_courselesson", "view_coursevideo"),
        )
    )
    client = _client(viewer)
    base = f"/admin/courses/courselesson/{lesson.pk}/video"

    page = client.get(f"/admin/courses/courselesson/{lesson.pk}/change/").content.decode()
    assert "Взять кадр" not in page
    assert "Заменить видео" not in page
    assert "Удалить" not in page
    for url, data in (
        (f"{base}/upload/", {"file": SimpleUploadedFile("a.mp4", b"x"), "spoken_language": "ru"}),
        (f"{base}/poster/", {"video": video.pk, "second": "1"}),
        (f"{base}/language/", {"video": video.pk, "spoken_language": "en"}),
        (f"{base}/remove/", {"video": video.pk}),
        (f"{base}/dubs/tr/upload/", {"file": SimpleUploadedFile("a.mp3", b"x"), "video": video.pk}),
        (f"{base}/dubs/en/delete/", {"video": video.pk}),
    ):
        assert client.post(url, data).status_code == 403, url
    assert _client(owner).get(f"{base}/upload/").status_code == 405
    lesson.refresh_from_db()
    assert lesson.video == video
    assert video.dubs.count() == 1


@pytest.mark.django_db
def test_editors_upload_and_reviewers_watch() -> None:
    def codenames(name: str) -> set[str]:
        return set(Group.objects.get(name=name).permissions.values_list("codename", flat=True))

    assert {
        "add_coursevideo",
        "change_coursevideo",
        "add_coursevideodub",
        "delete_coursevideodub",
    } <= codenames("Редактор курсов")
    assert {"view_coursevideo", "view_coursevideodub"} <= codenames("Религиозный рецензент")
    assert "add_coursevideo" not in codenames("Публикатор")


@pytest.mark.django_db
def test_course_with_videos_can_be_deleted_before_any_release(lesson: CourseLesson) -> None:
    _stored_video(lesson)
    lesson.course.delete()
    assert not CourseVideo.objects.exists()
    assert not CourseDocument.objects.exists()
