from __future__ import annotations

import hashlib
import hmac
import re
from base64 import b64encode
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Protocol, cast
from urllib.parse import urlsplit

import boto3  # type: ignore[import-untyped]
from botocore.config import Config  # type: ignore[import-untyped]
from botocore.exceptions import BotoCoreError, ClientError  # type: ignore[import-untyped]
from django.conf import settings
from django.core.exceptions import ImproperlyConfigured

IMMUTABLE_CACHE_CONTROL = "public, max-age=31536000, immutable"
STRONG_ETAG_PATTERN = re.compile(r'"[^"\r\n]+"\Z')
CONTENT_TYPE_PATTERN = re.compile(r"[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+\Z")


class ObjectStorageError(RuntimeError):
    """An immutable object could not be stored or verified safely."""


class ObjectStorageClient(Protocol):
    def put_object(self, **kwargs: Any) -> dict[str, Any]: ...

    def head_object(self, **kwargs: Any) -> dict[str, Any]: ...


class ObjectUploader(Protocol):
    def upload_path(self, source_path: Path, spec: ImmutableObjectSpec) -> StoredObject: ...


@dataclass(frozen=True, slots=True)
class ObjectStorageConfig:
    endpoint_url: str
    bucket: str
    access_key_id: str
    secret_access_key: str
    region: str
    addressing_style: str
    connect_timeout_seconds: int
    read_timeout_seconds: int
    max_attempts: int
    max_upload_bytes: int


@dataclass(frozen=True, slots=True)
class ImmutableObjectSpec:
    key: str
    content_type: str
    size_bytes: int
    checksum_sha256: str


@dataclass(frozen=True, slots=True)
class StoredObject:
    key: str
    etag: str
    created: bool


def object_storage_config() -> ObjectStorageConfig:
    if not bool(getattr(settings, "MEDIA_OBJECT_STORAGE_ENABLED", False)):
        raise ImproperlyConfigured("MEDIA_OBJECT_STORAGE_ENABLED must be true for uploads")

    endpoint_url = str(getattr(settings, "MEDIA_OBJECT_STORAGE_ENDPOINT_URL", ""))
    parsed = urlsplit(endpoint_url)
    allow_http = bool(getattr(settings, "MEDIA_OBJECT_STORAGE_ALLOW_HTTP", False))
    allowed_schemes = {"https", "http"} if allow_http else {"https"}
    if (
        parsed.scheme not in allowed_schemes
        or parsed.hostname is None
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path not in {"", "/"}
        or parsed.query
        or parsed.fragment
    ):
        protocol = "HTTP(S)" if allow_http else "HTTPS"
        raise ImproperlyConfigured(
            f"MEDIA_OBJECT_STORAGE_ENDPOINT_URL must be a credential-free {protocol} origin"
        )

    bucket = str(getattr(settings, "MEDIA_OBJECT_STORAGE_BUCKET", ""))
    access_key_id = str(getattr(settings, "MEDIA_OBJECT_STORAGE_ACCESS_KEY_ID", ""))
    secret_access_key = str(getattr(settings, "MEDIA_OBJECT_STORAGE_SECRET_ACCESS_KEY", ""))
    region = str(getattr(settings, "MEDIA_OBJECT_STORAGE_REGION", "auto"))
    if not bucket or not access_key_id or not secret_access_key or not region:
        raise ImproperlyConfigured(
            "MEDIA_OBJECT_STORAGE_BUCKET, credentials and region must be configured"
        )
    if any(character.isspace() for character in bucket):
        raise ImproperlyConfigured("MEDIA_OBJECT_STORAGE_BUCKET cannot contain whitespace")

    addressing_style = str(getattr(settings, "MEDIA_OBJECT_STORAGE_ADDRESSING_STYLE", "path"))
    if addressing_style not in {"auto", "path", "virtual"}:
        raise ImproperlyConfigured(
            "MEDIA_OBJECT_STORAGE_ADDRESSING_STYLE must be auto, path or virtual"
        )

    return ObjectStorageConfig(
        endpoint_url=endpoint_url.rstrip("/"),
        bucket=bucket,
        access_key_id=access_key_id,
        secret_access_key=secret_access_key,
        region=region,
        addressing_style=addressing_style,
        connect_timeout_seconds=_positive_setting("MEDIA_OBJECT_STORAGE_CONNECT_TIMEOUT_SECONDS"),
        read_timeout_seconds=_positive_setting("MEDIA_OBJECT_STORAGE_READ_TIMEOUT_SECONDS"),
        max_attempts=_positive_setting("MEDIA_OBJECT_STORAGE_MAX_ATTEMPTS"),
        max_upload_bytes=_positive_setting("MEDIA_OBJECT_STORAGE_MAX_UPLOAD_BYTES"),
    )


def configured_object_uploader() -> ImmutableObjectUploader:
    config = object_storage_config()
    client = cast(
        ObjectStorageClient,
        boto3.client(
            "s3",
            endpoint_url=config.endpoint_url,
            aws_access_key_id=config.access_key_id,
            aws_secret_access_key=config.secret_access_key,
            region_name=config.region,
            config=Config(
                signature_version="s3v4",
                connect_timeout=config.connect_timeout_seconds,
                read_timeout=config.read_timeout_seconds,
                retries={"max_attempts": config.max_attempts, "mode": "standard"},
                s3={"addressing_style": config.addressing_style},
            ),
        ),
    )
    return ImmutableObjectUploader(
        client=client,
        bucket=config.bucket,
        max_upload_bytes=config.max_upload_bytes,
    )


class ImmutableObjectUploader:
    def __init__(
        self,
        *,
        client: ObjectStorageClient,
        bucket: str,
        max_upload_bytes: int,
    ) -> None:
        if not bucket or max_upload_bytes <= 0:
            raise ValueError("A bucket and positive upload limit are required")
        self._client = client
        self._bucket = bucket
        self._max_upload_bytes = max_upload_bytes

    def upload_path(self, source_path: Path, spec: ImmutableObjectSpec) -> StoredObject:
        source, fingerprint = self._validate_source(source_path, spec)
        created = True
        try:
            with source.open("rb") as stream:
                response = self._client.put_object(
                    Bucket=self._bucket,
                    Key=spec.key,
                    Body=stream,
                    ContentLength=spec.size_bytes,
                    ContentType=spec.content_type,
                    ContentDisposition="inline",
                    CacheControl=IMMUTABLE_CACHE_CONTROL,
                    Metadata={"sha256": spec.checksum_sha256},
                    ChecksumSHA256=b64encode(bytes.fromhex(spec.checksum_sha256)).decode("ascii"),
                    IfNoneMatch="*",
                )
        except ClientError as exc:
            if not _is_precondition_failure(exc):
                raise ObjectStorageError(_safe_client_error("PutObject", exc)) from exc
            created = False
            response = {}
        except (BotoCoreError, OSError) as exc:
            raise ObjectStorageError(f"PutObject failed: {type(exc).__name__}") from exc

        if _file_fingerprint(source) != fingerprint:
            raise ObjectStorageError("Source file changed during upload")

        response_etag = _strong_etag(response.get("ETag"))
        head = self._head(spec, if_match=response_etag if created else None)
        etag = self._validate_head(head, spec)
        if response_etag is not None and not hmac.compare_digest(etag, response_etag):
            raise ObjectStorageError("PutObject and HeadObject returned different ETags")
        return StoredObject(key=spec.key, etag=etag, created=created)

    def _validate_source(
        self,
        source_path: Path,
        spec: ImmutableObjectSpec,
    ) -> tuple[Path, tuple[int, int, int, int]]:
        _validate_spec(spec)
        try:
            source = source_path.resolve(strict=True)
        except (OSError, RuntimeError) as exc:
            raise ObjectStorageError("Source file cannot be resolved") from exc
        if source_path.is_symlink() or not source.is_file():
            raise ObjectStorageError("Source must be a regular non-symlink file")
        fingerprint = _file_fingerprint(source)
        if fingerprint[2] != spec.size_bytes:
            raise ObjectStorageError("Source size does not match immutable object metadata")
        if spec.size_bytes > self._max_upload_bytes:
            raise ObjectStorageError("Source exceeds MEDIA_OBJECT_STORAGE_MAX_UPLOAD_BYTES")
        actual_checksum = _sha256_file(source)
        if not hmac.compare_digest(actual_checksum, spec.checksum_sha256):
            raise ObjectStorageError("Source SHA-256 does not match immutable object metadata")
        if _file_fingerprint(source) != fingerprint:
            raise ObjectStorageError("Source file changed during checksum verification")
        return source, fingerprint

    def _head(
        self,
        spec: ImmutableObjectSpec,
        *,
        if_match: str | None,
    ) -> dict[str, Any]:
        arguments: dict[str, Any] = {"Bucket": self._bucket, "Key": spec.key}
        if if_match is not None:
            arguments["IfMatch"] = if_match
        try:
            return self._client.head_object(**arguments)
        except ClientError as exc:
            raise ObjectStorageError(_safe_client_error("HeadObject", exc)) from exc
        except BotoCoreError as exc:
            raise ObjectStorageError(f"HeadObject failed: {type(exc).__name__}") from exc

    @staticmethod
    def _validate_head(head: dict[str, Any], spec: ImmutableObjectSpec) -> str:
        etag = _strong_etag(head.get("ETag"))
        if etag is None:
            raise ObjectStorageError("HeadObject did not return a strong ETag")
        content_length = head.get("ContentLength")
        if isinstance(content_length, bool) or not isinstance(content_length, int):
            raise ObjectStorageError("HeadObject returned an invalid ContentLength")
        metadata = head.get("Metadata")
        observed_checksum = metadata.get("sha256") if isinstance(metadata, dict) else None
        mismatches = [
            content_length != spec.size_bytes,
            head.get("ContentType") != spec.content_type,
            head.get("ContentDisposition") != "inline",
            head.get("CacheControl") != IMMUTABLE_CACHE_CONTROL,
            not isinstance(observed_checksum, str)
            or not hmac.compare_digest(observed_checksum, spec.checksum_sha256),
        ]
        if any(mismatches):
            raise ObjectStorageError(
                "Existing object conflicts with immutable size, type, cache or checksum metadata"
            )
        return etag


def _positive_setting(name: str) -> int:
    value = getattr(settings, name, None)
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ImproperlyConfigured(f"{name} must be a positive integer")
    return value


def _validate_spec(spec: ImmutableObjectSpec) -> None:
    path = PurePosixPath(spec.key)
    if (
        not spec.key
        or path.is_absolute()
        or ".." in path.parts
        or "\\" in spec.key
        or "//" in spec.key
        or spec.key.endswith("/")
    ):
        raise ObjectStorageError("Immutable object key must be a safe relative POSIX path")
    if CONTENT_TYPE_PATTERN.fullmatch(spec.content_type) is None:
        raise ObjectStorageError("Immutable object content type is invalid")
    if spec.size_bytes <= 0:
        raise ObjectStorageError("Immutable object size must be positive")
    if re.fullmatch(r"[0-9a-f]{64}", spec.checksum_sha256) is None:
        raise ObjectStorageError("Immutable object SHA-256 must be lowercase hexadecimal")


def _strong_etag(value: object) -> str | None:
    if not isinstance(value, str) or STRONG_ETAG_PATTERN.fullmatch(value) is None:
        return None
    return value


def _is_precondition_failure(exc: ClientError) -> bool:
    response = exc.response
    metadata = response.get("ResponseMetadata", {})
    error = response.get("Error", {})
    return metadata.get("HTTPStatusCode") == 412 or error.get("Code") in {
        "PreconditionFailed",
        "412",
    }


def _safe_client_error(operation: str, exc: ClientError) -> str:
    error = exc.response.get("Error", {})
    code = error.get("Code") if isinstance(error, dict) else None
    return f"{operation} failed: {code or 'ClientError'}"


def _file_fingerprint(path: Path) -> tuple[int, int, int, int]:
    stat = path.stat()
    return stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
