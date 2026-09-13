import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, Mock

from ops import dev


class LocalWorkspaceTests(unittest.TestCase):
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
             patch.object(dev, "manage", side_effect=manage), patch.object(dev, "compose") as compose:
            dev.data(web_only=True, extras=True)
        self.assertEqual([args[0] for args in calls], [
            "import_dua_catalog", "import_dua_catalog", "sync_quran_foundation_mushafs", "import_quran_corpus",
            "sync_quran_foundation_translations", "sync_quran_foundation_tafsirs", "dev_data_status",
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

    def test_failed_render_never_publishes_a_partial_mobile_catalog(self):
        calls = []
        directory = dev.WORK / "mushaf" / "verified-source"
        def manage(*args, **kwargs):
            calls.append(args)
            return Mock(stdout=b"source snapshot")
        def compose(*args, **kwargs):
            if "run" in args:
                raise dev.subprocess.CalledProcessError(1, ["renderer"])
        with patch.object(dev, "require_credentials"), patch.object(dev, "download"), \
             patch.object(dev, "manage", side_effect=manage), \
             patch.object(dev, "prepare_source", return_value=directory), \
             patch.object(dev, "compose", side_effect=compose), \
             self.assertRaises(dev.subprocess.CalledProcessError):
            dev.data()
        self.assertNotIn("publish_mushaf_rendition", [args[0] for args in calls])
        self.assertNotIn("dev_data_status", [args[0] for args in calls])

    def test_full_setup_publishes_only_after_render_and_requires_mobile_readiness(self):
        calls = []
        directory = dev.WORK / "mushaf" / "verified-source"
        def manage(*args, **kwargs):
            calls.append(args)
            return Mock(stdout=b"source snapshot")
        def compose(*args, **kwargs):
            calls.append(args)
        with patch.object(dev, "require_credentials"), patch.object(dev, "download"), \
             patch.object(dev, "manage", side_effect=manage), \
             patch.object(dev, "prepare_source", return_value=directory), \
             patch.object(dev, "compose", side_effect=compose):
            dev.data()
        rendered = next(index for index, args in enumerate(calls) if "run" in args)
        published = next(index for index, args in enumerate(calls) if args[0] == "publish_mushaf_rendition")
        self.assertLess(rendered, published)
        self.assertEqual(calls[-1], ("dev_data_status", "--require-mobile"))
        self.assertTrue(calls[published][1].startswith("/app/.dev/mushaf/verified-source/rendered-"))

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
