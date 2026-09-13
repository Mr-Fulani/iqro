"""Reproducible local workspace commands. Python standard library only."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
ENV_FILE = ROOT / "services/backend/.env"
WORK = ROOT / ".dev"
TOOLS = ROOT / "ops/mushaf-glyph-pilot"
COMPOSE = ["docker", "compose", "--env-file", str(ENV_FILE), "-f", str(ROOT / "compose.yaml")]


def run(args, **kwargs):
    environment = os.environ.copy()
    environment.setdefault("LOCAL_UID", str(os.getuid()))
    environment.setdefault("LOCAL_GID", str(os.getgid()))
    return subprocess.run(args, cwd=ROOT, check=True, env=environment, **kwargs)


def compose(*args, **kwargs):
    return run([*COMPOSE, *args], **kwargs)


def manage(*args, **kwargs):
    return compose("exec", "-T", "backend", "python", "manage.py", *args, **kwargs)


def write_once(path: Path, data: bytes):
    if path.is_symlink():
        raise ValueError(f"Refusing symlink: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with path.open("xb") as stream:
            stream.write(data)
    except FileExistsError:
        if path.read_bytes() != data:
            raise ValueError(f"Existing file differs; preserved: {path}") from None


def init():
    if ENV_FILE.exists():
        print("Existing services/backend/.env preserved.")
        return
    template = (ROOT / "services/backend/.env.example").read_text()
    lines = []
    for line in template.splitlines():
        key, separator, value = line.partition("=")
        if separator and value.startswith("replace-"):
            value = secrets.token_hex(32)
        if key == "DJANGO_ALLOWED_HOSTS":
            value = "localhost,127.0.0.1,10.0.2.2,backend,web"
        lines.append(f"{key}={value}" if separator else line)
    # The umask prevents a window with world-readable credentials.
    previous = os.umask(0o077)
    try:
        write_once(ENV_FILE, ("\n".join(lines) + "\n").encode())
    finally:
        os.umask(previous)
    print("Created services/backend/.env. Set QF_CLIENT_ID, QF_CLIENT_SECRET and QF_ENV.")


def require_credentials():
    # Check presence without displaying secret values or sourcing shell code.
    values = {key.strip(): value.strip()
              for line in ENV_FILE.read_text().splitlines()
              if "=" in line and not line.lstrip().startswith("#")
              for key, value in [line.split("=", 1)]}
    missing = [key for key in ("QF_CLIENT_ID", "QF_CLIENT_SECRET")
               if not values.get(key, "").strip().strip("\"'")]
    if missing:
        raise ValueError("Fill services/backend/.env: " + ", ".join(missing))


@contextmanager
def setup_lock():
    """Serialize startup/imports in one checkout; keep the lock file for reuse."""
    WORK.mkdir(parents=True, exist_ok=True)
    with (WORK / "setup.lock").open("a") as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError("Local setup is already running in this checkout") from None
        try:
            yield
        finally:
            fcntl.flock(stream, fcntl.LOCK_UN)


def backup_before_migration():
    pending = subprocess.run(
        [*COMPOSE, "run", "--no-deps", "-T", "migrate", "python", "manage.py", "migrate", "--check"],
        cwd=ROOT, check=False,
    )
    if pending.returncode == 0:
        return
    existing = compose("exec", "-T", "postgres", "sh", "-c",
                       'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT to_regclass(\'public.django_migrations\')"',
                       capture_output=True).stdout.strip()
    if not existing:
        return
    path = WORK / "backups" / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + ".dump")
    path.parent.mkdir(parents=True, exist_ok=True)
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as stream:
        compose("exec", "-T", "postgres", "sh", "-c",
                'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc', stdout=stream)
    with path.open("rb") as stream:
        compose("exec", "-T", "postgres", "pg_restore", "--list", stdin=stream,
                stdout=subprocess.DEVNULL)
    print(f"Verified backup before pending migrations: {path.relative_to(ROOT)}")


def up(*, web_only=False, build=True):
    init()
    (ROOT / "services/backend/media").mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    if build:
        compose("build", "backend", "web")
    compose("up", "--detach", "--wait", "postgres", "redis")
    backup_before_migration()
    compose("up", "--detach", "--wait", "backend")
    data(web_only=web_only, build=build)
    compose("up", "--detach", "--wait", "web", "worker", "beat")
    print(f"Web: http://localhost:{os.environ.get('LOCAL_WEB_PORT', '3000')} · "
          f"API: http://localhost:{os.environ.get('LOCAL_API_PORT', '8000')}/api/v1")
    print("Local application and data are ready.")


def download(url: str, checksum: str, target: Path, *, max_bytes: int):
    if target.exists():
        data = target.read_bytes()
    else:
        with urllib.request.urlopen(url, timeout=90) as response:
            data = response.read(max_bytes + 1)
    if len(data) > max_bytes or hashlib.sha256(data).hexdigest() != checksum:
        raise ValueError(f"Source checksum/size mismatch: {target.name}")
    write_once(target, data)


def prepare_source(snapshot: bytes) -> Path:
    data = json.loads(snapshot)
    if (data.get("source_id"), data.get("pages_count"), len(data.get("pages", []))) != (5, 604, 604):
        raise ValueError("Expected complete QF source 5")
    checksum = hashlib.sha256(snapshot).hexdigest()
    directory = WORK / "mushaf" / checksum
    lock = json.loads((TOOLS / "kfgqpc.source.lock.json").read_bytes())
    lock.update(publication_scope="local", snapshot_sha256=checksum,
                source_checksum_sha256=data["source_checksum_sha256"])
    write_once(directory / "source/snapshot.json", snapshot)
    write_once(directory / "source/lock.json", json.dumps(lock, sort_keys=True).encode())
    download(lock["font_url"], lock["font_sha256"],
             directory / "source/UthmanicHafs1Ver18.woff2", max_bytes=lock["font_bytes"])
    return directory


def render_directory(directory: Path) -> Path:
    identity = hashlib.sha256(b"".join((TOOLS / name).read_bytes() for name in (
        "prepare.py", "kfgqpc.py", "build_full.py", "raster.cjs", "render_page.cjs",
        "requirements.txt", "package-lock.json", "Dockerfile",
    ))).hexdigest()[:20]
    return directory / f"rendered-{identity}"


def data_status(*, web_only=False):
    return json.loads(manage("dev_data_status", "--json",
                             *([] if web_only else ["--require-mobile"]),
                             capture_output=True).stdout)


def data(*, web_only=False, refresh=False, build=True):
    status = data_status(web_only=web_only)
    if status["ready"] and not refresh:
        print("All local data already available; no downloads or rendering needed.", flush=True)
        return
    require_credentials()
    checks = status["checks"]
    print("Preparing local content: " + ", ".join(k for k, ready in checks.items() if not ready),
          flush=True)
    for snapshot in status["missing_dua"]:
        manage("import_dua_catalog", f"src/quran_backend/modules/dua/data/{snapshot}", "--publish")
    if not checks["mushaf"] or refresh:
        manage("sync_quran_foundation_mushafs", "--source-id", "5")
    # Import constants without loading Django or requiring host backend packages.
    if not checks["canonical"]:
        source = json.loads((ROOT / "services/backend/docs/quran-sources.lock.json").read_bytes())["corpus"]
        corpus = WORK / "sources" / f'{source["quran_json_sha256"]}.json'
        download(f'https://raw.githubusercontent.com/mjmirza/quran-dataset/{source["commit"]}/data/quran.json',
                 source["quran_json_sha256"], corpus, max_bytes=32 * 1024 * 1024)
        manage("import_quran_corpus", "/app/" + str(corpus.relative_to(ROOT)))
    # Each resource has an independent checkpoint. A later failure keeps completed imports.
    for kind in ("translations", "tafsirs"):
        ids = status[f"configured_{kind}"] if refresh else status[f"missing_{kind}"]
        for resource_id in ids:
            print(f"Preparing {kind}: {resource_id}", flush=True)
            manage(f"sync_quran_foundation_{kind}", "--resource-id", str(resource_id))
    if not checks["audio"]:
        manage("sync_quran_foundation_audio", "--reciter-id", "159", "--all-surahs",
               "--content-version", "local-dev-v1", "--publish", "--resume")
    # A source refresh can invalidate a previously published image package.
    current = data_status(web_only=web_only)
    if not web_only and not current["checks"]["mobile"]:
        snapshot = manage("export_qf_mushaf_source", "--mushaf", "5", capture_output=True).stdout
        directory = prepare_source(snapshot)
        relative = str(directory.relative_to(WORK / "mushaf"))
        rendered = render_directory(directory)
        if build:
            compose("--profile", "tools", "build", "mushaf-tools")
        print("Preparing 604 pages for mobile. Repeated runs verify and reuse existing files.", flush=True)
        compose("--profile", "tools", "run", "--no-deps", "-T", "mushaf-tools",
                "python", "kfgqpc.py", "--source-dir", f"/data/{relative}/source",
                "--workers", "2",
                "--source-lock", f"/data/{relative}/source/lock.json",
                "--output-dir", f"/data/{relative}/{rendered.name}")
        manifest = "/app/" + str((rendered / "manifest.json").relative_to(ROOT))
        manage("publish_mushaf_rendition", manifest)
    manage("dev_data_status", *([] if web_only else ["--require-mobile"]))


def doctor():
    failed = False
    for command in ("docker",):
        found = shutil.which(command)
        print(f"{command}: {'available' if found else 'missing'}")
        failed |= found is None
    print(f"backend .env: {'present' if ENV_FILE.is_file() else 'missing (make dev-init)'}")
    if failed or not ENV_FILE.is_file():
        raise ValueError("Install prerequisites and run make dev-init")
    compose("config", "--quiet")
    manage("migrate", "--check")
    manage("dev_data_status", "--require-mobile")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("init", "up", "data", "doctor"))
    parser.add_argument("--web-only", action="store_true", help="Skip mobile page rendering")
    parser.add_argument("--extras", action="store_true", help="Compatibility flag: translations/Tafsirs are always included")
    parser.add_argument("--refresh", action="store_true", help="Refresh QF Mushaf, translations and Tafsirs; normal startup only fills missing data")
    parser.add_argument("--no-build", action="store_true", help="Reuse existing local images (they must already be built)")
    args = parser.parse_args()
    if args.refresh and args.command != "data":
        parser.error("--refresh is supported by the data command only")
    try:
        if args.command in ("up", "data"):
            with setup_lock():
                if args.command == "up":
                    up(web_only=args.web_only, build=not args.no_build)
                else:
                    data(web_only=args.web_only, refresh=args.refresh, build=not args.no_build)
        else:
            {"init": init, "up": up, "doctor": doctor}[args.command]()
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"Local setup failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
