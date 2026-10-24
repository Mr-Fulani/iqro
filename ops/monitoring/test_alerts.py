from __future__ import annotations

import json
import os
import stat
import tempfile
import unittest
from datetime import UTC, datetime, timedelta
from pathlib import Path
from unittest import mock

from ops.monitoring import alerts, heartbeat

TOKEN = "123456:test-only-token"


class TelegramCredentialsTests(unittest.TestCase):
    def test_only_the_two_telegram_lines_are_read_from_the_backend_env_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            env_file = Path(directory) / ".env.production"
            env_file.write_text(
                "DATABASE_PASSWORD=never-read\n"
                f'TELEGRAM_BOT_TOKEN="{TOKEN}"\n'
                "# comment\n"
                "TELEGRAM_ALERT_CHAT_ID=-1001234\n",
                encoding="utf-8",
            )
            self.assertEqual(
                alerts.read_env_file(env_file),
                {"TELEGRAM_BOT_TOKEN": TOKEN, "TELEGRAM_ALERT_CHAT_ID": "-1001234"},
            )
            self.assertEqual(
                alerts.credentials({"UPTIME_TELEGRAM_ENV_FILE": str(env_file)}),
                (TOKEN, "-1001234"),
            )

    def test_environment_wins_and_missing_values_turn_alerts_off(self) -> None:
        environ = {"TELEGRAM_BOT_TOKEN": TOKEN, "TELEGRAM_ALERT_CHAT_ID": "-1"}
        self.assertEqual(alerts.credentials(environ), (TOKEN, "-1"))
        missing = {"UPTIME_TELEGRAM_ENV_FILE": "/nonexistent/.env"}
        self.assertIsNone(alerts.credentials(missing))
        with mock.patch.object(alerts, "_post") as post:
            self.assertFalse(alerts.send("text", missing))
        post.assert_not_called()

    def test_send_reports_telegram_answer_without_raising(self) -> None:
        environ = {"TELEGRAM_BOT_TOKEN": TOKEN, "TELEGRAM_ALERT_CHAT_ID": "-1"}
        with mock.patch.object(alerts, "_post", return_value=200) as post:
            self.assertTrue(alerts.send("<b>hi</b>", environ))
        token, payload, _timeout = post.call_args.args
        self.assertEqual(token, TOKEN)
        self.assertEqual(payload["chat_id"], "-1")
        self.assertEqual(payload["parse_mode"], "HTML")
        with mock.patch.object(alerts, "_post", return_value=None):
            self.assertFalse(alerts.send("hi", environ))


class ReportCheckTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        self.backups = root / "backups"
        self.backups.mkdir()
        self.state = root / "state"
        self.environ = {
            "STATE_DIRECTORY": str(self.state),
            "UPTIME_BACKUP_DIR": str(self.backups),
            "TELEGRAM_BOT_TOKEN": TOKEN,
            "TELEGRAM_ALERT_CHAT_ID": "-1",
        }
        self.now = datetime(2026, 10, 24, 12, tzinfo=UTC)

    def _report(self, ok: bool, minutes: int = 0) -> list[str]:
        with mock.patch.object(alerts, "send", return_value=True) as send:
            alerts.report_check(
                ok=ok,
                problem="" if ok else "latest PostgreSQL backup is stale",
                environ=self.environ,
                now=self.now + timedelta(minutes=minutes),
            )
        return [call.args[0] for call in send.call_args_list]

    def test_summary_for_the_admin_is_world_readable_and_secret_free(self) -> None:
        dump = self.backups / "quran_20261024T010000Z.dump"
        dump.write_bytes(b"dump")
        stamp = datetime(2026, 10, 24, 1, tzinfo=UTC).timestamp()
        os.utime(dump, (stamp, stamp))

        self._report(ok=True)

        status_path = self.state / "status.json"
        self.assertEqual(stat.S_IMODE(status_path.stat().st_mode), 0o644)
        status = json.loads(status_path.read_text())
        self.assertEqual(
            status,
            {
                "schema_version": 1,
                "checked_at": self.now.isoformat(),
                "ok": True,
                "problem": None,
                "last_backup_at": "2026-10-24T01:00:00+00:00",
            },
        )
        self.assertNotIn(TOKEN, status_path.read_text())
        self.assertEqual(
            stat.S_IMODE((self.state / "alert-state.json").stat().st_mode), 0o600
        )

    def test_failure_is_sent_once_then_every_six_hours_and_its_end_once(self) -> None:
        first = self._report(ok=False)
        self.assertEqual(len(first), 1)
        self.assertIn("Бэкап базы не прошёл или устарел", first[0])
        self.assertEqual(self._report(ok=False, minutes=5), [])
        self.assertEqual(self._report(ok=False, minutes=355), [])
        reminder = self._report(ok=False, minutes=361)
        self.assertEqual(len(reminder), 1)
        self.assertIn("всё ещё", reminder[0])
        recovered = self._report(ok=True, minutes=366)
        self.assertEqual(len(recovered), 1)
        self.assertIn("снова проходит", recovered[0])
        self.assertEqual(self._report(ok=True, minutes=371), [])
        status = json.loads((self.state / "status.json").read_text())
        self.assertTrue(status["ok"])

    def test_nothing_is_written_without_a_state_directory(self) -> None:
        del self.environ["STATE_DIRECTORY"]
        self.assertEqual(self._report(ok=False), [])
        self.assertFalse(self.state.exists())

    def test_problem_wording(self) -> None:
        self.assertEqual(
            alerts.describe_problem("public target failed: iqro.forum"),
            "Сайт или API не отвечают",
        )
        self.assertEqual(
            alerts.describe_problem("postgres offsite backup is missing, failed or stale"),
            "Бэкап базы не прошёл или устарел",
        )


class HeartbeatAlertTests(unittest.TestCase):
    def test_failed_backup_job_is_sent_even_without_heartbeat_settings(self) -> None:
        with (
            mock.patch.dict(os.environ, {"SERVICE_RESULT": "exit-code"}, clear=True),
            mock.patch.object(heartbeat, "report_job_failure") as job_failure,
            mock.patch("sys.stderr"),
        ):
            self.assertEqual(heartbeat.main(["--job-result", "postgres"]), 1)
        job_failure.assert_called_once_with("postgres")

    def test_successful_job_sends_nothing(self) -> None:
        with (
            mock.patch.dict(os.environ, {"SERVICE_RESULT": "success"}, clear=True),
            mock.patch.object(heartbeat, "report_job_failure") as job_failure,
        ):
            self.assertEqual(heartbeat.main(["--job-result", "postgres"]), 0)
        job_failure.assert_not_called()

    def test_job_failure_message_names_the_unit(self) -> None:
        environ = {
            "TELEGRAM_BOT_TOKEN": TOKEN,
            "TELEGRAM_ALERT_CHAT_ID": "-1",
            "UPTIME_BACKUP_ENVIRONMENT": "production",
        }
        with mock.patch.object(alerts, "_post", return_value=200) as post:
            self.assertTrue(alerts.report_job_failure("postgres", environ))
        text = post.call_args.args[1]["text"]
        self.assertIn("Бэкап базы не прошёл", text)
        self.assertIn("journalctl -u quran-backup@production", text)

    def test_heartbeat_runs_without_a_dead_man_url(self) -> None:
        settings = heartbeat.load_settings({"SITE_URL": "https://iqro.example.test"})
        self.assertIsNone(settings.success_url)
        with (
            mock.patch.object(heartbeat, "check_target"),
            mock.patch.object(heartbeat, "check_backup_freshness"),
            mock.patch.object(heartbeat, "ping") as ping,
        ):
            heartbeat.run(settings)
        ping.assert_not_called()

    def test_heartbeat_reports_each_run(self) -> None:
        environ = {"SITE_URL": "https://iqro.example.test"}
        with (
            mock.patch.dict(os.environ, environ, clear=True),
            mock.patch.object(heartbeat, "run", side_effect=heartbeat.HeartbeatError("x")),
            mock.patch.object(heartbeat, "report_check") as report,
            mock.patch("sys.stderr"),
        ):
            self.assertEqual(heartbeat.main([]), 1)
        report.assert_called_once_with(ok=False, problem="x")
        with (
            mock.patch.dict(os.environ, environ, clear=True),
            mock.patch.object(heartbeat, "run"),
            mock.patch.object(heartbeat, "report_check") as report,
            mock.patch("sys.stdout"),
        ):
            self.assertEqual(heartbeat.main([]), 0)
        report.assert_called_once_with(ok=True)


if __name__ == "__main__":
    unittest.main()
