"""Telegram alerts and an admin summary from the host heartbeat and backup jobs.

Standard library only: this runs under the host's /usr/bin/python3, outside
the containers, so it still reports when Docker or Redis is down.

The bot token and chat id are the two lines of the backend env file
(docs/alerts.md); only those two keys are read from it. The token is never
printed, logged or put into an exception.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import tempfile
from collections.abc import Mapping
from datetime import UTC, datetime
from html import escape
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

TELEGRAM_KEYS = ("TELEGRAM_BOT_TOKEN", "TELEGRAM_ALERT_CHAT_ID")
DEFAULT_ENV_FILE = "services/backend/.env.production"
# A failure that lasts is repeated this rarely, not on every 5-minute run.
REMIND_SECONDS = 6 * 3600
# Disk fill (2026-11-07 outage): a warning first, the heartbeat itself fails above 90%.
DISK_WARN_PERCENT = 80
DISK_CRITICAL_PERCENT = 90
RECOVERY_SET = re.compile(r"[0-9]{8}T[0-9]{6}Z-[0-9a-f]{32}")


def read_env_file(path: Path) -> dict[str, str]:
    """TELEGRAM_* values of a docker-compose env file; every other line is skipped."""
    values: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return values
    for line in lines:
        key, separator, value = line.strip().partition("=")
        key = key.removeprefix("export ").strip()
        if not separator or key not in TELEGRAM_KEYS:
            continue
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[key] = value.strip()
    return values


def credentials(environ: Mapping[str, str]) -> tuple[str, str] | None:
    values = {key: environ.get(key, "").strip() for key in TELEGRAM_KEYS}
    if not all(values.values()):
        from_file = read_env_file(Path(environ.get("UPTIME_TELEGRAM_ENV_FILE") or DEFAULT_ENV_FILE))
        values = {key: values[key] or from_file.get(key, "") for key in TELEGRAM_KEYS}
    if not all(values.values()):
        return None
    return values["TELEGRAM_BOT_TOKEN"], values["TELEGRAM_ALERT_CHAT_ID"]


def _post(token: str, payload: dict[str, Any], timeout: float) -> int | None:
    request = Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=timeout) as response:
            return int(response.status)
    except HTTPError as error:
        status = int(error.code)
        error.close()
        return status
    except (URLError, TimeoutError, OSError):
        return None


def send(text: str, environ: Mapping[str, str] | None = None, *, timeout: float = 10) -> bool:
    """True when Telegram took the message; False when it is off or failed. Never raises."""
    found = credentials(os.environ if environ is None else environ)
    if found is None:
        return False
    token, chat_id = found
    status = _post(
        token,
        {
            "chat_id": chat_id,
            "text": text[:4000],
            "parse_mode": "HTML",
            "disable_web_page_preview": True,
        },
        timeout,
    )
    return status is not None and 200 <= status < 300


def describe_problem(message: str) -> str:
    """A HeartbeatError message in the owner's words."""
    lowered = message.lower()
    if "disk" in lowered:
        return "Диск почти заполнен"
    if "backup" in lowered:
        return "Бэкап базы не прошёл или устарел"
    if "public target" in lowered or "readiness" in lowered:
        return "Сайт или API не отвечают"
    if "external heartbeat" in lowered:
        return "Внешний монитор не принял сигнал"
    return "Проверка сервера не прошла"


def latest_backup_time(backup_dir: Path) -> str | None:
    try:
        dumps = [path for path in backup_dir.glob("*.dump") if path.is_file()]
    except OSError:
        return None
    if not dumps:
        return None
    newest = max(path.stat().st_mtime for path in dumps)
    return datetime.fromtimestamp(newest, tz=UTC).isoformat()


def disk_used_percent(*paths: Path) -> float:
    """The fullest filesystem holding these paths, counted the way df does."""
    worst = 0.0
    for path in paths:
        existing = path
        while not existing.exists() and existing != existing.parent:
            existing = existing.parent
        usage = shutil.disk_usage(existing)
        worst = max(worst, 100 * usage.used / max(usage.used + usage.free, 1))
    return worst


def recovery_sets(backup_dir: Path) -> tuple[int, int]:
    """Complete local recovery sets (with a receipt) and their total size in bytes."""
    count = size = 0
    try:
        directories = list((backup_dir / "recovery").iterdir())
    except OSError:
        return 0, 0
    for directory in directories:
        if (
            not RECOVERY_SET.fullmatch(directory.name)
            or directory.is_symlink()
            or not (directory / "receipt.json").is_file()
        ):
            continue
        count += 1
        for parent, _directories, files in os.walk(directory):
            for name in files:
                try:
                    size += os.lstat(os.path.join(parent, name)).st_size
                except OSError:
                    pass
    return count, size


def state_dir(environ: Mapping[str, str]) -> Path | None:
    """systemd's StateDirectory= (the heartbeat unit sets it), or UPTIME_STATE_DIR."""
    raw = environ.get("STATE_DIRECTORY") or environ.get("UPTIME_STATE_DIR") or ""
    first = raw.split(":")[0].strip()
    return Path(first) if first else None


def _write_json(path: Path, payload: dict[str, Any], mode: int) -> None:
    descriptor, name = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    temporary = Path(name)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(payload, stream)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def _read_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return payload if isinstance(payload, dict) else {}


def report_check(
    *,
    ok: bool,
    problem: str = "",
    environ: Mapping[str, str] | None = None,
    now: datetime | None = None,
) -> None:
    """After a heartbeat run: the admin summary, and an alert when the state changes.

    A failure is reported once, again every REMIND_SECONDS while it lasts, and
    its end once more. Without a state directory nothing is written or sent.
    """
    source = os.environ if environ is None else environ
    directory = state_dir(source)
    if directory is None:
        return
    current = now or datetime.now(UTC)
    summary = describe_problem(problem) if not ok else None
    backup_dir = Path(source.get("UPTIME_BACKUP_DIR", "./backups"))
    try:
        directory.mkdir(parents=True, exist_ok=True)
        # World-readable on purpose: the backend container mounts it for the admin.
        _write_json(
            directory / "status.json",
            {
                "schema_version": 1,
                "checked_at": current.isoformat(),
                "ok": ok,
                "problem": summary,
                "last_backup_at": latest_backup_time(backup_dir),
            },
            0o644,
        )
    except OSError:
        return
    state_path = directory / "alert-state.json"
    state = _read_json(state_path)
    was_failing = bool(state.get("failing"))
    last_alert = state.get("last_alert_at")
    environment = source.get("UPTIME_BACKUP_ENVIRONMENT", "production")
    if ok:
        if was_failing:
            send(f"<b>✅ Сервер {escape(environment)}: проверка снова проходит</b>", source)
        state = {"failing": False, "last_alert_at": None}
    else:
        due = not was_failing
        if was_failing and isinstance(last_alert, str):
            try:
                age = (current - datetime.fromisoformat(last_alert)).total_seconds()
            except ValueError:
                age = REMIND_SECONDS
            due = age >= REMIND_SECONDS
        if due:
            prefix = "всё ещё: " if was_failing else ""
            send(
                f"<b>🔴 Сервер {escape(environment)}: {escape(prefix + (summary or ''))}</b>\n"
                f"<code>{escape(problem[:300])}</code>\n"
                f"Проверьте: journalctl -u quran-heartbeat@{escape(environment)}",
                source,
            )
            last_alert = current.isoformat()
        state = {"failing": True, "last_alert_at": last_alert}
    try:
        _write_json(state_path, state, 0o600)
    except OSError:
        return


def report_disk(
    percent: float,
    *,
    environ: Mapping[str, str] | None = None,
    now: datetime | None = None,
) -> None:
    """Warn once the disk is DISK_WARN_PERCENT full, remind every REMIND_SECONDS, say when it clears.

    From DISK_CRITICAL_PERCENT the heartbeat check itself fails and report_check
    speaks, so no second message is sent from here.
    """
    source = os.environ if environ is None else environ
    directory = state_dir(source)
    if directory is None:
        return
    current = now or datetime.now(UTC)
    environment = escape(source.get("UPTIME_BACKUP_ENVIRONMENT", "production"))
    state_path = directory / "disk-alert-state.json"
    state = _read_json(state_path)
    warned = bool(state.get("warning"))
    last_alert = state.get("last_alert_at")
    if percent < DISK_WARN_PERCENT:
        if warned:
            send(f"<b>✅ Сервер {environment}: диск снова заполнен на {percent:.0f}%</b>", source)
        state = {"warning": False, "last_alert_at": None}
    else:
        due = not warned
        if warned and isinstance(last_alert, str):
            try:
                age = (current - datetime.fromisoformat(last_alert)).total_seconds()
            except ValueError:
                age = REMIND_SECONDS
            due = age >= REMIND_SECONDS
        if due and percent < DISK_CRITICAL_PERCENT:
            count, size = recovery_sets(Path(source.get("UPTIME_BACKUP_DIR", "./backups")))
            prefix = "всё ещё: " if warned else ""
            send(
                f"<b>🟡 Сервер {environment}: {prefix}диск заполнен на {percent:.0f}%</b>\n"
                f"Локальных наборов восстановления: {count}, {size / 1e9:.1f} ГБ "
                "(хранятся 3 последних, лишние удаляет ночной job).\n"
                "Проверьте: df -h и du -sh /opt/quran/backups/*",
                source,
            )
            last_alert = current.isoformat()
        state = {"warning": True, "last_alert_at": last_alert}
    try:
        directory.mkdir(parents=True, exist_ok=True)
        _write_json(state_path, state, 0o600)
    except OSError:
        return


def report_job_failure(
    component: str,
    environ: Mapping[str, str] | None = None,
    *,
    problem: str | None = None,
) -> bool:
    """A backup or recovery job failed: always sent, these run once a day."""
    source = os.environ if environ is None else environ
    environment = source.get("UPTIME_BACKUP_ENVIRONMENT", "production")
    unit = "quran-backup" if component == "postgres" else "quran-recovery"
    title = "Бэкап базы" if component == "postgres" else "Резервная копия медиа и кода"
    reason = f"Причина: {escape(problem)}\n" if problem else ""
    return send(
        f"<b>🔴 {title} не прошёл ({escape(environment)})</b>\n"
        f"{reason}"
        f"Проверьте: journalctl -u {unit}@{escape(environment)}",
        source,
    )
