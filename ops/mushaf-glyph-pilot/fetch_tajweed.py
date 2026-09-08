"""Acquire public QF19 fonts; freeze their exact bytes in a new immutable lock.

No credentials, database mutation, upload or overwriting. Snapshot must be a
read-only export of the source already present on the backend.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess

from build_full import write_once
import prepare as p

SOURCE_SHA = "b7f0bcd06bfd51232555a163c1f1ce404bd62b14791ce357c7c5689d70b72e60"
BASE = "https://verses.quran.foundation/fonts/quran/hafs/v4/colrv1/woff2"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--lock-output", required=True, type=Path)
    args = parser.parse_args()
    data = json.loads((args.source_dir / "snapshot.json").read_bytes())
    p.require(data["source_id"] == 19 and data["source_checksum_sha256"] == SOURCE_SHA, "Wrong snapshot")
    def fetch(number):
        name = f"p{number}.woff2"
        file = args.source_dir / name
        if not file.exists():
            result = subprocess.run(["curl", "-fSs", "--retry", "3", "--max-time", "90", f"{BASE}/{name}"], capture_output=True, check=True)
            p.require(1000 < len(result.stdout) < 2_000_000 and result.stdout[:4] == b"wOF2", "Invalid font response")
            write_once(file, result.stdout)
        p.require(not file.is_symlink() and file.read_bytes()[:4] == b"wOF2", "Invalid cached font")
        return name, {"sha256": p.digest(file), "bytes": file.stat().st_size}
    with ThreadPoolExecutor(max_workers=6) as pool:
        files = {}
        for name, info in pool.map(fetch, range(1, 605)):
            files[name] = info
            if len(files) % 50 == 0:
                print(f"QF19 verified font downloads: {len(files)}/604", flush=True)
    lock = {"source_id": 19, "source_checksum_sha256": SOURCE_SHA,
            "snapshot_sha256": p.digest(args.source_dir / "snapshot.json"),
            "font_url_template": BASE + "/p{page}.woff2", "palette_index": 0, "files": files}
    write_once(args.lock_output, p.canonical(lock))
    print(f"Pinned {len(files)} fonts; lock SHA256 {hashlib.sha256(p.canonical(lock)).hexdigest()}")


if __name__ == "__main__":
    main()
