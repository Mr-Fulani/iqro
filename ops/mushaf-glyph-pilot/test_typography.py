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
        by_line[glyph["line"]].append(glyph["bounds"])
    for row in rows:
        test.assertGreaterEqual(row["word_gap"], 0)
        test.assertLessEqual(row["word_gap"], height / (8 if row["centered"] else 4))
        boxes = by_line[row["line"]]
        for box in boxes:
            test.assertGreaterEqual(box[1] + .0001, row["top"])
            test.assertLessEqual(box[3] - .0001, row["top"] + height)
        # Reading order is RTL; bounds, paths and regions share this spacing.
        for right, left in zip(boxes, boxes[1:]):
            test.assertAlmostEqual(right[0] - left[2], row["word_gap"], delta=.0002)
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

    def test_dense_line_reserves_space_before_fitting_glyphs(self):
        shapes = [(p.Shaped([], (0, -10, 100, 80)), None)] * 18
        grid = p.PageTypography.fit([shapes])
        gap, right = grid.horizontal([s.width * grid.scale for s, _ in shapes], centered=False)
        self.assertGreaterEqual(gap + .000001, grid.row_height / 12)
        self.assertEqual(right, p.WIDTH - p.MARGIN)

    def test_short_line_does_not_expand_spaces_to_fill_paper(self):
        grid = p.PageTypography(96, 1, 70)
        gap, right = grid.horizontal([100, 100, 100], centered=False)
        self.assertEqual(gap, 24)
        self.assertEqual(right, 976)
        self.assertGreater(right - 300 - gap * 2, p.MARGIN)

    def test_centered_line_uses_same_natural_gap_in_both_adapters(self):
        grid = p.PageTypography(96, 1, 70)
        gap, right = grid.horizontal([100, 100, 100], centered=True)
        self.assertEqual(gap, 12)
        self.assertEqual(right, (1000 + 300 + 24) / 2)

    def test_overflow_and_nonfinite_width_are_rejected(self):
        grid = p.PageTypography(96, 1, 70)
        for widths in ([], [1000], [float('nan')], [0]):
            with self.subTest(widths=widths), self.assertRaises(ValueError):
                grid.horizontal(widths, centered=False)


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
