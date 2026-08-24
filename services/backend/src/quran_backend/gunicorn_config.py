from __future__ import annotations

import os


def _positive_env_int(name: str, default: int) -> int:
    try:
        value = int(os.getenv(name, str(default)))
    except ValueError as exc:
        raise RuntimeError(f"{name} must be a positive integer") from exc
    if value <= 0:
        raise RuntimeError(f"{name} must be a positive integer")
    return value


bind = "0.0.0.0:8000"
workers = _positive_env_int("GUNICORN_WORKERS", 2)
worker_class = "quran_backend.gunicorn_worker.BoundedUvicornWorker"
accesslog = "-"
errorlog = "-"
