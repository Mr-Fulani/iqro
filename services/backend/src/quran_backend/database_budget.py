from __future__ import annotations

from collections.abc import Mapping
from dataclasses import asdict, dataclass
from typing import Literal

DatabasePoolMode = Literal["direct", "transaction"]


class DatabaseBudgetError(ValueError):
    """Raised when the declared database connection budget is unsafe."""


def _integer(
    environ: Mapping[str, str],
    name: str,
    default: int,
    *,
    minimum: int,
) -> int:
    raw = environ.get(name, str(default))
    try:
        value = int(raw)
    except ValueError as exc:
        raise DatabaseBudgetError(f"{name} must be an integer") from exc
    if value < minimum:
        raise DatabaseBudgetError(f"{name} must be at least {minimum}")
    return value


@dataclass(frozen=True, slots=True)
class DatabaseConnectionBudget:
    pool_mode: DatabasePoolMode
    postgres_max_connections: int
    postgres_reserved_connections: int
    pgbouncer_server_connections: int
    pgbouncer_client_connections: int
    api_replicas: int
    api_processes_per_replica: int
    api_max_concurrent_requests_per_process: int
    worker_replicas: int
    worker_connections_per_replica: int
    beat_connections: int
    release_job_connections: int
    operations_connections: int

    @classmethod
    def from_environ(cls, environ: Mapping[str, str]) -> DatabaseConnectionBudget:
        raw_pool_mode = environ.get("DATABASE_POOL_MODE", "direct").strip().lower()
        if raw_pool_mode not in {"direct", "transaction"}:
            raise DatabaseBudgetError("DATABASE_POOL_MODE must be either 'direct' or 'transaction'")
        pool_mode: DatabasePoolMode = raw_pool_mode  # type: ignore[assignment]
        budget = cls(
            pool_mode=pool_mode,
            postgres_max_connections=_integer(
                environ,
                "DATABASE_POSTGRES_MAX_CONNECTIONS",
                100,
                minimum=1,
            ),
            postgres_reserved_connections=_integer(
                environ,
                "DATABASE_POSTGRES_RESERVED_CONNECTIONS",
                20,
                minimum=0,
            ),
            pgbouncer_server_connections=_integer(
                environ,
                "DATABASE_PGBOUNCER_SERVER_CONNECTIONS",
                40,
                minimum=1,
            ),
            pgbouncer_client_connections=_integer(
                environ,
                "DATABASE_PGBOUNCER_CLIENT_CONNECTIONS",
                100,
                minimum=1,
            ),
            api_replicas=_integer(environ, "DATABASE_API_REPLICAS", 1, minimum=1),
            api_processes_per_replica=_integer(
                environ,
                "GUNICORN_WORKERS",
                2,
                minimum=1,
            ),
            api_max_concurrent_requests_per_process=_integer(
                environ,
                "API_MAX_CONCURRENT_REQUESTS_PER_WORKER",
                5,
                minimum=1,
            ),
            worker_replicas=_integer(environ, "DATABASE_WORKER_REPLICAS", 1, minimum=0),
            worker_connections_per_replica=_integer(
                environ,
                "CELERY_WORKER_CONCURRENCY",
                4,
                minimum=1,
            ),
            beat_connections=_integer(environ, "DATABASE_BEAT_CONNECTIONS", 1, minimum=0),
            release_job_connections=_integer(
                environ,
                "DATABASE_RELEASE_JOB_CONNECTIONS",
                2,
                minimum=0,
            ),
            operations_connections=_integer(
                environ,
                "DATABASE_OPERATIONS_CONNECTIONS",
                2,
                minimum=0,
            ),
        )
        budget.validate()
        return budget

    @property
    def postgres_available_connections(self) -> int:
        return self.postgres_max_connections - self.postgres_reserved_connections

    @property
    def api_connections_per_replica(self) -> int:
        return self.api_processes_per_replica * self.api_max_concurrent_requests_per_process

    @property
    def projected_client_connections(self) -> int:
        return (
            self.api_replicas * self.api_connections_per_replica
            + self.worker_replicas * self.worker_connections_per_replica
            + self.beat_connections
            + self.release_job_connections
            + self.operations_connections
        )

    @property
    def configured_server_connection_limit(self) -> int:
        if self.pool_mode == "transaction":
            return self.pgbouncer_server_connections
        return self.projected_client_connections

    @property
    def configured_client_connection_limit(self) -> int:
        if self.pool_mode == "transaction":
            return self.pgbouncer_client_connections
        return self.postgres_available_connections

    def validate(self) -> None:
        if self.postgres_reserved_connections >= self.postgres_max_connections:
            raise DatabaseBudgetError(
                "DATABASE_POSTGRES_RESERVED_CONNECTIONS must be smaller than "
                "DATABASE_POSTGRES_MAX_CONNECTIONS"
            )
        if self.pool_mode == "direct":
            if self.projected_client_connections > self.postgres_available_connections:
                raise DatabaseBudgetError(
                    "projected direct database connections exceed the PostgreSQL application budget"
                )
            return
        if self.pgbouncer_server_connections > self.postgres_available_connections:
            raise DatabaseBudgetError(
                "DATABASE_PGBOUNCER_SERVER_CONNECTIONS exceeds the PostgreSQL application budget"
            )
        if self.pgbouncer_client_connections < self.projected_client_connections:
            raise DatabaseBudgetError(
                "DATABASE_PGBOUNCER_CLIENT_CONNECTIONS is smaller than projected application "
                "clients"
            )
        if self.pgbouncer_server_connections > self.pgbouncer_client_connections:
            raise DatabaseBudgetError(
                "DATABASE_PGBOUNCER_SERVER_CONNECTIONS cannot exceed "
                "DATABASE_PGBOUNCER_CLIENT_CONNECTIONS"
            )

    def report(self) -> dict[str, int | str]:
        report: dict[str, int | str] = asdict(self)
        report.update(
            {
                "api_connections_per_replica": self.api_connections_per_replica,
                "postgres_available_connections": self.postgres_available_connections,
                "projected_client_connections": self.projected_client_connections,
                "configured_server_connection_limit": self.configured_server_connection_limit,
                "configured_client_connection_limit": self.configured_client_connection_limit,
                "postgres_connection_headroom": (
                    self.postgres_available_connections - self.configured_server_connection_limit
                ),
                "client_connection_headroom": (
                    self.configured_client_connection_limit - self.projected_client_connections
                ),
            }
        )
        return report
