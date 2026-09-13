from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent


class SystemdUnitTests(unittest.TestCase):
    def test_backup_timer_is_persistent_and_service_is_locked(self) -> None:
        service = (ROOT / "quran-backup@.service").read_text(encoding="utf-8")
        timer = (ROOT / "quran-backup@.timer").read_text(encoding="utf-8")
        self.assertIn("/usr/bin/flock", service)
        self.assertIn("%i-backup-offsite", service)
        self.assertNotIn("/bin/sh", service)
        self.assertIn("Persistent=true", timer)
        self.assertIn("RandomizedDelaySec=15m", timer)

    def test_heartbeat_uses_secret_environment_file_and_dead_man_interval(self) -> None:
        service = (ROOT / "quran-heartbeat@.service").read_text(encoding="utf-8")
        timer = (ROOT / "quran-heartbeat@.timer").read_text(encoding="utf-8")
        self.assertIn("EnvironmentFile=/etc/iqro/%i-heartbeat.env", service)
        self.assertIn("ProtectSystem=strict", service)
        self.assertIn("OnUnitActiveSec=5m", timer)
        self.assertIn("Persistent=true", timer)

    def test_both_backup_jobs_use_existing_failure_monitor(self) -> None:
        for service_name, component in (
            ("quran-backup@.service", "postgres"),
            ("quran-recovery@.service", "recovery"),
        ):
            service = (ROOT / service_name).read_text()
            self.assertIn("EnvironmentFile=-/etc/iqro/%i-heartbeat.env", service)
            self.assertIn(f"ops.monitoring.heartbeat --job-result {component}", service)
            self.assertIn("/usr/bin/flock", service)
        timer = (ROOT / "quran-recovery@.timer").read_text()
        self.assertIn("Persistent=true", timer)
        self.assertIn("quran-recovery@.service", (ROOT / "install.sh").read_text())


if __name__ == "__main__":
    unittest.main()
