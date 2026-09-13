"""One retention policy, exact reviewable plans, and guarded application of approved plans."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from ops.monitoring.backup_status import backup_lock, check_status
from ops.postgres.offsite import (
    BACKUP_NAME,
    SHA256,
    ObjectStore,
    Settings,
    _existing_head,
    expected_checksum,
    file_sha256,
    load_settings,
    object_store,
)
from ops.recovery.snapshot import validated_artifacts, write_json

POLICY = {"local_latest": 3, "remote_daily": 7, "remote_weekly": 4}
SNAPSHOT_ID = re.compile(r"[0-9]{8}T[0-9]{6}Z-[0-9a-f]{32}")
MAX_MANIFEST_BYTES = 64 * 1024 * 1024


class RetentionError(RuntimeError):
    pass


@dataclass(frozen=True)
class Copy:
    identifier: str
    timestamp: datetime
    group: str
    targets: tuple[str, ...]
    blobs: frozenset[str] = frozenset()


def digest(value: Any) -> str:
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def keep_copies(copies: list[Copy], *, local: bool) -> set[str]:
    """Newest three locally; union of newest copy per seven UTC days/four ISO weeks remotely."""
    keep = set()
    for group in {copy.group for copy in copies}:
        ordered = sorted(
            (copy for copy in copies if copy.group == group),
            key=lambda copy: (copy.timestamp, copy.identifier),
            reverse=True,
        )
        if local:
            keep.update(copy.identifier for copy in ordered[: POLICY["local_latest"]])
            continue
        days, weeks = set(), set()
        for copy in ordered:
            timestamp = copy.timestamp.astimezone(UTC)
            day = timestamp.date().isoformat()
            week = timestamp.isocalendar()[:2]
            if day not in days and len(days) < POLICY["remote_daily"]:
                days.add(day)
                keep.add(copy.identifier)
            if week not in weeks and len(weeks) < POLICY["remote_weekly"]:
                weeks.add(week)
                keep.add(copy.identifier)
    return keep


def timestamp(value: str, now: datetime) -> datetime:
    parsed = datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(tzinfo=UTC)
    if (parsed - now).total_seconds() > 300:
        raise RetentionError("future-dated backup; retention refused")
    return parsed


def read_remote(store: ObjectStore, settings: Settings, key: str, limit: int) -> bytes:
    response = store.get_object(Bucket=settings.bucket, Key=key)
    body = response["Body"]
    try:
        payload = body.read(limit + 1)
        if len(payload) > limit:
            raise RetentionError("remote manifest exceeds limit")
        return payload
    finally:
        if hasattr(body, "close"):
            body.close()


def local_identity(path: Path) -> dict[str, Any]:
    if path.is_symlink() or not path.is_file():
        raise RetentionError("retention only accepts regular files")
    stat = path.stat()
    return {
        "path": str(path),
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
        "inode": stat.st_ino,
        "sha256": file_sha256(path),
    }


def make_plan(
    settings: Settings,
    store: ObjectStore,
    *,
    recovery_dir: Path,
    status_dir: Path,
    now: datetime | None = None,
) -> dict[str, Any]:
    now = now or datetime.now(UTC)
    backup_dir = settings.backup_dir.resolve(strict=True)
    recovery_dir = recovery_dir.resolve(strict=True)
    status_dir = status_dir.resolve(strict=True)
    if any(path == Path("/") for path in (backup_dir, recovery_dir, status_dir)):
        raise RetentionError("dedicated backup directories are required")
    if (backup_dir / ".backup.lock").exists():
        raise RetentionError("PostgreSQL dump is running; retry after it completes")
    statuses = {}
    # Failed/missing/stale jobs block rotation even when older copies remain healthy.
    for component in ("postgres", "recovery"):
        statuses[component] = check_status(
            status_dir / f"{component}.json",
            component=component,
            environment=settings.environment,
            max_age_seconds=93600,
            now=now,
        )
    prefix = settings.root_prefix + "/"
    remote: dict[str, dict[str, Any]] = {}
    for page in store.get_paginator("list_objects_v2").paginate(
        Bucket=settings.bucket, Prefix=prefix
    ):
        for item in page.get("Contents", []):
            key = item["Key"]
            if not key.startswith(prefix):
                raise RetentionError("storage listing escaped environment prefix")
            remote[key] = {"key": key, "size": item["Size"], "etag": item.get("ETag")}
    heads: dict[str, Any] = {}

    def checked_head(key: str, checksum: str, size: int) -> None:
        if key not in remote:
            raise RetentionError("a completed backup references a missing object")
        if key not in heads:
            result = _existing_head(settings, store, key)
            heads[key] = (
                {
                    "ContentLength": result["ContentLength"],
                    "Metadata": {"sha256": result.get("Metadata", {}).get("sha256")},
                    "ETag": result.get("ETag"),
                }
                if result
                else None
            )
        head = heads[key]
        if (
            not head
            or head["ContentLength"] != size
            or head.get("Metadata", {}).get("sha256") != checksum
        ):
            raise RetentionError("backup object verification failed; retention refused")

    remote_copies: list[Copy] = []
    local_copies: list[Copy] = []
    local_files: dict[str, dict[str, Any]] = {}
    local_directories: dict[str, dict[str, Any]] = {}
    ignored: list[str] = []

    def add_local(path: Path) -> str:
        identity = local_identity(path)
        local_files[str(path)] = identity
        return str(path)

    for key in sorted(remote):
        name = key.removeprefix(prefix)
        match = BACKUP_NAME.fullmatch(name)
        if not match:
            continue
        sidecar = key + ".sha256"
        if sidecar not in remote:
            ignored.append(key)
            continue
        fields = read_remote(store, settings, sidecar, 1024).decode("ascii").split()
        if len(fields) != 2 or fields[1] != name or not SHA256.fullmatch(fields[0]):
            raise RetentionError("invalid PostgreSQL checksum; retention refused")
        checked_head(key, fields[0], remote[key]["size"])
        remote_copies.append(
            Copy(
                key,
                timestamp(match["timestamp"], now),
                "postgres:" + name.rsplit("_", 1)[0],
                (key, sidecar),
            )
        )

    recovery_prefix = prefix + "recovery/"
    for key in sorted(remote):
        if not key.startswith(recovery_prefix + "snapshots/"):
            continue
        name = key.removeprefix(recovery_prefix + "snapshots/")
        if not name.endswith(".json") or not SNAPSHOT_ID.fullmatch(name[:-5]):
            # Unknown manifests may contain references we cannot safely garbage collect.
            raise RetentionError("unknown snapshot format; retention refused")
        payload = read_remote(store, settings, key, MAX_MANIFEST_BYTES)
        checked_head(key, hashlib.sha256(payload).hexdigest(), len(payload))
        manifest = json.loads(payload)
        if (
            manifest.get("schema_version") != 1
            or manifest.get("environment") != settings.environment
            or manifest.get("snapshot_id") != name[:-5]
        ):
            raise RetentionError("invalid snapshot identity; retention refused")
        blobs = set()
        for record in validated_artifacts(manifest, settings):
            checked_head(record["object_key"], record["sha256"], record["size"])
            blobs.add(record["object_key"])
        remote_copies.append(
            Copy(
                key,
                timestamp(name.split("-", 1)[0], now),
                "recovery",
                (key,),
                frozenset(blobs),
            )
        )

    # Successful offsite evidence survives remote rotation and is removed with the local dump.
    for path in sorted(backup_dir.glob("*.dump")):
        match = BACKUP_NAME.fullmatch(path.name)
        receipt_path = status_dir / "postgres-uploads" / f"{path.name}.json"
        checksum_path = path.with_name(path.name + ".sha256")
        if not match or not receipt_path.is_file() or not checksum_path.is_file():
            ignored.append(str(path))
            continue
        receipt = json.loads(receipt_path.read_text())
        checksum = expected_checksum(path)
        if (
            receipt.get("filename") != path.name
            or receipt.get("environment") != settings.environment
            or receipt.get("sha256") != checksum
            or receipt.get("size") != path.stat().st_size
            or receipt.get("object_key") != prefix + path.name
        ):
            raise RetentionError("local dump differs from successful upload receipt")
        targets = tuple(add_local(item) for item in (path, checksum_path, receipt_path))
        local_copies.append(
            Copy(
                str(path),
                timestamp(match["timestamp"], now),
                "postgres:" + path.name.rsplit("_", 1)[0],
                targets,
            )
        )

    for directory in sorted(recovery_dir.iterdir()):
        if (
            not directory.is_dir()
            or directory.is_symlink()
            or not SNAPSHOT_ID.fullmatch(directory.name)
        ):
            ignored.append(str(directory))
            continue
        receipt_path, manifest_path = (
            directory / "receipt.json",
            directory / "snapshot.json",
        )
        if not receipt_path.is_file() or not manifest_path.is_file():
            ignored.append(str(directory))
            continue
        receipt = json.loads(receipt_path.read_text())
        if (
            receipt.get("object_key")
            != recovery_prefix + "snapshots/" + directory.name + ".json"
            or receipt.get("sha256") != file_sha256(manifest_path)
            or receipt.get("size") != manifest_path.stat().st_size
        ):
            raise RetentionError(
                "local snapshot differs from successful upload receipt"
            )
        manifest = json.loads(manifest_path.read_text())
        expected = {"snapshot.json", "receipt.json"}
        for record in validated_artifacts(manifest, settings):
            relative = record["path"]
            path = directory / relative
            if (
                local_identity(path)["sha256"] != record["sha256"]
                or path.stat().st_size != record["size"]
            ):
                raise RetentionError("local snapshot file verification failed")
            expected.add(relative)
        found = set()
        directories = []
        for path in directory.rglob("*"):
            if path.is_symlink():
                raise RetentionError("symlink in local snapshot; retention refused")
            if path.is_file():
                found.add(path.relative_to(directory).as_posix())
            elif path.is_dir():
                directories.append(path)
            else:
                raise RetentionError("unexpected local snapshot entry")
        if found != expected:
            raise RetentionError(
                "local snapshot contains unrecognized or missing files"
            )
        targets = [add_local(directory / relative) for relative in sorted(found)]
        for path in sorted(
            [*directories, directory], key=lambda p: len(p.parts), reverse=True
        ):
            stat = path.stat()
            local_directories[str(path)] = {
                "path": str(path),
                "inode": stat.st_ino,
                "mtime_ns": stat.st_mtime_ns,
                "size": 0,
            }
            targets.append(str(path))
        local_copies.append(
            Copy(
                str(directory),
                timestamp(directory.name.split("-", 1)[0], now),
                "recovery",
                tuple(targets),
            )
        )

    local_keep = keep_copies(local_copies, local=True)
    remote_keep = keep_copies(remote_copies, local=False)
    # Never delete the PostgreSQL recovery pointer's target, even if it is older than the policy.
    latest_key = prefix + "latest.json"
    if latest_key in remote:
        latest = json.loads(
            read_remote(store, settings, latest_key, MAX_MANIFEST_BYTES)
        )
        if latest.get("object_key") not in {
            copy.identifier
            for copy in remote_copies
            if copy.group.startswith("postgres:")
        }:
            raise RetentionError(
                "latest PostgreSQL pointer does not refer to a complete backup"
            )
        remote_keep.add(latest["object_key"])
    retained_blobs = set().union(
        *(copy.blobs for copy in remote_copies if copy.identifier in remote_keep)
    )
    retired_blobs = set().union(
        *(copy.blobs for copy in remote_copies if copy.identifier not in remote_keep)
    )
    deletions = []
    for copy in local_copies:
        if copy.identifier not in local_keep:
            for path in copy.targets:
                kind = "local_file" if path in local_files else "local_directory"
                item = (
                    local_files[path]
                    if kind == "local_file"
                    else local_directories[path]
                )
                deletions.append({"kind": kind, **item})
    # Manifests first, then only blobs no retained manifest uses. Orphans are never swept blindly.
    for copy in remote_copies:
        if copy.identifier not in remote_keep:
            deletions.extend(
                {"kind": "remote_object", **remote[key]} for key in copy.targets
            )
    deletions.extend(
        {"kind": "remote_object", **remote[key]}
        for key in sorted(retired_blobs - retained_blobs)
    )
    if not local_copies or not remote_copies:
        raise RetentionError("no complete backup inventory; retention refused")
    inventory = {
        "remote": remote,
        "heads": heads,
        "local": local_files,
        "directories": local_directories,
        "statuses": statuses,
        "ignored": ignored,
    }
    return {
        "schema_version": 1,
        "policy": POLICY,
        "environment": settings.environment,
        "endpoint_url": settings.endpoint_url,
        "bucket": settings.bucket,
        "prefix": settings.prefix,
        "backup_dir": str(backup_dir),
        "recovery_dir": str(recovery_dir),
        "status_dir": str(status_dir),
        "inventory_sha256": digest(inventory),
        "keep_local": sorted(local_keep),
        "keep_remote": sorted(remote_keep),
        "delete": deletions,
        "delete_bytes": sum(item["size"] for item in deletions),
        "ignored": ignored,
    }


def apply_plan(
    settings: Settings, store: ObjectStore, plan: dict[str, Any], approved_sha256: str
) -> None:
    if digest(plan) != approved_sha256:
        raise RetentionError("approval does not match the exact plan")
    if (
        settings.environment != plan["environment"]
        or settings.bucket != plan["bucket"]
        or settings.endpoint_url != plan["endpoint_url"]
        or settings.prefix != plan["prefix"]
        or str(settings.backup_dir.resolve()) != plan["backup_dir"]
    ):
        raise RetentionError(
            "current storage configuration differs from the approved plan"
        )
    status_dir = Path(plan["status_dir"])
    with backup_lock(status_dir):
        fresh = make_plan(
            settings,
            store,
            recovery_dir=Path(plan["recovery_dir"]),
            status_dir=status_dir,
        )
        if fresh != plan:
            raise RetentionError(
                "backup inventory changed; generate and approve a new plan"
            )
        for item in plan["delete"]:
            if item["kind"] == "local_file":
                Path(item["path"]).unlink()
            elif item["kind"] == "local_directory":
                Path(item["path"]).rmdir()
            else:
                result = store.delete_objects(
                    Bucket=settings.bucket, Delete={"Objects": [{"Key": item["key"]}]}
                )
                if result.get("Errors"):
                    raise RetentionError(
                        "storage deletion failed; stopped without deleting further objects"
                    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Preview 3-local / 7-daily + 4-weekly retention; apply only an approved exact plan."
    )
    subs = parser.add_subparsers(dest="command", required=True)
    preview = subs.add_parser("plan")
    preview.add_argument("--recovery-dir", type=Path, required=True)
    preview.add_argument("--status-dir", type=Path, required=True)
    preview.add_argument("--output", type=Path, required=True)
    apply = subs.add_parser("apply")
    apply.add_argument("--plan", type=Path, required=True)
    apply.add_argument("--approved-plan-sha256", required=True)
    args = parser.parse_args(argv)
    try:
        settings = load_settings()
        store = object_store(settings)
        if args.command == "plan":
            with backup_lock(args.status_dir):
                plan = make_plan(
                    settings,
                    store,
                    recovery_dir=args.recovery_dir,
                    status_dir=args.status_dir,
                )
            write_json(args.output, plan)
            print(
                f"Plan saved: {len(plan['delete'])} targets; {plan['delete_bytes']} bytes; approval SHA-256: {digest(plan)}"
            )
        else:
            plan = json.loads(args.plan.read_text())
            apply_plan(settings, store, plan, args.approved_plan_sha256)
            print("Only the exact approved retention targets were removed.")
    except Exception as exc:
        if isinstance(exc, (RetentionError, ValueError)):
            print(f"ERROR: {exc}", file=sys.stderr)
        else:
            print(
                f"ERROR: retention failed ({type(exc).__name__}); stopped",
                file=sys.stderr,
            )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
