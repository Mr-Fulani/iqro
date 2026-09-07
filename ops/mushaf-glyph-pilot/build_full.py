"""Build/resume a complete staging-only rendition, one page in memory at a time."""
import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import subprocess

import prepare as p


def write_once(path, payload):
    if path.is_symlink():
        raise ValueError("Symlink artifact")
    if path.exists():
        p.require(path.read_bytes() == payload, "Existing artifact differs; nothing overwritten")
    else:
        with path.open("xb") as stream:
            stream.write(payload)


def reuse_raster(cache, output, stem, vector):
    """Reuse only a byte-verified raster of the exact freshly rebuilt SVG."""
    if cache is None or not (cache / f"{stem}.bundle.json").is_file():
        return None
    entry = json.loads((cache / f"{stem}.bundle.json").read_text())
    if entry["source_svg_sha256"] != hashlib.sha256(vector).hexdigest():
        return None
    p.require([a["width"] for a in entry["assets"]] == [720, 1440, 2160], "Bad cached widths")
    for asset in entry["assets"]:
        name = asset["path"]
        p.require(Path(name).name == name, "Unsafe cached path")
        file = cache / name
        p.require(not file.is_symlink() and file.stat().st_size == asset["bytes"] and
                  p.digest(file) == asset["sha256"], "Cached raster integrity check failed")
        write_once(output / name, file.read_bytes())
    return entry["assets"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--raster-cache-dir", type=Path)
    parser.add_argument("--pages", help="Comma-separated sample; never writes a publication manifest")
    args = parser.parse_args()
    selected = list(map(int, args.pages.split(","))) if args.pages else list(range(1, 605))
    p.require(selected == sorted(set(selected)) and all(1 <= n <= 604 for n in selected), "Invalid page selection")
    runtime = p.verify_runtime()
    lock = json.loads((args.source_dir / "source.full.lock.json").read_text())
    p.require(lock["sample_pages"] == list(range(1, 605)), "Full source lock required")
    p.verify_files(args.source_dir, lock)
    args.output_dir.mkdir(exist_ok=True)
    p.require(not args.output_dir.is_symlink(), "Output must not be a symlink")
    identity = {"schema_version": 1, "edition": lock["edition"], "source_commit": lock["commit"],
                "source_lock_sha256": hashlib.sha256(p.canonical(lock)).hexdigest(),
                "renderer": p.VERSION, "runtime": runtime, "widths": [720, 1440, 2160]}
    identity["renderer_code_sha256"] = hashlib.sha256(b"".join(
        Path(__file__).with_name(name).read_bytes()
        for name in ("prepare.py", "build_full.py", "raster.cjs", "render_page.cjs"))).hexdigest()
    write_once(args.output_dir / "build-identity.json", p.canonical(identity))
    entries = []
    with closing(p.open_database(args.source_dir / "mushaf_database.db")) as db:
        audit = p.audit_corpus(db)
        for number in selected:
            stem = f"page-{number:03d}"
            receipt = args.output_dir / f"{stem}.bundle.json"
            if receipt.exists():
                entry = json.loads(receipt.read_text())
                p.require(entry["page"] == number, "Wrong resume page")
                for asset in [*entry["assets"], entry["geometry"]]:
                    name = asset["path"]
                    p.require(Path(name).name == name, "Invalid resume path")
                    file = args.output_dir / name
                    p.require(not file.is_symlink() and file.stat().st_size == asset["bytes"] and
                              p.digest(file) == asset["sha256"], "Resume integrity check failed")
            else:
                page = p.build_page(db, args.source_dir, lock, number)
                geometry = p.canonical(p.mobile_geometry(page))
                vector = p.svg(page).encode()
                assets = reuse_raster(args.raster_cache_dir, args.output_dir, stem, vector)
                if assets is None:
                    result = subprocess.run(
                        ["node", str(Path(__file__).with_name("render_page.cjs")), str(args.output_dir), stem],
                        input=vector, capture_output=True, check=True, timeout=120)
                    assets = json.loads(result.stdout)
                geometry_name = f"{stem}.mobile.json"
                write_once(args.output_dir / geometry_name, geometry)
                entry = {"page": number, "source_svg_sha256": hashlib.sha256(vector).hexdigest(),
                         "geometry": {"path": geometry_name, "bytes": len(geometry),
                                      "sha256": hashlib.sha256(geometry).hexdigest()}, "assets": assets}
                write_once(receipt, p.canonical(entry))
            entries.append(entry)
            if number % 10 == 0 or number == 604:
                print(f"Verified native pages: {number}/604", flush=True)
    p.verify_files(args.source_dir, lock)
    if args.pages:
        print(f"Verified {len(entries)} sample pages; no publication manifest", flush=True)
        return
    manifest = {**identity, "status": "prepared", "publication_scope": "staging",
                "canonical_edition": "madani-hafs", "version": "qcf-v2-iqro-20260908-v4",
                "page_count": 604, "corpus_audit": audit, "pages": entries}
    payload = p.canonical(manifest)
    write_once(args.output_dir / "manifest.json", payload)
    write_once(args.output_dir / "manifest.sha256", f"{hashlib.sha256(payload).hexdigest()}  manifest.json\n".encode())
    print(f"Complete staging bundle: {sum(a['bytes'] for e in entries for a in e['assets'])} raster bytes", flush=True)


if __name__ == "__main__":
    main()
