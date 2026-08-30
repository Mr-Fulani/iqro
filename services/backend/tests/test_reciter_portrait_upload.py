from __future__ import annotations

from pathlib import Path

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile

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
    with pytest.raises(ReciterPortraitUploadError, match="не больше 2 МБ"):
        upload_reciter_portrait(
            SimpleUploadedFile("portrait.png", payload),
            reciter_code="saad-al-ghamdi",
            uploader=FakeUploader(),
        )
