from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import Any
from unittest.mock import patch

import pytest
from django.contrib import admin
from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import IntegrityError, transaction
from django.test import override_settings

from quran_backend.modules.audio.admin import PlayerBackgroundAdmin, PlayerBackgroundAdminForm
from quran_backend.modules.audio.models import PlayerBackground
from quran_backend.modules.audio.player_background_upload import (
    MAX_PLAYER_BACKGROUND_BYTES,
    PlayerBackgroundUploadError,
    PlayerBackgroundUploadResult,
    upload_player_background,
)
from quran_backend.modules.audio.player_background_video import (
    PlayerBackgroundVideoError,
    PlayerBackgroundVideoResult,
    upload_player_background_video,
)
from quran_backend.modules.audio.selectors import MAX_PUBLIC_PLAYER_BACKGROUNDS
from quran_backend.modules.core.object_storage import ImmutableObjectSpec, StoredObject

WEBP = b"RIFF\x10\x00\x00\x00WEBPbackground-bytes"
JPEG = b"\xff\xd8\xff\xe0background-bytes"


class FakeUploader:
    def __init__(self) -> None:
        self.calls: list[ImmutableObjectSpec] = []

    def upload_path(self, source_path: Path, spec: ImmutableObjectSpec) -> StoredObject:
        assert source_path.read_bytes()
        self.calls.append(spec)
        return StoredObject(key=spec.key, etag='"background-etag"', created=True)


def _background(**overrides: Any) -> PlayerBackground:
    values: dict[str, Any] = {
        "title_ar": "الصحراء",
        "title_en": "Desert",
        "title_ru": "Пустыня",
        "image_object_key": "audio/player-backgrounds/desert.webp",
    }
    values.update(overrides)
    return PlayerBackground.objects.create(**values)


@pytest.mark.parametrize(
    ("payload", "content_type", "extension"),
    [(WEBP, "image/webp", "webp"), (JPEG, "image/jpeg", "jpg")],
)
def test_background_upload_uses_hash_addressed_key(
    payload: bytes, content_type: str, extension: str
) -> None:
    uploader = FakeUploader()

    result = upload_player_background(
        SimpleUploadedFile(f"bg.{extension}", payload), uploader=uploader
    )

    spec = uploader.calls[0]
    assert result.object_key == spec.key
    assert spec.key.startswith("audio/player-backgrounds/")
    assert spec.key.endswith(f".{extension}")
    assert spec.content_type == content_type
    assert spec.size_bytes == len(payload)


@pytest.mark.parametrize(
    "payload",
    [
        b"\x89PNG\r\n\x1a\nnot-allowed-for-backgrounds",
        b"<svg xmlns='http://www.w3.org/2000/svg'></svg>",
        b"GIF89a-animated",
    ],
)
def test_background_upload_accepts_only_webp_and_jpeg(payload: bytes) -> None:
    uploader = FakeUploader()
    with pytest.raises(PlayerBackgroundUploadError, match="WebP и JPEG"):
        upload_player_background(SimpleUploadedFile("bg.bin", payload), uploader=uploader)
    assert uploader.calls == []


def test_background_upload_rejects_empty_and_oversized_files() -> None:
    uploader = FakeUploader()
    with pytest.raises(PlayerBackgroundUploadError, match="пуст"):
        upload_player_background(SimpleUploadedFile("bg.webp", b""), uploader=uploader)

    oversized = WEBP + b"0" * MAX_PLAYER_BACKGROUND_BYTES
    with pytest.raises(PlayerBackgroundUploadError, match="512 КБ"):
        upload_player_background(SimpleUploadedFile("bg.webp", oversized), uploader=uploader)
    assert uploader.calls == []


@override_settings(
    DEBUG=True,
    LOCAL_DEVELOPMENT=True,
    MEDIA_OBJECT_STORAGE_ENABLED=False,
    MEDIA_OBJECT_STORAGE_REQUIRED=False,
)
def test_local_background_upload_saves_media(tmp_path: Path) -> None:
    with override_settings(MEDIA_ROOT=tmp_path):
        result = upload_player_background(SimpleUploadedFile("bg.webp", WEBP))

    assert (tmp_path / result.object_key).read_bytes() == WEBP


@pytest.mark.django_db
def test_background_without_image_is_hidden_and_db_enforces_it() -> None:
    background = _background(image_object_key="", is_active=True)
    assert background.is_active is False

    with transaction.atomic(), pytest.raises(IntegrityError):
        PlayerBackground.objects.filter(pk=background.pk).update(is_active=True)


@pytest.mark.django_db
def test_public_background_api_lists_active_rows_in_order_with_cache_validators(
    api_client: Any,
) -> None:
    second = _background(title_en="Sea", sort_order=20, image_object_key="audio/pb/sea.webp")
    first = _background(title_en="Desert", sort_order=10)
    _background(title_en="Hidden", sort_order=1, is_active=False)

    response = api_client.get("/api/v1/player-backgrounds")

    assert response.status_code == 200
    payload = response.json()
    assert [item["id"] for item in payload] == [str(first.id), str(second.id)]
    assert payload[0] == {
        "id": str(first.id),
        "title_ar": "الصحراء",
        "title_en": "Desert",
        "title_ru": "Пустыня",
        "title_tr": "",
        "image_url": "http://localhost:8000/media/audio/player-backgrounds/desert.webp",
        "video_url": None,
        "sort_order": 10,
    }
    assert response["Cache-Control"] == "public, max-age=300, stale-while-revalidate=86400"
    etag = response["ETag"]
    assert etag.startswith('W/"')

    not_modified = api_client.get("/api/v1/player-backgrounds", HTTP_IF_NONE_MATCH=etag)
    assert not_modified.status_code == 304
    assert not_modified["ETag"] == etag


@pytest.mark.django_db
def test_public_background_api_is_bounded(api_client: Any) -> None:
    for index in range(MAX_PUBLIC_PLAYER_BACKGROUNDS + 3):
        _background(sort_order=index, image_object_key=f"audio/pb/{index}.webp")

    response = api_client.get("/api/v1/player-backgrounds")

    assert len(response.json()) == MAX_PUBLIC_PLAYER_BACKGROUNDS


@pytest.mark.django_db
def test_background_admin_requires_and_uploads_an_image() -> None:
    data = {
        "title_ru": "Оазис",
        "title_en": "Oasis",
        "title_ar": "واحة",
        "title_tr": "",
        "sort_order": 30,
        "is_active": True,
    }
    missing = PlayerBackgroundAdminForm(data=data)
    assert not missing.is_valid()
    assert "image_upload" in missing.errors

    result = PlayerBackgroundUploadResult(
        object_key="audio/player-backgrounds/hash.webp",
        etag='"background-etag"',
        created=True,
    )
    with patch(
        "quran_backend.modules.audio.admin.upload_player_background",
        return_value=result,
    ) as mocked_upload:
        form = PlayerBackgroundAdminForm(
            data=data,
            files={"image_upload": SimpleUploadedFile("oasis.webp", WEBP)},
        )
        assert form.is_valid(), form.errors
        saved = form.save()

    mocked_upload.assert_called_once()
    assert saved.image_object_key == result.object_key
    assert saved.is_active is True

    # Editing titles keeps the stored image without a new upload.
    edit = PlayerBackgroundAdminForm(data={**data, "title_ru": "Оазис ночью"}, instance=saved)
    assert edit.is_valid(), edit.errors
    assert edit.save().image_object_key == result.object_key


def test_background_admin_is_registered_without_raw_storage_key_input() -> None:
    assert isinstance(admin.site._registry[PlayerBackground], PlayerBackgroundAdmin)
    assert "image_object_key" not in PlayerBackgroundAdminForm.base_fields
    assert "image_upload" in PlayerBackgroundAdminForm.base_fields


FFMPEG = shutil.which("ffmpeg") or "ffmpeg"
FFPROBE = shutil.which("ffprobe") or "ffprobe"
needs_ffmpeg = pytest.mark.skipif(
    shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None,
    reason="ffmpeg is not installed",
)


class KeepingUploader(FakeUploader):
    def __init__(self, folder: Path) -> None:
        super().__init__()
        self.folder = folder

    def upload_path(self, source_path: Path, spec: ImmutableObjectSpec) -> StoredObject:
        shutil.copy(source_path, self.folder / Path(spec.key).name)
        return super().upload_path(source_path, spec)


def _streams(path: Path) -> list[dict[str, Any]]:
    probe = subprocess.run(  # noqa: S603 - test-made file
        [FFPROBE, "-v", "error", "-show_streams", "-of", "json", str(path)],
        check=True,
        capture_output=True,
    )
    return list(json.loads(probe.stdout)["streams"])


@needs_ffmpeg
@pytest.mark.parametrize(
    ("source_size", "output_size"),
    [((1920, 1080), (1280, 720)), ((720, 720), (720, 720))],
)
def test_background_video_is_silent_smaller_and_gets_a_poster(
    tmp_path: Path, source_size: tuple[int, int], output_size: tuple[int, int]
) -> None:
    source = tmp_path / "clip.mov"
    width, height = source_size
    subprocess.run(  # noqa: S603 - fixed arguments
        [
            FFMPEG, "-v", "error", "-f", "lavfi", "-i", f"testsrc=size={width}x{height}:rate=60",
            "-f", "lavfi", "-i", "sine=frequency=440", "-t", "2", "-c:v", "libx264",
            "-c:a", "aac", str(source),
        ],
        check=True,
    )  # fmt: skip
    uploader = KeepingUploader(tmp_path)

    result = upload_player_background_video(
        SimpleUploadedFile("clip.mov", source.read_bytes()), uploader=uploader
    )

    assert result.video_object_key.startswith("audio/player-backgrounds/")
    assert result.video_object_key.endswith(".mp4")
    assert result.poster_object_key.endswith(".jpg")
    assert [spec.content_type for spec in uploader.calls] == ["video/mp4", "image/jpeg"]
    streams = _streams(tmp_path / Path(result.video_object_key).name)
    assert [stream["codec_type"] for stream in streams] == ["video"]
    assert (streams[0]["width"], streams[0]["height"]) == output_size
    assert streams[0]["r_frame_rate"] == "30/1"
    poster = _streams(tmp_path / Path(result.poster_object_key).name)
    assert (poster[0]["width"], poster[0]["height"]) == output_size


@needs_ffmpeg
def test_background_video_rejects_files_that_are_not_video() -> None:
    uploader = FakeUploader()
    with pytest.raises(PlayerBackgroundVideoError, match="MP4, MOV или WebM"):
        upload_player_background_video(
            SimpleUploadedFile("clip.mp4", b"not a video"), uploader=uploader
        )
    with pytest.raises(PlayerBackgroundVideoError, match="пуст"):
        upload_player_background_video(SimpleUploadedFile("clip.mp4", b""), uploader=uploader)
    assert uploader.calls == []


@pytest.mark.django_db
def test_background_admin_video_brings_its_poster_and_can_be_removed() -> None:
    data = {
        "title_ru": "Чтец",
        "title_en": "Reciter",
        "title_ar": "القارئ",
        "title_tr": "",
        "sort_order": 40,
        "is_active": True,
    }
    clip = PlayerBackgroundVideoResult(
        video_object_key="audio/player-backgrounds/clip.mp4",
        poster_object_key="audio/player-backgrounds/clip.jpg",
    )
    with patch(
        "quran_backend.modules.audio.admin.upload_player_background_video",
        return_value=clip,
    ) as mocked_video:
        form = PlayerBackgroundAdminForm(
            data=data,
            files={"video_upload": SimpleUploadedFile("clip.mp4", b"video")},
        )
        assert form.is_valid(), form.errors
        saved = form.save()

    mocked_video.assert_called_once()
    assert saved.video_object_key == clip.video_object_key
    assert saved.image_object_key == clip.poster_object_key
    assert saved.is_active is True

    both = PlayerBackgroundAdminForm(
        data={**data, "remove_video": True},
        files={"video_upload": SimpleUploadedFile("clip.mp4", b"video")},
        instance=saved,
    )
    assert not both.is_valid()
    assert "remove_video" in both.errors

    removed = PlayerBackgroundAdminForm(data={**data, "remove_video": True}, instance=saved)
    assert removed.is_valid(), removed.errors
    still = removed.save()
    assert still.video_object_key == ""
    assert still.image_object_key == clip.poster_object_key


@pytest.mark.django_db
def test_background_admin_keeps_a_separate_image_as_the_poster() -> None:
    image = PlayerBackgroundUploadResult(
        object_key="audio/player-backgrounds/own.webp", etag='"e"', created=True
    )
    clip = PlayerBackgroundVideoResult(
        video_object_key="audio/player-backgrounds/clip.mp4",
        poster_object_key="audio/player-backgrounds/clip.jpg",
    )
    with (
        patch("quran_backend.modules.audio.admin.upload_player_background", return_value=image),
        patch(
            "quran_backend.modules.audio.admin.upload_player_background_video",
            return_value=clip,
        ),
    ):
        form = PlayerBackgroundAdminForm(
            data={"title_ru": "Ч", "title_en": "R", "title_ar": "ق", "sort_order": 1},
            files={
                "image_upload": SimpleUploadedFile("own.webp", WEBP),
                "video_upload": SimpleUploadedFile("clip.mp4", b"video"),
            },
        )
        assert form.is_valid(), form.errors
        saved = form.save()

    assert saved.image_object_key == image.object_key
    assert saved.video_object_key == clip.video_object_key


@pytest.mark.django_db
def test_public_background_api_gives_the_video_url(api_client: Any) -> None:
    _background(video_object_key="audio/player-backgrounds/clip.mp4")

    payload = api_client.get("/api/v1/player-backgrounds").json()

    assert payload[0]["video_url"] == (
        "http://localhost:8000/media/audio/player-backgrounds/clip.mp4"
    )
    assert payload[0]["image_url"].endswith("/desert.webp")
