from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

import pytest
from django.core.exceptions import ImproperlyConfigured
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings

from quran_backend.modules.audio.portrait_upload import (
    MAX_RECITER_PORTRAIT_BYTES,
    ReciterPortraitUploadError,
    upload_reciter_portrait,
)
from quran_backend.modules.core.object_storage import ImmutableObjectSpec, StoredObject


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
def test_local_portrait_upload_saves_media_without_cloud_credentials(tmp_path: Path) -> None:
    payload = b"RIFF\x10\x00\x00\x00WEBPportrait-bytes"
    with override_settings(MEDIA_ROOT=tmp_path):
        first = upload_reciter_portrait(
            SimpleUploadedFile("portrait.webp", payload), reciter_code="saad-al-ghamdi"
        )
        repeated = upload_reciter_portrait(
            SimpleUploadedFile("portrait.webp", payload), reciter_code="saad-al-ghamdi"
        )

    assert (tmp_path / first.object_key).read_bytes() == payload
    assert first.created is True
    assert repeated.created is False
    assert repeated.object_key == first.object_key


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
            SimpleUploadedFile("portrait.webp", b"RIFF\x10\x00\x00\x00WEBPportrait"),
            reciter_code="saad-al-ghamdi",
        )
    assert result.object_key == uploader.calls[0][1].key
    assert list(tmp_path.iterdir()) == []


def test_reciter_portrait_upload_uses_validated_hash_addressed_key() -> None:
    payload = b"RIFF\x10\x00\x00\x00WEBPportrait-bytes"
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
