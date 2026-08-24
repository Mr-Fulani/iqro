from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any

import pytest
from botocore.exceptions import ClientError  # type: ignore[import-untyped]
from django.core.exceptions import ImproperlyConfigured
from django.test import override_settings

from quran_backend.modules.core.checks import check_media_object_storage
from quran_backend.modules.core.object_storage import (
    IMMUTABLE_CACHE_CONTROL,
    ImmutableObjectSpec,
    ImmutableObjectUploader,
    ObjectStorageError,
    object_storage_config,
)


class FakeObjectStorageClient:
    def __init__(self) -> None:
        self.objects: dict[str, dict[str, Any]] = {}
        self.put_calls = 0
        self.head_calls: list[dict[str, Any]] = []

    def put_object(self, **kwargs: Any) -> dict[str, Any]:
        self.put_calls += 1
        key = str(kwargs["Key"])
        if key in self.objects:
            raise ClientError(
                {
                    "Error": {"Code": "PreconditionFailed"},
                    "ResponseMetadata": {"HTTPStatusCode": 412},
                },
                "PutObject",
            )
        body = kwargs["Body"].read()
        etag = '"immutable-etag"'
        self.objects[key] = {
            "ETag": etag,
            "ContentLength": len(body),
            "ContentType": kwargs["ContentType"],
            "ContentDisposition": kwargs["ContentDisposition"],
            "CacheControl": kwargs["CacheControl"],
            "Metadata": kwargs["Metadata"],
            "ChecksumSHA256": kwargs["ChecksumSHA256"],
            "Body": body,
            "IfNoneMatch": kwargs["IfNoneMatch"],
        }
        return {"ETag": etag}

    def head_object(self, **kwargs: Any) -> dict[str, Any]:
        self.head_calls.append(kwargs)
        return dict(self.objects[str(kwargs["Key"])])


def _source(
    tmp_path: Path, payload: bytes = b"immutable-media"
) -> tuple[Path, ImmutableObjectSpec]:
    path = tmp_path / "source.mp3"
    path.write_bytes(payload)
    return path, ImmutableObjectSpec(
        key="audio/hafs/1.0.0/surah-001-standard.mp3",
        content_type="audio/mpeg",
        size_bytes=len(payload),
        checksum_sha256=hashlib.sha256(payload).hexdigest(),
    )


def test_uploader_creates_and_verifies_an_immutable_object(tmp_path: Path) -> None:
    source, spec = _source(tmp_path)
    client = FakeObjectStorageClient()
    uploader = ImmutableObjectUploader(
        client=client,
        bucket="quran-media",
        max_upload_bytes=1024,
    )

    stored = uploader.upload_path(source, spec)

    assert stored.created is True
    assert stored.etag == '"immutable-etag"'
    assert client.objects[spec.key]["Body"] == source.read_bytes()
    assert client.objects[spec.key]["IfNoneMatch"] == "*"
    assert (
        client.objects[spec.key]["ChecksumSHA256"] == "QJKyX/txsDVjWlfZnpFrdF1VHwiDl58FN+oV4kGf37U="
    )
    assert client.objects[spec.key]["CacheControl"] == IMMUTABLE_CACHE_CONTROL
    assert client.head_calls == [
        {"Bucket": "quran-media", "Key": spec.key, "IfMatch": '"immutable-etag"'}
    ]


def test_uploader_is_idempotent_when_existing_object_matches(tmp_path: Path) -> None:
    source, spec = _source(tmp_path)
    client = FakeObjectStorageClient()
    uploader = ImmutableObjectUploader(
        client=client,
        bucket="quran-media",
        max_upload_bytes=1024,
    )

    uploader.upload_path(source, spec)
    stored = uploader.upload_path(source, spec)

    assert stored.created is False
    assert stored.etag == '"immutable-etag"'
    assert client.put_calls == 2
    assert client.head_calls[-1] == {"Bucket": "quran-media", "Key": spec.key}


def test_uploader_rejects_existing_object_with_conflicting_metadata(tmp_path: Path) -> None:
    source, spec = _source(tmp_path)
    client = FakeObjectStorageClient()
    client.objects[spec.key] = {
        "ETag": '"different"',
        "ContentLength": spec.size_bytes,
        "ContentType": spec.content_type,
        "ContentDisposition": "inline",
        "CacheControl": IMMUTABLE_CACHE_CONTROL,
        "Metadata": {"sha256": "0" * 64},
    }
    uploader = ImmutableObjectUploader(
        client=client,
        bucket="quran-media",
        max_upload_bytes=1024,
    )

    with pytest.raises(ObjectStorageError, match="conflicts"):
        uploader.upload_path(source, spec)


def test_uploader_rejects_local_integrity_mismatch_before_request(tmp_path: Path) -> None:
    source, spec = _source(tmp_path)
    client = FakeObjectStorageClient()
    uploader = ImmutableObjectUploader(
        client=client,
        bucket="quran-media",
        max_upload_bytes=1024,
    )
    source.write_bytes(b"changed-content")

    with pytest.raises(ObjectStorageError, match="SHA-256 does not match"):
        uploader.upload_path(source, spec)

    assert client.put_calls == 0


@override_settings(
    MEDIA_OBJECT_STORAGE_ENABLED=True,
    MEDIA_OBJECT_STORAGE_ALLOW_HTTP=False,
    MEDIA_OBJECT_STORAGE_ENDPOINT_URL="https://account.r2.cloudflarestorage.com",
    MEDIA_OBJECT_STORAGE_BUCKET="quran-media",
    MEDIA_OBJECT_STORAGE_ACCESS_KEY_ID="access-key",
    MEDIA_OBJECT_STORAGE_SECRET_ACCESS_KEY="secret-key",
    MEDIA_OBJECT_STORAGE_REGION="auto",
    MEDIA_OBJECT_STORAGE_ADDRESSING_STYLE="path",
    MEDIA_OBJECT_STORAGE_CONNECT_TIMEOUT_SECONDS=5,
    MEDIA_OBJECT_STORAGE_READ_TIMEOUT_SECONDS=60,
    MEDIA_OBJECT_STORAGE_MAX_ATTEMPTS=3,
    MEDIA_OBJECT_STORAGE_MAX_UPLOAD_BYTES=1024,
)
def test_object_storage_configuration_is_provider_neutral() -> None:
    config = object_storage_config()

    assert config.bucket == "quran-media"
    assert config.endpoint_url == "https://account.r2.cloudflarestorage.com"
    assert check_media_object_storage() == []


@override_settings(
    MEDIA_OBJECT_STORAGE_ENABLED=True,
    MEDIA_OBJECT_STORAGE_ALLOW_HTTP=False,
    MEDIA_OBJECT_STORAGE_ENDPOINT_URL="http://insecure.example.test",
)
def test_object_storage_configuration_rejects_insecure_endpoint() -> None:
    with pytest.raises(ImproperlyConfigured, match="HTTPS origin"):
        object_storage_config()

    errors = check_media_object_storage()
    assert [error.id for error in errors] == ["core.E002"]
