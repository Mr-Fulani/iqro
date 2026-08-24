#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import http.client
import json
import secrets
import ssl
import sys
import threading
import time
import uuid
from collections import Counter, defaultdict
from collections.abc import Callable, Mapping, Sequence
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, replace
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Protocol
from urllib.parse import SplitResult, urlsplit

if __package__:
    from ops.load.capacity import StageSpec, parse_stage
    from ops.load.smoke import percentile, validate_base_url
else:  # Allow the documented `python3 ops/load/sync_capacity.py ...` invocation.
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from ops.load.capacity import StageSpec, parse_stage
    from ops.load.smoke import percentile, validate_base_url


MAX_CONCURRENCY = 100
MAX_STAGE_SECONDS = 900.0
MAX_CYCLES_PER_USER = 500
MAX_OPERATIONS_PER_PUSH = 20
MAX_SYNC_OPERATIONS_PER_STAGE = 20_000
DEFAULT_SYNC_OPERATIONS_PER_STAGE = 5_000
MAX_RESPONSE_BYTES = 1024 * 1024
MAX_PULL_PAGES_PER_CYCLE = 5


@dataclass(frozen=True, slots=True)
class JourneyResult:
    step: str
    latency_ms: float
    status: int | None
    bytes_received: int
    successful: bool
    error: str | None


@dataclass(frozen=True, slots=True)
class JourneyResponse:
    result: JourneyResult
    payload: Mapping[str, Any] | None


@dataclass(frozen=True, slots=True)
class JourneyCredentials:
    access_token: str
    refresh_token: str


@dataclass(frozen=True, slots=True)
class UserJourneySummary:
    results: tuple[JourneyResult, ...]
    bootstrapped: bool
    cycles_completed: int
    sync_operations_completed: int
    refreshes_completed: int
    hit_cycle_cap: bool
    hit_sync_operation_cap: bool


@dataclass(frozen=True, slots=True)
class SyncStageConfig:
    deadline: float
    run_tag: str
    edition: str
    operations_per_push: int
    max_cycles_per_user: int
    refresh_every_cycles: int
    think_time_seconds: float
    claim_sync_operations: Callable[[int], bool]


@dataclass(frozen=True, slots=True)
class SyncRunConfig:
    run_tag: str
    edition: str
    operations_per_push: int
    max_cycles_per_user: int
    refresh_every_cycles: int
    think_time_seconds: float
    max_sync_operations: int


@dataclass(frozen=True, slots=True)
class SyncStageSummary:
    stage: StageSpec
    results: tuple[JourneyResult, ...]
    elapsed_seconds: float
    stop_reason: str
    users_bootstrapped: int
    cycles_completed: int
    sync_operations_completed: int
    refreshes_completed: int

    @property
    def error_rate(self) -> float:
        if not self.results:
            return 1.0
        return sum(not result.successful for result in self.results) / len(self.results)

    @property
    def requests_per_second(self) -> float:
        if self.elapsed_seconds <= 0:
            return 0.0
        return len(self.results) / self.elapsed_seconds

    def latency_percentile(self, quantile: float) -> float:
        return percentile([result.latency_ms for result in self.results], quantile)


class JourneyClient(Protocol):
    def request(
        self,
        *,
        step: str,
        method: str,
        path: str,
        payload: Mapping[str, Any] | None = None,
        access_token: str | None = None,
        expected_statuses: tuple[int, ...] = (200,),
    ) -> JourneyResponse: ...

    def close(self) -> None: ...


class StatefulHttpClient:
    def __init__(self, *, base_url: str, timeout_seconds: float) -> None:
        self.parsed = urlsplit(base_url)
        self.timeout_seconds = timeout_seconds
        self.connection: http.client.HTTPConnection | None = None

    def _new_connection(self) -> http.client.HTTPConnection:
        host = self.parsed.hostname
        if host is None:  # validate_base_url prevents this.
            raise ValueError("base URL has no hostname")
        if self.parsed.scheme == "https":
            return http.client.HTTPSConnection(
                host,
                self.parsed.port,
                timeout=self.timeout_seconds,
                context=ssl.create_default_context(),
            )
        return http.client.HTTPConnection(
            host,
            self.parsed.port,
            timeout=self.timeout_seconds,
        )

    def _target(self, path: str) -> str:
        prefix = self.parsed.path.rstrip("/")
        return f"{prefix}{path}" or "/"

    def close(self) -> None:
        if self.connection is not None:
            self.connection.close()
            self.connection = None

    def request(
        self,
        *,
        step: str,
        method: str,
        path: str,
        payload: Mapping[str, Any] | None = None,
        access_token: str | None = None,
        expected_statuses: tuple[int, ...] = (200,),
    ) -> JourneyResponse:
        body = None
        headers = {
            "Accept": "application/json",
            "Accept-Encoding": "identity",
            "User-Agent": "quran-platform-sync-capacity/1",
        }
        if payload is not None:
            body = json.dumps(payload, separators=(",", ":")).encode()
            headers["Content-Type"] = "application/json"
        if access_token is not None:
            headers["Authorization"] = f"Bearer {access_token}"

        started = time.perf_counter()
        status: int | None = None
        bytes_received = 0
        response_payload: Mapping[str, Any] | None = None
        error: str | None = None
        try:
            if self.connection is None:
                self.connection = self._new_connection()
            self.connection.request(
                method,
                self._target(path),
                body=body,
                headers=headers,
            )
            response = self.connection.getresponse()
            status = response.status
            response_body = response.read(MAX_RESPONSE_BYTES + 1)
            bytes_received = len(response_body)
            if bytes_received > MAX_RESPONSE_BYTES:
                raise ValueError("response_too_large")
            if status not in expected_statuses:
                raise ValueError(f"unexpected_status_{status}")
            if response_body:
                decoded = json.loads(response_body)
                if not isinstance(decoded, dict):
                    raise ValueError("response_json_not_object")
                response_payload = decoded
        except json.JSONDecodeError:
            error = "invalid_json_response"
            self.close()
        except (
            OSError,
            TimeoutError,
            ValueError,
            http.client.HTTPException,
            ssl.SSLError,
        ) as exc:
            error = str(exc) if isinstance(exc, ValueError) else type(exc).__name__
            self.close()
        latency_ms = (time.perf_counter() - started) * 1_000
        return JourneyResponse(
            result=JourneyResult(
                step=step,
                latency_ms=latency_ms,
                status=status,
                bytes_received=bytes_received,
                successful=error is None,
                error=error,
            ),
            payload=response_payload,
        )


def _invalid_response(response: JourneyResponse, reason: str) -> JourneyResponse:
    return JourneyResponse(
        result=replace(response.result, successful=False, error=reason),
        payload=response.payload,
    )


def _credentials(response: JourneyResponse) -> JourneyCredentials | None:
    payload = response.payload
    if payload is None:
        return None
    access_token = payload.get("access_token")
    refresh_token = payload.get("refresh_token")
    if not isinstance(access_token, str) or not access_token:
        return None
    if not isinstance(refresh_token, str) or not refresh_token:
        return None
    return JourneyCredentials(access_token=access_token, refresh_token=refresh_token)


def _timestamp() -> str:
    return datetime.now(UTC).isoformat()


def _bootstrap_payload(run_tag: str) -> dict[str, object]:
    return {
        "installation_id": str(uuid.uuid4()),
        "installation_credential": secrets.token_urlsafe(32),
        "platform": "web",
        "locale": "ru",
        "app_version": f"load.{run_tag}",
    }


def _sync_push_payload(
    *,
    entity_id: uuid.UUID,
    edition: str,
    base_revision: int,
    operations_per_push: int,
    cycle: int,
) -> dict[str, object]:
    operations: list[dict[str, object]] = []
    for index in range(operations_per_push):
        timestamp = _timestamp()
        operations.append(
            {
                "operation_id": str(uuid.uuid4()),
                "entity_type": "reading_position",
                "entity_id": str(entity_id),
                "action": "upsert",
                "base_revision": base_revision + index,
                "client_updated_at": timestamp,
                "payload": {
                    "edition_code": edition,
                    "page_number": 1,
                    "surah_number": 1,
                    "ayah_number": 1,
                    "progress_percent": f"{((cycle + index) % 100):.2f}",
                    "last_read_at": timestamp,
                },
            }
        )
    return {"operations": operations}


def _accepted_revision(
    response: JourneyResponse,
    *,
    expected_operations: int,
) -> tuple[JourneyResponse, int | None]:
    payload = response.payload
    if not response.result.successful or payload is None:
        return response, None
    results = payload.get("results")
    if not isinstance(results, list) or len(results) != expected_operations:
        return _invalid_response(response, "invalid_sync_push_results"), None
    revision: int | None = None
    for row in results:
        if not isinstance(row, dict) or row.get("outcome") != "accepted":
            return _invalid_response(response, "sync_operation_not_accepted"), None
        entity = row.get("entity")
        if not isinstance(entity, dict) or not isinstance(entity.get("revision"), int):
            return _invalid_response(response, "invalid_sync_push_entity"), None
        revision = entity["revision"]
    return response, revision


def _pull_cursor(response: JourneyResponse) -> tuple[JourneyResponse, int | None, bool]:
    payload = response.payload
    if not response.result.successful or payload is None:
        return response, None, False
    cursor = payload.get("next_cursor")
    has_more = payload.get("has_more")
    if payload.get("mode") != "incremental" or not isinstance(cursor, int):
        return _invalid_response(response, "invalid_sync_pull_response"), None, False
    if not isinstance(has_more, bool):
        return _invalid_response(response, "invalid_sync_pull_pagination"), None, False
    return response, cursor, has_more


def _pull_all(
    client: JourneyClient,
    *,
    access_token: str,
    cursor: int,
) -> tuple[list[JourneyResult], int | None]:
    results: list[JourneyResult] = []
    next_cursor = cursor
    for _ in range(MAX_PULL_PAGES_PER_CYCLE):
        response = client.request(
            step="sync-pull",
            method="GET",
            path=f"/api/v1/sync/pull?cursor={next_cursor}&limit=100",
            access_token=access_token,
        )
        response, observed_cursor, has_more = _pull_cursor(response)
        results.append(response.result)
        if not response.result.successful or observed_cursor is None:
            return results, None
        next_cursor = observed_cursor
        if not has_more:
            return results, next_cursor
    results[-1] = replace(
        results[-1],
        successful=False,
        error="sync_pull_page_cap_exceeded",
    )
    return results, None


def run_user_journey(
    client: JourneyClient,
    *,
    config: SyncStageConfig,
) -> UserJourneySummary:
    results: list[JourneyResult] = []
    bootstrapped = False
    cycles_completed = 0
    sync_operations_completed = 0
    refreshes_completed = 0
    hit_cycle_cap = False
    hit_sync_operation_cap = False
    credentials: JourneyCredentials | None = None

    bootstrap = client.request(
        step="guest-bootstrap",
        method="POST",
        path="/api/v1/auth/guest",
        payload=_bootstrap_payload(config.run_tag),
    )
    credentials = _credentials(bootstrap)
    if bootstrap.result.successful and credentials is None:
        bootstrap = _invalid_response(bootstrap, "invalid_bootstrap_credentials")
    results.append(bootstrap.result)
    if not bootstrap.result.successful or credentials is None:
        return UserJourneySummary(tuple(results), False, 0, 0, 0, False, False)
    bootstrapped = True

    current_session = client.request(
        step="current-session",
        method="GET",
        path="/api/v1/me",
        access_token=credentials.access_token,
    )
    results.append(current_session.result)
    if not current_session.result.successful:
        logout = client.request(
            step="logout",
            method="POST",
            path="/api/v1/auth/logout",
            access_token=credentials.access_token,
            expected_statuses=(204,),
        )
        results.append(logout.result)
        return UserJourneySummary(tuple(results), True, 0, 0, 0, False, False)

    entity_id = uuid.uuid4()
    revision = 0
    pull_cursor = 0
    try:
        while time.perf_counter() < config.deadline:
            if cycles_completed >= config.max_cycles_per_user:
                hit_cycle_cap = True
                break
            if not config.claim_sync_operations(config.operations_per_push):
                hit_sync_operation_cap = True
                break
            push = client.request(
                step="sync-push",
                method="POST",
                path="/api/v1/sync/push",
                payload=_sync_push_payload(
                    entity_id=entity_id,
                    edition=config.edition,
                    base_revision=revision,
                    operations_per_push=config.operations_per_push,
                    cycle=cycles_completed,
                ),
                access_token=credentials.access_token,
            )
            push, observed_revision = _accepted_revision(
                push,
                expected_operations=config.operations_per_push,
            )
            results.append(push.result)
            if not push.result.successful or observed_revision is None:
                break
            revision = observed_revision
            sync_operations_completed += config.operations_per_push

            pull_results, observed_cursor = _pull_all(
                client,
                access_token=credentials.access_token,
                cursor=pull_cursor,
            )
            results.extend(pull_results)
            if observed_cursor is None:
                break
            pull_cursor = observed_cursor
            cycles_completed += 1

            if cycles_completed % config.refresh_every_cycles == 0:
                refresh = client.request(
                    step="token-refresh",
                    method="POST",
                    path="/api/v1/auth/token/refresh",
                    payload={"refresh_token": credentials.refresh_token},
                )
                refreshed_credentials = _credentials(refresh)
                if refresh.result.successful and refreshed_credentials is None:
                    refresh = _invalid_response(refresh, "invalid_refresh_credentials")
                results.append(refresh.result)
                if not refresh.result.successful or refreshed_credentials is None:
                    break
                credentials = refreshed_credentials
                refreshes_completed += 1

            if config.think_time_seconds > 0:
                time.sleep(config.think_time_seconds)
    finally:
        logout = client.request(
            step="logout",
            method="POST",
            path="/api/v1/auth/logout",
            access_token=credentials.access_token,
            expected_statuses=(204,),
        )
        results.append(logout.result)

    return UserJourneySummary(
        results=tuple(results),
        bootstrapped=bootstrapped,
        cycles_completed=cycles_completed,
        sync_operations_completed=sync_operations_completed,
        refreshes_completed=refreshes_completed,
        hit_cycle_cap=hit_cycle_cap,
        hit_sync_operation_cap=hit_sync_operation_cap,
    )


def run_sync_stage(
    *,
    stage: StageSpec,
    client_factory: Callable[[], JourneyClient],
    config: SyncRunConfig,
) -> SyncStageSummary:
    start_event = threading.Event()
    issue_lock = threading.Lock()
    sync_operations_reserved = 0
    sync_cap_reached = False
    deadline = 0.0

    def claim_sync_operations(amount: int) -> bool:
        nonlocal sync_operations_reserved, sync_cap_reached
        with issue_lock:
            if sync_operations_reserved + amount > config.max_sync_operations:
                sync_cap_reached = True
                return False
            sync_operations_reserved += amount
            return True

    def worker() -> UserJourneySummary:
        client = client_factory()
        start_event.wait()
        try:
            return run_user_journey(
                client,
                config=SyncStageConfig(
                    deadline=deadline,
                    run_tag=config.run_tag,
                    edition=config.edition,
                    operations_per_push=config.operations_per_push,
                    max_cycles_per_user=config.max_cycles_per_user,
                    refresh_every_cycles=config.refresh_every_cycles,
                    think_time_seconds=config.think_time_seconds,
                    claim_sync_operations=claim_sync_operations,
                ),
            )
        finally:
            client.close()

    with ThreadPoolExecutor(max_workers=stage.concurrency) as executor:
        futures = [executor.submit(worker) for _ in range(stage.concurrency)]
        started = time.perf_counter()
        deadline = started + stage.duration_seconds
        start_event.set()
        user_summaries = tuple(future.result() for future in futures)
    elapsed = time.perf_counter() - started
    if sync_cap_reached or any(item.hit_sync_operation_cap for item in user_summaries):
        stop_reason = "sync_operation_cap"
    elif any(item.hit_cycle_cap for item in user_summaries):
        stop_reason = "cycle_cap"
    elif elapsed < stage.duration_seconds * 0.95:
        stop_reason = "journey_ended"
    else:
        stop_reason = "duration"
    return SyncStageSummary(
        stage=stage,
        results=tuple(result for user_summary in user_summaries for result in user_summary.results),
        elapsed_seconds=elapsed,
        stop_reason=stop_reason,
        users_bootstrapped=sum(item.bootstrapped for item in user_summaries),
        cycles_completed=sum(item.cycles_completed for item in user_summaries),
        sync_operations_completed=sum(item.sync_operations_completed for item in user_summaries),
        refreshes_completed=sum(item.refreshes_completed for item in user_summaries),
    )


def threshold_failures(
    summary: SyncStageSummary,
    *,
    max_error_rate: float,
    max_p95_ms: float,
    max_p99_ms: float,
) -> tuple[str, ...]:
    failures: list[str] = []
    if summary.stop_reason != "duration":
        failures.append("stage ended before the requested duration")
    if summary.users_bootstrapped != summary.stage.concurrency:
        failures.append(
            f"only {summary.users_bootstrapped}/{summary.stage.concurrency} users bootstrapped"
        )
    if summary.cycles_completed < summary.users_bootstrapped:
        failures.append("not every bootstrapped user completed one sync push/pull cycle")
    if summary.error_rate > max_error_rate:
        failures.append(f"error rate {summary.error_rate:.2%} exceeds {max_error_rate:.2%}")
    if summary.latency_percentile(0.95) > max_p95_ms:
        failures.append(f"p95 {summary.latency_percentile(0.95):.1f}ms exceeds {max_p95_ms:.1f}ms")
    if summary.latency_percentile(0.99) > max_p99_ms:
        failures.append(f"p99 {summary.latency_percentile(0.99):.1f}ms exceeds {max_p99_ms:.1f}ms")
    return tuple(failures)


def stage_payload(summary: SyncStageSummary, failures: Sequence[str]) -> dict[str, object]:
    grouped: dict[str, list[JourneyResult]] = defaultdict(list)
    for result in summary.results:
        grouped[result.step].append(result)
    step_payload: dict[str, object] = {}
    for step, results in sorted(grouped.items()):
        latencies = [result.latency_ms for result in results]
        step_payload[step] = {
            "requests": len(results),
            "errors": sum(not result.successful for result in results),
            "error_rate": round(sum(not result.successful for result in results) / len(results), 6),
            "bytes_received": sum(result.bytes_received for result in results),
            "p50_ms": round(percentile(latencies, 0.50), 2),
            "p95_ms": round(percentile(latencies, 0.95), 2),
            "p99_ms": round(percentile(latencies, 0.99), 2),
            "statuses": dict(sorted(Counter(str(result.status) for result in results).items())),
            "errors_by_reason": dict(
                sorted(
                    Counter(
                        result.error or "unspecified_error"
                        for result in results
                        if not result.successful
                    ).items()
                )
            ),
        }
    return {
        "concurrency": summary.stage.concurrency,
        "requested_duration_seconds": summary.stage.duration_seconds,
        "elapsed_seconds": round(summary.elapsed_seconds, 3),
        "stop_reason": summary.stop_reason,
        "requests": len(summary.results),
        "requests_per_second": round(summary.requests_per_second, 2),
        "error_rate": round(summary.error_rate, 6),
        "p50_ms": round(summary.latency_percentile(0.50), 2),
        "p95_ms": round(summary.latency_percentile(0.95), 2),
        "p99_ms": round(summary.latency_percentile(0.99), 2),
        "bytes_received": sum(result.bytes_received for result in summary.results),
        "users_bootstrapped": summary.users_bootstrapped,
        "cycles_completed": summary.cycles_completed,
        "sync_operations_completed": summary.sync_operations_completed,
        "refreshes_completed": summary.refreshes_completed,
        "passed": not failures,
        "failures": list(failures),
        "steps": step_payload,
    }


def print_stage(payload: Mapping[str, Any]) -> None:
    print(
        "SYNC STAGE "
        f"concurrency={payload['concurrency']} duration={payload['elapsed_seconds']}s "
        f"requests={payload['requests']} rps={payload['requests_per_second']} "
        f"errors={float(payload['error_rate']):.2%} p95={payload['p95_ms']}ms "
        f"p99={payload['p99_ms']}ms users={payload['users_bootstrapped']} "
        f"sync_ops={payload['sync_operations_completed']} stop={payload['stop_reason']}"
    )
    for failure in payload["failures"]:
        print(f"  FAIL: {failure}", file=sys.stderr)


def bounded_stage(value: str) -> StageSpec:
    stage = parse_stage(value)
    if stage.concurrency > MAX_CONCURRENCY:
        raise argparse.ArgumentTypeError(f"stateful concurrency must be at most {MAX_CONCURRENCY}")
    if stage.duration_seconds > MAX_STAGE_SECONDS:
        raise argparse.ArgumentTypeError(
            f"stateful stage duration must be at most {MAX_STAGE_SECONDS:g} seconds"
        )
    return stage


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("value must be positive")
    return parsed


def bounded_int(maximum: int, field: str) -> Callable[[str], int]:
    def parser(value: str) -> int:
        parsed = positive_int(value)
        if parsed > maximum:
            raise argparse.ArgumentTypeError(f"{field} must be at most {maximum}")
        return parsed

    return parser


def non_negative_float(value: str) -> float:
    parsed = float(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("value must not be negative")
    return parsed


def unit_interval(value: str) -> float:
    parsed = float(value)
    if not 0 <= parsed <= 1:
        raise argparse.ArgumentTypeError("value must be between 0 and 1")
    return parsed


def validate_stateful_authorization(
    *,
    base_url: str,
    confirmed_host: str,
    allow_stateful_writes: bool,
    confirm_disposable_staging_data: bool,
) -> None:
    parsed = urlsplit(base_url)
    if parsed.hostname != confirmed_host:
        raise ValueError("--confirm-target-host must exactly match the base URL hostname")
    if not allow_stateful_writes:
        raise ValueError("--allow-stateful-writes is required")
    if not confirm_disposable_staging_data:
        raise ValueError("--confirm-disposable-staging-data is required")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Run a bounded stateful guest auth/token refresh/reading sync journey. "
            "It creates persistent guest and sync rows and is only for disposable staging."
        )
    )
    parser.add_argument("--base-url", type=validate_base_url, required=True)
    parser.add_argument("--stage", type=bounded_stage, action="append", required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--json-report", type=Path, required=True)
    parser.add_argument("--confirm-target-host", required=True)
    parser.add_argument("--allow-stateful-writes", action="store_true")
    parser.add_argument("--confirm-disposable-staging-data", action="store_true")
    parser.add_argument("--edition", default="madani-hafs")
    parser.add_argument("--timeout-seconds", type=positive_int, default=5)
    parser.add_argument(
        "--operations-per-push",
        type=bounded_int(MAX_OPERATIONS_PER_PUSH, "operations per push"),
        default=1,
    )
    parser.add_argument(
        "--max-cycles-per-user",
        type=bounded_int(MAX_CYCLES_PER_USER, "cycles per user"),
        default=200,
    )
    parser.add_argument(
        "--refresh-every-cycles",
        type=bounded_int(MAX_CYCLES_PER_USER, "refresh interval"),
        default=20,
    )
    parser.add_argument("--think-time-ms", type=non_negative_float, default=500.0)
    parser.add_argument(
        "--max-sync-operations-per-stage",
        type=bounded_int(MAX_SYNC_OPERATIONS_PER_STAGE, "sync operations per stage"),
        default=DEFAULT_SYNC_OPERATIONS_PER_STAGE,
    )
    parser.add_argument("--max-error-rate", type=unit_interval, default=0.01)
    parser.add_argument("--max-p95-ms", type=non_negative_float, default=750.0)
    parser.add_argument("--max-p99-ms", type=non_negative_float, default=1_500.0)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if not args.label.strip():
            raise ValueError("--label must be non-empty")
        validate_stateful_authorization(
            base_url=args.base_url,
            confirmed_host=args.confirm_target_host,
            allow_stateful_writes=args.allow_stateful_writes,
            confirm_disposable_staging_data=args.confirm_disposable_staging_data,
        )
    except ValueError as exc:
        parser.error(str(exc))

    parsed_base: SplitResult = urlsplit(args.base_url)
    run_tag = hashlib.sha256(args.label.encode()).hexdigest()[:8]
    stage_payloads: list[dict[str, object]] = []
    report: dict[str, object] = {
        "schema_version": 1,
        "generated_at": datetime.now(UTC).isoformat(),
        "label": args.label,
        "run_tag": run_tag,
        "target": (f"{parsed_base.scheme}://{parsed_base.netloc}{parsed_base.path.rstrip('/')}"),
        "journey": "guest-auth-reading-sync",
        "edition": args.edition,
        "operations_per_push": args.operations_per_push,
        "refresh_every_cycles": args.refresh_every_cycles,
        "think_time_ms": args.think_time_ms,
        "safety_caps": {
            "max_concurrency": MAX_CONCURRENCY,
            "max_stage_seconds": MAX_STAGE_SECONDS,
            "max_cycles_per_user": args.max_cycles_per_user,
            "max_sync_operations_per_stage": args.max_sync_operations_per_stage,
            "max_response_bytes": MAX_RESPONSE_BYTES,
        },
        "thresholds": {
            "max_error_rate": args.max_error_rate,
            "max_p95_ms": args.max_p95_ms,
            "max_p99_ms": args.max_p99_ms,
        },
        "persistent_test_data": {
            "guest_users_created_at_most": sum(stage.concurrency for stage in args.stage),
            "reading_positions_per_user_at_most": 1,
            "device_app_version_marker": f"load.{run_tag}",
        },
        "stages": stage_payloads,
    }
    all_passed = True
    for stage in args.stage:
        summary = run_sync_stage(
            stage=stage,
            client_factory=lambda: StatefulHttpClient(
                base_url=args.base_url,
                timeout_seconds=args.timeout_seconds,
            ),
            config=SyncRunConfig(
                run_tag=run_tag,
                edition=args.edition,
                operations_per_push=args.operations_per_push,
                max_cycles_per_user=args.max_cycles_per_user,
                refresh_every_cycles=args.refresh_every_cycles,
                think_time_seconds=args.think_time_ms / 1_000,
                max_sync_operations=args.max_sync_operations_per_stage,
            ),
        )
        failures = threshold_failures(
            summary,
            max_error_rate=args.max_error_rate,
            max_p95_ms=args.max_p95_ms,
            max_p99_ms=args.max_p99_ms,
        )
        payload = stage_payload(summary, failures)
        print_stage(payload)
        stage_payloads.append(payload)
        all_passed = all_passed and not failures
    report["passed"] = all_passed
    args.json_report.parent.mkdir(parents=True, exist_ok=True)
    args.json_report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        "PASS: all stateful sync capacity stages satisfied."
        if all_passed
        else "FAIL: stateful sync capacity thresholds exceeded."
    )
    return 0 if all_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
