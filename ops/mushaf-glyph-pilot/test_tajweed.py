import copy
import json
import os
from pathlib import Path
import unittest

import kfgqpc
import prepare as p
import tajweed as t


@unittest.skipUnless(os.environ.get("IQRO_TAJWEED_SOURCE_DIR") and os.environ.get("IQRO_KFGQPC_SOURCE_DIR"), "Pinned public source fonts required")
class TajweedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(os.environ["IQRO_TAJWEED_SOURCE_DIR"])
        cls.data = json.loads((cls.root / "snapshot.json").read_bytes())
        cls.lock = json.loads(Path(__file__).with_name("tajweed.source.lock.json").read_bytes())
        cls.refs = t.audit(cls.data)
        cls.heading = p.SourceFont(Path(os.environ["IQRO_KFGQPC_SOURCE_DIR"]) / kfgqpc.FONT, "KFGQPC HAFS Uthmanic Script")
        first = t.ColorFont(cls.root / "p1.woff2", 1)
        cls.basmala = [first.shape(w["text"]) for w in cls.data["pages"][0]["words"] if w["verse_id"] == 1 and w["char_type_name"] == "word"]
        first.close()

    @classmethod
    def tearDownClass(cls):
        cls.heading.close()

    def test_all_source_font_bytes_and_snapshot_pinned(self):
        self.assertEqual(len(self.lock["files"]), 604)
        self.assertEqual(p.digest(self.root / "snapshot.json"), self.lock["snapshot_sha256"])
        for name, spec in self.lock["files"].items():
            self.assertEqual(p.digest(self.root / name), spec["sha256"])

    def test_all_6236_ayahs_and_provider_marker_exception(self):
        self.assertEqual(len(self.refs), 6236)
        self.assertEqual(self.refs[188], (2, 181))
        bad = copy.deepcopy(self.data)
        bad["pages"][26]["words"][-1]["text"] = "wrong"
        with self.assertRaisesRegex(ValueError, "marker exception"):
            t.audit(bad)

    def test_original_color_channels_and_layer_order(self):
        font = t.ColorFont(self.root / "p1.woff2", 1)
        try:
            shape = font.shape("ﱃ")
            self.assertEqual(shape.colors, [(0, 0, 0, 255), (163, 165, 165, 255),
                (63, 72, 230, 255), (206, 158, 0, 255), (159, 165, 165, 255)])
            with self.assertRaisesRegex(ValueError, "Missing colour glyph"):
                font.shape("🙂")
        finally:
            font.close()

    def test_control_pages_keep_every_word_and_hit_region(self):
        for number in (1, 2, 3, 5, 27, 51, 208, 245, 604):
            with self.subTest(page=number):
                font = t.ColorFont(self.root / f"p{number}.woff2", number)
                try:
                    source = self.data["pages"][number - 1]
                    page = t.compose(self.data, source, font, self.heading, self.basmala, self.refs, self.lock)
                finally:
                    font.close()
                self.assertEqual([g["word_id"] for g in page["glyphs"] if g["word_id"] is not None], [w["id"] for w in source["words"]])
                self.assertEqual({(r["surah"], r["ayah"]) for r in page["ayah_regions"]}, {self.refs[w["verse_id"]] for w in source["words"]})
                self.assertEqual(p.mobile_geometry(page)["edition"], t.EDITION)
                self.assertNotIn("<text", t.svg(page))
                self.assertNotIn("<image", t.svg(page))
                for glyph in page["glyphs"]:
                    if "layers" in glyph:
                        self.assertEqual(glyph["commands"], [cmd for layer in glyph["layers"] for cmd in layer["commands"]])


if __name__ == "__main__":
    unittest.main()
