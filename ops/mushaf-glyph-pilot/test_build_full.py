import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from build_full import reuse_raster, write_once


class FullBuildTests(unittest.TestCase):
    def test_write_once_never_overwrites_different_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "artifact"
            write_once(path, b"original")
            write_once(path, b"original")
            with self.assertRaisesRegex(ValueError, "nothing overwritten"):
                write_once(path, b"changed")
            self.assertEqual(path.read_bytes(), b"original")

    def test_reuse_requires_identical_vector_and_verified_raster_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory) / "cache"
            cache.mkdir()
            output = Path(directory) / "output"
            output.mkdir()
            vector = b"verified vector"
            assets = []
            for width in (720, 1440, 2160):
                data = str(width).encode()
                name = f"page-001-w{width}.webp"
                (cache / name).write_bytes(data)
                assets.append({"path": name, "width": width, "bytes": len(data),
                               "sha256": hashlib.sha256(data).hexdigest()})
            (cache / "page-001.bundle.json").write_text(json.dumps({
                "source_svg_sha256": hashlib.sha256(vector).hexdigest(), "assets": assets}))
            self.assertIsNone(reuse_raster(cache, output, "page-001", b"different vector"))
            self.assertEqual(list(output.iterdir()), [])
            self.assertEqual(reuse_raster(cache, output, "page-001", vector), assets)
            (cache / assets[0]["path"]).write_bytes(b"tampered")
            with self.assertRaisesRegex(ValueError, "integrity check"):
                reuse_raster(cache, output, "page-001", vector)
