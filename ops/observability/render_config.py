from __future__ import annotations

import argparse
import os
import stat
import tempfile
from decimal import Decimal, InvalidOperation
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent
NOBODY_UID = 65534
NOBODY_GID = 65534


class ConfigurationError(ValueError):
    pass


def required_environment(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise ConfigurationError(f"{name} is required")
    return value


def positive_decimal_environment(name: str) -> str:
    raw = required_environment(name)
    try:
        value = Decimal(raw)
    except InvalidOperation as exc:
        raise ConfigurationError(f"{name} must be a positive decimal") from exc
    if not value.is_finite() or value <= 0:
        raise ConfigurationError(f"{name} must be a positive decimal")
    return format(value.normalize(), "f")


def positive_integer_environment(name: str) -> str:
    raw = required_environment(name)
    try:
        value = int(raw)
    except ValueError as exc:
        raise ConfigurationError(f"{name} must be a positive integer") from exc
    if value <= 0:
        raise ConfigurationError(f"{name} must be a positive integer")
    return str(value)


def optional_https_url(name: str) -> str | None:
    raw = os.getenv(name, "").strip()
    if not raw:
        return None
    parsed = urlsplit(raw)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ConfigurationError(f"{name} must be an HTTPS URL without embedded credentials")
    return raw


def _write(path: Path, content: str, *, secret: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(content)
            if not content.endswith("\n"):
                stream.write("\n")
        temporary_path.chmod(stat.S_IRUSR if secret else stat.S_IRUSR | stat.S_IRGRP | stat.S_IROTH)
        if os.geteuid() == 0:
            os.chown(temporary_path, NOBODY_UID, NOBODY_GID)
        temporary_path.replace(path)
    finally:
        temporary_path.unlink(missing_ok=True)


def render(output: Path) -> None:
    operations_token = required_environment("QURAN_OPERATIONS_TOKEN")
    if len(operations_token) < 32:
        raise ConfigurationError("QURAN_OPERATIONS_TOKEN must contain at least 32 characters")
    monthly_budget = positive_decimal_environment("OBSERVABILITY_MONTHLY_BUDGET_USD")
    origin_egress_budget = positive_integer_environment(
        "OBSERVABILITY_MONTHLY_ORIGIN_EGRESS_BUDGET_BYTES"
    )
    alert_webhook = optional_https_url("OBSERVABILITY_ALERT_WEBHOOK_URL")

    output.mkdir(parents=True, exist_ok=True)
    _write(output / "operations-token", operations_token, secret=True)
    _write(output / "prometheus.yml", (ROOT / "prometheus.yml").read_text(encoding="utf-8"))

    rules = (ROOT / "rules.yml.template").read_text(encoding="utf-8")
    rules = rules.replace("@@MONTHLY_BUDGET_USD@@", monthly_budget)
    rules = rules.replace("@@MONTHLY_ORIGIN_EGRESS_BUDGET_BYTES@@", origin_egress_budget)
    if "@@" in rules:
        raise ConfigurationError("An unknown observability rules placeholder remains")
    _write(output / "rules.yml", rules)

    if alert_webhook:
        _write(output / "alert-webhook-url", alert_webhook, secret=True)
        alertmanager = """route:
  receiver: webhook
  group_by: [alertname, severity]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h

receivers:
  - name: webhook
    webhook_configs:
      - url_file: /runtime/alert-webhook-url
        send_resolved: true
        max_alerts: 50
"""
    else:
        (output / "alert-webhook-url").unlink(missing_ok=True)
        alertmanager = """route:
  receiver: unconfigured
  group_by: [alertname, severity]

receivers:
  - name: unconfigured
"""
    _write(output / "alertmanager.yml", alertmanager)


def main() -> None:
    parser = argparse.ArgumentParser(description="Render secret-safe observability runtime files.")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        render(args.output)
    except ConfigurationError as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    main()
