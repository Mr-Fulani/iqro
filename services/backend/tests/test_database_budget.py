from __future__ import annotations

import json

import pytest
from django.core.management import call_command

from quran_backend.database_budget import DatabaseBudgetError, DatabaseConnectionBudget


def test_default_direct_budget_has_bounded_headroom() -> None:
    budget = DatabaseConnectionBudget.from_environ({})

    assert budget.pool_mode == "direct"
    assert budget.projected_client_connections == 19
    assert budget.postgres_available_connections == 80
    assert budget.report()["postgres_connection_headroom"] == 61


def test_transaction_budget_separates_clients_from_postgres_connections() -> None:
    budget = DatabaseConnectionBudget.from_environ(
        {
            "DATABASE_POOL_MODE": "transaction",
            "DATABASE_API_REPLICAS": "4",
            "GUNICORN_WORKERS": "4",
            "API_MAX_CONCURRENT_REQUESTS_PER_WORKER": "5",
            "DATABASE_WORKER_REPLICAS": "2",
            "CELERY_WORKER_CONCURRENCY": "8",
            "DATABASE_PGBOUNCER_CLIENT_CONNECTIONS": "128",
            "DATABASE_PGBOUNCER_SERVER_CONNECTIONS": "40",
        }
    )

    assert budget.projected_client_connections == 101
    assert budget.configured_client_connection_limit == 128
    assert budget.configured_server_connection_limit == 40
    assert budget.report()["postgres_connection_headroom"] == 40


@pytest.mark.parametrize(
    ("environ", "message"),
    [
        ({"DATABASE_POOL_MODE": "session"}, "DATABASE_POOL_MODE"),
        (
            {
                "API_MAX_CONCURRENT_REQUESTS_PER_WORKER": "50",
                "DATABASE_POSTGRES_RESERVED_CONNECTIONS": "20",
            },
            "projected direct database connections",
        ),
        (
            {
                "DATABASE_POOL_MODE": "transaction",
                "DATABASE_PGBOUNCER_SERVER_CONNECTIONS": "81",
            },
            "DATABASE_PGBOUNCER_SERVER_CONNECTIONS",
        ),
        (
            {
                "DATABASE_POOL_MODE": "transaction",
                "DATABASE_API_REPLICAS": "10",
                "DATABASE_PGBOUNCER_CLIENT_CONNECTIONS": "50",
            },
            "DATABASE_PGBOUNCER_CLIENT_CONNECTIONS",
        ),
        ({"GUNICORN_WORKERS": "many"}, "GUNICORN_WORKERS"),
    ],
)
def test_unsafe_budget_is_rejected(environ: dict[str, str], message: str) -> None:
    with pytest.raises(DatabaseBudgetError, match=message):
        DatabaseConnectionBudget.from_environ(environ)


def test_database_connection_budget_command_prints_machine_readable_report(
    capsys: pytest.CaptureFixture[str],
) -> None:
    call_command("database_connection_budget")

    report = json.loads(capsys.readouterr().out)
    assert report["pool_mode"] == "direct"
    assert report["projected_client_connections"] == 19
