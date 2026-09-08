import copy
import os
from pathlib import Path
import unittest

import kfgqpc as k
import prepare as p


@unittest.skipUnless(os.environ.get("IQRO_KFGQPC_SOURCE_DIR"), "Pinned KFGQPC source required")
class KfgqpcSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(os.environ["IQRO_KFGQPC_SOURCE_DIR"])
        cls.data, cls.lock = k.load_source(cls.root)
        cls.refs = k.audit(cls.data)
        cls.font = p.SourceFont(cls.root / k.FONT, "KFGQPC HAFS Uthmanic Script")

    @classmethod
    def tearDownClass(cls):
        cls.font.close()

    def test_complete_corpus_and_terminal_markers(self):
        self.assertEqual(len(self.refs), 6236)
        self.assertEqual(self.refs[188], (2, 181))
        self.assertEqual(p.digest(self.root / k.FONT), self.lock["font_sha256"])

    def test_missing_word_rejected(self):
        data = copy.deepcopy(self.data)
        data["pages"][2]["words"].pop(1)
        with self.assertRaisesRegex(ValueError, "Word sequence"):
            k.audit(data)

    def test_wrong_ayah_number_rejected(self):
        data = copy.deepcopy(self.data)
        data["pages"][0]["words"][4]["text"] = "٢"
        with self.assertRaisesRegex(ValueError, "terminal ayah number"):
            k.audit(data)

    def test_shared_unicode_space_preserves_shaping(self):
        shape = self.font.shape("بَعۡدَ مَا")
        self.assertGreater(shape.width, 0)
        self.assertTrue(shape.pieces)

    def test_unavailable_glyph_never_falls_back(self):
        with self.assertRaisesRegex(ValueError, "Missing glyph"):
            self.font.shape("🙂")

    def test_control_pages_have_exact_ayah_ink_regions_and_headings(self):
        for number in (1, 2, 3, 27, 50, 77, 187, 245, 604):
            with self.subTest(page=number):
                source = self.data["pages"][number - 1]
                page = k.compose(self.data, source, self.font, self.refs, self.lock)
                p.validate_artifact(page)
                self.assertEqual(len([g for g in page["glyphs"] if g["word_id"] is not None]), len(source["words"]))
                geometry = p.mobile_geometry(page)
                self.assertEqual(geometry["edition"], "kfgqpc-hafs")
                self.assertEqual({(r["ayah"]["surah"], r["ayah"]["number"]) for r in geometry["regions"]},
                                 {self.refs[w["verse_id"]] for w in source["words"]})

    def test_surah_closing_line_is_centered_from_source_marker_not_gap_size(self):
        page = k.compose(self.data, self.data["pages"][254], self.font, self.refs, self.lock)
        lines = {r["line"]: r for r in page["lines"]}
        self.assertFalse(lines[1]["centered"])
        self.assertTrue(lines[2]["centered"])
        self.assertEqual(lines[2]["word_gap"], 0)
        self.assertEqual(lines[2]["spacing"], "source-advance")


if __name__ == "__main__":
    unittest.main()
