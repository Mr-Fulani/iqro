from __future__ import annotations

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
