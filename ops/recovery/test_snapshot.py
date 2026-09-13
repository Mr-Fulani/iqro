from __future__ import annotations

import hashlib
import io
import json
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from ops.postgres.offsite import OffsiteBackupError
from ops.postgres.test_offsite import settings
from ops.recovery.snapshot import (
    RecoveryError,
    build_snapshot,
    capture_git,
    capture_media,
    command,
    decrypt_config,
    encrypt_config,
    media_settings,
    release_manifest,
    restore_media,
    restore_snapshot,
    snapshot_receipt,
)


class MemoryStore:
    def __init__(self):
        self.objects = {}
        self.metadata = {}
        self.uploads = []
        self.fail_upload = False
        self.change_etag = False
        self.listings = 0

    def upload_file(self, filename, bucket, key, ExtraArgs=None):
        if self.fail_upload:
            raise OSError("simulated storage outage")
        self.objects[bucket, key] = Path(filename).read_bytes()
        self.metadata[bucket, key] = ExtraArgs["Metadata"]
        self.uploads.append((bucket, key))

    def head_object(self, Bucket, Key):
        return {
            "ContentLength": len(self.objects[Bucket, Key]),
            "Metadata": self.metadata.get((Bucket, Key), {}),
        }

    def get_object(self, Bucket, Key, **kwargs):
        if "IfMatch" in kwargs and kwargs["IfMatch"] != '"etag"':
            raise OSError("source changed")
        return {
            "Body": io.BytesIO(self.objects[Bucket, Key]),
            "ContentType": "image/webp",
        }

    def get_paginator(self, operation):
        assert operation == "list_objects_v2"
        return self

    def paginate(self, Bucket, Prefix=""):
        self.listings += 1
        etag = '"changed"' if self.change_etag and self.listings > 1 else '"etag"'
        return [
            {
                "Contents": [
                    {"Key": key, "Size": len(data), "ETag": etag}
                    for (bucket, key), data in self.objects.items()
                    if bucket == Bucket and key.startswith(Prefix)
                ]
            }
        ]


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "source"
        self.repo.mkdir()
        command(["git", "init", "-b", "main"], cwd=self.repo)
        command(["git", "config", "user.name", "Backup Test"], cwd=self.repo)
        command(["git", "config", "user.email", "backup@example.test"], cwd=self.repo)
        (self.repo / "app.txt").write_text("original application")
        command(["git", "add", "app.txt"], cwd=self.repo)
        command(["git", "commit", "-m", "fixture"], cwd=self.repo)
        command(["git", "branch", "feature/test"], cwd=self.repo)
        self.destination = settings(self.root)
        from dataclasses import replace

        self.source = replace(
            self.destination, bucket="media", access_key_id="media-key"
        )
        self.store = MemoryStore()
        self.store.objects["media", "pages/1.webp"] = b"page one"
        self.store.objects["media", "../unusual-key"] = b"opaque object name"
        self.identity = self.root / "identity"
        if shutil.which("age-keygen"):
            subprocess.run(
                ["age-keygen", "-o", str(self.identity)],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            self.recipient = command(["age-keygen", "-y", str(self.identity)])
        self.secret = self.root / "production.env"
        self.secret.write_text("DATABASE_PASSWORD=private-test-secret\n")

    def config(self):
        return {
            "repository": str(self.repo),
            "output_dir": str(self.root / "snapshots"),
            "config_files": {"production.env": str(self.secret)},
            "age_recipients": [self.recipient],
            "media_max_bytes": 1024,
            "media_max_objects": 10,
        }

    @unittest.skipUnless(
        shutil.which("age") and shutil.which("age-keygen"), "age required"
    )
    def test_full_backup_download_git_restore_and_authenticated_config_roundtrip(self):
        directory, receipt = build_snapshot(
            self.config(), self.destination, self.store, self.source, self.store
        )
        self.assertEqual(
            snapshot_receipt(self.destination, self.store, receipt["object_key"]),
            receipt,
        )
        # No secret plaintext is uploaded, even though it is present in the source env.
        for (bucket, _), value in self.store.objects.items():
            if bucket == self.destination.bucket:
                self.assertNotIn(b"private-test-secret", value)
        restored = self.root / "restored"
        manifest = restore_snapshot(self.destination, self.store, receipt, restored)
        self.assertEqual(len(manifest["git"]["refs"]), 2)
        self.assertTrue((restored / "verified.json").is_file())
        from dataclasses import replace

        target = replace(self.source, bucket="restored-media")
        restore_media(restored, target, self.store)
        self.assertEqual(
            self.store.objects["restored-media", "pages/1.webp"], b"page one"
        )
        with self.assertRaisesRegex(RecoveryError, "separate"):
            restore_media(restored, self.source, self.store)
        decrypt_config(restored, self.identity, self.root / "config")
        self.assertEqual(
            (self.root / "config/production.env").read_bytes(), self.secret.read_bytes()
        )
        self.assertEqual(
            (self.root / "config/production.env").stat().st_mode & 0o777, 0o600
        )
        self.assertTrue((directory / "receipt.json").is_file())
        with self.assertRaises(FileExistsError):
            restore_snapshot(self.destination, self.store, receipt, restored)

    @unittest.skipUnless(
        shutil.which("age") and shutil.which("age-keygen"), "age required"
    )
    def test_failed_upload_publishes_no_snapshot_manifest(self):
        self.store.fail_upload = True
        with self.assertRaises(OSError):
            build_snapshot(
                self.config(), self.destination, self.store, self.source, self.store
            )
        self.assertFalse(any("/snapshots/" in key for _, key in self.store.objects))

    @unittest.skipUnless(
        shutil.which("age") and shutil.which("age-keygen"), "age required"
    )
    def test_corrupted_blob_is_rejected_before_git_restore(self):
        _, receipt = build_snapshot(
            self.config(), self.destination, self.store, self.source, self.store
        )
        manifest = json.loads(
            self.store.objects[self.destination.bucket, receipt["object_key"]]
        )
        record = manifest["artifacts"][0]
        self.store.objects[self.destination.bucket, record["object_key"]] = b"corrupt"
        output = self.root / "bad"
        with self.assertRaises(OffsiteBackupError):
            restore_snapshot(self.destination, self.store, receipt, output)
        self.assertFalse((output / "verified.json").exists())
        self.assertFalse((output / record["path"]).exists())

    @unittest.skipUnless(
        shutil.which("age") and shutil.which("age-keygen"), "age required"
    )
    def test_tampered_ciphertext_writes_no_plaintext(self):
        snapshot = self.root / "encrypted"
        snapshot.mkdir()
        encrypted = snapshot / "configuration.tar.age"
        encrypt_config(
            {"production.env": str(self.secret)}, [self.recipient], encrypted
        )
        data = bytearray(encrypted.read_bytes())
        data[-1] ^= 1
        encrypted.write_bytes(data)
        with self.assertRaises(RecoveryError):
            decrypt_config(snapshot, self.identity, self.root / "plaintext")
        self.assertFalse((self.root / "plaintext").exists())

    def test_media_changes_and_budgets_abort_snapshot(self):
        output = self.root / "media-test"
        output.mkdir()
        self.store.change_etag = True
        with self.assertRaisesRegex(RecoveryError, "inventory changed"):
            capture_media(
                self.source, self.store, output, max_bytes=1024, max_objects=10
            )
        output = self.root / "limited"
        output.mkdir()
        with self.assertRaisesRegex(RecoveryError, "budget"):
            capture_media(self.source, self.store, output, max_bytes=1, max_objects=10)

    def test_git_bundle_restores_all_branches_and_tags(self):
        command(["git", "tag", "v0.1.0"], cwd=self.repo)
        output = self.root / "git-backup"
        output.mkdir()
        info = capture_git(self.repo, output)
        clone = self.root / "clone.git"
        command(
            ["git", "clone", "--mirror", str(output / "repository.bundle"), str(clone)]
        )
        self.assertEqual(
            command(["git", "show-ref"], cwd=clone).splitlines(), info["refs"]
        )

    def test_lfs_history_is_rejected(self):
        (self.repo / ".gitattributes").write_text(
            "*.bin filter=lfs diff=lfs merge=lfs -text\n"
        )
        command(["git", "add", ".gitattributes"], cwd=self.repo)
        command(["git", "commit", "-m", "LFS fixture"], cwd=self.repo)
        output = self.root / "lfs"
        output.mkdir()
        with self.assertRaisesRegex(RecoveryError, "Git LFS"):
            capture_git(self.repo, output)

    def test_release_tag_cannot_be_moved_and_manifest_records_digest(self):
        image = "web=registry/web@sha256:" + "a" * 64
        output = self.root / "release.json"
        release_manifest(self.repo, "v1.0.0", [image], output)
        self.assertEqual(
            json.loads(output.read_text())["images"]["web"], image.split("=", 1)[1]
        )
        (self.repo / "app.txt").write_text("next version")
        command(["git", "commit", "-am", "next"], cwd=self.repo)
        with self.assertRaisesRegex(RecoveryError, "points elsewhere"):
            release_manifest(self.repo, "v1.0.0", [image], self.root / "another.json")

    def test_snapshot_namespace_cannot_escape(self):
        with self.assertRaisesRegex(RecoveryError, "outside"):
            restore_snapshot(
                self.destination,
                self.store,
                {"object_key": "other/secret"},
                self.root / "escape",
            )
        self.assertFalse((self.root / "escape").exists())

    def test_media_requires_separate_destination_and_credentials(self):
        values = {
            "MEDIA_OBJECT_STORAGE_ENDPOINT_URL": self.destination.endpoint_url,
            "MEDIA_OBJECT_STORAGE_BUCKET": self.destination.bucket,
            "MEDIA_OBJECT_STORAGE_ACCESS_KEY_ID": "media",
            "MEDIA_OBJECT_STORAGE_SECRET_ACCESS_KEY": "secret",
        }
        with self.assertRaisesRegex(RecoveryError, "buckets"):
            media_settings(values, self.destination)

    def test_scheduled_refresh_preserves_deleted_source_branches(self):
        from ops.recovery.scheduled import main as scheduled_main

        mirror = self.root / "mirror.git"
        command(["git", "clone", "--mirror", str(self.repo), str(mirror)])
        command(["git", "branch", "-D", "feature/test"], cwd=self.repo)
        command(["git", "branch", "feature/new"], cwd=self.repo)
        config = self.root / "schedule.json"
        config.write_text(json.dumps({"repository": str(mirror)}))
        with (
            patch("sys.argv", ["scheduled", "--config", str(config)]),
            patch("ops.recovery.scheduled.snapshot_main", return_value=0) as backup,
        ):
            self.assertEqual(scheduled_main(), 0)
            backup.assert_called_once()
        branches = command(["git", "branch", "--format=%(refname:short)"], cwd=mirror)
        self.assertIn("feature/test", branches)
        self.assertIn("feature/new", branches)

    @unittest.skipUnless(
        shutil.which("age") and shutil.which("age-keygen"), "age required"
    )
    def test_encrypted_archive_cannot_escape_output_directory(self):
        archive = io.BytesIO()
        with tarfile.open(fileobj=archive, mode="w") as tar:
            member = tarfile.TarInfo("../outside")
            member.size = 4
            tar.addfile(member, io.BytesIO(b"evil"))
        snapshot = self.root / "hostile"
        snapshot.mkdir()
        subprocess.run(
            [
                "age",
                "-r",
                self.recipient,
                "-o",
                str(snapshot / "configuration.tar.age"),
            ],
            input=archive.getvalue(),
            check=True,
            stderr=subprocess.DEVNULL,
        )
        with self.assertRaisesRegex(RecoveryError, "unsafe"):
            decrypt_config(snapshot, self.identity, self.root / "extracted")
        self.assertFalse((self.root / "outside").exists())
        self.assertFalse((self.root / "extracted").exists())

    @unittest.skipUnless(
        shutil.which("age") and shutil.which("age-keygen"), "age required"
    )
    def test_snapshot_manifest_cannot_write_outside_restore_directory(self):
        _, receipt = build_snapshot(
            self.config(), self.destination, self.store, self.source, self.store
        )
        manifest = json.loads(
            self.store.objects[self.destination.bucket, receipt["object_key"]]
        )
        manifest["artifacts"][0]["path"] = "../outside"
        payload = json.dumps(manifest).encode()
        self.store.objects[self.destination.bucket, receipt["object_key"]] = payload
        receipt = {
            **receipt,
            "size": len(payload),
            "sha256": hashlib.sha256(payload).hexdigest(),
        }
        with self.assertRaisesRegex(RecoveryError, "unsafe"):
            restore_snapshot(
                self.destination, self.store, receipt, self.root / "restore-unsafe"
            )
        self.assertFalse((self.root / "outside").exists())


if __name__ == "__main__":
    unittest.main()
