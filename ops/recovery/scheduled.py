"""Rotate verified old local sets, refresh a dedicated source clone without git pruning,
then run the shared snapshot CLI."""

from __future__ import annotations

import argparse
import json
import os
import sys
from html import escape
from pathlib import Path

from ops.monitoring.alerts import send
from ops.monitoring.backup_status import backup_lock
from ops.postgres.offsite import load_settings, object_store
from ops.recovery.retention import RetentionError, prune_local_recovery
from ops.recovery.snapshot import RecoveryError, command
from ops.recovery.snapshot import main as snapshot_main


def prune(config: dict) -> None:
    """Free space from old local sets before the space check; never blocks the backup."""
    environment = escape(os.environ.get("BACKUP_ENVIRONMENT", "production"))
    try:
        settings = load_settings()
        status_dir = Path(os.environ["RECOVERY_STATUS_FILE"]).parent
        with backup_lock(status_dir):
            report = prune_local_recovery(
                settings,
                object_store(settings),
                recovery_dir=Path(config["output_dir"]),
            )
    except Exception as exc:  # noqa: BLE001 - rotation is best-effort; the backup still runs.
        reason = str(exc) if isinstance(exc, RetentionError) else type(exc).__name__
        print(f"WARNING: local recovery rotation skipped ({reason})", file=sys.stderr)
        send(
            f"<b>⚠️ Автоочистка старых локальных наборов не выполнена ({environment})</b>\n"
            f"<code>{escape(reason[:200])}</code>\n"
            f"Проверьте: journalctl -u quran-recovery@{environment}"
        )
        return
    lines = []
    if report["removed"]:
        freed = sum(item["bytes"] for item in report["removed"])
        names = ", ".join(item["snapshot"][:16] for item in report["removed"])
        print(
            f"Removed {len(report['removed'])} old local recovery sets, {freed} bytes"
        )
        lines.append(
            f"Удалено старых локальных наборов: {len(report['removed'])}, "
            f"освобождено {freed / 1e9:.1f} ГБ ({escape(names)}). "
            "Их копии в R2 проверены и не тронуты."
        )
    for item in report["kept"]:
        print(f"WARNING: kept {item['snapshot']}: {item['reason']}", file=sys.stderr)
        lines.append(
            f"Оставлен {escape(item['snapshot'][:16])}: проверка не прошла "
            f"(<code>{escape(item['reason'])}</code>)."
        )
    if lines:
        icon = "⚠️" if report["kept"] else "🧹"
        send(f"<b>{icon} Резервные копии ({environment})</b>\n" + "\n".join(lines))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    try:
        config = json.loads(args.config.read_text())
        prune(config)
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
