"""Refresh a dedicated source clone without pruning, then run the shared snapshot CLI."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from ops.recovery.snapshot import RecoveryError, command
from ops.recovery.snapshot import main as snapshot_main


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    try:
        config = json.loads(args.config.read_text())
        repo = Path(config["repository"]).resolve(strict=True)
        if command(["git", "rev-parse", "--is-bare-repository"], cwd=repo) != "true":
            raise RecoveryError("scheduled backups require a dedicated bare repository")
        # Explicit mappings preserve deleted remote branches locally. Immutable snapshots
        # retain earlier ref values, even if a remote branch is force-pushed later.
        command(
            [
                "git",
                "-c",
                "fetch.prune=false",
                "-c",
                "fetch.pruneTags=false",
                "fetch",
                "--no-prune",
                "--no-tags",
                "origin",
                "+refs/heads/*:refs/heads/*",
                "refs/tags/*:refs/tags/*",
            ],
            cwd=repo,
        )
        return snapshot_main(["backup", "--config", str(args.config)])
    except Exception:
        print(
            "ERROR: recovery source refresh failed; snapshot was not marked successful",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
