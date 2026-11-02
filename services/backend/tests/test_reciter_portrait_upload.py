from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from unittest.mock import patch

import pytest
from django.core.exceptions import ImproperlyConfigured
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings

from quran_backend.modules.audio.portrait_upload import (
    MAX_RECITER_PORTRAIT_BYTES,
    ReciterPortraitUploadError,
    store_reciter_portrait_variants,
    upload_reciter_portrait,
)
from quran_backend.modules.core.object_storage import ImmutableObjectSpec, StoredObject

needs_ffmpeg = pytest.mark.skipif(
    shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None,
    reason="ffmpeg is not installed",
)


def _picture(tmp_path: Path, name: str, size: str, *extra: str) -> bytes:
    """A real picture made by ffmpeg: a detailed test pattern, so copies are smaller."""
    target = tmp_path / name
    subprocess.run(  # noqa: S603 - fixed program, arguments we built
        [  # noqa: S607 - ffmpeg from PATH, like the code under test
            "ffmpeg",
            "-nostdin",
            "-loglevel",
            "error",
            "-y",
            "-f",
            "lavfi",
            "-i",
            f"testsrc2=size={size}",
            "-frames:v",
            "1",
            *extra,
            str(target),
        ],
        check=True,
    )
    payload = target.read_bytes()
    target.unlink()
    return payload


def _dimensions(payload: bytes, tmp_path: Path) -> tuple[int, int]:
    probe = tmp_path / "probe.bin"
    probe.write_bytes(payload)
    output = subprocess.run(  # noqa: S603 - fixed program, arguments we built
        [  # noqa: S607 - ffprobe from PATH, like the code under test
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "stream=width,height",
            "-of",
            "json",
            str(probe),
        ],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    probe.unlink()
    stream = json.loads(output)["streams"][0]
    return int(stream["width"]), int(stream["height"])


class FakeUploader:
    def __init__(self) -> None:
        self.calls: list[tuple[Path, ImmutableObjectSpec, bytes]] = []

    def upload_path(self, source_path: Path, spec: ImmutableObjectSpec) -> StoredObject:
        self.calls.append((source_path, spec, source_path.read_bytes()))
        return StoredObject(key=spec.key, etag='"portrait-etag"', created=True)


@override_settings(
    DEBUG=True,
    LOCAL_DEVELOPMENT=True,
    MEDIA_OBJECT_STORAGE_ENABLED=False,
    MEDIA_OBJECT_STORAGE_REQUIRED=False,
)
@needs_ffmpeg
def test_local_portrait_upload_saves_media_without_cloud_credentials(tmp_path: Path) -> None:
    payload = _picture(tmp_path, "portrait.png", "800x800")
    with override_settings(MEDIA_ROOT=tmp_path):
        first = upload_reciter_portrait(
            SimpleUploadedFile("portrait.png", payload), reciter_code="saad-al-ghamdi"
        )
        repeated = upload_reciter_portrait(
            SimpleUploadedFile("portrait.png", payload), reciter_code="saad-al-ghamdi"
        )

    assert (tmp_path / first.object_key).read_bytes() == payload
    assert first.created is True
    assert repeated.created is False
    assert repeated.object_key == first.object_key
    assert repeated.variants == first.variants
    assert (tmp_path / first.variants.display_object_key).is_file()
    assert (tmp_path / first.variants.thumbnail_object_key).is_file()


@pytest.mark.parametrize(
    ("debug", "local", "required"),
    [(False, False, True), (True, False, False), (False, True, False), (True, True, True)],
)
def test_portrait_upload_does_not_fall_back_outside_local_mode(
    tmp_path: Path, *, debug: bool, local: bool, required: bool
) -> None:
    with (
        override_settings(
            DEBUG=debug,
            LOCAL_DEVELOPMENT=local,
            MEDIA_OBJECT_STORAGE_ENABLED=False,
            MEDIA_OBJECT_STORAGE_REQUIRED=required,
            MEDIA_ROOT=tmp_path,
        ),
        pytest.raises(ImproperlyConfigured, match="MEDIA_OBJECT_STORAGE_ENABLED"),
    ):
        upload_reciter_portrait(
            SimpleUploadedFile("portrait.webp", b"RIFF\x10\x00\x00\x00WEBPportrait"),
            reciter_code="saad-al-ghamdi",
        )
    assert list(tmp_path.iterdir()) == []


@needs_ffmpeg
@override_settings(DEBUG=True, LOCAL_DEVELOPMENT=True, MEDIA_OBJECT_STORAGE_ENABLED=True)
def test_local_portrait_upload_respects_explicit_object_storage(tmp_path: Path) -> None:
    uploader = FakeUploader()
    with (
        override_settings(MEDIA_ROOT=tmp_path),
        patch(
            "quran_backend.modules.audio.portrait_upload.configured_object_uploader",
            return_value=uploader,
        ),
    ):
        result = upload_reciter_portrait(
            SimpleUploadedFile("portrait.png", _picture(tmp_path, "portrait.png", "800x800")),
            reciter_code="saad-al-ghamdi",
        )
    assert result.object_key == uploader.calls[0][1].key
    assert list(tmp_path.iterdir()) == []


@needs_ffmpeg
def test_reciter_portrait_upload_uses_validated_hash_addressed_key(tmp_path: Path) -> None:
    payload = _picture(tmp_path, "portrait.webp", "800x800", "-c:v", "libwebp", "-lossless", "1")
    uploaded = SimpleUploadedFile("portrait.webp", payload, content_type="image/webp")
    uploader = FakeUploader()

    result = upload_reciter_portrait(
        uploaded,
        reciter_code="saad-al-ghamdi",
        uploader=uploader,
    )

    assert result.created is True
    assert result.object_key.startswith("audio/reciter-portraits/saad-al-ghamdi/")
    source_path, spec, observed = uploader.calls[0]
    assert source_path.name.endswith(".upload")
    assert observed == payload
    assert spec.content_type == "image/webp"
    assert spec.size_bytes == len(payload)
    assert spec.key == result.object_key


@pytest.mark.parametrize(
    "payload",
    [b"not-an-image", b"<svg xmlns='http://www.w3.org/2000/svg'></svg>"],
)
def test_reciter_portrait_upload_rejects_unsupported_content(payload: bytes) -> None:
    with pytest.raises(ReciterPortraitUploadError, match="WebP, JPEG и PNG"):
        upload_reciter_portrait(
            SimpleUploadedFile("portrait.bin", payload),
            reciter_code="saad-al-ghamdi",
            uploader=FakeUploader(),
        )


def test_reciter_portrait_upload_enforces_size_limit() -> None:
    payload = b"\x89PNG\r\n\x1a\n" + b"0" * MAX_RECITER_PORTRAIT_BYTES
    with pytest.raises(ReciterPortraitUploadError, match="не больше 50 МБ"):
        upload_reciter_portrait(
            SimpleUploadedFile("portrait.png", payload),
            reciter_code="saad-al-ghamdi",
            uploader=FakeUploader(),
        )


@needs_ffmpeg
def test_reciter_portrait_upload_stores_smaller_webp_copies(tmp_path: Path) -> None:
    payload = _picture(tmp_path, "portrait.png", "1254x1000")
    uploader = FakeUploader()

    result = upload_reciter_portrait(
        SimpleUploadedFile("portrait.png", payload),
        reciter_code="saad-al-ghamdi",
        uploader=uploader,
    )

    original, display, thumbnail = uploader.calls
    assert original[1].key == result.object_key
    assert original[2] == payload
    assert display[1].key == result.variants.display_object_key
    assert thumbnail[1].key == result.variants.thumbnail_object_key
    for _, spec, observed in (display, thumbnail):
        assert spec.key.startswith("audio/reciter-portraits/saad-al-ghamdi/")
        assert spec.key.endswith(".webp")
        assert spec.content_type == "image/webp"
        assert spec.size_bytes == len(observed) < len(payload)
    # The shorter side is scaled down; the proportions are kept.
    assert _dimensions(display[2], tmp_path) == (803, 640)
    assert _dimensions(thumbnail[2], tmp_path) == (401, 320)


@needs_ffmpeg
def test_portrait_copies_reuse_an_original_that_is_already_small(tmp_path: Path) -> None:
    source = tmp_path / "small.webp"
    source.write_bytes(
        _picture(tmp_path, "small.webp", "256x256", "-c:v", "libwebp", "-quality", "5")
    )
    uploader = FakeUploader()

    variants = store_reciter_portrait_variants(
        str(source),
        original_object_key="audio/reciter-portraits/small/original.webp",
        reciter_code="small",
        uploader=uploader,
    )

    assert variants.display_object_key == "audio/reciter-portraits/small/original.webp"
    assert variants.thumbnail_object_key == "audio/reciter-portraits/small/original.webp"
    assert uploader.calls == []


@needs_ffmpeg
def test_reciter_portrait_upload_rejects_an_unreadable_picture(tmp_path: Path) -> None:
    with pytest.raises(ReciterPortraitUploadError, match=r"размер портрета|обработать портрет"):
        upload_reciter_portrait(
            SimpleUploadedFile("portrait.png", b"\x89PNG\r\n\x1a\n" + b"broken" * 20),
            reciter_code="saad-al-ghamdi",
            uploader=FakeUploader(),
        )
