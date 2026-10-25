"""ERROR log records of the backend, worker and beat as Telegram alerts.

Settings attach the handler to Django's loggers; in Celery processes
apps.py adds it again to the root logger Celery sets up.
"""

from __future__ import annotations

import hashlib
import logging
import sys
import threading
import traceback
from html import escape
from pathlib import Path

# Bots knocking with a foreign Host header: Django logs each one as an error.
IGNORED_LOGGERS = frozenset({"django.security.DisallowedHost"})

_local = threading.local()


def process_role(argv: list[str] | None = None) -> str:
    args = sys.argv if argv is None else argv
    if args and Path(args[0]).name == "celery":
        return "beat" if "beat" in args else "worker"
    return "backend"


def _ignored(record: logging.LogRecord) -> bool:
    if record.name in IGNORED_LOGGERS or record.name.startswith("quran_backend.modules.alerts"):
        return True
    # Celery's own report of a failed alerts task.
    return record.name.startswith("celery") and "alerts." in record.getMessage()


def _innermost_frame(record: logging.LogRecord) -> tuple[str, int]:
    if record.exc_info and record.exc_info[2] is not None:
        frame = traceback.extract_tb(record.exc_info[2])[-1]
        return frame.filename, frame.lineno or 0
    return record.pathname, record.lineno


def fingerprint(record: logging.LogRecord) -> str:
    """The same error from the same place gets the same fingerprint, whatever its arguments."""
    exc_type = record.exc_info[0].__name__ if record.exc_info and record.exc_info[0] else ""
    filename, lineno = _innermost_frame(record)
    key = f"{record.name}|{record.msg}|{exc_type}|{filename}|{lineno}"
    return hashlib.sha256(key.encode()).hexdigest()[:24]


def describe(record: logging.LogRecord, role: str) -> tuple[str, str]:
    """The alert text (Telegram HTML) and a one-line title for the repeats message."""
    message = " ".join(record.getMessage().split())[:300]
    title = f"{role} · {record.name}: {message}"[:300]
    lines = [f"<b>🔴 Ошибка сервера · {escape(role)}</b>", escape(f"{record.name}: {message}")]
    if record.exc_info and record.exc_info[1] is not None:
        error = record.exc_info[1]
        detail = " ".join(str(error).split())[:300]
        lines.append(escape(f"{type(error).__name__}: {detail}"))
    filename, lineno = _innermost_frame(record)
    lines.append(escape(f"Где: {Path(filename).name}:{lineno}"))
    lines.append("Подробности — в Sentry и в логах.")
    return "\n".join(lines), title


class TelegramAlertHandler(logging.Handler):
    def __init__(self, level: int = logging.ERROR) -> None:
        super().__init__(level)

    def emit(self, record: logging.LogRecord) -> None:
        if getattr(_local, "busy", False) or _ignored(record):
            return
        _local.busy = True
        try:
            from django.apps import apps  # noqa: PLC0415

            if not apps.ready:
                return
            from quran_backend.modules.alerts.services import report_error  # noqa: PLC0415

            text, title = describe(record, process_role())
            report_error(fingerprint(record), text, title)
        except Exception:  # noqa: S110 - logging must survive a broken alert path
            pass
        finally:
            _local.busy = False
