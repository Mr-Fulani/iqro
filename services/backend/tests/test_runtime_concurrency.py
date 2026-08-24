from __future__ import annotations

from quran_backend import gunicorn_config
from quran_backend.gunicorn_worker import BoundedUvicornWorker


def test_gunicorn_runtime_matches_default_database_budget() -> None:
    assert gunicorn_config.workers == 2
    assert BoundedUvicornWorker.CONFIG_KWARGS["limit_concurrency"] == 5
