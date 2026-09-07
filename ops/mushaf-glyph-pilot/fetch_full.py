"""Fetch pinned public source data; resume only byte-identical files, never overwrite."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import urllib.request

COMMIT = "1d040f68d284f8e6db515157f8425abfefd78df6"
ORIGIN = f"https://raw.githubusercontent.com/JMApps/mymushaf/{COMMIT}/"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tree", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    tree = json.loads(args.tree.read_text())
    if tree.get("sha") != COMMIT or tree.get("truncated"):
        raise ValueError("Wrong/incomplete pinned source tree")
    entries = {e["path"]: e for e in tree["tree"] if e["type"] == "blob"}
    paths = ["assets/databases/mushaf_database.db", "assets/fonts/surah_name_v4.ttf"]
    paths += [f"assets/pageFonts/p{n}.ttf" for n in range(1, 605)]
    if any(p not in entries for p in paths):
        raise ValueError("Source tree does not contain the full font set")
    args.output.mkdir(exist_ok=True)
    if args.output.is_symlink():
        raise ValueError("Output must not be a symlink")

    def fetch(source_path):
        entry = entries[source_path]
        name = Path(source_path).name
        target = args.output / name
        if target.is_symlink():
            raise ValueError(f"Symlink: {name}")
        if target.exists():
            data = target.read_bytes()
        else:
            request = urllib.request.Request(ORIGIN + source_path, headers={"User-Agent": "IQRO-source-audit"})
            with urllib.request.urlopen(request, timeout=90) as response:
                data = response.read(entry["size"] + 1)
        git_hash = hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()
        if len(data) != entry["size"] or git_hash != entry["sha"]:
            raise ValueError(f"Pinned git object differs: {name}")
        if not target.exists():
            with target.open("xb") as stream:
                stream.write(data)
        return name, {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                      "git_blob_sha1": git_hash, "source_path": source_path}

    files = {}
    with ThreadPoolExecutor(max_workers=4) as pool:
        for index, (name, spec) in enumerate(pool.map(fetch, paths), 1):
            files[name] = spec
            if index % 25 == 0 or index == len(paths):
                print(f"Verified source files: {index}/{len(paths)}", flush=True)
    lock = {"schema_version": 1, "edition": "qcf-v2-hafs", "status": "draft",
            "repository": "https://github.com/JMApps/mymushaf", "commit": COMMIT,
            "source_pages": 604, "sample_pages": list(range(1, 605)),
            "publication_approved": False, "files": files}
    payload = json.dumps(lock, ensure_ascii=False, sort_keys=True, indent=2).encode()
    destination = args.output / "source.full.lock.json"
    if destination.exists():
        if destination.read_bytes() != payload:
            raise ValueError("Existing lock differs; nothing overwritten")
    else:
        with destination.open("xb") as stream:
            stream.write(payload)
    print(f"Source complete: {sum(s['bytes'] for s in files.values())} bytes", flush=True)


if __name__ == "__main__":
    main()
