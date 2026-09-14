"""Build checked QUL line profiles from downloaded SQLite and QF snapshots.

Usage: python build_qul_layouts.py LAYOUT_DIRECTORY SNAPSHOT_DIRECTORY OUTPUT_DIRECTORY
Inputs are read-only. No network, credentials or database writes are needed.
"""

import hashlib
import json
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

PROFILES = {
    "qpc-v1-15-lines": (15, (2, 10, 11, 12)),
    "qpc-v2-15-lines": (10, (1, 4, 5, 16)),
    "qpc-v4-tajweed-15-lines": (19, (19,)),
    "qudratullah-indopak-15-lines": (12, (6, 14)),
    "taj-indopak-16-lines": (11, (7, 15)),
}
# QF stores these adjacent QUL tokens as one word: بَعْدَ مَا.
JOINED_WORDS = {(2, 181): 3, (8, 6): 4, (13, 37): 8}


def build(layout_directory: Path, snapshot_directory: Path, output: Path) -> None:
    def snapshot(source: int) -> list[dict]:
        return json.loads((snapshot_directory / f"mushaf-{source}.json").read_text())["records"]

    canonical = snapshot(1)
    counts = defaultdict(int)
    for record in canonical:
        if record["record_type"] == "mushaf_page":
            for surah, ranges in record["verse_mapping"].items():
                counts[int(surah)] = max(
                    counts[int(surah)],
                    *(int(n) for part in ranges.split(",") for n in part.split("-")),
                )
    assert len(counts) == 114 and sum(counts.values()) == 6236
    offsets, total = {}, 0
    for surah, count in sorted(counts.items()):
        offsets[surah], total = total, total + count
    identities = {
        (w["verse_id"], w["position_in_verse"]): w["word_id"]
        for w in canonical if w["record_type"] == "mushaf_word"
    }
    companion = layout_directory / "indopak-nastaleeq.db"
    with sqlite3.connect(f"file:{companion}?mode=ro", uri=True) as db:
        word_index = {}
        for index, surah, ayah, position in db.execute("SELECT id, surah, ayah, word FROM words"):
            join = JOINED_WORDS.get((surah, ayah))
            if join is not None and position > join:
                position -= 1
            word_index[index] = identities[(offsets[surah] + ayah, position)]
    output.mkdir(parents=True, exist_ok=True)
    for name, (resource, source_ids) in PROFILES.items():
        path = layout_directory / f"{name}.db"
        pages = defaultdict(list)
        with sqlite3.connect(f"file:{path}?mode=ro", uri=True) as db:
            title, page_count, line_count, _ = db.execute("SELECT * FROM info").fetchone()
            for page, line, kind, centered, first, last, surah in db.execute(
                "SELECT * FROM pages ORDER BY page_number, line_number"
            ):
                ids = list(dict.fromkeys(word_index[i] for i in range(first, last + 1))) if kind == "ayah" else []
                pages[str(page)].append({
                    "line_number": line, "line_type": kind, "is_centered": bool(centered),
                    "surah_number": surah or None, "word_ids": ids,
                })
        assert len(pages) == page_count
        for source in source_ids:
            actual = defaultdict(list)
            for word in snapshot(source):
                if word["record_type"] == "mushaf_word":
                    actual[str(word["page_number"])].append(word["word_id"])
            assert actual.keys() == pages.keys(), source
            for page, rows in pages.items():
                expected = [w for row in rows for w in row["word_ids"]]
                assert len(expected) == len(set(expected)) == len(actual[page]), (source, page)
                assert set(expected) == set(actual[page]), (source, page)
        profile = {
            "version": 1, "name": title.strip(), "qf_source_ids": source_ids,
            "source_url": f"https://qul.tarteel.ai/resources/mushaf-layout/{resource}",
            "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "companion_sha256": hashlib.sha256(companion.read_bytes()).hexdigest(),
            "lines_per_page": line_count, "pages": pages,
        }
        (output / f"{name}.json").write_text(json.dumps(profile, ensure_ascii=False, separators=(",", ":")) + "\n")
        print(f"{name}: {page_count} pages, QF {source_ids}, all words verified")


if __name__ == "__main__":
    build(*(Path(argument) for argument in sys.argv[1:]))
