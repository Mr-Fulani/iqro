"""Read-only source audit and font-free vector pilot; never publishes content.

Typography is an IQRO draft layout using unchanged, HarfBuzz-shaped source
glyph outlines. It is not claimed to be a facsimile of an official print.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import sqlite3
from collections import defaultdict
from contextlib import closing
from dataclasses import dataclass
from pathlib import Path
from xml.sax.saxutils import escape

import fontTools
from fontTools.pens.basePen import BasePen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.ttLib import TTFont, newTable
import uharfbuzz as hb

WIDTH, HEIGHT, MARGIN, ROW = 1000, 1600, 24, 96
TOP = (HEIGHT - ROW * 15) / 2
VERSION = "iqro-glyph-pilot-3"
EXPECTED_RUNTIME = {"fonttools": "4.43.0", "uharfbuzz": "0.56.1", "harfbuzz": "14.4.0"}


def require(value, message):
    if not value:
        raise ValueError(message)


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify_runtime():
    actual = {"fonttools": fontTools.__version__, "uharfbuzz": hb.__version__,
              "harfbuzz": hb.version_string()}
    require(actual == EXPECTED_RUNTIME, f"Renderer runtime differs from pinned versions: {actual}")
    return actual


def verify_files(root, lock):
    require(lock["schema_version"] == 1 and lock["source_pages"] == 604, "Unsupported source contract")
    require(lock["status"] == "draft" and lock["publication_approved"] is False,
            "This tool only prepares unpublished drafts")
    pages = lock["sample_pages"]
    require(pages and pages == sorted(set(pages)) and all(type(n) is int and 1 <= n <= 604 for n in pages),
            "Invalid sample pages")
    required = {"mushaf_database.db", "p1.ttf", "surah_name_v4.ttf"} | {f"p{n}.ttf" for n in pages}
    require(required <= set(lock["files"]), "Unpinned required source")
    root = root.resolve()
    for name, spec in lock["files"].items():
        require(Path(name).name == name, "Unsafe source filename")
        path = root / name
        require(not path.is_symlink() and path.is_file(), f"Missing source: {name}")
        require(path.stat().st_size == spec["bytes"], f"Wrong size: {name}")
        require(digest(path) == spec["sha256"], f"Wrong checksum: {name}")


def open_database(path):
    db = sqlite3.connect(f"{path.resolve().as_uri()}?mode=ro&immutable=1", uri=True)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA trusted_schema=OFF")
    db.execute("PRAGMA query_only=ON")
    return db


def audit_corpus(db):
    require(db.execute("PRAGMA quick_check").fetchone()[0] == "ok", "Invalid SQLite database")
    verses = list(db.execute("SELECT * FROM Table_of_ayah_by_ayah ORDER BY ayah_id"))
    surahs = list(db.execute("SELECT * FROM Table_of_surah ORDER BY surah_number"))
    words = list(db.execute("SELECT * FROM Table_of_glyph ORDER BY id"))
    lines = list(db.execute("SELECT * FROM Table_of_layout ORDER BY page_number,line_number"))
    require(len(verses) == 6236 and len(surahs) == 114, "Incomplete Hafs verse corpus")
    require([s["surah_number"] for s in surahs] == list(range(1, 115)), "Surah sequence mismatch")
    verse_keys = {(v["surah_number"], v["ayah_number"]) for v in verses}
    expected = {(s["surah_number"], a) for s in surahs for a in range(1, s["ayahs_count"] + 1)}
    require(verse_keys == expected and len(verse_keys) == len(verses), "Verse sequence mismatch")
    require([w["id"] for w in words] == list(range(1, len(words) + 1)), "Word ID gaps")
    word_map = {w["id"]: w for w in words}
    seen = set()
    per_page = defaultdict(list)
    headers = []
    basmalas = 0
    expected_word_id = 1
    multi_glyph = 0
    per_verse = defaultdict(list)
    for word in words:
        key = (word["surah_number"], word["ayah_number"])
        require(key in verse_keys, "Word points to an unknown ayah")
        require(word["location"] == f"{key[0]}:{key[1]}:{word['word_number']}", "Word identity mismatch")
        require(1 <= len(word["glyph"]) <= 3, "Unsupported glyph sequence")
        per_verse[key].append(word["word_number"])
        multi_glyph += len(word["glyph"]) > 1
    require(set(per_verse) == verse_keys, "Missing verse glyphs")
    for numbers in per_verse.values():
        require(numbers == list(range(1, len(numbers) + 1)), "Word sequence mismatch")
    for line in lines:
        page, number, kind = line["page_number"], line["line_number"], line["line_type"]
        require(1 <= page <= 604 and 1 <= number <= 15, "Invalid page/line")
        require(line["is_centered"] in (0, 1), "Invalid centering flag")
        per_page[page].append(number)
        if kind == "ayah":
            first, last = line["first_word_id"], line["last_word_id"]
            require(isinstance(first, int) and isinstance(last, int) and 0 <= last - first < 100,
                    "Invalid word range")
            require(first == expected_word_id, "Page reading order differs from word sequence")
            expected_word_id = last + 1
            for word_id in range(first, last + 1):
                require(word_id in word_map and word_id not in seen, "Overlapping/missing page words")
                seen.add(word_id)
        else:
            require(kind in ("surah_name", "basmallah"), "Unknown line kind")
            require(line["first_word_id"] is None and line["last_word_id"] is None,
                    "Decoration line contains verse words")
            if kind == "surah_name":
                headers.append(line["number_surah"])
            else:
                basmalas += 1
    require(set(per_page) == set(range(1, 605)), "Missing page")
    require(headers == list(range(1, 115)), "Surah heading sequence mismatch")
    require(basmalas == 112, "Unexpected introductory basmala count")
    require(len(seen) == len(words), "Unassigned glyphs")
    for numbers in per_page.values():
        require(numbers == list(range(1, len(numbers) + 1)), "Duplicate or missing line")
    return {"pages": len(per_page), "verses": len(verses), "words": len(words),
            "multi_glyph_words": multi_glyph, "surahs": len(surahs)}


class OutlinePen(BasePen):
    def __init__(self, glyphs):
        super().__init__(glyphs)
        self.commands = []

    def _moveTo(self, p):
        self.commands.append(["M", *p])

    def _lineTo(self, p):
        self.commands.append(["L", *p])

    def _qCurveToOne(self, control, end):
        self.commands.append(["Q", *control, *end])

    def _curveToOne(self, a, b, end):
        self.commands.append(["C", *a, *b, *end])

    def _closePath(self):
        self.commands.append(["Z"])

    def _endPath(self):
        # Fonts for this adapter must contain closed fill contours.
        raise ValueError("Open glyph contour")


@dataclass
class Shaped:
    pieces: list
    bounds: tuple

    @property
    def width(self):
        return self.bounds[2] - self.bounds[0]


def union(rects):
    return (min(r[0] for r in rects), min(r[1] for r in rects),
            max(r[2] for r in rects), max(r[3] for r in rects))


class SourceFont:
    def __init__(self, path, expected_name):
        self.tt = TTFont(path)
        try:
            require(self.tt["name"].getDebugName(1) == expected_name, "Wrong page font identity")
            require(not any(t in self.tt for t in ("COLR", "SVG ", "CBDT", "sbix")),
                    "Colour/bitmap fonts require a separate renderer")
            self.glyphs = self.tt.getGlyphSet()
            self.cmap = self.tt.getBestCmap()
            self.order = self.tt.getGlyphOrder()
            face = hb.Face(path.read_bytes())
            self.font = hb.Font(face)
            # The pinned p245 font contains a truncated legacy Macintosh cmap.
            # HarfBuzz rejects the entire cmap, even though both Unicode maps
            # agree. Supply ONLY the original Unicode maps in memory; all other
            # tables, glyph IDs, outlines and shaping rules remain byte-identical.
            if any(self.font.get_nominal_glyph(c) != self.tt.getGlyphID(g)
                   for c, g in self.cmap.items()):
                require(expected_name == "QCF2245" and digest(path) ==
                        "3aa219eb172861eee4915f284f4c2cc11c9ee8caa21fda7c3c8bbcb517773d68",
                        "Unverified font character map; fallback forbidden")
                unicode_maps = [t for t in self.tt["cmap"].tables if t.isUnicode()]
                require(len(unicode_maps) == 2 and all(t.cmap == self.cmap for t in unicode_maps),
                        "Conflicting Unicode character maps")
                cmap = newTable("cmap")
                cmap.tableVersion = 0
                cmap.tables = unicode_maps
                cmap_data = cmap.compile(self.tt)
                self._source_face = face
                self._unicode_cmap = cmap_data
                # uharfbuzz callbacks require the backing bytes to outlive the
                # face. Keep every table alive; never return temporary blobs.
                self._table_data = {tag: face.reference_table(tag).data for tag in face.table_tags}
                self._table_data["cmap"] = cmap_data
                face = hb.Face.create_for_tables(
                    lambda _, tag, data: data.get(tag, b""),
                    self._table_data)
                self.font = hb.Font(face)
                require(all(self.font.get_nominal_glyph(c) == self.tt.getGlyphID(g)
                            for c, g in self.cmap.items()), "Unicode map normalization failed")
            self.font.scale = (self.tt["head"].unitsPerEm,) * 2
            hb.ot_font_set_funcs(self.font)
            self.outlines = {}
        except BaseException:
            self.tt.close()
            raise

    def close(self):
        self.tt.close()

    def shape(self, text, direction="rtl"):
        require(text and all(ord(c) in self.cmap for c in text), "Missing glyph; fallback forbidden")
        buf = hb.Buffer()
        buf.add_str(text)
        buf.guess_segment_properties()
        buf.direction = direction
        hb.shape(self.font, buf, {"kern": True, "liga": True})
        x, y, pieces, boxes = 0, 0, [], []
        for info, pos in zip(buf.glyph_infos, buf.glyph_positions, strict=True):
            require(info.codepoint != 0, "HarfBuzz produced .notdef")
            name = self.order[info.codepoint]
            if name not in self.outlines:
                pen = OutlinePen(self.glyphs)
                bounds = BoundsPen(self.glyphs)
                self.glyphs[name].draw(pen)
                self.glyphs[name].draw(bounds)
                require(bounds.bounds is not None and pen.commands, "Empty glyph outline")
                self.outlines[name] = (pen.commands, bounds.bounds)
            commands, box = self.outlines[name]
            dx, dy = x + pos.x_offset, y + pos.y_offset
            pieces.append((commands, dx, dy))
            boxes.append((box[0] + dx, box[1] + dy, box[2] + dx, box[3] + dy))
            x += pos.x_advance
            y += pos.y_advance
        require(pieces, "No shaped glyphs")
        return Shaped(pieces, union(boxes))


def place(shaped, x, baseline, scale):
    """Preserve each curve under one uniform scale and a Y-axis flip."""
    result = []
    for commands, dx, dy in shaped.pieces:
        for command in commands:
            out = [command[0]]
            for i in range(1, len(command), 2):
                out += [round(x + (command[i] + dx - shaped.bounds[0]) * scale, 4),
                        round(baseline - (command[i + 1] + dy) * scale, 4)]
            result.append(out)
    return result


def build_page(db, root, lock, number):
    require(number in lock["sample_pages"], "Page not pinned by this pilot lock")
    fonts = {}
    try:
        fonts["page"] = SourceFont(root / f"p{number}.ttf", f"QCF2{number:03d}")
        fonts["heading"] = SourceFont(root / "surah_name_v4.ttf", "surah-name-v4")
        # Reuse the verified 1:1 word glyphs, without the ayah number. The
        # separate QCF_BSML asset in the repository is not the same font release.
        fonts["basmala"] = SourceFont(root / "p1.ttf", "QCF2001")
        basmala_words = list(db.execute(
            "SELECT glyph FROM Table_of_glyph WHERE surah_number=1 AND ayah_number=1 "
            "AND word_number BETWEEN 1 AND 4 ORDER BY word_number"))
        require(len(basmala_words) == 4, "Incomplete source basmala")
        rows = list(db.execute("SELECT * FROM Table_of_layout WHERE page_number=? ORDER BY line_number", (number,)))
        prepared, verse_shapes = [], []
        for row in rows:
            kind = row["line_type"]
            if kind == "ayah":
                words = list(db.execute("SELECT * FROM Table_of_glyph WHERE id BETWEEN ? AND ? ORDER BY id",
                                        (row["first_word_id"], row["last_word_id"])))
                items = [(fonts["page"].shape(w["glyph"]), dict(w)) for w in words]
                verse_shapes += [s for s, _ in items]
            elif kind == "surah_name":
                # Use the font's own ligature; never synthesize a heading in a system font.
                items = [(fonts["heading"].shape(f"surah{row['number_surah']:03d}", "ltr"), None)]
            else:
                items = [(fonts["basmala"].shape(w["glyph"]), None) for w in basmala_words]
            prepared.append((row, items))
        require(verse_shapes, "Page has no verse glyphs")
        verse_lines = [items for row, items in prepared if row["line_type"] == "ayah"]
        longest = max(sum(s.width for s, _ in items) for items in verse_lines)
        ink_height = sum(max(s.bounds[3] for s, _ in items) - min(s.bounds[1] for s, _ in items)
                         for items in verse_lines)
        # One uniform font scale for the entire page. Allocate vertical space by
        # each line's actual ink bounds instead of combining the tallest mark on
        # one line with the deepest descender from a different line 15 times.
        # Leading remains >= 6 canvas units; no line intersects its neighbour.
        scale = min((WIDTH - 2 * MARGIN - 48) / longest,
                    len(verse_lines) * (ROW - 6) / ink_height)
        leading = (len(verse_lines) * ROW - ink_height * scale) / len(verse_lines)
        block_offset = (15 - len(rows)) / 2 if number in (1, 2) else 0
        glyphs, regions = [], []
        top = TOP + block_offset * ROW
        for row, items in prepared:
            is_verse = row["line_type"] == "ayah"
            if is_verse:
                line_scale = scale
                ascent = max(s.bounds[3] for s, _ in items)
                descent = min(s.bounds[1] for s, _ in items)
                row_height = (ascent - descent) * scale + leading
                baseline = top + leading / 2 + ascent * scale
            else:
                row_height = ROW
                box = union([s.bounds for s, _ in items])
                line_scale = min(ROW * .60 / (box[3] - box[1]),
                                 WIDTH * .66 / sum(s.width for s, _ in items))
                baseline = top + ROW / 2 + (box[3] + box[1]) * line_scale / 2
            widths = [s.width * line_scale for s, _ in items]
            centered = bool(row["is_centered"])
            gap = 7 if centered else (WIDTH - 2 * MARGIN - sum(widths)) / max(1, len(items) - 1)
            require(gap >= 0, "Line overflows page")
            total_width = sum(widths) + gap * (len(items) - 1)
            right = (WIDTH + total_width) / 2 if centered else WIDTH - MARGIN
            verse_boxes = defaultdict(list)
            for (shaped, word), width in zip(items, widths, strict=True):
                left = right - width
                bounds = [left, baseline - shaped.bounds[3] * line_scale,
                          right, baseline - shaped.bounds[1] * line_scale]
                glyphs.append({"line": row["line_number"], "kind": row["line_type"],
                               "word_id": word["id"] if word else None,
                               "verse": f"{word['surah_number']}:{word['ayah_number']}" if word else None,
                               "bounds": [round(v, 4) for v in bounds],
                               "commands": place(shaped, left, baseline, line_scale)})
                if word:
                    verse_boxes[(word["surah_number"], word["ayah_number"])].append(bounds)
                right = left - gap
            for (surah, ayah), boxes in verse_boxes.items():
                left, _, right, _ = union(boxes)
                regions.append({"surah": surah, "ayah": ayah, "line": row["line_number"],
                                "rect": [round(left, 4), round(top, 4), round(right, 4), round(top + row_height, 4)]})
            top += row_height
        result = {"schema_version": 1, "status": "draft", "renderer": VERSION,
                  "edition": lock["edition"], "source_commit": lock["commit"],
                  "source_lock_sha256": hashlib.sha256(canonical(lock)).hexdigest(),
                  "page": number, "width": WIDTH, "height": HEIGHT,
                  "glyphs": glyphs, "ayah_regions": regions}
        validate_artifact(result)
        return result
    finally:
        for font in fonts.values():
            font.close()


def validate_artifact(page):
    require(page["status"] == "draft", "Preview artifacts cannot publish content")
    require(page["schema_version"] == 1 and 1 <= page["page"] <= 604, "Invalid page identity")
    require(page["width"] == WIDTH and page["height"] == HEIGHT, "Invalid canvas")
    require(page["glyphs"] and page["ayah_regions"], "Empty page")
    counts = {"M": 3, "L": 3, "Q": 5, "C": 7, "Z": 1}
    expected_regions = defaultdict(list)
    for glyph in page["glyphs"]:
        box = glyph["bounds"]
        require(0 <= box[0] < box[2] <= page["width"] and 0 <= box[1] < box[3] <= page["height"],
                "Glyph ink outside page")
        require(glyph["commands"] and glyph["commands"][0] and glyph["commands"][0][0] == "M",
                "Missing contour start")
        contour = False
        for command in glyph["commands"]:
            require(command and command[0] in counts and len(command) == counts[command[0]], "Invalid path command")
            require(all(isinstance(v, (int, float)) and math.isfinite(v) for v in command[1:]),
                    "Nonfinite path coordinate")
            if command[0] == "M":
                require(not contour, "Unclosed contour")
                contour = True
            else:
                require(contour, "Path command outside contour")
                if command[0] == "Z":
                    contour = False
        require(not contour, "Unclosed contour")
        if glyph["word_id"] is not None:
            require(glyph["kind"] == "ayah" and glyph["verse"], "Missing verse identity")
            expected_regions[(glyph["verse"], glyph["line"])].append(box)
        else:
            require(glyph["verse"] is None and glyph["kind"] != "ayah", "Decoration is not an ayah")
    seen = set()
    for region in page["ayah_regions"]:
        l, t, r, b = region["rect"]
        require(0 <= l < r <= page["width"] and 0 <= t < b <= page["height"], "Invalid ayah region")
        key = (f"{region['surah']}:{region['ayah']}", region["line"])
        require(key in expected_regions and key not in seen, "Unknown/duplicate ayah region")
        seen.add(key)
        # Region boundaries and paths share the same coordinate system and rounding.
        for box in expected_regions[key]:
            require(l <= box[0] and t <= box[1] and r >= box[2] and b >= box[3], "Ayah region misses ink")
    require(seen == set(expected_regions), "Missing ayah regions")
    for index, a in enumerate(page["ayah_regions"]):
        for b in page["ayah_regions"][index + 1:]:
            ar, br = a["rect"], b["rect"]
            require(max(ar[0], br[0]) >= min(ar[2], br[2]) or max(ar[1], br[1]) >= min(ar[3], br[3]),
                    "Overlapping ayah regions")


def mobile_geometry(page):
    """Existing mobile geometry schema, without URLs or a publication claim."""
    validate_artifact(page)
    regions = []
    for index, region in enumerate(page["ayah_regions"]):
        l, t, r, b = region["rect"]
        regions.append({"id": f"{page['edition']}:{page['page']}:{index}",
                        "ayah": {"surah": region["surah"], "number": region["ayah"]},
                        "reading_order": index, "polygon": [],
                        "x": l / WIDTH, "y": t / HEIGHT,
                        "width": (r - l) / WIDTH, "height": (b - t) / HEIGHT})
    return {"number": page["page"], "edition": page["edition"], "status": "draft",
            "content_version": VERSION, "checksum_sha256": hashlib.sha256(canonical(page)).hexdigest(),
            "image_width": WIDTH, "image_height": HEIGHT, "assets": [], "regions": regions}


def svg(page):
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}">',
             f'<title>{escape(page["edition"])} — page {page["page"]} — draft</title>',
             '<rect width="100%" height="100%" fill="#fffcf6"/>']
    for glyph in page["glyphs"]:
        path = " ".join(c[0] + " ".join(str(v) for v in c[1:]) for c in glyph["commands"])
        parts.append(f'<path fill="#241e17" d="{path}"/>')
    return "\n".join(parts + ["</svg>"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True, help="Must not exist; never overwritten")
    parser.add_argument("--lock", type=Path, default=Path(__file__).with_name("source.lock.json"))
    args = parser.parse_args()
    runtime = verify_runtime()
    lock = json.loads(args.lock.read_text())
    verify_files(args.source_dir, lock)
    require(not args.output_dir.exists(), "Output directory already exists; nothing overwritten")
    with closing(open_database(args.source_dir / "mushaf_database.db")) as db:
        report = audit_corpus(db)
        # Validate all selected pages before exposing any output directory.
        pages = [build_page(db, args.source_dir, lock, n) for n in lock["sample_pages"]]
    args.output_dir.mkdir(parents=False, exist_ok=False)
    report.update({"renderer": VERSION, "status": "draft", "source_commit": lock["commit"],
                   **runtime, "pages_prepared": [], "publication_approved": False})
    for page in pages:
        stem = f"page-{page['page']:03d}"
        data = canonical(page)
        svg_data = svg(page).encode()
        geometry_data = canonical(mobile_geometry(page))
        with (args.output_dir / f"{stem}.json").open("xb") as output:
            output.write(data)
        with (args.output_dir / f"{stem}.svg").open("xb") as output:
            output.write(svg_data)
        with (args.output_dir / f"{stem}.mobile.json").open("xb") as output:
            output.write(geometry_data)
        report["pages_prepared"].append({"page": page["page"], "bytes": len(data),
                                         "sha256": hashlib.sha256(data).hexdigest(),
                                         "svg_sha256": hashlib.sha256(svg_data).hexdigest(),
                                         "mobile_sha256": hashlib.sha256(geometry_data).hexdigest(),
                                         "words": sum(g["word_id"] is not None for g in page["glyphs"]),
                                         "ayah_regions": len(page["ayah_regions"])})
    with (args.output_dir / "audit.json").open("xb") as output:
        output.write(canonical(report))
    with (args.output_dir / "index.html").open("x") as output:
        output.write(Path(__file__).with_name("preview.html").read_text())
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
