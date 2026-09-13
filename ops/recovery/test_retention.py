from __future__ import annotations

import hashlib
import io
import json
import tempfile
import unittest
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from pathlib import Path

from ops.monitoring.backup_status import write_status, write_upload_receipt
from ops.postgres.offsite import OffsiteBackupError
from ops.postgres.test_offsite import settings
from ops.recovery.retention import (
    Copy,
    RetentionError,
    apply_plan,
    digest,
    keep_copies,
    make_plan,
)
from ops.recovery.snapshot import write_json


class Store:
    def __init__(self):
        self.data = {}
        self.deleted = []
        self.fail_delete = False

    def put(self, key, data):
        self.data[key] = data

    def head_object(self, Bucket, Key):
        data = self.data[Key]
        checksum = hashlib.sha256(data).hexdigest()
        return {
            "ContentLength": len(data),
            "Metadata": {"sha256": checksum},
            "ETag": checksum,
            "LastModified": datetime.now(UTC),
        }

    def get_object(self, Bucket, Key):
        return {"Body": io.BytesIO(self.data[Key])}

    def get_paginator(self, operation):
        assert operation == "list_objects_v2"
        return self

    def paginate(self, Bucket, Prefix):
        items = [
            {"Key": key, "Size": len(data), "ETag": hashlib.sha256(data).hexdigest()}
            for key, data in sorted(self.data.items())
            if key.startswith(Prefix)
        ]
        # Exercise pagination, including shared references across pages.
        return [{"Contents": items[:3]}, {"Contents": items[3:]}]

    def delete_objects(self, Bucket, Delete):
        if self.fail_delete:
            return {"Errors": [{"Code": "AccessDenied"}]}
        for item in Delete["Objects"]:
            self.deleted.append(item["Key"])
            del self.data[item["Key"]]
        return {}


class PolicyTests(unittest.TestCase):
    def test_three_latest_per_local_type(self):
        now = datetime.now(UTC)
        copies = [
            Copy(f"{group}/{i}", now - timedelta(hours=i), group, ())
            for group in ("postgres:one", "postgres:two", "recovery")
            for i in range(8)
        ]
        keep = keep_copies(copies, local=True)
        self.assertEqual(
            keep,
            {
                f"{group}/{i}"
                for group in ("postgres:one", "postgres:two", "recovery")
                for i in range(3)
            },
        )

    def test_daily_and_weekly_are_calendar_buckets_not_last_eleven_files(self):
        now = datetime(2026, 1, 10, 12, tzinfo=UTC)
        copies = [
            Copy(str(i), now - timedelta(hours=12 * i), "recovery", ())
            for i in range(100)
        ]
        keep = keep_copies(copies, local=False)
        chosen = [copy for copy in copies if copy.identifier in keep]
        self.assertLessEqual(len(keep), 11)
        self.assertEqual(len({copy.timestamp.isocalendar()[:2] for copy in chosen}), 4)
        self.assertIn("0", keep)
        self.assertNotIn("1", keep)  # Same day, older copy.
        for day in range(7):
            self.assertIn(str(day * 2), keep)

    def test_fewer_copies_are_never_discarded_locally(self):
        now = datetime.now(UTC)
        self.assertEqual(
            keep_copies([Copy("one", now, "recovery", ())], local=True), {"one"}
        )


class RetentionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.backups = self.root / "backups"
        self.recovery = self.backups / "recovery"
        self.status = self.backups / "status"
        self.recovery.mkdir(parents=True)
        self.status.mkdir()
        self.config = settings(self.backups)
        self.store = Store()
        self.now = datetime.now(UTC).replace(microsecond=0)
        for component in ("postgres", "recovery"):
            write_status(
                self.status / f"{component}.json",
                component=component,
                environment=self.config.environment,
                state="success",
                source_time=self.now.isoformat(),
            )
        self.dumps = []
        self.snapshots = []
        for index in range(35):
            time = self.now - timedelta(days=index)
            self.dumps.append(self.dump(time))
            self.snapshots.append(self.snapshot(time, index))
        self.store.put(
            self.config.latest_manifest_key,
            json.dumps({"object_key": self.dumps[0]}).encode(),
        )
        self.orphan = self.config.root_prefix + "/recovery/blobs/" + "f" * 64
        self.store.put(self.orphan, b"unfinished upload")
        self.partial = self.recovery / (
            self.now.strftime("%Y%m%dT%H%M%SZ") + "-" + "e" * 32
        )
        self.partial.mkdir()
        (self.partial / "configuration.tar.age").write_bytes(
            b"incomplete encrypted attempt"
        )

    def dump(self, time):
        name = "quran_" + time.strftime("%Y%m%dT%H%M%SZ") + ".dump"
        data = ("database " + time.isoformat()).encode()
        checksum = hashlib.sha256(data).hexdigest()
        path = self.backups / name
        path.write_bytes(data)
        sidecar = f"{checksum}  {name}\n".encode()
        path.with_name(name + ".sha256").write_bytes(sidecar)
        key = self.config.root_prefix + "/" + name
        self.store.put(key, data)
        self.store.put(key + ".sha256", sidecar)
        write_upload_receipt(
            self.status,
            {
                "filename": name,
                "environment": self.config.environment,
                "object_key": key,
                "checksum_key": key + ".sha256",
                "sha256": checksum,
                "size": len(data),
            },
        )
        return key

    def snapshot(self, time, index):
        identifier = time.strftime("%Y%m%dT%H%M%SZ") + "-" + f"{index:032x}"
        directory = self.recovery / identifier
        directory.mkdir()
        artifacts = []
        # repository.bundle is shared by retained and obsolete snapshots.
        for name, data in {
            "repository.bundle": b"shared git history",
            "media.json": b"media manifest",
            "configuration.tar.age": f"encrypted config {index}".encode(),
        }.items():
            checksum = hashlib.sha256(data).hexdigest()
            key = self.config.root_prefix + "/recovery/blobs/" + checksum
            (directory / name).write_bytes(data)
            self.store.put(key, data)
            artifacts.append(
                {"path": name, "object_key": key, "sha256": checksum, "size": len(data)}
            )
        manifest = {
            "schema_version": 1,
            "snapshot_id": identifier,
            "environment": self.config.environment,
            "started_at": time.isoformat(),
            "artifacts": artifacts,
        }
        write_json(directory / "snapshot.json", manifest)
        payload = (directory / "snapshot.json").read_bytes()
        key = self.config.root_prefix + "/recovery/snapshots/" + identifier + ".json"
        self.store.put(key, payload)
        write_json(
            directory / "receipt.json",
            {
                "object_key": key,
                "size": len(payload),
                "sha256": hashlib.sha256(payload).hexdigest(),
            },
        )
        return key

    def plan(self):
        return make_plan(
            self.config, self.store, recovery_dir=self.recovery, status_dir=self.status
        )

    def test_preview_preserves_shared_blobs_partial_uploads_and_latest_pointer(self):
        plan = self.plan()
        self.assertEqual(len(plan["keep_local"]), 6)
        remote_deleted = {
            item["key"] for item in plan["delete"] if item["kind"] == "remote_object"
        }
        shared = (
            self.config.root_prefix
            + "/recovery/blobs/"
            + hashlib.sha256(b"shared git history").hexdigest()
        )
        self.assertNotIn(shared, remote_deleted)
        self.assertNotIn(self.orphan, remote_deleted)
        self.assertNotIn(self.config.latest_manifest_key, remote_deleted)
        self.assertNotIn(self.dumps[0], remote_deleted)
        self.assertIn(str(self.partial.resolve()), plan["ignored"])
        self.assertEqual(self.store.deleted, [])
        self.assertEqual(len(list(self.backups.glob("*.dump"))), 35)

    def test_only_exact_approved_plan_is_applied(self):
        plan = self.plan()
        with self.assertRaisesRegex(RetentionError, "approval"):
            apply_plan(self.config, self.store, plan, "0" * 64)
        self.assertEqual(self.store.deleted, [])
        apply_plan(self.config, self.store, plan, digest(plan))
        self.assertEqual(len(list(self.backups.glob("*.dump"))), 3)
        self.assertEqual(
            len(list(self.status.joinpath("postgres-uploads").glob("*.json"))), 3
        )
        self.assertEqual(
            len(list(self.recovery.iterdir())), 4
        )  # Three complete plus one partial.
        self.assertIn(self.orphan, self.store.data)
        for key in plan["keep_remote"]:
            self.assertIn(key, self.store.data)
        # Replanning is idempotent; references still resolve after shared-blob GC.
        self.assertEqual(self.plan()["delete"], [])

    def test_new_snapshot_invalidates_approval_before_any_deletion(self):
        plan = self.plan()
        self.snapshot(self.now + timedelta(seconds=1), 99)
        with self.assertRaisesRegex(RetentionError, "changed"):
            apply_plan(self.config, self.store, plan, digest(plan))
        self.assertEqual(self.store.deleted, [])
        self.assertEqual(len(list(self.backups.glob("*.dump"))), 35)

    def test_failed_job_blocks_rotation(self):
        write_status(
            self.status / "recovery.json",
            component="recovery",
            environment=self.config.environment,
            state="failed",
        )
        with self.assertRaises(ValueError):
            self.plan()
        self.assertEqual(self.store.deleted, [])

    def test_missing_blob_blocks_all_retention(self):
        key = self.snapshots[-1]
        manifest = json.loads(self.store.data[key])
        del self.store.data[manifest["artifacts"][-1]["object_key"]]
        with self.assertRaisesRegex(RetentionError, "missing"):
            self.plan()
        self.assertEqual(self.store.deleted, [])

    def test_local_file_changed_after_approval_blocks_all_deletions(self):
        plan = self.plan()
        name = self.dumps[-1].rsplit("/", 1)[-1]
        (self.backups / name).write_bytes(b"modified after review")
        with self.assertRaises(OffsiteBackupError):
            apply_plan(self.config, self.store, plan, digest(plan))
        self.assertEqual(self.store.deleted, [])
        self.assertEqual(len(list(self.backups.glob("*.dump"))), 35)

    def test_unknown_manifest_version_blocks_garbage_collection(self):
        key = self.snapshots[-1]
        manifest = json.loads(self.store.data[key])
        manifest["schema_version"] = 99
        self.store.put(key, json.dumps(manifest).encode())
        with self.assertRaisesRegex(RetentionError, "invalid snapshot"):
            self.plan()
        self.assertEqual(self.store.deleted, [])

    def test_storage_scope_cannot_change_after_approval(self):
        plan = self.plan()
        with self.assertRaisesRegex(RetentionError, "configuration"):
            apply_plan(
                replace(self.config, bucket="other-bucket"),
                self.store,
                plan,
                digest(plan),
            )
        self.assertEqual(self.store.deleted, [])

    def test_storage_delete_failure_stops_further_deletions(self):
        plan = self.plan()
        self.store.fail_delete = True
        with self.assertRaisesRegex(RetentionError, "deletion failed"):
            apply_plan(self.config, self.store, plan, digest(plan))
        self.assertEqual(self.store.deleted, [])
        self.assertIn(self.snapshots[0], self.store.data)


if __name__ == "__main__":
    unittest.main()
