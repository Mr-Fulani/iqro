import json
import os
import subprocess
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "src"
SCRIPT = """
import json
from quran_backend.settings import base
print(json.dumps({
    "options": base.DATABASES["default"]["OPTIONS"].get("options"),
    "celery": [
        base.CELERY_TASK_SOFT_TIME_LIMIT,
        base.CELERY_TASK_TIME_LIMIT,
        base.CELERY_BROKER_TRANSPORT_OPTIONS["visibility_timeout"],
    ],
}))
"""


def _settings(**environ: str) -> subprocess.CompletedProcess[str]:
    # A fresh interpreter, so module-level settings see this environment only.
    return subprocess.run(  # noqa: S603
        [sys.executable, "-c", SCRIPT],
        cwd=SRC,
        env={**os.environ, **environ},
        capture_output=True,
        text=True,
        check=False,
    )


def test_statement_timeout_is_opt_in_and_sent_as_a_connection_option() -> None:
    default = json.loads(_settings().stdout)
    assert default["options"] is None

    capped = json.loads(_settings(DATABASE_STATEMENT_TIMEOUT_MS="30000").stdout)
    assert capped["options"] == "-c statement_timeout=30000"


def test_statement_timeout_is_refused_with_pgbouncer_transaction_pooling() -> None:
    result = _settings(DATABASE_STATEMENT_TIMEOUT_MS="30000", DATABASE_POOL_MODE="transaction")
    assert result.returncode != 0
    assert "DATABASE_STATEMENT_TIMEOUT_MS" in result.stderr


def test_celery_tasks_end_before_the_broker_redelivers_them() -> None:
    soft, hard, visibility = json.loads(_settings().stdout)["celery"]
    assert soft < hard < visibility

    result = _settings(CELERY_TASK_TIME_LIMIT_SECONDS="4000")
    assert result.returncode != 0
    assert "visibility timeout" in result.stderr
