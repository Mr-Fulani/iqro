import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, Mock

from ops import dev


def missing_status():
    return {
        "ready": False,
        "checks": dict.fromkeys(("canonical", "mushaf", "dua", "translations", "tafsirs", "audio", "mobile"), False),
        "missing_dua": ["hisn_al_muslim_full_v1.json", "supplications_from_quran_jmapps_v1.json"],
        "configured_translations": [20, 45, 77], "missing_translations": [20, 45, 77],
        "configured_tafsirs": [16, 169, 170], "missing_tafsirs": [16, 169, 170],
    }


def ready_status():
    result = missing_status()
    result["ready"] = True
    result["checks"] = dict.fromkeys(result["checks"], True)
    for key in ("missing_dua", "missing_translations", "missing_tafsirs"):
        result[key] = []
    return result


class LocalWorkspaceTests(unittest.TestCase):
    def test_up_prepares_data_after_services_and_never_reports_success_on_failure(self):
        calls = []
        with patch.object(dev, "init"), patch.object(dev, "backup_before_migration"), \
             patch.object(dev, "compose", side_effect=lambda *args: calls.append(args)), \
             patch.object(dev, "data", side_effect=lambda **kw: calls.append(("data", kw))), \
             patch("builtins.print") as output:
            dev.up()
        self.assertEqual(calls[-2], ("data", {"web_only": False, "build": True}))
        self.assertIn("backend", calls[-3])
        self.assertEqual(calls[-1], ("up", "--detach", "--wait", "web", "worker", "beat"))
        self.assertTrue(any("are ready" in str(call) for call in output.call_args_list))
        with patch.object(dev, "init"), patch.object(dev, "backup_before_migration"), \
             patch.object(dev, "compose"), \
             patch.object(dev, "data", side_effect=ValueError("source unavailable")), \
             patch("builtins.print") as output, self.assertRaises(ValueError):
            dev.up()
        self.assertFalse(any("are ready" in str(call) for call in output.call_args_list))

    def test_ready_workspace_starts_without_credentials_downloads_or_rendering(self):
        with patch.object(dev, "data_status", return_value=ready_status()), \
             patch.object(dev, "require_credentials") as credentials, \
             patch.object(dev, "manage") as manage, patch.object(dev, "compose") as compose:
            dev.data()
        credentials.assert_not_called()
        manage.assert_not_called()
        compose.assert_not_called()

    def test_prebuilt_images_still_require_data_and_gate_web_start(self):
        with patch.object(dev, "init"), patch.object(dev, "backup_before_migration"), \
             patch.object(dev, "compose") as compose, patch.object(dev, "data") as data:
            dev.up(build=False)
        self.assertFalse(any(call.args[0] == "build" for call in compose.call_args_list))
        data.assert_called_once_with(web_only=False, build=False)
        with patch.object(dev, "init"), patch.object(dev, "backup_before_migration"), \
             patch.object(dev, "compose") as compose, \
             patch.object(dev, "data", side_effect=ValueError("missing credentials")), \
             self.assertRaises(ValueError):
            dev.up(build=False)
        self.assertFalse(any("web" in call.args for call in compose.call_args_list))

    def test_missing_credentials_prevent_imports_and_rendering(self):
        with patch.object(dev, "data_status", return_value=missing_status()), \
             patch.object(dev, "require_credentials", side_effect=ValueError("QF_CLIENT_SECRET")), \
             patch.object(dev, "manage") as manage, patch.object(dev, "compose") as compose, \
             self.assertRaisesRegex(ValueError, "QF_CLIENT_SECRET"):
            dev.data()
        manage.assert_not_called()
        compose.assert_not_called()

    def test_missing_one_translation_preserves_existing_corpus_sources_and_media(self):
        status = ready_status()
        status.update(ready=False, missing_translations=[45])
        status["checks"]["translations"] = False
        with patch.object(dev, "data_status", side_effect=[status, ready_status()]), \
             patch.object(dev, "require_credentials"), patch.object(dev, "manage") as manage, \
             patch.object(dev, "compose") as compose, patch.object(dev, "download") as download:
            dev.data()
        self.assertEqual([call.args for call in manage.call_args_list], [
            ("sync_quran_foundation_translations", "--resource-id", "45"),
            ("dev_data_status", "--require-mobile"),
        ])
        compose.assert_not_called()
        download.assert_not_called()

    def test_explicit_refresh_checks_all_configured_resources_and_preserves_corpus(self):
        with patch.object(dev, "data_status", return_value=ready_status()), \
             patch.object(dev, "require_credentials"), patch.object(dev, "manage") as manage, \
             patch.object(dev, "compose") as compose, patch.object(dev, "download") as download:
            dev.data(refresh=True)
        self.assertEqual([call.args for call in manage.call_args_list], [
            ("sync_quran_foundation_mushafs", "--force"),
            *[("sync_quran_foundation_translations", "--resource-id", str(n)) for n in (20, 45, 77)],
            *[("sync_quran_foundation_tafsirs", "--resource-id", str(n)) for n in (16, 169, 170)],
            ("dev_data_status", "--require-mobile"),
        ])
        compose.assert_not_called()
        download.assert_not_called()

    def test_retry_after_provider_failure_only_fetches_missing_resource(self):
        state = ready_status()
        state.update(ready=False, missing_translations=[20, 45])
        state["checks"]["translations"] = False
        imported = []
        def manage(*args, **kwargs):
            if args[0] == "sync_quran_foundation_translations":
                imported.append(int(args[-1]))
                if args[-1] == "45":
                    raise dev.subprocess.CalledProcessError(1, ["sync"])
        with patch.object(dev, "data_status", return_value=state), \
             patch.object(dev, "require_credentials"), patch.object(dev, "manage", side_effect=manage), \
             self.assertRaises(dev.subprocess.CalledProcessError):
            dev.data()
        self.assertEqual(imported, [20, 45])
        state["missing_translations"] = [45]
        with patch.object(dev, "data_status", side_effect=[state, ready_status()]), \
             patch.object(dev, "require_credentials"), patch.object(dev, "manage") as resumed:
            dev.data()
        self.assertEqual(resumed.call_args_list[0].args, ("sync_quran_foundation_translations", "--resource-id", "45"))
        self.assertEqual(len(resumed.call_args_list), 2)

    def test_setup_lock_blocks_concurrent_import_and_releases_after_failure(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(dev, "WORK", Path(temporary)):
            with self.assertRaisesRegex(ValueError, "interrupted"), dev.setup_lock():
                with self.assertRaisesRegex(ValueError, "already running"), dev.setup_lock():
                    self.fail("A second setup acquired the same lock")
                raise ValueError("interrupted")
            with dev.setup_lock():
                self.assertTrue((dev.WORK / "setup.lock").exists())

    def test_failed_backup_verification_prevents_service_start(self):
        with tempfile.TemporaryDirectory() as temporary, \
             patch.object(dev, "WORK", Path(temporary)), patch.object(dev, "init"), \
             patch.object(dev.subprocess, "run", return_value=Mock(returncode=1)):
            calls = []
            def compose(*args, **kwargs):
                calls.append(args)
                if args[:4] == ("exec", "-T", "postgres", "pg_restore"):
                    raise dev.subprocess.CalledProcessError(1, ["pg_restore"])
                if "stdout" in kwargs:
                    kwargs["stdout"].write(b"verification-test-dump")
                return Mock(stdout=b"django_migrations")
            with patch.object(dev, "compose", side_effect=compose), \
                 self.assertRaises(dev.subprocess.CalledProcessError):
                dev.up()
            self.assertFalse(any("backend" in call and call[0] == "up" for call in calls))
            backups = list((dev.WORK / "backups").glob("*.dump"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_bytes(), b"verification-test-dump")
            self.assertEqual(backups[0].stat().st_mode & 0o777, 0o600)

    def test_no_backup_is_needed_when_migrations_are_current(self):
        with patch.object(dev.subprocess, "run", return_value=Mock(returncode=0)), \
             patch.object(dev, "compose") as compose:
            dev.backup_before_migration()
        compose.assert_not_called()

    def test_init_is_private_and_preserves_existing_configuration(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "backend.env"
            with patch.object(dev, "ENV_FILE", target):
                dev.init()
                original = target.read_bytes()
                self.assertEqual(target.stat().st_mode & 0o777, 0o600)
                self.assertIn(b"QF_CLIENT_ID=\n", original)
                self.assertNotIn(b"replace-with", original)
                dev.init()
                self.assertEqual(target.read_bytes(), original)

    def test_credentials_check_never_returns_secret_values(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "env"
            target.write_text("QF_CLIENT_ID=public\nQF_CLIENT_SECRET=\n")
            with patch.object(dev, "ENV_FILE", target), self.assertRaisesRegex(ValueError, "QF_CLIENT_SECRET"):
                dev.require_credentials()

    def test_download_verifies_content_and_reuses_it_without_network(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "corpus.json"
            data = b"verified corpus"
            target.write_bytes(data)
            checksum = hashlib.sha256(data).hexdigest()
            with patch.object(dev.urllib.request, "urlopen", side_effect=AssertionError("network")):
                dev.download("https://example.test", checksum, target, max_bytes=100)
                with self.assertRaisesRegex(ValueError, "checksum"):
                    dev.download("https://example.test", "0" * 64, target, max_bytes=100)
            self.assertEqual(target.read_bytes(), data)

    def test_write_once_rejects_changed_content(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "asset"
            dev.write_once(target, b"first")
            dev.write_once(target, b"first")
            with self.assertRaisesRegex(ValueError, "preserved"):
                dev.write_once(target, b"second")
            self.assertEqual(target.read_bytes(), b"first")

    def test_data_import_order_and_web_only_do_not_require_private_artifacts(self):
        calls = []
        def manage(*args, **kwargs):
            calls.append(args)
            return Mock(stdout=b"")
        with patch.object(dev, "require_credentials"), patch.object(dev, "download"), \
             patch.object(dev, "data_status", return_value=missing_status()), \
             patch.object(dev, "manage", side_effect=manage), patch.object(dev, "compose") as compose:
            dev.data(web_only=True)
        self.assertEqual([args[0] for args in calls], [
            "import_dua_catalog", "import_dua_catalog", "sync_quran_foundation_mushafs", "import_quran_corpus",
            *["sync_quran_foundation_translations"] * 3,
            *["sync_quran_foundation_tafsirs"] * 3,
            "sync_quran_foundation_audio", "dev_data_status",
        ])
        compose.assert_not_called()

    def test_source_lock_is_local_and_binds_exported_bytes(self):
        data = {"source_id": 5, "pages_count": 604, "pages": [{}] * 604,
                "source_checksum_sha256": "a" * 64}
        raw = json.dumps(data).encode()
        with tempfile.TemporaryDirectory() as temporary, patch.object(dev, "WORK", Path(temporary)), \
             patch.object(dev, "download"):
            directory = dev.prepare_source(raw)
            lock = json.loads((directory / "source/lock.json").read_bytes())
            self.assertEqual(lock["publication_scope"], "local")
            self.assertEqual(lock["snapshot_sha256"], hashlib.sha256(raw).hexdigest())
            self.assertEqual((directory / "source/snapshot.json").read_bytes(), raw)
            self.assertNotIn("staging", str(dev.render_directory(directory)))

    def test_failed_source_sync_prevents_claiming_mobile_readiness(self):
        calls = []
        def manage(*args, **kwargs):
            calls.append(args)
            if args[0] == "sync_quran_foundation_mushafs":
                raise dev.subprocess.CalledProcessError(1, ["source sync"])
            return Mock(stdout=b"")
        with patch.object(dev, "require_credentials"), patch.object(dev, "download"), \
             patch.object(dev, "data_status", return_value=missing_status()), \
             patch.object(dev, "manage", side_effect=manage), \
             self.assertRaises(dev.subprocess.CalledProcessError):
            dev.data()
        self.assertNotIn("dev_data_status", [args[0] for args in calls])

    def test_mobile_first_launch_uses_source_data_without_private_raster_artifacts(self):
        calls = []
        def manage(*args, **kwargs):
            calls.append(args)
            return Mock(stdout=b"")
        with patch.object(dev, "require_credentials"), patch.object(dev, "download"), \
             patch.object(dev, "data_status", return_value=missing_status()), \
             patch.object(dev, "manage", side_effect=manage), \
             patch.object(dev, "compose") as compose, \
             patch.object(dev, "prepare_source", side_effect=AssertionError("private raster")):
            dev.data()
        compose.assert_not_called()
        self.assertIn(("sync_quran_foundation_mushafs", "--force"), calls)
        self.assertEqual(calls[-1], ("dev_data_status", "--require-mobile"))

    def test_unverified_download_is_not_written(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "source.json"
            response = Mock()
            response.read.return_value = b"unexpected data"
            response.__enter__ = Mock(return_value=response)
            response.__exit__ = Mock(return_value=False)
            with patch.object(dev.urllib.request, "urlopen", return_value=response), \
                 self.assertRaisesRegex(ValueError, "checksum/size"):
                dev.download("https://example.test/source", "0" * 64, target, max_bytes=4)
            response.read.assert_called_once_with(5)
            self.assertFalse(target.exists())


if __name__ == "__main__":
    unittest.main()
