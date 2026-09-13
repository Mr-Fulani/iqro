"""Shared, secret-free backup receipts consumed by the existing heartbeat."""

from __future__ import annotations

import fcntl
import json
import os
import tempfile
from contextlib import contextmanager
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


@contextmanager
def backup_lock(status_dir: Path):
    """Serialize uploads and approved retention on the single production backup host."""
    status_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (status_dir / ".storage.lock").open("a") as stream:
        os.chmod(stream.name, 0o600)
        fcntl.flock(stream, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(stream, fcntl.LOCK_UN)


@contextmanager
def backup_attempt(status_path: Path, *, component: str, environment: str):
    with backup_lock(status_path.parent):
        try:
            yield
        except BaseException:
            # Mark failure before releasing the lock to a waiting retention process.
            write_status(
                status_path,
                component=component,
                environment=environment,
                state="failed",
            )
            raise


def write_upload_receipt(status_dir: Path, manifest: dict[str, Any]) -> None:
    """Keep per-dump evidence after the mutable latest pointer advances."""
    directory = status_dir / "postgres-uploads"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = directory / f"{manifest['filename']}.json"
    receipt = {
        key: manifest[key]
        for key in (
            "filename",
            "environment",
            "object_key",
            "checksum_key",
            "sha256",
            "size",
        )
    }
    if path.exists():
        if json.loads(path.read_text()) != receipt:
            raise ValueError("immutable upload receipt differs from previous upload")
        return
    with path.open("x") as stream:
        os.chmod(path, 0o600)
        json.dump(receipt, stream, sort_keys=True)


def write_status(
    path: Path,
    *,
    component: str,
    environment: str,
    state: str,
    source_time: str | None = None,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    payload = {
        "schema_version": 1,
        "component": component,
        "environment": environment,
        "state": state,
        "updated_at": datetime.now(UTC).isoformat(),
        "source_time": source_time,
    }
    fd, name = tempfile.mkstemp(dir=path.parent, prefix=".status-")
    temporary = Path(name)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(payload, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def check_status(
    path: Path,
    *,
    component: str,
    environment: str,
    max_age_seconds: int,
    now: datetime | None = None,
) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text())
        if (
            not isinstance(payload, dict)
            or payload.get("schema_version") != 1
            or payload.get("component") != component
            or payload.get("environment") != environment
            or payload.get("state") != "success"
        ):
            raise ValueError("invalid receipt")
        current = now or datetime.now(UTC)
        for field in ("updated_at", "source_time"):
            timestamp = datetime.fromisoformat(payload[field])
            if timestamp.utcoffset() is None:
                raise ValueError("timestamp has no timezone")
            age = (current - timestamp).total_seconds()
            if not -300 <= age <= max_age_seconds:
                raise ValueError("stale receipt")
        return payload
    except (OSError, ValueError, TypeError, KeyError) as exc:
        raise ValueError(
            f"{component} offsite backup is missing, failed or stale"
        ) from exc
