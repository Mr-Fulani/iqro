import copy
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

import prepare as p


def fixture():
    return {"schema_version": 1, "status": "draft", "edition": "test", "page": 3,
            "width": 1000, "height": 1600, "glyphs": [
                {"word_id": 1, "kind": "ayah", "verse": "2:6", "line": 1,
                 "bounds": [20, 90, 100, 130],
                 "commands": [["M", 20, 90], ["L", 100, 90], ["Q", 100, 130, 20, 130], ["Z"]]}],
            "ayah_regions": [{"surah": 2, "ayah": 6, "line": 1, "rect": [20, 80, 100, 176]}]}


class ContractTests(unittest.TestCase):
    def test_canonical_order(self):
        self.assertEqual(p.canonical({"b": 1, "a": "ب"}), p.canonical({"a": "ب", "b": 1}))

    def test_runtime_pinned(self):
        self.assertEqual(p.verify_runtime(), p.EXPECTED_RUNTIME)
        with patch.object(p.hb, "__version__", "unexpected"):
            with self.assertRaisesRegex(ValueError, "runtime differs"):
                p.verify_runtime()

    def test_uniform_transform_preserves_curve(self):
        shape = p.Shaped([([["M", -5, 10], ["Q", 0, 20, 5, 10], ["Z"]], 0, 0)], (-5, 10, 5, 20))
        self.assertEqual(p.place(shape, 100, 200, 2), [["M", 100, 180], ["Q", 110, 160, 120, 180], ["Z"]])

    def test_ayah_regions_normalize_without_urls(self):
        model = p.mobile_geometry(fixture())
        self.assertEqual(model["assets"], [])
        self.assertEqual(model["status"], "draft")
        self.assertEqual(model["regions"][0]["ayah"], {"surah": 2, "number": 6})
        self.assertEqual(model["regions"][0]["x"], .02)
        self.assertEqual(model["regions"][0]["width"], .08)
        self.assertEqual(len(model["checksum_sha256"]), 64)

    def test_svg_has_outlines_not_font_fallback(self):
        page = fixture()
        page["edition"] = '<unsafe & "name">'
        value = p.svg(page)
        self.assertIn("&lt;unsafe &amp;", value)
        self.assertNotIn("<text", value)
        self.assertNotIn("href", value)
        self.assertIn('<path fill=', value)

    def test_reject_invalid_geometry_and_contours(self):
        for change in (
            lambda d: d.update(status="ready"),
            lambda d: d.update(page=605),
            lambda d: d.update(width=0),
            lambda d: d.update(glyphs=[]),
            lambda d: d["glyphs"][0].update(bounds=[-1, 0, 3, 4]),
            lambda d: d["glyphs"][0].update(commands=[]),
            lambda d: d["glyphs"][0].update(commands=[[]]),
            lambda d: d["glyphs"][0].update(commands=[["M", float("nan"), 1], ["Z"]]),
            lambda d: d["glyphs"][0].update(commands=[["M", 1, 2], ["L", 2, 3]]),
            lambda d: d["glyphs"][0].update(commands=[["M", 1, 2], ["A", 3, 4], ["Z"]]),
            lambda d: d["glyphs"][0].update(verse=None),
            lambda d: d.update(ayah_regions=[]),
            lambda d: d["ayah_regions"][0].update(rect=[40, 80, 100, 176]),
            lambda d: d["ayah_regions"].append(copy.deepcopy(d["ayah_regions"][0])),
            lambda d: d["ayah_regions"][0].update(ayah=7),
        ):
            page = fixture()
            change(page)
            with self.subTest(page=page):
                with self.assertRaises(ValueError):
                    p.validate_artifact(page)

    def test_wrong_size_checksum_symlink_and_unsafe_name(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            lock = {"schema_version": 1, "source_pages": 604, "status": "draft",
                    "sample_pages": [1], "publication_approved": False, "files": {}}
            for name in ("mushaf_database.db", "p1.ttf", "surah_name_v4.ttf"):
                (root / name).write_bytes(b"abc")
                lock["files"][name] = {"bytes": 3, "sha256": hashlib.sha256(b"abc").hexdigest()}
            p.verify_files(root, lock)
            for spec in ({"bytes": 4, "sha256": "a" * 64}, {"bytes": 3, "sha256": "a" * 64}):
                bad = copy.deepcopy(lock)
                bad["files"]["p1.ttf"] = spec
                with self.assertRaises(ValueError):
                    p.verify_files(root, bad)
            (root / "linked.ttf").symlink_to(root / "p1.ttf")
            for name in ("../p1.ttf", "linked.ttf"):
                bad = copy.deepcopy(lock)
                bad["files"][name] = lock["files"]["p1.ttf"]
                with self.assertRaises(ValueError):
                    p.verify_files(root, bad)
            for patch_value in ({"publication_approved": True}, {"sample_pages": [1, 1]}, {"files": {}}):
                with self.assertRaises(ValueError):
                    p.verify_files(root, {**lock, **patch_value})


SOURCE = os.environ.get("IQRO_MUSHAF_SOURCE_DIR")


@unittest.skipUnless(SOURCE, "Set IQRO_MUSHAF_SOURCE_DIR for pinned source integration tests")
class SourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(SOURCE)
        cls.lock = json.loads(Path(p.__file__).with_name("source.lock.json").read_text())
        p.verify_runtime()
        p.verify_files(cls.root, cls.lock)
        cls.db = p.open_database(cls.root / "mushaf_database.db")
        cls.pages = {n: p.build_page(cls.db, cls.root, cls.lock, n) for n in cls.lock["sample_pages"]}

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def test_complete_corpus(self):
        self.assertEqual(p.audit_corpus(self.db), {"pages": 604, "verses": 6236, "words": 83668,
                                                 "multi_glyph_words": 4514, "surahs": 114})

    def test_source_read_only(self):
        with self.assertRaises(sqlite3.OperationalError):
            self.db.execute("UPDATE Table_of_glyph SET glyph='bad' WHERE id=1")
        self.assertEqual(p.digest(self.root / "mushaf_database.db"), self.lock["files"]["mushaf_database.db"]["sha256"])

    def test_corrupt_corpus_rejected_in_memory(self):
        for query in (
            "DELETE FROM Table_of_ayah_by_ayah WHERE ayah_id=1",
            "UPDATE Table_of_glyph SET location='2:1:1' WHERE id=1",
            "UPDATE Table_of_layout SET first_word_id=2 WHERE page_number=1 AND line_number=2",
        ):
            with self.subTest(query=query):
                copy_db = sqlite3.connect(":memory:")
                try:
                    self.db.backup(copy_db)
                    copy_db.row_factory = sqlite3.Row
                    copy_db.execute(query)
                    with self.assertRaises(ValueError):
                        p.audit_corpus(copy_db)
                finally:
                    copy_db.close()

    def test_all_sample_word_ranges_and_identity(self):
        for number, page in self.pages.items():
            with self.subTest(page=number):
                expected = list(self.db.execute(
                    "SELECT g.id,g.surah_number,g.ayah_number FROM Table_of_layout l JOIN Table_of_glyph g "
                    "ON g.id BETWEEN l.first_word_id AND l.last_word_id WHERE l.page_number=? ORDER BY g.id", (number,)))
                actual = [g for g in page["glyphs"] if g["word_id"] is not None]
                self.assertEqual([g["word_id"] for g in actual], [r["id"] for r in expected])
                self.assertEqual([g["verse"] for g in actual], [f"{r['surah_number']}:{r['ayah_number']}" for r in expected])
                p.validate_artifact(page)
                self.assertLess(len(p.canonical(p.mobile_geometry(page))), 10000)

    def test_stop_mark_is_preserved(self):
        font = p.SourceFont(self.root / "p3.ttf", "QCF2003")
        try:
            word = self.db.execute("SELECT glyph FROM Table_of_glyph WHERE id=95").fetchone()[0]
            self.assertEqual(len(word), 2)
            self.assertEqual(len(font.shape(word).pieces), 2)
            with self.assertRaisesRegex(ValueError, "fallback forbidden"):
                font.shape(" ")
        finally:
            font.close()

    def test_wrong_font_and_unpinned_page_rejected(self):
        with self.assertRaisesRegex(ValueError, "font identity"):
            p.SourceFont(self.root / "p3.ttf", "QCF2002")
        with self.assertRaisesRegex(ValueError, "not pinned"):
            p.build_page(self.db, self.root, self.lock, 4)

    def test_basmala_is_four_source_words_not_ayah_marker(self):
        for number in (2, 50, 604):
            decorations = [g for g in self.pages[number]["glyphs"] if g["kind"] == "basmallah"]
            self.assertEqual(len(decorations), 12 if number == 604 else 4)
            self.assertTrue(all(g["word_id"] is None and g["verse"] is None for g in decorations))

    def test_output_deterministic(self):
        again = p.build_page(self.db, self.root, self.lock, 3)
        self.assertEqual(p.canonical(again), p.canonical(self.pages[3]))

    def test_main_never_overwrites_existing_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "keep.txt"
            marker.write_text("unchanged")
            with patch("sys.argv", ["prepare.py", "--source-dir", str(self.root), "--output-dir", directory]):
                with self.assertRaisesRegex(ValueError, "nothing overwritten"):
                    p.main()
            self.assertEqual(marker.read_text(), "unchanged")
            self.assertEqual(list(Path(directory).iterdir()), [marker])


if __name__ == "__main__":
    unittest.main()
