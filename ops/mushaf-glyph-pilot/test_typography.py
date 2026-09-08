"""Typography regressions, including opt-in audits of both complete sources."""
from collections import defaultdict
import json
import copy
import os
from pathlib import Path
import unittest

import kfgqpc as k
import prepare as p


def assert_grid(test, page):
    rows = page["lines"]
    verse_rows = [r for r in rows if r["kind"] == "ayah"]
    height = verse_rows[0]["height"]
    scale = verse_rows[0]["scale"]
    offset = verse_rows[0]["baseline"] - verse_rows[0]["top"]
    for row in verse_rows:
        test.assertAlmostEqual(row["height"], height)
        test.assertEqual(row["scale"], scale)
        test.assertAlmostEqual(row["baseline"] - row["top"], offset)
    for first, second in zip(verse_rows, verse_rows[1:]):
        test.assertAlmostEqual(second["baseline"] - first["baseline"],
                               (second["line"] - first["line"]) * height)
    by_line = defaultdict(list)
    for glyph in page["glyphs"]:
        by_line[glyph["line"]].append(glyph)
    for row in rows:
        test.assertEqual(row["word_gap"], 0)
        test.assertEqual(row["spacing"], "source-advance")
        glyphs = by_line[row["line"]]
        for glyph in glyphs:
            box = glyph["bounds"]
            test.assertGreaterEqual(box[1] + .0001, row["top"])
            test.assertLessEqual(box[3] - .0001, row["top"] + height)
        # Check pen positions, not ink widths (bearings belong to the font).
        for right, left in zip(glyphs, glyphs[1:]):
            test.assertAlmostEqual(right["origin_x"] - right["space"] - left["advance"],
                                   left["origin_x"], delta=.0002)
        left = min(g["origin_x"] for g in glyphs)
        left = min(left, *(g["bounds"][0] for g in glyphs))
        right = max(g["origin_x"] + g["advance"] for g in glyphs)
        right = max(right, *(g["bounds"][2] for g in glyphs))
        test.assertAlmostEqual(left, p.WIDTH - right, delta=.0002)
    p.validate_artifact(page)


class TypographyTests(unittest.TestCase):
    def test_shared_baseline_keeps_tall_marks_and_descenders_inside_rows(self):
        lines = [[(p.Shaped([], (0, -20, 200, 60)), None)],
                 [(p.Shaped([], (0, -5, 400, 110)), None)]]
        grid = p.PageTypography.fit(lines)
        for line in lines:
            shape = line[0][0]
            self.assertGreaterEqual(grid.baseline_offset - shape.bounds[3] * grid.scale, 4)
            self.assertLessEqual(grid.baseline_offset - shape.bounds[1] * grid.scale, 92)

    def test_dense_line_fits_source_advances_and_real_spaces(self):
        shapes = [(p.Shaped([], (10, -10, 100, 80), 120, 15), None)] * 18
        grid = p.PageTypography.fit([shapes])
        positions = p.positioned_line([s for s, _ in shapes], grid.scale)
        self.assertGreaterEqual(min(left for _, left, _ in positions), p.MARGIN)
        self.assertLessEqual(max(right for _, _, right in positions), p.WIDTH - p.MARGIN)

    def test_short_line_is_centered_without_inventing_spaces(self):
        shapes = [p.Shaped([], (0, -10, 100, 60), 100)] * 3
        positions = p.positioned_line(shapes, 1)
        self.assertEqual(positions, [(550, 550, 650), (450, 450, 550), (350, 350, 450)])

    def test_bearings_and_advance_survive_instead_of_tight_ink_packing(self):
        shapes = [p.Shaped([], (10, -10, 90, 60), 120, 20),
                  p.Shaped([], (-5, -10, 60, 60), 80, 20)]
        origins, left, right = p.source_line(shapes)
        self.assertEqual(origins, [-120, -220])
        self.assertEqual((left, right), (-225, 0))
        placed = p.positioned_line(shapes, 2)
        self.assertEqual(placed[0][0] - placed[1][0], 200)
        self.assertEqual(placed[0][1] - placed[1][2], 100)

    def test_overflow_and_nonfinite_width_are_rejected(self):
        for shapes in ([], [p.Shaped([], (0, 0, 1000, 10), 1000)],
                       [p.Shaped([], (0, 0, 10, 10), float('nan'))],
                       [p.Shaped([], (0, 0, 10, 10), 0)]):
            with self.subTest(shapes=shapes), self.assertRaises(ValueError):
                p.positioned_line(shapes, 1)

    def test_combining_record_does_not_invent_a_word_gap(self):
        shapes = [p.Shaped([], (0, -10, 100, 60), 100),
                  p.Shaped([], (20, 65, 30, 75), 0),
                  p.Shaped([], (0, -10, 80, 60), 80)]
        origins, left, right = p.source_line(shapes)
        self.assertEqual(origins, [-100, -100, -180])
        self.assertEqual((left, right), (-180, 0))


@unittest.skipUnless(os.environ.get("IQRO_KFGQPC_SOURCE_DIR"), "Pinned KFGQPC source required")
class KfgqpcTypographyTests(unittest.TestCase):
    def test_content_build_rejects_typography_regressions(self):
        root = Path(os.environ["IQRO_KFGQPC_SOURCE_DIR"])
        data, lock = k.load_source(root)
        font = p.SourceFont(root / k.FONT, "KFGQPC HAFS Uthmanic Script")
        try:
            page = k.compose(data, data["pages"][2], font, k.audit(data), lock)
        finally:
            font.close()
        for field, value in (("baseline", 500), ("scale", 1), ("height", 150),
                             ("word_gap", 80), ("baseline", float('nan'))):
            broken = copy.deepcopy(page)
            broken["lines"][1][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                p.validate_artifact(broken)

    def test_source_pages_have_stable_baselines_and_bounded_spaces(self):
        root = Path(os.environ["IQRO_KFGQPC_SOURCE_DIR"])
        data, lock = k.load_source(root)
        refs = k.audit(data)
        font = p.SourceFont(root / k.FONT, "KFGQPC HAFS Uthmanic Script")
        pages = range(1, 605) if os.environ.get("IQRO_MUSHAF_TYPOGRAPHY_FULL") else (1, 2, 3, 50, 77, 255, 604)
        try:
            for number in pages:
                with self.subTest(page=number):
                    source = data["pages"][number - 1]
                    page = k.compose(data, source, font, refs, lock)
                    assert_grid(self, page)
                    self.assertEqual([g["word_id"] for g in page["glyphs"] if g["word_id"] is not None],
                                     [w["id"] for w in source["words"]])
        finally:
            font.close()


@unittest.skipUnless(os.environ.get("IQRO_MUSHAF_FULL_SOURCE_DIR"), "Pinned QCF source required")
class QcfTypographyTests(unittest.TestCase):
    def test_source_pages_have_stable_baselines_and_bounded_spaces(self):
        root = Path(os.environ["IQRO_MUSHAF_FULL_SOURCE_DIR"])
        lock = json.loads((root / "source.full.lock.json").read_text())
        pages = range(1, 605) if os.environ.get("IQRO_MUSHAF_TYPOGRAPHY_FULL") else (1, 2, 3, 50, 77, 255, 604)
        db = p.open_database(root / 'mushaf_database.db')
        try:
            for number in pages:
                with self.subTest(page=number):
                    page = p.build_page(db, root, lock, number)
                    assert_grid(self, page)
                    expected = db.execute(
                        'SELECT g.id FROM Table_of_layout l JOIN Table_of_glyph g '
                        'ON g.id BETWEEN l.first_word_id AND l.last_word_id '
                        'WHERE l.page_number=? ORDER BY g.id', (number,))
                    self.assertEqual([g['word_id'] for g in page['glyphs'] if g['word_id'] is not None],
                                     [row['id'] for row in expected])
        finally:
            db.close()


if __name__ == '__main__':
    unittest.main()
