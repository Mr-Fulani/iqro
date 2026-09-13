from __future__ import annotations

import json
import tempfile
import unittest
from datetime import UTC, datetime, timedelta
from pathlib import Path
from unittest.mock import patch

from ops.monitoring.backup_status import check_status, write_status
from ops.monitoring.heartbeat import HeartbeatError, load_settings, main, run


class BackupStatusTests(unittest.TestCase):
    def test_recent_upload_of_old_source_is_still_stale(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "postgres.json"
            write_status(
                path,
                component="postgres",
                environment="production",
                state="success",
                source_time=(datetime.now(UTC) - timedelta(days=2)).isoformat(),
            )
            with self.assertRaisesRegex(ValueError, "stale"):
                check_status(
                    path,
                    component="postgres",
                    environment="production",
                    max_age_seconds=93600,
                )

    def test_failed_malformed_and_wrong_environment_receipts_fail_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "postgres.json"
            for state in ("failed", "running", "success"):
                write_status(
                    path,
                    component="postgres",
                    environment="staging",
                    state=state,
                    source_time=datetime.now(UTC).isoformat(),
                )
                with self.assertRaises(ValueError):
                    check_status(
                        path,
                        component="postgres",
                        environment="production",
                        max_age_seconds=93600,
                    )
            path.write_text("invalid")
            with self.assertRaises(ValueError):
                check_status(
                    path,
                    component="postgres",
                    environment="production",
                    max_age_seconds=93600,
                )

    def test_existing_monitor_blocks_success_when_offsite_is_missing(self):
        with tempfile.TemporaryDirectory() as temporary:
            settings = load_settings(
                {
                    "SITE_URL": "https://example.test",
                    "UPTIME_HEARTBEAT_URL": "https://monitor.test/secret",
                    "UPTIME_BACKUP_STATUS_DIR": temporary,
                }
            )
            with (
                patch("ops.monitoring.heartbeat.check_target"),
                patch("ops.monitoring.heartbeat.check_backup_freshness"),
                patch("ops.monitoring.heartbeat.ping") as ping,
            ):
                with self.assertRaisesRegex(HeartbeatError, "postgres"):
                    run(settings)
                ping.assert_not_called()
                for component in ("postgres", "recovery"):
                    write_status(
                        Path(temporary) / f"{component}.json",
                        component=component,
                        environment="production",
                        state="success",
                        source_time=datetime.now(UTC).isoformat(),
                    )
                run(settings)
                ping.assert_called_once()

    def test_job_failure_uses_same_failure_channel_and_marks_receipt(self):
        with tempfile.TemporaryDirectory() as temporary:
            values = {
                "SITE_URL": "https://example.test",
                "UPTIME_HEARTBEAT_URL": "https://monitor.test/success",
                "UPTIME_HEARTBEAT_FAILURE_URL": "https://monitor.test/failure",
                "UPTIME_BACKUP_STATUS_DIR": temporary,
                "SERVICE_RESULT": "exit-code",
            }
            with (
                patch.dict("os.environ", values, clear=True),
                patch("ops.monitoring.heartbeat.ping") as ping,
            ):
                self.assertEqual(main(["--job-result", "postgres"]), 1)
                ping.assert_called_once_with(
                    values["UPTIME_HEARTBEAT_FAILURE_URL"], timeout=10
                )
            self.assertEqual(
                json.loads((Path(temporary) / "postgres.json").read_text())["state"],
                "failed",
            )


if __name__ == "__main__":
    unittest.main()
