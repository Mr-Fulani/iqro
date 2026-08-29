from __future__ import annotations

import os
import tempfile
import unittest
from datetime import UTC, datetime
from pathlib import Path

from ops.monitoring.heartbeat import (
    HeartbeatError,
    check_backup_freshness,
    load_settings,
)


class HeartbeatTests(unittest.TestCase):
    def test_settings_derive_public_targets_without_exposing_heartbeat_path(
        self,
    ) -> None:
        settings = load_settings(
            {
                "SITE_URL": "https://staging.example.test",
                "UPTIME_HEARTBEAT_URL": "https://heartbeat.example.test/secret-token",
                "UPTIME_HEARTBEAT_FAILURE_URL": (
                    "https://heartbeat.example.test/secret-token/fail"
                ),
            }
        )
        self.assertEqual(
            settings.targets,
            (
                "https://staging.example.test/",
                "https://staging.example.test/api/v1/health/ready",
            ),
        )

    def test_settings_reject_insecure_heartbeat_url(self) -> None:
        with self.assertRaisesRegex(HeartbeatError, "must be an HTTPS URL"):
            load_settings(
                {
                    "SITE_URL": "https://staging.example.test",
                    "UPTIME_HEARTBEAT_URL": "http://heartbeat.example.test/token",
                }
            )

    def test_settings_reject_control_characters_in_secret_url(self) -> None:
        with self.assertRaisesRegex(HeartbeatError, "control characters"):
            load_settings(
                {
                    "SITE_URL": "https://staging.example.test",
                    "UPTIME_HEARTBEAT_URL": (
                        "https://heartbeat.example.test/token\nINJECTED=true"
                    ),
                }
            )

    def test_backup_freshness_requires_dump_and_checksum(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            backup = directory / "quran_20260829T010000Z.dump"
            backup.write_bytes(b"backup")
            timestamp = datetime(2026, 8, 29, 1, tzinfo=UTC).timestamp()
            os.utime(backup, (timestamp, timestamp))
            now = datetime(2026, 8, 29, 2, tzinfo=UTC)

            with self.assertRaisesRegex(HeartbeatError, "has no checksum"):
                check_backup_freshness(directory, max_age_seconds=7200, now=now)

            backup.with_name(f"{backup.name}.sha256").write_text(
                "checksum", encoding="ascii"
            )
            self.assertEqual(
                check_backup_freshness(directory, max_age_seconds=7200, now=now),
                backup,
            )
            with self.assertRaisesRegex(HeartbeatError, "is stale"):
                check_backup_freshness(directory, max_age_seconds=1800, now=now)


if __name__ == "__main__":
    unittest.main()
