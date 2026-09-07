"""Build the existing QF resource 5 as an interactive IQRO page rendition.

Uses the unmodified, checksum-pinned QPC Unicode words/font. The composition is
IQRO's, not a claim of official print facsimile. No network or publication here.
"""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import subprocess

import prepare as p
from build_full import write_once

VERSION = "iqro-kfgqpc-1"
FONT = "UthmanicHafs1Ver18.woff2"


def load_source(root):
    lock = json.loads(Path(__file__).with_name("kfgqpc.source.lock.json").read_text())
    p.require(p.digest(root / "snapshot.json") == lock["snapshot_sha256"], "Snapshot checksum differs")
    p.require(p.digest(root / FONT) == lock["font_sha256"], "Font checksum differs")
    data = json.loads((root / "snapshot.json").read_bytes())
    p.require(data["source_id"] == 5 and data["source_checksum_sha256"] == lock["source_checksum_sha256"],
              "Wrong QF source")
    p.require(data["qirat_name"] == "Hafs" and data["pages_count"] == 604 and data["lines_per_page"] == 15,
              "Unsupported Quran edition")
    return data, lock


def audit(data):
    p.require([s["number"] for s in data["surahs"]] == list(range(1, 115)), "Missing surahs")
    refs = [(s["number"], n) for s in data["surahs"] for n in range(1, s["ayah_count"] + 1)]
    p.require(len(refs) == 6236, "Incomplete canonical references")
    references = dict(enumerate(refs, 1))
    p.require([page["page_number"] for page in data["pages"]] == list(range(1, 605)), "Missing pages")
    seen_ids, per_verse, endings = set(), defaultdict(list), defaultdict(list)
    for page in data["pages"]:
        words = page["words"]
        p.require(words and [w["position_in_page"] for w in words] == list(range(1, len(words) + 1)),
                  "Word sequence differs")
        p.require([w["line_number"] for w in words] == sorted(w["line_number"] for w in words),
                  "Line order differs")
        actual = set()
        for word in words:
            p.require(word["id"] not in seen_ids, "Duplicate source word")
            seen_ids.add(word["id"])
            p.require(word["page_number"] == page["page_number"] and 1 <= word["line_number"] <= 15,
                      "Wrong word page/line")
            key = references[word["verse_id"]]
            actual.add(key)
            per_verse[word["verse_id"]].append(word["position_in_verse"])
            p.require(word["char_type_name"] in ("word", "end") and word["text"], "Unsupported source word")
            # QF word 621307 is labelled 'word', but contains the unmodified
            # terminal number ١٨١. Recognize numeric markers; do not insert text.
            if word["text"].isdecimal():
                p.require(int(word["text"]) == key[1], "Wrong terminal ayah number")
                endings[word["verse_id"]].append(word["position_in_verse"])
            elif word["char_type_name"] == "end":
                raise ValueError("Non-numeric end marker")
        expected = set()
        for surah, ranges in page["verse_mapping"].items():
            for interval in ranges.split(","):
                bounds = list(map(int, interval.split("-")))
                expected.update((int(surah), a) for a in range(bounds[0], bounds[-1] + 1))
        p.require(actual == expected, "Page verse mapping differs")
    p.require(set(per_verse) == set(references), "Missing verse words")
    for key, positions in per_verse.items():
        p.require(positions == list(range(1, len(positions) + 1)), "Verse word gap")
        p.require(endings[key] == [len(positions)], "Missing/misplaced terminal marker")
    return references


def compose(data, page, font, references, lock):
    number = page["page_number"]
    groups = defaultdict(list)
    for word in page["words"]:
        surah, ayah = references[word["verse_id"]]
        groups[word["line_number"]].append((font.shape(word["text"]),
            {**word, "surah_number": surah, "ayah_number": ayah}))
    rows = {line: ({"line_number": line, "line_type": "ayah", "is_centered": number in (1, 2)}, items)
            for line, items in groups.items()}
    basmala = [w["text"] for w in data["pages"][0]["words"] if w["verse_id"] == 1 and w["char_type_name"] == "word"]
    for word in page["words"]:
        surah, ayah = references[word["verse_id"]]
        if ayah != 1 or word["position_in_verse"] != 1:
            continue
        first = word["line_number"]
        header = first - (1 if surah in (1, 9) else 2)
        # Some QF pages start the first ayah on line 2: the heading belongs
        # above the 15 source rows. Reserve a separate header row, not a
        # replacement for an ayah or an omitted introductory basmala.
        p.require(header >= 0 and header not in rows, f"No heading slot on page {number}")
        text = data["surahs"][surah - 1]["name_ar"]
        rows[header] = ({"line_number": header, "line_type": "surah_name", "is_centered": True},
                        [(font.shape(w), None) for w in text.split(" ")])
        if surah not in (1, 9):
            p.require(first - 1 not in rows, "No source basmala slot")
            rows[first - 1] = ({"line_number": first - 1, "line_type": "basmallah", "is_centered": True},
                              [(font.shape(w), None) for w in basmala])
    lines = list(range(min(rows), max(rows) + 1))
    row_height = p.ROW * 15 / max(15, len(lines))
    # Empty source rows remain empty; they are never filled with guessed words.
    verse_lines = [items for row, items in rows.values() if row["line_type"] == "ayah"]
    longest = max(sum(s.width for s, _ in items) for items in verse_lines)
    ink_height = sum(max(s.bounds[3] for s, _ in items) - min(s.bounds[1] for s, _ in items)
                     for items in verse_lines)
    scale = min((p.WIDTH - 2 * p.MARGIN - 48) / longest, len(verse_lines) * (row_height - 6) / ink_height)
    leading = (len(verse_lines) * row_height - ink_height * scale) / len(verse_lines)
    top = p.TOP + (15 - len(lines)) * row_height / 2 if number in (1, 2) else p.TOP
    glyphs, regions = [], []
    for line in lines:
        if line not in rows:
            top += row_height
            continue
        row, items = rows[line]
        if row["line_type"] == "ayah":
            line_scale = scale
            ascent, descent = max(s.bounds[3] for s, _ in items), min(s.bounds[1] for s, _ in items)
            height = (ascent - descent) * scale + leading
            baseline = top + leading / 2 + ascent * scale
        else:
            height = row_height
            box = p.union([s.bounds for s, _ in items])
            line_scale = min(row_height * .6 / (box[3] - box[1]), p.WIDTH * .66 / sum(s.width for s, _ in items))
            baseline = top + row_height / 2 + (box[3] + box[1]) * line_scale / 2
        widths = [s.width * line_scale for s, _ in items]
        # Do not spread the few words of a short closing line across the
        # entire screen. Only spacing changes; font size and source rows do not.
        natural_gap = (p.WIDTH - 2 * p.MARGIN - sum(widths)) / max(1, len(items) - 1)
        centered = row["is_centered"] or len(items) == 1 or natural_gap > 72
        gap = 12 if centered else (p.WIDTH - 2 * p.MARGIN - sum(widths)) / (len(items) - 1)
        p.require(gap >= 0, "Line overflow")
        total = sum(widths) + gap * (len(items) - 1)
        right = (p.WIDTH + total) / 2 if centered else p.WIDTH - p.MARGIN
        boxes = defaultdict(list)
        for (shape, word), width in zip(items, widths, strict=True):
            left = right - width
            bounds = [left, baseline - shape.bounds[3] * line_scale, right, baseline - shape.bounds[1] * line_scale]
            verse = f"{word['surah_number']}:{word['ayah_number']}" if word else None
            glyphs.append({"line": line, "kind": row["line_type"], "word_id": word["id"] if word else None,
                           "verse": verse, "bounds": [round(v, 4) for v in bounds],
                           "commands": p.place(shape, left, baseline, line_scale)})
            if word:
                boxes[(word["surah_number"], word["ayah_number"])].append(bounds)
            right = left - gap
        for (surah, ayah), values in boxes.items():
            left, _, right, _ = p.union(values)
            regions.append({"surah": surah, "ayah": ayah, "line": line,
                            "rect": [round(v, 4) for v in (left, top, right, top + height)]})
        top += height
    result = {"schema_version": 1, "status": "draft", "renderer": VERSION, "edition": "kfgqpc-hafs",
              "source_lock_sha256": hashlib.sha256(p.canonical(lock)).hexdigest(),
              "page": number, "width": p.WIDTH, "height": p.HEIGHT, "glyphs": glyphs, "ayah_regions": regions}
    p.validate_artifact(result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--pages", help="Comma-separated page sample; cannot produce a publishable manifest")
    parser.add_argument("--audit-only", action="store_true")
    args = parser.parse_args()
    runtime = p.verify_runtime()
    data, lock = load_source(args.source_dir)
    references = audit(data)
    selected = list(map(int, args.pages.split(","))) if args.pages else list(range(1, 605))
    p.require(selected == sorted(set(selected)) and all(1 <= n <= 604 for n in selected), "Invalid page selection")
    args.output_dir.mkdir(exist_ok=True)
    p.require(not args.output_dir.is_symlink(), "Symlink output")
    identity = {"schema_version": 1, "edition": "kfgqpc-hafs", "source": {"kind": "quran-foundation", **lock},
                "renderer": VERSION, "runtime": runtime, "widths": [720, 1440, 2160],
                "renderer_code_sha256": hashlib.sha256(b"".join(Path(__file__).with_name(n).read_bytes()
                   for n in ("prepare.py", "kfgqpc.py", "raster.cjs", "render_page.cjs"))).hexdigest()}
    write_once(args.output_dir / "build-identity.json", p.canonical(identity))
    font = p.SourceFont(args.source_dir / FONT, "KFGQPC HAFS Uthmanic Script")
    entries = []
    try:
        for number in selected:
            page = compose(data, data["pages"][number - 1], font, references, lock)
            if args.audit_only:
                continue
            stem = f"page-{number:03d}"
            vector = p.svg(page).encode()
            receipt = args.output_dir / f"{stem}.bundle.json"
            if receipt.exists():
                entry = json.loads(receipt.read_bytes())
                p.require(entry["source_svg_sha256"] == hashlib.sha256(vector).hexdigest(), "Resume rendering differs")
                for spec in [entry["geometry"], *entry["assets"]]:
                    p.require(Path(spec["path"]).name == spec["path"], "Unsafe resume file")
                    file = args.output_dir / spec["path"]
                    p.require(not file.is_symlink() and file.stat().st_size == spec["bytes"] and p.digest(file) == spec["sha256"],
                              "Resume integrity check failed")
            else:
                raster = subprocess.run(["node", str(Path(__file__).with_name("render_page.cjs")), str(args.output_dir), stem],
                                        input=vector, capture_output=True, check=True, timeout=120)
                geometry = p.canonical(p.mobile_geometry(page))
                name = f"{stem}.mobile.json"
                write_once(args.output_dir / name, geometry)
                entry = {"page": number, "source_svg_sha256": hashlib.sha256(vector).hexdigest(),
                         "geometry": {"path": name, "bytes": len(geometry), "sha256": hashlib.sha256(geometry).hexdigest()},
                         "assets": json.loads(raster.stdout)}
                write_once(receipt, p.canonical(entry))
            entries.append(entry)
            print(f"KFGQPC pages: {len(entries)}/{len(selected)}", flush=True)
    finally:
        font.close()
    load_source(args.source_dir)
    if not args.pages and not args.audit_only:
        manifest = {**identity, "status": "prepared", "publication_scope": "staging", "canonical_edition": "madani-hafs",
                    "version": "kfgqpc-iqro-20260907-v1", "page_count": 604, "pages": entries}
        raw = p.canonical(manifest)
        write_once(args.output_dir / "manifest.json", raw)
        write_once(args.output_dir / "manifest.sha256", f"{hashlib.sha256(raw).hexdigest()}  manifest.json\n".encode())
    print(f"Verified {len(selected)} KFGQPC pages; canonical references: {len(references)}", flush=True)


if __name__ == "__main__":
    main()
