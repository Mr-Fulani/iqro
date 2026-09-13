from __future__ import annotations

import argparse
import json
import os
import sys
from collections.abc import Mapping
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

from ops.monitoring.backup_status import check_status, write_status


class HeartbeatError(RuntimeError):
    pass


@dataclass(frozen=True)
class Settings:
    targets: tuple[str, ...]
    success_url: str
    failure_url: str | None
    timeout_seconds: float
    backup_dir: Path
    backup_max_age_seconds: int
    backup_status_dir: Path | None = None
    backup_environment: str = "production"


def _https_url(value: str, label: str, *, allow_secret_path: bool) -> str:
    normalized = value.strip()
    if any(ord(character) < 32 or ord(character) == 127 for character in normalized):
        raise HeartbeatError(f"{label} must not contain control characters")
    parsed = urlsplit(normalized)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.fragment
    ):
        raise HeartbeatError(
            f"{label} must be an HTTPS URL without embedded credentials"
        )
    if not allow_secret_path and (parsed.query or parsed.path not in {"", "/"}):
        raise HeartbeatError(f"{label} must be an HTTPS origin or root URL")
    return normalized


def load_settings(values: Mapping[str, str] | None = None) -> Settings:
    source = os.environ if values is None else values
    success_url = source.get("UPTIME_HEARTBEAT_URL", "").strip()
    if not success_url:
        raise HeartbeatError("UPTIME_HEARTBEAT_URL is required")
    success_url = _https_url(
        success_url, "UPTIME_HEARTBEAT_URL", allow_secret_path=True
    )
    failure_url = source.get("UPTIME_HEARTBEAT_FAILURE_URL", "").strip() or None
    if failure_url:
        failure_url = _https_url(
            failure_url, "UPTIME_HEARTBEAT_FAILURE_URL", allow_secret_path=True
        )

    targets_value = source.get("UPTIME_TARGET_URLS", "").strip()
    if not targets_value:
        site_url = source.get("SITE_URL", "").strip().rstrip("/")
        if not site_url:
            raise HeartbeatError("UPTIME_TARGET_URLS or SITE_URL is required")
        _https_url(site_url, "SITE_URL", allow_secret_path=False)
        targets = (f"{site_url}/", f"{site_url}/api/v1/health/ready")
    else:
        targets = tuple(
            _https_url(value, "UPTIME_TARGET_URLS", allow_secret_path=True)
            for value in targets_value.split(",")
            if value.strip()
        )
        if not targets:
            raise HeartbeatError("UPTIME_TARGET_URLS must contain at least one URL")
    try:
        timeout_seconds = float(source.get("UPTIME_REQUEST_TIMEOUT_SECONDS", "10"))
        backup_max_age_seconds = int(
            source.get("UPTIME_BACKUP_MAX_AGE_SECONDS", "93600")
        )
    except ValueError as exc:
        raise HeartbeatError(
            "heartbeat timeout and backup age must be numeric"
        ) from exc
    if not 1 <= timeout_seconds <= 60:
        raise HeartbeatError("UPTIME_REQUEST_TIMEOUT_SECONDS must be between 1 and 60")
    if not 3600 <= backup_max_age_seconds <= 604800:
        raise HeartbeatError(
            "UPTIME_BACKUP_MAX_AGE_SECONDS must be between 3600 and 604800"
        )
    backup_dir = Path(source.get("UPTIME_BACKUP_DIR", "./backups")).resolve()
    if backup_dir == Path("/"):
        raise HeartbeatError("UPTIME_BACKUP_DIR must be a dedicated directory")
    return Settings(
        targets=targets,
        success_url=success_url,
        failure_url=failure_url,
        timeout_seconds=timeout_seconds,
        backup_dir=backup_dir,
        backup_max_age_seconds=backup_max_age_seconds,
        backup_status_dir=(
            Path(source["UPTIME_BACKUP_STATUS_DIR"]).resolve()
            if source.get("UPTIME_BACKUP_STATUS_DIR")
            else None
        ),
        backup_environment=source.get("UPTIME_BACKUP_ENVIRONMENT", "production"),
    )


def _request(url: str, *, timeout: float) -> tuple[int, bytes]:
    request = Request(
        url,
        headers={
            "User-Agent": "Iqro-Release-Monitor/1.0",
            "Accept": "application/json,*/*",
        },
    )
    with urlopen(request, timeout=timeout) as response:
        return response.status, response.read(64 * 1024)


def check_target(url: str, *, timeout: float) -> None:
    try:
        status, body = _request(url, timeout=timeout)
    except (HTTPError, URLError, TimeoutError, OSError) as exc:
        raise HeartbeatError(f"public target failed: {urlsplit(url).hostname}") from exc
    if status != 200:
        raise HeartbeatError(
            f"public target returned HTTP {status}: {urlsplit(url).hostname}"
        )
    if urlsplit(url).path.endswith("/health/ready"):
        try:
            payload: Any = json.loads(body)
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            raise HeartbeatError("readiness endpoint returned invalid JSON") from exc
        if not isinstance(payload, dict) or payload.get("status") not in {
            "ok",
            "ready",
        }:
            raise HeartbeatError("readiness endpoint did not report a ready status")


def check_backup_freshness(
    backup_dir: Path,
    *,
    max_age_seconds: int,
    now: datetime | None = None,
) -> Path:
    backups = [path for path in backup_dir.glob("*.dump") if path.is_file()]
    if not backups:
        raise HeartbeatError("no local PostgreSQL backup is available")
    latest = max(backups, key=lambda path: path.stat().st_mtime)
    checksum = latest.with_name(f"{latest.name}.sha256")
    if not checksum.is_file():
        raise HeartbeatError("latest PostgreSQL backup has no checksum")
    current = now or datetime.now(tz=UTC)
    age_seconds = current.timestamp() - latest.stat().st_mtime
    if age_seconds < -300 or age_seconds > max_age_seconds:
        raise HeartbeatError("latest PostgreSQL backup is stale")
    return latest


def ping(url: str, *, timeout: float) -> None:
    try:
        status, _body = _request(url, timeout=timeout)
    except (HTTPError, URLError, TimeoutError, OSError) as exc:
        raise HeartbeatError("external heartbeat delivery failed") from exc
    if status < 200 or status >= 300:
        raise HeartbeatError(f"external heartbeat returned HTTP {status}")


def run(settings: Settings) -> None:
    for target in settings.targets:
        check_target(target, timeout=settings.timeout_seconds)
    check_backup_freshness(
        settings.backup_dir,
        max_age_seconds=settings.backup_max_age_seconds,
    )
    if settings.backup_status_dir:
        for component in ("postgres", "recovery"):
            try:
                check_status(
                    settings.backup_status_dir / f"{component}.json",
                    component=component,
                    environment=settings.backup_environment,
                    max_age_seconds=settings.backup_max_age_seconds,
                )
            except ValueError as exc:
                raise HeartbeatError(str(exc)) from exc
    ping(settings.success_url, timeout=settings.timeout_seconds)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Verify public endpoints and backup freshness, then ping a dead-man monitor."
    )
    parser.add_argument(
        "--job-result",
        choices=("postgres", "recovery"),
        help="Systemd ExecStopPost: report failed jobs through the existing monitor.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    if args.job_result and os.environ.get("SERVICE_RESULT") == "success":
        return 0
    try:
        settings = load_settings()
        if args.job_result:
            if settings.backup_status_dir:
                write_status(
                    settings.backup_status_dir / f"{args.job_result}.json",
                    component=args.job_result,
                    environment=settings.backup_environment,
                    state="failed",
                )
            if settings.failure_url:
                ping(settings.failure_url, timeout=settings.timeout_seconds)
            return 1
        run(settings)
    except HeartbeatError as exc:
        try:
            failure_settings = load_settings()
            if failure_settings.failure_url:
                ping(
                    failure_settings.failure_url,
                    timeout=failure_settings.timeout_seconds,
                )
        except HeartbeatError:
            pass
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print("Public endpoints, backup freshness and external heartbeat passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
