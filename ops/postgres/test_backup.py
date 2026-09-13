from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("backup.sh").resolve()


class BackupShellTests(unittest.TestCase):
    def test_backup_never_removes_old_dumps_even_with_legacy_retention(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            backups = root / "backups"
            backups.mkdir()
            old = backups / "quran_20200101T000000Z.dump"
            old.write_bytes(b"must survive")
            os.utime(old, (1, 1))
            binaries = root / "bin"
            binaries.mkdir()
            for name, script in {
                "pg_dump": '#!/bin/sh\nfor arg do case "$arg" in --file=*) printf "dump-data" > "${arg#--file=}";; esac; done\n',
                "pg_restore": '#!/bin/sh\nexit "${TEST_RESTORE_EXIT:-0}"\n',
                "date": "#!/bin/sh\nprintf 20260913T120000Z\n",
                "sha256sum": '#!/bin/sh\nprintf "test-checksum  %s\\n" "$1"\n',
            }.items():
                executable = binaries / name
                executable.write_text(script)
                executable.chmod(0o700)
            env = {
                **os.environ,
                "PATH": str(binaries) + os.pathsep + os.environ["PATH"],
                "PGHOST": "fixture",
                "PGPORT": "5432",
                "PGUSER": "fixture",
                "PGDATABASE": "quran",
                "BACKUP_DIR": str(backups),
                "BACKUP_MIN_FREE_MB": "0",
                "BACKUP_RETENTION_DAYS": "1",
            }
            result = subprocess.run(["sh", str(SCRIPT)], env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(old.read_bytes(), b"must survive")
            created = backups / "quran_20260913T120000Z.dump"
            self.assertEqual(created.read_bytes(), b"dump-data")
            self.assertEqual(created.stat().st_mode & 0o777, 0o600)
            second = subprocess.run(["sh", str(SCRIPT)], env=env, capture_output=True)
            self.assertNotEqual(second.returncode, 0)
            self.assertEqual(created.read_bytes(), b"dump-data")
            self.assertEqual(old.read_bytes(), b"must survive")


if __name__ == "__main__":
    unittest.main()
