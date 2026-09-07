from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path, PurePosixPath
from typing import Any, Protocol
from urllib.parse import urlsplit

BACKUP_NAME = re.compile(r"^[A-Za-z0-9_-]+_(?P<timestamp>\d{8}T\d{6}Z)\.dump$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
MANIFEST_SCHEMA = 1


class OffsiteBackupError(RuntimeError):
    pass


class Body(Protocol):
    def read(self, amount: int | None = None) -> bytes: ...


class ObjectStore(Protocol):
    def upload_file(
        self,
        filename: str,
        bucket: str,
        key: str,
        ExtraArgs: Mapping[str, Any] | None = None,
    ) -> None: ...

    def put_object(self, **kwargs: Any) -> Mapping[str, Any]: ...

    def get_object(self, **kwargs: Any) -> Mapping[str, Any]: ...

    def head_object(self, **kwargs: Any) -> Mapping[str, Any]: ...

    def get_paginator(self, operation_name: str) -> Any: ...

    def delete_objects(self, **kwargs: Any) -> Mapping[str, Any]: ...


@dataclass(frozen=True)
class Settings:
    endpoint_url: str
    bucket: str
    access_key_id: str
    secret_access_key: str
    region: str
    addressing_style: str
    prefix: str
    environment: str
    backup_dir: Path
    retention_days: int

    @property
    def root_prefix(self) -> str:
        return f"{self.prefix}/{self.environment}"

    @property
    def latest_manifest_key(self) -> str:
        return f"{self.root_prefix}/latest.json"


def _required(values: Mapping[str, str], name: str) -> str:
    value = values.get(name, "").strip()
    if not value:
        raise OffsiteBackupError(f"{name} is required")
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise OffsiteBackupError(f"{name} must not contain control characters")
    return value


def _safe_segment(value: str, label: str) -> str:
    normalized = value.strip().strip("/")
    if not normalized or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._/-]*", normalized):
        raise OffsiteBackupError(f"{label} contains unsupported characters")
    parts = PurePosixPath(normalized).parts
    if any(part in {"", ".", ".."} for part in parts):
        raise OffsiteBackupError(f"{label} must not contain relative path segments")
    return normalized


def _safe_bucket(value: str) -> str:
    normalized = value.strip()
    if (
        len(normalized) < 3
        or len(normalized) > 255
        or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", normalized)
    ):
        raise OffsiteBackupError("bucket contains unsupported characters")
    return normalized


def load_settings(values: Mapping[str, str] | None = None) -> Settings:
    source = os.environ if values is None else values
    endpoint_url = _required(source, "BACKUP_OBJECT_STORAGE_ENDPOINT_URL").rstrip("/")
    parsed = urlsplit(endpoint_url)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.query
        or parsed.fragment
    ):
        raise OffsiteBackupError(
            "BACKUP_OBJECT_STORAGE_ENDPOINT_URL must be HTTPS without embedded credentials"
        )
    addressing_style = source.get(
        "BACKUP_OBJECT_STORAGE_ADDRESSING_STYLE", "path"
    ).strip()
    if addressing_style not in {"path", "virtual"}:
        raise OffsiteBackupError(
            "BACKUP_OBJECT_STORAGE_ADDRESSING_STYLE must be path or virtual"
        )
    try:
        retention_days = int(source.get("BACKUP_OBJECT_STORAGE_RETENTION_DAYS", "30"))
    except ValueError as exc:
        raise OffsiteBackupError(
            "BACKUP_OBJECT_STORAGE_RETENTION_DAYS must be an integer"
        ) from exc
    if retention_days < 7 or retention_days > 3650:
        raise OffsiteBackupError(
            "BACKUP_OBJECT_STORAGE_RETENTION_DAYS must be between 7 and 3650"
        )
    backup_dir = Path(source.get("BACKUP_DIR", "/backups")).resolve()
    if backup_dir == Path("/"):
        raise OffsiteBackupError("BACKUP_DIR must be a dedicated directory")
    return Settings(
        endpoint_url=endpoint_url,
        bucket=_safe_bucket(_required(source, "BACKUP_OBJECT_STORAGE_BUCKET")),
        access_key_id=_required(source, "BACKUP_OBJECT_STORAGE_ACCESS_KEY_ID"),
        secret_access_key=_required(source, "BACKUP_OBJECT_STORAGE_SECRET_ACCESS_KEY"),
        region=source.get("BACKUP_OBJECT_STORAGE_REGION", "auto").strip() or "auto",
        addressing_style=addressing_style,
        prefix=_safe_segment(
            source.get("BACKUP_OBJECT_STORAGE_PREFIX", "quran-platform/postgres"),
            "BACKUP_OBJECT_STORAGE_PREFIX",
        ),
        environment=_safe_bucket(source.get("BACKUP_ENVIRONMENT", "production")),
        backup_dir=backup_dir,
        retention_days=retention_days,
    )


def object_store(settings: Settings) -> ObjectStore:
    import boto3
    from botocore.config import Config as BotoConfig

    return boto3.client(
        "s3",
        endpoint_url=settings.endpoint_url,
        aws_access_key_id=settings.access_key_id,
        aws_secret_access_key=settings.secret_access_key,
        region_name=settings.region,
        config=BotoConfig(
            signature_version="s3v4",
            s3={"addressing_style": settings.addressing_style},
            retries={"max_attempts": 5, "mode": "standard"},
            connect_timeout=10,
            read_timeout=120,
        ),
    )


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def expected_checksum(path: Path) -> str:
    checksum_path = path.with_name(f"{path.name}.sha256")
    if not checksum_path.is_file():
        raise OffsiteBackupError(f"checksum is missing for {path.name}")
    fields = checksum_path.read_text(encoding="ascii").strip().split()
    if (
        len(fields) != 2
        or fields[1].lstrip("*") != path.name
        or not SHA256.fullmatch(fields[0])
    ):
        raise OffsiteBackupError(f"checksum file is invalid for {path.name}")
    actual = file_sha256(path)
    if actual != fields[0]:
        raise OffsiteBackupError(f"local checksum mismatch for {path.name}")
    return actual


def latest_backup(backup_dir: Path) -> Path:
    candidates = [
        path
        for path in backup_dir.glob("*.dump")
        if path.is_file() and BACKUP_NAME.fullmatch(path.name)
    ]
    if not candidates:
        raise OffsiteBackupError("no completed PostgreSQL backup was found")
    return max(candidates, key=lambda path: path.name)


def _object_key(settings: Settings, backup: Path) -> str:
    if not BACKUP_NAME.fullmatch(backup.name):
        raise OffsiteBackupError(
            "backup filename does not follow the immutable timestamp format"
        )
    return f"{settings.root_prefix}/{backup.name}"


def _metadata(response: Mapping[str, Any]) -> Mapping[str, str]:
    value = response.get("Metadata", {})
    return value if isinstance(value, Mapping) else {}


def _read_body(response: Mapping[str, Any]) -> bytes:
    body = response.get("Body")
    if body is None or not hasattr(body, "read"):
        raise OffsiteBackupError(
            "object storage returned a response without a readable body"
        )
    return body.read()


def _manifest(settings: Settings, store: ObjectStore) -> dict[str, Any]:
    response = store.get_object(
        Bucket=settings.bucket, Key=settings.latest_manifest_key
    )
    try:
        manifest = json.loads(_read_body(response))
    except (json.JSONDecodeError, UnicodeDecodeError, TypeError) as exc:
        raise OffsiteBackupError("latest offsite manifest is invalid JSON") from exc
    if (
        not isinstance(manifest, dict)
        or manifest.get("schema_version") != MANIFEST_SCHEMA
    ):
        raise OffsiteBackupError("latest offsite manifest has an unsupported schema")
    key = manifest.get("object_key")
    checksum_key = manifest.get("checksum_key")
    if (
        not isinstance(key, str)
        or not isinstance(checksum_key, str)
        or not key.startswith(f"{settings.root_prefix}/")
        or checksum_key != f"{key}.sha256"
        or not BACKUP_NAME.fullmatch(PurePosixPath(key).name)
    ):
        raise OffsiteBackupError(
            "latest offsite manifest points outside the backup prefix"
        )
    checksum = manifest.get("sha256")
    if not isinstance(checksum, str) or not SHA256.fullmatch(checksum):
        raise OffsiteBackupError("latest offsite manifest has an invalid checksum")
    size = manifest.get("size")
    if not isinstance(size, int) or isinstance(size, bool) or size < 1:
        raise OffsiteBackupError("latest offsite manifest has an invalid object size")
    return manifest


def _is_not_found(error: Exception) -> bool:
    if isinstance(error, KeyError):
        return True
    response = getattr(error, "response", None)
    if not isinstance(response, Mapping):
        return False
    details = response.get("Error")
    if not isinstance(details, Mapping):
        return False
    return str(details.get("Code", "")) in {"404", "NoSuchKey", "NotFound"}


def _existing_head(
    settings: Settings, store: ObjectStore, key: str
) -> Mapping[str, Any] | None:
    try:
        return store.head_object(Bucket=settings.bucket, Key=key)
    except Exception as exc:
        if _is_not_found(exc):
            return None
        raise


def _verify_head(
    settings: Settings,
    store: ObjectStore,
    *,
    key: str,
    expected_size: int,
    checksum: str,
) -> None:
    head = store.head_object(Bucket=settings.bucket, Key=key)
    if int(head.get("ContentLength", -1)) != expected_size:
        raise OffsiteBackupError("offsite object size differs from the local backup")
    if _metadata(head).get("sha256") != checksum:
        raise OffsiteBackupError(
            "offsite object metadata checksum is missing or incorrect"
        )


def upload_latest(
    settings: Settings, store: ObjectStore, *, keep_existing: bool = False
) -> dict[str, Any]:
    backup = latest_backup(settings.backup_dir)
    checksum = expected_checksum(backup)
    size = backup.stat().st_size
    key = _object_key(settings, backup)
    checksum_key = f"{key}.sha256"
    metadata = {
        "sha256": checksum,
        "environment": settings.environment,
        "immutable": "true",
    }
    existing = _existing_head(settings, store, key)
    if existing is None:
        store.upload_file(
            str(backup),
            settings.bucket,
            key,
            ExtraArgs={"ContentType": "application/octet-stream", "Metadata": metadata},
        )
    elif (
        int(existing.get("ContentLength", -1)) != size
        or _metadata(existing).get("sha256") != checksum
    ):
        raise OffsiteBackupError(
            "immutable offsite backup key already contains different data"
        )
    checksum_body = f"{checksum}  {backup.name}\n".encode("ascii")
    store.put_object(
        Bucket=settings.bucket,
        Key=checksum_key,
        Body=checksum_body,
        ContentType="text/plain",
        CacheControl="no-store",
        Metadata=metadata,
    )
    _verify_head(settings, store, key=key, expected_size=size, checksum=checksum)
    remote_checksum = _read_body(
        store.get_object(Bucket=settings.bucket, Key=checksum_key)
    ).decode("ascii")
    if remote_checksum != checksum_body.decode("ascii"):
        raise OffsiteBackupError(
            "offsite checksum object differs from the local checksum"
        )

    manifest = {
        "schema_version": MANIFEST_SCHEMA,
        "environment": settings.environment,
        "created_at": datetime.now(tz=UTC).isoformat(),
        "filename": backup.name,
        "object_key": key,
        "checksum_key": checksum_key,
        "size": size,
        "sha256": checksum,
    }
    store.put_object(
        Bucket=settings.bucket,
        Key=settings.latest_manifest_key,
        Body=(json.dumps(manifest, sort_keys=True) + "\n").encode("utf-8"),
        ContentType="application/json",
        CacheControl="no-store",
        Metadata={"sha256": checksum, "environment": settings.environment},
    )
    if not keep_existing:
        prune(
            settings, store, preserve={key, checksum_key, settings.latest_manifest_key}
        )
    return manifest


def _iter_remote_body(body: Body) -> Iterable[bytes]:
    while chunk := body.read(1024 * 1024):
        yield chunk


def verify_latest(settings: Settings, store: ObjectStore) -> dict[str, Any]:
    manifest = _manifest(settings, store)
    key = str(manifest["object_key"])
    checksum = str(manifest["sha256"])
    expected_size = int(manifest["size"])
    _verify_head(
        settings, store, key=key, expected_size=expected_size, checksum=checksum
    )
    response = store.get_object(Bucket=settings.bucket, Key=key)
    digest = hashlib.sha256()
    downloaded_size = 0
    body = response.get("Body")
    if body is None or not hasattr(body, "read"):
        raise OffsiteBackupError("offsite backup response has no readable body")
    for chunk in _iter_remote_body(body):
        downloaded_size += len(chunk)
        digest.update(chunk)
    if downloaded_size != expected_size or digest.hexdigest() != checksum:
        raise OffsiteBackupError("offsite backup failed full download verification")
    return manifest


def download_latest(
    settings: Settings,
    store: ObjectStore,
    *,
    output: Path,
    replace: bool,
) -> dict[str, Any]:
    manifest = _manifest(settings, store)
    if output.suffix != ".dump" or output.resolve() == Path("/"):
        raise OffsiteBackupError("download output must be a dedicated .dump file")
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists() and not replace:
        raise OffsiteBackupError(
            "download output already exists; pass --replace explicitly"
        )
    response = store.get_object(Bucket=settings.bucket, Key=str(manifest["object_key"]))
    body = response.get("Body")
    if body is None or not hasattr(body, "read"):
        raise OffsiteBackupError("offsite backup response has no readable body")
    digest = hashlib.sha256()
    downloaded_size = 0
    descriptor, temporary_name = tempfile.mkstemp(
        dir=output.parent, prefix=f".{output.name}.", suffix=".partial"
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            for chunk in _iter_remote_body(body):
                stream.write(chunk)
                digest.update(chunk)
                downloaded_size += len(chunk)
            stream.flush()
            os.fsync(stream.fileno())
        expected_size = int(manifest["size"])
        checksum = str(manifest["sha256"])
        if downloaded_size != expected_size or digest.hexdigest() != checksum:
            raise OffsiteBackupError(
                "downloaded offsite backup checksum does not match"
            )
        os.chmod(temporary, 0o600)
        os.replace(temporary, output)
        output.with_name(f"{output.name}.sha256").write_text(
            f"{checksum}  {output.name}\n", encoding="ascii"
        )
        os.chmod(output.with_name(f"{output.name}.sha256"), 0o600)
    finally:
        temporary.unlink(missing_ok=True)
    return manifest


def prune(settings: Settings, store: ObjectStore, *, preserve: set[str]) -> int:
    cutoff = datetime.now(tz=UTC) - timedelta(days=settings.retention_days)
    paginator = store.get_paginator("list_objects_v2")
    delete_keys: list[str] = []
    for page in paginator.paginate(
        Bucket=settings.bucket, Prefix=f"{settings.root_prefix}/"
    ):
        for item in page.get("Contents", []):
            key = item.get("Key")
            last_modified = item.get("LastModified")
            if (
                not isinstance(key, str)
                or key in preserve
                or not isinstance(last_modified, datetime)
            ):
                continue
            name = PurePosixPath(key).name
            backup_name = name.removesuffix(".sha256")
            if not BACKUP_NAME.fullmatch(backup_name):
                continue
            normalized_modified = (
                last_modified.replace(tzinfo=UTC)
                if last_modified.tzinfo is None
                else last_modified.astimezone(UTC)
            )
            if normalized_modified < cutoff:
                delete_keys.append(key)
    for index in range(0, len(delete_keys), 1000):
        response = store.delete_objects(
            Bucket=settings.bucket,
            Delete={
                "Objects": [{"Key": key} for key in delete_keys[index : index + 1000]]
            },
        )
        errors = response.get("Errors", [])
        if isinstance(errors, list) and errors:
            raise OffsiteBackupError("object storage failed to prune expired backups")
    return len(delete_keys)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Upload and verify immutable PostgreSQL backups in private S3 storage."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    upload = subparsers.add_parser("upload")
    upload.add_argument(
        "--keep-existing",
        action="store_true",
        help="Skip retention pruning and preserve all previous offsite backups.",
    )
    subparsers.add_parser("verify")
    download = subparsers.add_parser("download")
    download.add_argument("--output", type=Path, required=True)
    download.add_argument("--replace", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        settings = load_settings()
        store = object_store(settings)
        if args.command == "upload":
            manifest = upload_latest(settings, store, keep_existing=args.keep_existing)
            print(
                "Offsite PostgreSQL backup uploaded and HEAD/checksum verified: "
                f"{manifest['filename']}"
            )
        elif args.command == "verify":
            manifest = verify_latest(settings, store)
            print(
                "Offsite PostgreSQL backup passed full download verification: "
                f"{manifest['filename']}"
            )
        else:
            manifest = download_latest(
                settings, store, output=args.output, replace=args.replace
            )
            print(
                "Offsite PostgreSQL backup downloaded and verified: "
                f"{manifest['filename']}"
            )
    except (OSError, OffsiteBackupError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    except Exception as exc:
        if exc.__class__.__module__.startswith(("botocore", "boto3")):
            print("ERROR: object storage request failed", file=sys.stderr)
            return 1
        raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
