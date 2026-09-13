from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import tarfile
import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Mapping

from ops.monitoring.backup_status import backup_attempt, write_status
from ops.postgres.offsite import (
    SHA256,
    ObjectStore,
    OffsiteBackupError,
    Settings,
    _existing_head,
    download_verified_file,
    file_sha256,
    load_settings,
    object_store,
    upload_verified_file,
)


class RecoveryError(RuntimeError):
    pass


def command(args: list[str], *, cwd: Path | None = None) -> str:
    result = subprocess.run(
        args,
        cwd=cwd,
        capture_output=True,
        text=True,
        env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
        timeout=600,
    )
    if result.returncode:
        # Git/age stderr may contain paths, remote credentials or secret input.
        raise RecoveryError(
            f"{Path(args[0]).name} operation failed (exit {result.returncode})"
        )
    return result.stdout.strip()


def write_json(path: Path, value: Any) -> None:
    with path.open("x", encoding="utf-8") as stream:
        os.chmod(path, 0o600)
        json.dump(value, stream, sort_keys=True, indent=2)
        stream.write("\n")


def media_settings(values: Mapping[str, str], destination: Settings) -> Settings:
    mapped = {
        "BACKUP_" + key.removeprefix("MEDIA_"): value
        for key, value in values.items()
        if key.startswith("MEDIA_OBJECT_STORAGE_")
    }
    mapped["BACKUP_ENVIRONMENT"] = destination.environment
    source = load_settings(mapped)
    if (
        source.endpoint_url == destination.endpoint_url
        and source.bucket == destination.bucket
    ):
        raise RecoveryError("media and backup buckets must be separate")
    if source.access_key_id == destination.access_key_id:
        raise RecoveryError("media and backup credentials must be separate")
    return source


def capture_git(repo: Path, output: Path) -> dict[str, Any]:
    repo = repo.resolve(strict=True)
    if command(["git", "rev-parse", "--is-shallow-repository"], cwd=repo) != "false":
        raise RecoveryError("a full repository is required for recovery")
    # --all contains local refs. The scheduler must explicitly fetch its dedicated mirror first.
    config = command(["git", "config", "--local", "--list"], cwd=repo)
    if re.search(r"(?im)^(extensions\.partialclone|remote\..*\.promisor)=", config):
        raise RecoveryError("partial clones are not supported")
    head = command(["git", "rev-parse", "HEAD"], cwd=repo)
    refs = command(["git", "show-ref"], cwd=repo)
    # Reject unsupported dependencies anywhere in saved history instead of silently omitting them.
    history = command(
        ["git", "log", "--all", "--raw", "--format=", "--no-renames"], cwd=repo
    )
    if re.search(r"(?m)^:(?:160000 |[0-7]{6} 160000 )", history):
        raise RecoveryError("submodules need a separate backup inventory")
    attributes = command(
        [
            "git",
            "log",
            "--all",
            "--format=%H",
            "-G",
            "filter=lfs",
            "--",
            ".gitattributes",
            ":(glob)**/.gitattributes",
        ],
        cwd=repo,
    )
    if attributes:
        raise RecoveryError("Git LFS requires a separate backup inventory")
    bundle = output / "repository.bundle"
    command(["git", "bundle", "create", str(bundle), "--all"], cwd=repo)
    os.chmod(bundle, 0o600)
    command(["git", "bundle", "verify", str(bundle)], cwd=repo)
    if (
        command(["git", "show-ref"], cwd=repo) != refs
        or command(["git", "rev-parse", "HEAD"], cwd=repo) != head
    ):
        raise RecoveryError("repository refs changed during snapshot; retry")
    return {
        "refs": refs.splitlines(),
        "head": head,
    }


def encrypt_config(
    files: Mapping[str, str], recipients: list[str], output: Path
) -> None:
    if (
        not files
        or not recipients
        or len(files) > 256
        or any(not re.fullmatch(r"age1[0-9a-z]+", r) for r in recipients)
    ):
        raise RecoveryError(
            "explicit config files and age public recipients are required"
        )
    checked = []
    fingerprints = {}
    total = 0
    for label, name in files.items():
        path = Path(name)
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", label):
            raise RecoveryError("config labels must be simple filenames")
        if path.is_symlink() or not path.is_file():
            raise RecoveryError("config entries must be regular files, not symlinks")
        stat = path.stat()
        fingerprints[path] = (stat.st_ino, stat.st_mtime_ns, stat.st_size)
        total += stat.st_size
        if total > 16 * 1024 * 1024:
            raise RecoveryError("configuration exceeds 16 MiB backup budget")
        checked.append((label, path))
    args = ["age", "--encrypt"]
    for recipient in recipients:
        args.extend(["--recipient", recipient])
    # No plaintext tar is ever written to disk. Backup host needs public recipients only.
    with output.open("xb") as encrypted:
        os.chmod(output, 0o600)
        with subprocess.Popen(
            args, stdin=subprocess.PIPE, stdout=encrypted, stderr=subprocess.DEVNULL
        ) as process:
            assert process.stdin is not None
            try:
                with tarfile.open(fileobj=process.stdin, mode="w|") as archive:
                    for label, path in checked:
                        archive.add(path, arcname=label, recursive=False)
                process.stdin.close()
            except BaseException:
                process.kill()
                process.wait()
                raise
            if process.wait(timeout=600):
                raise RecoveryError("age encryption failed")
    for _, path in checked:
        stat = path.stat()
        if (stat.st_ino, stat.st_mtime_ns, stat.st_size) != fingerprints[path]:
            raise RecoveryError("configuration changed during encryption; retry")


def capture_media(
    source: Settings,
    store: ObjectStore,
    output: Path,
    *,
    max_bytes: int,
    max_objects: int,
) -> list[dict[str, Any]]:
    if max_bytes < 1 or max_objects < 1:
        raise RecoveryError("positive media size and object limits are required")
    directory = output / "media"
    directory.mkdir(mode=0o700)
    records = []
    total = 0
    seen: set[str] = set()
    original = {}
    for page in store.get_paginator("list_objects_v2").paginate(Bucket=source.bucket):
        for item in page.get("Contents", []):
            key = item["Key"]
            if not isinstance(key, str) or not key or key in seen:
                raise RecoveryError("invalid or duplicate media object key")
            seen.add(key)
            original[key] = (item["Size"], item["ETag"])
            if len(seen) > max_objects or total + int(item["Size"]) > max_bytes:
                raise RecoveryError("media inventory exceeds configured backup budget")
            local = directory / hashlib.sha256(key.encode()).hexdigest()
            response = store.get_object(
                Bucket=source.bucket, Key=key, IfMatch=item["ETag"]
            )
            body = response["Body"]
            digest = hashlib.sha256()
            size = 0
            try:
                with local.open("xb") as stream:
                    os.chmod(local, 0o600)
                    while chunk := body.read(1024 * 1024):
                        size += len(chunk)
                        if total + size > max_bytes or size > int(item["Size"]):
                            raise RecoveryError(
                                "media object changed size or exceeds budget"
                            )
                        digest.update(chunk)
                        stream.write(chunk)
            finally:
                if hasattr(body, "close"):
                    body.close()
            if size != int(item["Size"]):
                raise RecoveryError("incomplete media download")
            total += size
            records.append(
                {
                    "key": key,
                    "path": local.relative_to(output).as_posix(),
                    "size": size,
                    "sha256": digest.hexdigest(),
                    "content_type": response.get(
                        "ContentType", "application/octet-stream"
                    ),
                }
            )
    # Catch concurrent publication/deletion; a listing alone is not a point-in-time snapshot.
    after = {
        item["Key"]: (item["Size"], item["ETag"])
        for page in store.get_paginator("list_objects_v2").paginate(
            Bucket=source.bucket
        )
        for item in page.get("Contents", [])
    }
    if after != original:
        raise RecoveryError("media inventory changed during snapshot; retry")
    return records


def build_snapshot(
    config: dict[str, Any],
    destination: Settings,
    store: ObjectStore,
    source: Settings,
    source_store: ObjectStore,
) -> tuple[Path, dict[str, Any]]:
    root = Path(config["output_dir"]).resolve()
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    started = datetime.now(UTC).isoformat()
    snapshot_id = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex
    directory = root / snapshot_id
    directory.mkdir(mode=0o700)
    git = capture_git(Path(config["repository"]), directory)
    if config.get("release_manifest"):
        supplied_release = json.loads(Path(config["release_manifest"]).read_text())
        release = {
            key: supplied_release[key]
            for key in ("schema_version", "tag", "commit", "images", "created_at")
        }
        # Keep the release pointer alongside every snapshot, without embedding credentials.
        if release.get("schema_version") != 1 or not re.fullmatch(
            r"[0-9a-f]{40,64}", release.get("commit", "")
        ):
            raise RecoveryError("invalid release manifest")
        refs = dict(line.split(" ", 1)[::-1] for line in git["refs"])
        if f"refs/tags/{release.get('tag', '')}" not in refs:
            raise RecoveryError("release tag is missing from the source mirror")
        actual = command(
            ["git", "rev-parse", f"refs/tags/{release['tag']}^{{commit}}"],
            cwd=Path(config["repository"]),
        )
        if actual != release["commit"]:
            raise RecoveryError("release tag differs from manifest commit")
        write_json(directory / "release.json", release)
    encrypt_config(
        config["config_files"],
        config["age_recipients"],
        directory / "configuration.tar.age",
    )
    media = capture_media(
        source,
        source_store,
        directory,
        max_bytes=config["media_max_bytes"],
        max_objects=config["media_max_objects"],
    )
    write_json(
        directory / "media.json",
        {"bucket": source.bucket, "endpoint": source.endpoint_url, "objects": media},
    )
    # Immutable blobs deduplicate unchanged media/Git content without deleting older snapshots.
    artifacts = []
    for path in sorted(directory.rglob("*")):
        if path.is_file():
            checksum = file_sha256(path)
            key = f"{destination.root_prefix}/recovery/blobs/{checksum}"
            record = upload_verified_file(destination, store, path, key)
            record["path"] = path.relative_to(directory).as_posix()
            artifacts.append(record)
    manifest = {
        "schema_version": 1,
        "snapshot_id": snapshot_id,
        "environment": destination.environment,
        "started_at": started,
        "git": git,
        "artifacts": artifacts,
    }
    # Publish the manifest LAST: partial snapshots cannot be mistaken for recoverable ones.
    path = directory / "snapshot.json"
    write_json(path, manifest)
    key = f"{destination.root_prefix}/recovery/snapshots/{snapshot_id}.json"
    receipt = upload_verified_file(destination, store, path, key)
    write_json(directory / "receipt.json", receipt)
    return directory, receipt


def validated_artifacts(
    manifest: dict[str, Any], destination: Settings
) -> list[dict[str, Any]]:
    """Validate the shared snapshot contract for both restore and retention."""
    prefix = f"{destination.root_prefix}/recovery/"
    if (
        manifest.get("schema_version") != 1
        or manifest.get("environment") != destination.environment
    ):
        raise RecoveryError("unsupported snapshot or wrong environment")
    seen = set()
    for record in manifest["artifacts"]:
        name = record["path"]
        if (
            not re.fullmatch(
                r"repository\.bundle|configuration\.tar\.age|media\.json|release\.json|media/[0-9a-f]{64}",
                name,
            )
            or name in seen
        ):
            raise RecoveryError("unsafe or duplicate recovery artifact path")
        seen.add(name)
        if (
            not SHA256.fullmatch(record["sha256"])
            or record["object_key"] != prefix + "blobs/" + record["sha256"]
        ):
            raise RecoveryError("artifact points outside recovery namespace")
        if type(record["size"]) is not int or record["size"] < 0:
            raise RecoveryError("invalid recovery artifact size")
    if not {"repository.bundle", "configuration.tar.age", "media.json"} <= seen:
        raise RecoveryError("incomplete recovery snapshot")
    return manifest["artifacts"]


def restore_snapshot(
    destination: Settings, store: ObjectStore, receipt: dict[str, Any], output: Path
) -> dict[str, Any]:
    prefix = f"{destination.root_prefix}/recovery/"
    if not re.fullmatch(
        re.escape(prefix) + r"snapshots/[0-9TZ]+-[0-9a-f]{32}\.json",
        receipt.get("object_key", ""),
    ):
        raise RecoveryError("snapshot receipt points outside recovery namespace")
    if (
        not SHA256.fullmatch(receipt.get("sha256", ""))
        or type(receipt.get("size")) is not int
        or not 0 < receipt["size"] <= 64 * 1024 * 1024
    ):
        raise RecoveryError("invalid snapshot receipt")
    output.mkdir(parents=True, mode=0o700, exist_ok=False)
    download_verified_file(destination, store, receipt, output / "snapshot.json")
    manifest = json.loads((output / "snapshot.json").read_text())
    records = validated_artifacts(manifest, destination)
    seen = {record["path"] for record in records}
    for record in records:
        download_verified_file(destination, store, record, output / record["path"])
    command(
        [
            "git",
            "clone",
            "--mirror",
            str(output / "repository.bundle"),
            str(output / "repository.git"),
        ]
    )
    command(["git", "fsck", "--full"], cwd=output / "repository.git")
    restored_refs = command(
        ["git", "show-ref"], cwd=output / "repository.git"
    ).splitlines()
    if sorted(restored_refs) != sorted(manifest["git"]["refs"]):
        raise RecoveryError("restored Git refs differ from snapshot")
    media = json.loads((output / "media.json").read_text())
    media_paths = set()
    for item in media["objects"]:
        name = "media/" + hashlib.sha256(item["key"].encode()).hexdigest()
        if name != item["path"] or name in media_paths or name not in seen:
            raise RecoveryError("media manifest is inconsistent")
        media_paths.add(name)
        path = output / name
        if path.stat().st_size != item["size"] or file_sha256(path) != item["sha256"]:
            raise RecoveryError("restored media checksum is inconsistent")
    if media_paths != {name for name in seen if name.startswith("media/")}:
        raise RecoveryError("media manifest omits restored objects")
    write_json(
        output / "verified.json",
        {
            "verified_at": datetime.now(UTC).isoformat(),
            "snapshot_id": manifest["snapshot_id"],
        },
    )
    return manifest


def snapshot_receipt(
    settings: Settings, store: ObjectStore, key: str
) -> dict[str, Any]:
    prefix = f"{settings.root_prefix}/recovery/snapshots/"
    if not re.fullmatch(re.escape(prefix) + r"[0-9TZ]+-[0-9a-f]{32}\.json", key):
        raise RecoveryError("snapshot key is outside recovery namespace")
    head = _existing_head(settings, store, key)
    if head is None:
        raise RecoveryError("snapshot does not exist")
    return {
        "object_key": key,
        "sha256": head.get("Metadata", {}).get("sha256"),
        "size": head["ContentLength"],
    }


def restore_media(snapshot: Path, target: Settings, store: ObjectStore) -> None:
    if not (snapshot / "verified.json").is_file():
        raise RecoveryError("first download and verify the recovery snapshot")
    manifest = json.loads((snapshot / "media.json").read_text())
    if (
        target.endpoint_url == manifest["endpoint"]
        and target.bucket == manifest["bucket"]
    ):
        raise RecoveryError("media restore requires a separate recovery bucket")
    for record in manifest["objects"]:
        name = "media/" + hashlib.sha256(record["key"].encode()).hexdigest()
        path = snapshot / name
        if (
            record["path"] != name
            or path.is_symlink()
            or not path.is_file()
            or path.stat().st_size != record["size"]
            or file_sha256(path) != record["sha256"]
        ):
            raise RecoveryError("local media changed after recovery verification")
        upload_verified_file(
            target, store, path, record["key"], content_type=record["content_type"]
        )


def decrypt_config(snapshot: Path, identity: Path, output: Path) -> None:
    # Authenticate the complete, bounded archive before writing any plaintext files.
    if output.exists():
        raise RecoveryError("decryption output already exists")
    plaintext = bytearray()
    with subprocess.Popen(
        [
            "age",
            "--decrypt",
            "--identity",
            str(identity),
            str(snapshot / "configuration.tar.age"),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    ) as process:
        assert process.stdout is not None
        try:
            while chunk := process.stdout.read(1024 * 1024):
                plaintext.extend(chunk)
                if len(plaintext) > 32 * 1024 * 1024:
                    raise RecoveryError(
                        "decrypted configuration exceeds recovery budget"
                    )
            if process.wait(timeout=600):
                raise RecoveryError("age decryption/authentication failed")
        except BaseException:
            process.kill()
            process.wait()
            raise
    with tarfile.open(fileobj=io.BytesIO(plaintext), mode="r:") as archive:
        members = archive.getmembers()
        names = [member.name for member in members]
        if (
            len(names) != len(set(names))
            or not names
            or any(
                not member.isfile()
                or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", member.name)
                for member in members
            )
        ):
            raise RecoveryError("unsafe entry in decrypted configuration")
        output.mkdir(parents=True, mode=0o700, exist_ok=False)
        for member in members:
            reader = archive.extractfile(member)
            assert reader is not None
            with (output / member.name).open("xb") as stream:
                os.chmod(output / member.name, 0o600)
                while chunk := reader.read(1024 * 1024):
                    stream.write(chunk)
    write_json(
        output / ".verified.json", {"verified_at": datetime.now(UTC).isoformat()}
    )


def release_manifest(repo: Path, tag: str, images: list[str], output: Path) -> None:
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?", tag):
        raise RecoveryError("release tag must be vMAJOR.MINOR.PATCH")
    if len({image.split("=", 1)[0] for image in images}) != len(images):
        raise RecoveryError("release image services must be unique")
    if not images or any(
        not re.fullmatch(
            r"[a-z][a-z0-9_-]*=[A-Za-z0-9][A-Za-z0-9._/:+-]*@sha256:[0-9a-f]{64}", image
        )
        for image in images
    ):
        raise RecoveryError("release images must be service=image@sha256:digest")
    main = command(["git", "rev-parse", "refs/heads/main^{commit}"], cwd=repo)
    if command(["git", "rev-parse", "HEAD"], cwd=repo) != main:
        raise RecoveryError("release must point at main")
    if command(["git", "status", "--porcelain"], cwd=repo):
        raise RecoveryError("release requires a clean working tree")
    if output.exists():
        raise RecoveryError("release manifest already exists")
    existing = command(["git", "tag", "--list", tag], cwd=repo)
    if existing:
        if (
            command(["git", "rev-parse", f"refs/tags/{tag}^{{commit}}"], cwd=repo)
            != main
        ):
            raise RecoveryError("existing release tag points elsewhere")
    else:
        command(["git", "tag", "-a", tag, main, "-m", f"Release {tag}"], cwd=repo)
    write_json(
        output,
        {
            "schema_version": 1,
            "tag": tag,
            "commit": main,
            "images": dict(image.split("=", 1) for image in images),
            "created_at": datetime.now(UTC).isoformat(),
        },
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Independent code/media/encrypted-config recovery snapshots."
    )
    subs = parser.add_subparsers(dest="command", required=True)
    backup = subs.add_parser("backup")
    backup.add_argument("--config", type=Path, required=True)
    restore = subs.add_parser("restore")
    selection = restore.add_mutually_exclusive_group(required=True)
    selection.add_argument("--receipt", type=Path)
    selection.add_argument("--snapshot-key")
    restore.add_argument("--output", type=Path, required=True)
    subs.add_parser("list")
    media_restore = subs.add_parser("restore-media")
    media_restore.add_argument("--snapshot", type=Path, required=True)
    decrypt = subs.add_parser("decrypt-config")
    decrypt.add_argument("--snapshot", type=Path, required=True)
    decrypt.add_argument("--identity", type=Path, required=True)
    decrypt.add_argument("--output", type=Path, required=True)
    release = subs.add_parser("release")
    release.add_argument("--repository", type=Path, required=True)
    release.add_argument("--tag", required=True)
    release.add_argument("--image", action="append", required=True)
    release.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    status_path = None
    succeeded = False
    environment = os.environ.get("BACKUP_ENVIRONMENT", "production")
    try:
        os.umask(0o077)
        if args.command == "backup":
            status_path = Path(os.environ["RECOVERY_STATUS_FILE"])
            config = json.loads(args.config.read_text())
            settings = load_settings()
            source = media_settings(os.environ, settings)
            with backup_attempt(
                status_path, component="recovery", environment=environment
            ):
                directory, receipt = build_snapshot(
                    config,
                    settings,
                    object_store(settings),
                    source,
                    object_store(source),
                )
                write_status(
                    status_path,
                    component="recovery",
                    environment=environment,
                    state="success",
                    source_time=json.loads((directory / "snapshot.json").read_text())[
                        "started_at"
                    ],
                )
            succeeded = True
            print(f"Recovery snapshot verified and uploaded: {receipt['object_key']}")
        elif args.command == "restore":
            settings = load_settings()
            store = object_store(settings)
            receipt = (
                json.loads(args.receipt.read_text())
                if args.receipt
                else snapshot_receipt(settings, store, args.snapshot_key)
            )
            restore_snapshot(settings, store, receipt, args.output.resolve())
            print("Recovery snapshot downloaded, checksums and Git restore verified.")
        elif args.command == "list":
            settings = load_settings()
            store = object_store(settings)
            prefix = f"{settings.root_prefix}/recovery/snapshots/"
            for page in store.get_paginator("list_objects_v2").paginate(
                Bucket=settings.bucket, Prefix=prefix
            ):
                for item in page.get("Contents", []):
                    if re.fullmatch(
                        re.escape(prefix) + r"[0-9TZ]+-[0-9a-f]{32}\.json", item["Key"]
                    ):
                        print(
                            json.dumps(
                                snapshot_receipt(settings, store, item["Key"]),
                                sort_keys=True,
                            )
                        )
        elif args.command == "decrypt-config":
            decrypt_config(
                args.snapshot.resolve(), args.identity.resolve(), args.output.resolve()
            )
            print(
                "Configuration decrypted and authenticated into a new private directory."
            )
        elif args.command == "restore-media":
            settings = load_settings()
            target = media_settings(os.environ, settings)
            restore_media(args.snapshot.resolve(), target, object_store(target))
            print("Media restored and verified in a separate recovery bucket.")
        else:
            release_manifest(
                args.repository.resolve(), args.tag, args.image, args.output.resolve()
            )
            print(
                "Local release tag and manifest prepared; nothing was pushed or deployed."
            )
    except Exception as exc:
        # Storage/crypto/subprocess failures must not leak credentials or plaintext in logs.
        if isinstance(exc, (RecoveryError, OffsiteBackupError)):
            print(f"ERROR: {exc}", file=sys.stderr)
        else:
            print(
                f"ERROR: recovery operation failed ({type(exc).__name__})",
                file=sys.stderr,
            )
        return 1
    finally:
        if status_path and not succeeded:
            write_status(
                status_path,
                component="recovery",
                environment=environment,
                state="failed",
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
