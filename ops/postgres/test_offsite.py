from __future__ import annotations

import hashlib
import io
import json
import tempfile
import unittest
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any
from unittest.mock import patch

from ops.postgres.offsite import (
    OffsiteBackupError,
    Settings,
    download_latest,
    latest_backup,
    load_settings,
    main,
    prune,
    upload_latest,
    verify_latest,
)


class FakePaginator:
    def __init__(self, store: FakeStore) -> None:
        self.store = store

    def paginate(self, **_kwargs: Any) -> list[dict[str, Any]]:
        return [{"Contents": list(self.store.listed)}]


class FakeStore:
    def __init__(self) -> None:
        self.objects: dict[str, bytes] = {}
        self.metadata: dict[str, dict[str, str]] = {}
        self.listed: list[dict[str, Any]] = []
        self.deleted: list[str] = []
        self.delete_errors: list[dict[str, str]] = []

    def upload_file(
        self,
        filename: str,
        _bucket: str,
        key: str,
        ExtraArgs: dict[str, Any] | None = None,
    ) -> None:
        self.objects[key] = Path(filename).read_bytes()
        self.metadata[key] = dict((ExtraArgs or {}).get("Metadata", {}))

    def put_object(self, **kwargs: Any) -> dict[str, Any]:
        key = str(kwargs["Key"])
        body = kwargs.get("Body", b"")
        self.objects[key] = body.encode() if isinstance(body, str) else bytes(body)
        self.metadata[key] = dict(kwargs.get("Metadata", {}))
        return {}

    def get_object(self, **kwargs: Any) -> dict[str, Any]:
        key = str(kwargs["Key"])
        return {
            "Body": io.BytesIO(self.objects[key]),
            "Metadata": self.metadata.get(key, {}),
        }

    def head_object(self, **kwargs: Any) -> dict[str, Any]:
        key = str(kwargs["Key"])
        return {
            "ContentLength": len(self.objects[key]),
            "Metadata": self.metadata.get(key, {}),
        }

    def get_paginator(self, _operation_name: str) -> FakePaginator:
        return FakePaginator(self)

    def delete_objects(self, **kwargs: Any) -> dict[str, Any]:
        for item in kwargs["Delete"]["Objects"]:
            self.deleted.append(item["Key"])
        return {"Errors": self.delete_errors}


def settings(backup_dir: Path) -> Settings:
    return Settings(
        endpoint_url="https://account.example.test",
        bucket="private-backups",
        access_key_id="access",
        secret_access_key="secret",
        region="auto",
        addressing_style="path",
        prefix="quran-platform/postgres",
        environment="staging",
        backup_dir=backup_dir,
        retention_days=30,
    )


def write_backup(directory: Path, name: str, content: bytes) -> Path:
    backup = directory / name
    backup.write_bytes(content)
    checksum = hashlib.sha256(content).hexdigest()
    backup.with_name(f"{name}.sha256").write_text(
        f"{checksum}  {name}\n", encoding="ascii"
    )
    return backup


class OffsiteBackupTests(unittest.TestCase):
    def test_upload_keep_existing_never_lists_or_deletes_old_backups(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            backup = write_backup(directory, "quran_20260907T010000Z.dump", b"database")
            config = settings(directory)
            store = FakeStore()
            old_key = f"{config.root_prefix}/quran_20200101T010000Z.dump"
            store.objects[old_key] = b"previous database"
            with (
                patch.object(
                    store, "get_paginator", side_effect=AssertionError("pruning")
                ),
                patch.object(
                    store, "delete_objects", side_effect=AssertionError("deletion")
                ),
                patch("ops.postgres.offsite.load_settings", return_value=config),
                patch("ops.postgres.offsite.object_store", return_value=store),
            ):
                self.assertEqual(main(["upload", "--keep-existing"]), 0)
                verified = verify_latest(config, store)
            self.assertEqual(verified["filename"], backup.name)
            self.assertEqual(store.objects[old_key], b"previous database")

    def test_settings_require_private_https_storage(self) -> None:
        values = {
            "BACKUP_OBJECT_STORAGE_ENDPOINT_URL": "http://user:secret@example.test",
            "BACKUP_OBJECT_STORAGE_BUCKET": "private-backups",
            "BACKUP_OBJECT_STORAGE_ACCESS_KEY_ID": "access",
            "BACKUP_OBJECT_STORAGE_SECRET_ACCESS_KEY": "secret",
        }
        with self.assertRaisesRegex(OffsiteBackupError, "must be HTTPS"):
            load_settings(values)

    def test_settings_reject_control_characters_in_credentials(self) -> None:
        values = {
            "BACKUP_OBJECT_STORAGE_ENDPOINT_URL": "https://account.example.test",
            "BACKUP_OBJECT_STORAGE_BUCKET": "private-backups",
            "BACKUP_OBJECT_STORAGE_ACCESS_KEY_ID": "access\nINJECTED=true",
            "BACKUP_OBJECT_STORAGE_SECRET_ACCESS_KEY": "secret",
        }
        with self.assertRaisesRegex(OffsiteBackupError, "control characters"):
            load_settings(values)

    def test_latest_backup_ignores_partial_and_uses_timestamp_name(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            first = write_backup(directory, "quran_20260828T010000Z.dump", b"first")
            latest = write_backup(directory, "quran_20260829T010000Z.dump", b"latest")
            (directory / "quran_20260830T010000Z.dump.partial").write_bytes(b"partial")
            self.assertEqual(latest_backup(directory), latest)
            first.unlink()

    def test_upload_verify_download_and_bounded_prune(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            backup = write_backup(directory, "quran_20260829T010000Z.dump", b"database")
            config = settings(directory)
            store = FakeStore()
            old_key = f"{config.root_prefix}/quran_20260701T010000Z.dump"
            unrelated_key = f"{config.root_prefix}/notes.txt"
            store.listed = [
                {
                    "Key": old_key,
                    "LastModified": datetime.now(tz=UTC) - timedelta(days=60),
                },
                {
                    "Key": unrelated_key,
                    "LastModified": datetime.now(tz=UTC) - timedelta(days=60),
                },
            ]

            manifest = upload_latest(config, store)
            self.assertEqual(manifest["filename"], backup.name)
            self.assertIn(config.latest_manifest_key, store.objects)
            self.assertEqual(store.deleted, [old_key])

            verified = verify_latest(config, store)
            self.assertEqual(
                verified["sha256"], hashlib.sha256(b"database").hexdigest()
            )

            output = directory / "restored.dump"
            download_latest(config, store, output=output, replace=False)
            self.assertEqual(output.read_bytes(), b"database")
            self.assertIn(
                output.name, output.with_name(f"{output.name}.sha256").read_text()
            )

    def test_manifest_cannot_escape_environment_prefix(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            config = settings(Path(temporary_directory))
            store = FakeStore()
            store.objects[config.latest_manifest_key] = json.dumps(
                {
                    "schema_version": 1,
                    "object_key": "other/production/stolen.dump",
                    "checksum_key": "other/production/stolen.dump.sha256",
                    "sha256": "a" * 64,
                    "size": 1,
                }
            ).encode()
            with self.assertRaisesRegex(
                OffsiteBackupError, "outside the backup prefix"
            ):
                verify_latest(config, store)

    def test_prune_fails_when_object_storage_reports_partial_errors(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            config = settings(Path(temporary_directory))
            store = FakeStore()
            store.listed = [
                {
                    "Key": f"{config.root_prefix}/quran_20260701T010000Z.dump",
                    "LastModified": datetime.now(tz=UTC) - timedelta(days=60),
                }
            ]
            store.delete_errors = [{"Code": "AccessDenied"}]
            with self.assertRaisesRegex(OffsiteBackupError, "failed to prune"):
                prune(config, store, preserve=set())


if __name__ == "__main__":
    unittest.main()
