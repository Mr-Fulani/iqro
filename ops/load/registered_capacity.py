#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import http.client
import json
import re
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
from urllib.parse import SplitResult, urlencode, urlsplit

if __package__:
    from ops.load.capacity import StageSpec, parse_stage
    from ops.load.smoke import percentile, validate_base_url
    from ops.load.sync_capacity import (
        MAX_CYCLES_PER_USER,
        MAX_SYNC_OPERATIONS_PER_STAGE,
        JourneyClient,
        JourneyCredentials,
        JourneyResponse,
        JourneyResult,
        StatefulHttpClient,
        _accepted_revision,
        _bootstrap_payload,
        _credentials,
        _pull_all,
        _sync_push_payload,
        validate_stateful_authorization,
    )
else:  # Allow the documented direct script invocation.
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from ops.load.capacity import StageSpec, parse_stage
    from ops.load.smoke import percentile, validate_base_url
    from ops.load.sync_capacity import (
        MAX_CYCLES_PER_USER,
        MAX_SYNC_OPERATIONS_PER_STAGE,
        JourneyClient,
        JourneyCredentials,
        JourneyResponse,
        JourneyResult,
        StatefulHttpClient,
        _accepted_revision,
        _bootstrap_payload,
        _credentials,
        _pull_all,
        _sync_push_payload,
        validate_stateful_authorization,
    )


MAX_CONCURRENCY = 20
MAX_TOTAL_REGISTERED_USERS = 40
MAX_STAGE_SECONDS = 600.0
MAX_MAILPIT_DELIVERY_SECONDS = 30.0
MAX_RESPONSE_BYTES = 1024 * 1024
MAIL_DELIVERY_STEP = "email-code-delivery"
EMAIL_CODE_PATTERN = re.compile(r"(?<![0-9])[0-9]{6}(?![0-9])")
TEST_EMAIL_DOMAIN_PATTERN = re.compile(
    r"^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*test$"
)


@dataclass(frozen=True, slots=True)
class MailCodeResponse:
    result: JourneyResult
    code: str | None


@dataclass(frozen=True, slots=True)
class RegisteredUserSummary:
    results: tuple[JourneyResult, ...]
    bootstrapped: bool
    registered: bool
    cycles_completed: int
    sync_operations_completed: int
    refreshes_completed: int
    hit_cycle_cap: bool
    hit_sync_operation_cap: bool


@dataclass(frozen=True, slots=True)
class RegisteredStageConfig:
    deadline: float
    run_tag: str
    email_domain: str
    edition: str
    operations_per_push: int
    max_cycles_per_user: int
    refresh_every_cycles: int
    think_time_seconds: float
    claim_sync_operations: Callable[[int], bool]


@dataclass(frozen=True, slots=True)
class RegisteredRunConfig:
    run_tag: str
    email_domain: str
    edition: str
    operations_per_push: int
    max_cycles_per_user: int
    refresh_every_cycles: int
    think_time_seconds: float
    max_sync_operations: int


@dataclass(frozen=True, slots=True)
class RegisteredStageSummary:
    stage: StageSpec
    results: tuple[JourneyResult, ...]
    elapsed_seconds: float
    stop_reason: str
    users_bootstrapped: int
    users_registered: int
    cycles_completed: int
    sync_operations_completed: int
    refreshes_completed: int

    @property
    def api_results(self) -> tuple[JourneyResult, ...]:
        return tuple(
            result for result in self.results if result.step != MAIL_DELIVERY_STEP
        )

    @property
    def delivery_results(self) -> tuple[JourneyResult, ...]:
        return tuple(
            result for result in self.results if result.step == MAIL_DELIVERY_STEP
        )

    @property
    def api_error_rate(self) -> float:
        if not self.api_results:
            return 1.0
        return sum(not result.successful for result in self.api_results) / len(
            self.api_results
        )

    @property
    def delivery_error_rate(self) -> float:
        if not self.delivery_results:
            return 1.0
        return sum(not result.successful for result in self.delivery_results) / len(
            self.delivery_results
        )

    @property
    def requests_per_second(self) -> float:
        if self.elapsed_seconds <= 0:
            return 0.0
        return len(self.api_results) / self.elapsed_seconds

    def api_latency_percentile(self, quantile: float) -> float:
        return percentile([result.latency_ms for result in self.api_results], quantile)

    def delivery_latency_percentile(self, quantile: float) -> float:
        return percentile(
            [result.latency_ms for result in self.delivery_results], quantile
        )


class MailCodeClient(Protocol):
    def wait_for_code(self, email: str) -> MailCodeResponse: ...

    def close(self) -> None: ...


class _StopJourney(Exception):
    pass


class MailpitHttpClient:
    def __init__(
        self,
        *,
        base_url: str,
        request_timeout_seconds: float,
        delivery_timeout_seconds: float,
        poll_interval_seconds: float,
    ) -> None:
        self.parsed = urlsplit(base_url)
        self.request_timeout_seconds = request_timeout_seconds
        self.delivery_timeout_seconds = delivery_timeout_seconds
        self.poll_interval_seconds = poll_interval_seconds
        self.connection: http.client.HTTPConnection | None = None

    def _new_connection(self) -> http.client.HTTPConnection:
        host = self.parsed.hostname
        if host is None:
            raise ValueError("Mailpit URL has no hostname")
        if self.parsed.scheme == "https":
            return http.client.HTTPSConnection(
                host,
                self.parsed.port,
                timeout=self.request_timeout_seconds,
                context=ssl.create_default_context(),
            )
        return http.client.HTTPConnection(
            host,
            self.parsed.port,
            timeout=self.request_timeout_seconds,
        )

    def close(self) -> None:
        if self.connection is not None:
            self.connection.close()
            self.connection = None

    def _target(self, email: str) -> str:
        prefix = self.parsed.path.rstrip("/")
        query = urlencode({"query": f'to:"{email}"'})
        return f"{prefix}/view/latest.txt?{query}"

    def wait_for_code(self, email: str) -> MailCodeResponse:
        started = time.perf_counter()
        deadline = started + self.delivery_timeout_seconds
        status: int | None = None
        bytes_received = 0
        error: str | None = None
        code: str | None = None
        while time.perf_counter() < deadline:
            try:
                if self.connection is None:
                    self.connection = self._new_connection()
                self.connection.request(
                    "GET",
                    self._target(email),
                    headers={
                        "Accept": "text/plain",
                        "Accept-Encoding": "identity",
                        "User-Agent": "quran-platform-registered-capacity/1",
                    },
                )
                response = self.connection.getresponse()
                status = response.status
                body = response.read(MAX_RESPONSE_BYTES + 1)
                bytes_received = len(body)
                if bytes_received > MAX_RESPONSE_BYTES:
                    error = "mailpit_response_too_large"
                    break
                if status == 200:
                    match = EMAIL_CODE_PATTERN.search(
                        body.decode("utf-8", errors="replace")
                    )
                    if match is None:
                        error = "verification_code_missing"
                    else:
                        code = match.group(0)
                    break
                if status != 404:
                    error = f"unexpected_mailpit_status_{status}"
                    break
            except (OSError, TimeoutError, http.client.HTTPException, ssl.SSLError):
                self.close()
            remaining = deadline - time.perf_counter()
            if remaining > 0:
                time.sleep(min(self.poll_interval_seconds, remaining))
        if code is None and error is None:
            error = "mailpit_code_timeout"
        return MailCodeResponse(
            result=JourneyResult(
                step=MAIL_DELIVERY_STEP,
                latency_ms=(time.perf_counter() - started) * 1_000,
                status=status,
                bytes_received=bytes_received,
                successful=code is not None and error is None,
                error=error,
            ),
            code=code,
        )


def _invalid_response(response: JourneyResponse, reason: str) -> JourneyResponse:
    return JourneyResponse(
        result=replace(response.result, successful=False, error=reason),
        payload=response.payload,
    )


def _challenge_id(response: JourneyResponse) -> str | None:
    if not response.result.successful or response.payload is None:
        return None
    value = response.payload.get("challenge_id")
    if not isinstance(value, str):
        return None
    try:
        uuid.UUID(value)
    except ValueError:
        return None
    return value


def _registered_credentials(
    response: JourneyResponse,
    *,
    expected_email: str,
) -> JourneyCredentials | None:
    credentials = _credentials(response)
    payload = response.payload
    if credentials is None or payload is None:
        return None
    user = payload.get("user")
    if not isinstance(user, dict):
        return None
    if user.get("status") != "active" or user.get("email") != expected_email:
        return None
    return credentials


def _active_session(response: JourneyResponse, *, expected_email: str) -> bool:
    if not response.result.successful or response.payload is None:
        return False
    user = response.payload.get("user")
    return (
        isinstance(user, dict)
        and user.get("status") == "active"
        and user.get("email") == expected_email
    )


def _test_email(run_tag: str, domain: str) -> str:
    return f"load-{run_tag}-{secrets.token_hex(8)}@{domain}"


def run_registered_user_journey(
    client: JourneyClient,
    mail_client: MailCodeClient,
    *,
    config: RegisteredStageConfig,
) -> RegisteredUserSummary:
    results: list[JourneyResult] = []
    bootstrapped = False
    registered = False
    cycles_completed = 0
    sync_operations_completed = 0
    refreshes_completed = 0
    hit_cycle_cap = False
    hit_sync_operation_cap = False
    credentials: JourneyCredentials | None = None

    bootstrap_payload = _bootstrap_payload(config.run_tag)
    installation_credential = str(bootstrap_payload["installation_credential"])
    bootstrap = client.request(
        step="guest-bootstrap",
        method="POST",
        path="/api/v1/auth/guest",
        payload=bootstrap_payload,
    )
    credentials = _credentials(bootstrap)
    if bootstrap.result.successful and credentials is None:
        bootstrap = _invalid_response(bootstrap, "invalid_bootstrap_credentials")
    results.append(bootstrap.result)
    if not bootstrap.result.successful or credentials is None:
        return RegisteredUserSummary(
            tuple(results), False, False, 0, 0, 0, False, False
        )
    bootstrapped = True

    email = _test_email(config.run_tag, config.email_domain)
    try:
        start = client.request(
            step="email-start",
            method="POST",
            path="/api/v1/auth/email/start",
            payload={"email": email},
            access_token=credentials.access_token,
            expected_statuses=(202,),
        )
        challenge_id = _challenge_id(start)
        if start.result.successful and challenge_id is None:
            start = _invalid_response(start, "invalid_email_challenge")
        results.append(start.result)
        if not start.result.successful or challenge_id is None:
            raise _StopJourney

        delivered = mail_client.wait_for_code(email)
        results.append(delivered.result)
        if not delivered.result.successful or delivered.code is None:
            raise _StopJourney

        verification = client.request(
            step="email-verify",
            method="POST",
            path="/api/v1/auth/email/verify",
            payload={
                "challenge_id": challenge_id,
                "code": delivered.code,
                "installation_credential": installation_credential,
                "idempotency_key": str(uuid.uuid4()),
            },
        )
        verified_credentials = _registered_credentials(
            verification,
            expected_email=email,
        )
        if verification.result.successful and verified_credentials is None:
            verification = _invalid_response(
                verification, "invalid_registered_credentials"
            )
        results.append(verification.result)
        if not verification.result.successful or verified_credentials is None:
            raise _StopJourney
        credentials = verified_credentials
        registered = True

        current_session = client.request(
            step="registered-session",
            method="GET",
            path="/api/v1/me",
            access_token=credentials.access_token,
        )
        if current_session.result.successful and not _active_session(
            current_session,
            expected_email=email,
        ):
            current_session = _invalid_response(
                current_session,
                "invalid_registered_session",
            )
        results.append(current_session.result)
        if not current_session.result.successful:
            raise _StopJourney

        entity_id = uuid.uuid4()
        revision = 0
        pull_cursor = 0
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
    except _StopJourney:
        pass
    finally:
        if credentials is not None:
            logout = client.request(
                step="logout",
                method="POST",
                path="/api/v1/auth/logout",
                access_token=credentials.access_token,
                expected_statuses=(204,),
            )
            results.append(logout.result)

    return RegisteredUserSummary(
        results=tuple(results),
        bootstrapped=bootstrapped,
        registered=registered,
        cycles_completed=cycles_completed,
        sync_operations_completed=sync_operations_completed,
        refreshes_completed=refreshes_completed,
        hit_cycle_cap=hit_cycle_cap,
        hit_sync_operation_cap=hit_sync_operation_cap,
    )


def run_registered_stage(
    *,
    stage: StageSpec,
    client_factory: Callable[[], JourneyClient],
    mail_client_factory: Callable[[], MailCodeClient],
    config: RegisteredRunConfig,
) -> RegisteredStageSummary:
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

    def worker() -> RegisteredUserSummary:
        client = client_factory()
        mail_client = mail_client_factory()
        start_event.wait()
        try:
            return run_registered_user_journey(
                client,
                mail_client,
                config=RegisteredStageConfig(
                    deadline=deadline,
                    run_tag=config.run_tag,
                    email_domain=config.email_domain,
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
            mail_client.close()

    with ThreadPoolExecutor(max_workers=stage.concurrency) as executor:
        futures = [executor.submit(worker) for _ in range(stage.concurrency)]
        started = time.perf_counter()
        deadline = started + stage.duration_seconds
        start_event.set()
        summaries = tuple(future.result() for future in futures)
    elapsed = time.perf_counter() - started
    if sync_cap_reached or any(item.hit_sync_operation_cap for item in summaries):
        stop_reason = "sync_operation_cap"
    elif any(item.hit_cycle_cap for item in summaries):
        stop_reason = "cycle_cap"
    elif elapsed < stage.duration_seconds * 0.95:
        stop_reason = "journey_ended"
    else:
        stop_reason = "duration"
    return RegisteredStageSummary(
        stage=stage,
        results=tuple(result for summary in summaries for result in summary.results),
        elapsed_seconds=elapsed,
        stop_reason=stop_reason,
        users_bootstrapped=sum(item.bootstrapped for item in summaries),
        users_registered=sum(item.registered for item in summaries),
        cycles_completed=sum(item.cycles_completed for item in summaries),
        sync_operations_completed=sum(
            item.sync_operations_completed for item in summaries
        ),
        refreshes_completed=sum(item.refreshes_completed for item in summaries),
    )


def threshold_failures(
    summary: RegisteredStageSummary,
    *,
    max_error_rate: float,
    max_p95_ms: float,
    max_p99_ms: float,
    max_email_delivery_p95_ms: float,
) -> tuple[str, ...]:
    failures: list[str] = []
    if summary.stop_reason != "duration":
        failures.append("stage ended before the requested duration")
    if summary.users_bootstrapped != summary.stage.concurrency:
        failures.append(
            f"only {summary.users_bootstrapped}/{summary.stage.concurrency} users bootstrapped"
        )
    if summary.users_registered != summary.stage.concurrency:
        failures.append(
            f"only {summary.users_registered}/{summary.stage.concurrency} users registered"
        )
    if summary.cycles_completed < summary.users_registered:
        failures.append("not every registered user completed one sync push/pull cycle")
    if summary.api_error_rate > max_error_rate:
        failures.append(
            f"API error rate {summary.api_error_rate:.2%} exceeds {max_error_rate:.2%}"
        )
    if summary.delivery_error_rate > max_error_rate:
        failures.append(
            "email delivery error rate "
            f"{summary.delivery_error_rate:.2%} exceeds {max_error_rate:.2%}"
        )
    if summary.api_latency_percentile(0.95) > max_p95_ms:
        failures.append(
            f"API p95 {summary.api_latency_percentile(0.95):.1f}ms exceeds "
            f"{max_p95_ms:.1f}ms"
        )
    if summary.api_latency_percentile(0.99) > max_p99_ms:
        failures.append(
            f"API p99 {summary.api_latency_percentile(0.99):.1f}ms exceeds "
            f"{max_p99_ms:.1f}ms"
        )
    if summary.delivery_latency_percentile(0.95) > max_email_delivery_p95_ms:
        failures.append(
            "email delivery p95 "
            f"{summary.delivery_latency_percentile(0.95):.1f}ms exceeds "
            f"{max_email_delivery_p95_ms:.1f}ms"
        )
    return tuple(failures)


def stage_payload(
    summary: RegisteredStageSummary,
    failures: Sequence[str],
) -> dict[str, object]:
    grouped: dict[str, list[JourneyResult]] = defaultdict(list)
    for result in summary.results:
        grouped[result.step].append(result)
    step_payload: dict[str, object] = {}
    for step, results in sorted(grouped.items()):
        latencies = [result.latency_ms for result in results]
        step_payload[step] = {
            "requests": len(results),
            "errors": sum(not result.successful for result in results),
            "error_rate": round(
                sum(not result.successful for result in results) / len(results),
                6,
            ),
            "bytes_received": sum(result.bytes_received for result in results),
            "p50_ms": round(percentile(latencies, 0.50), 2),
            "p95_ms": round(percentile(latencies, 0.95), 2),
            "p99_ms": round(percentile(latencies, 0.99), 2),
            "statuses": dict(
                sorted(Counter(str(result.status) for result in results).items())
            ),
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
        "api_requests": len(summary.api_results),
        "requests_per_second": round(summary.requests_per_second, 2),
        "api_error_rate": round(summary.api_error_rate, 6),
        "api_p50_ms": round(summary.api_latency_percentile(0.50), 2),
        "api_p95_ms": round(summary.api_latency_percentile(0.95), 2),
        "api_p99_ms": round(summary.api_latency_percentile(0.99), 2),
        "email_deliveries": len(summary.delivery_results),
        "email_delivery_error_rate": round(summary.delivery_error_rate, 6),
        "email_delivery_p95_ms": round(summary.delivery_latency_percentile(0.95), 2),
        "users_bootstrapped": summary.users_bootstrapped,
        "users_registered": summary.users_registered,
        "cycles_completed": summary.cycles_completed,
        "sync_operations_completed": summary.sync_operations_completed,
        "refreshes_completed": summary.refreshes_completed,
        "passed": not failures,
        "failures": list(failures),
        "steps": step_payload,
    }


def print_stage(payload: Mapping[str, Any]) -> None:
    print(
        "REGISTERED STAGE "
        f"concurrency={payload['concurrency']} duration={payload['elapsed_seconds']}s "
        f"api_requests={payload['api_requests']} rps={payload['requests_per_second']} "
        f"api_errors={float(payload['api_error_rate']):.2%} "
        f"api_p95={payload['api_p95_ms']}ms api_p99={payload['api_p99_ms']}ms "
        f"email_p95={payload['email_delivery_p95_ms']}ms "
        f"registered={payload['users_registered']} stop={payload['stop_reason']}"
    )
    for failure in payload["failures"]:
        print(f"  FAIL: {failure}", file=sys.stderr)


def bounded_stage(value: str) -> StageSpec:
    stage = parse_stage(value)
    if stage.concurrency > MAX_CONCURRENCY:
        raise argparse.ArgumentTypeError(
            f"registered concurrency must be at most {MAX_CONCURRENCY}"
        )
    if stage.duration_seconds > MAX_STAGE_SECONDS:
        raise argparse.ArgumentTypeError(
            f"registered stage duration must be at most {MAX_STAGE_SECONDS:g} seconds"
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


def positive_float(value: str) -> float:
    parsed = float(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("value must be positive")
    return parsed


def bounded_positive_float(maximum: float, field: str) -> Callable[[str], float]:
    def parser(value: str) -> float:
        parsed = positive_float(value)
        if parsed > maximum:
            raise argparse.ArgumentTypeError(f"{field} must be at most {maximum:g}")
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


def validate_mailpit_url(value: str) -> str:
    parsed = urlsplit(value)
    if parsed.scheme not in {"http", "https"}:
        raise argparse.ArgumentTypeError("Mailpit URL must use http or https")
    if parsed.hostname not in {"127.0.0.1", "localhost", "::1"}:
        raise argparse.ArgumentTypeError(
            "Mailpit URL must use a loopback host through an SSH tunnel"
        )
    if parsed.username is not None or parsed.password is not None:
        raise argparse.ArgumentTypeError("Mailpit URL must not contain credentials")
    if parsed.query or parsed.fragment:
        raise argparse.ArgumentTypeError(
            "Mailpit URL must not contain query or fragment"
        )
    return value.rstrip("/")


def validate_test_email_domain(value: str) -> str:
    normalized = value.strip().lower().rstrip(".")
    if not TEST_EMAIL_DOMAIN_PATTERN.fullmatch(normalized):
        raise argparse.ArgumentTypeError("email domain must be reserved under .test")
    return normalized


def validate_registered_authorization(
    *,
    base_url: str,
    confirmed_host: str,
    allow_stateful_writes: bool,
    confirm_disposable_staging_data: bool,
    allow_email_challenges: bool,
    confirm_intercepted_test_email: bool,
    mailpit_url: str,
    email_domain: str,
) -> None:
    validate_stateful_authorization(
        base_url=base_url,
        confirmed_host=confirmed_host,
        allow_stateful_writes=allow_stateful_writes,
        confirm_disposable_staging_data=confirm_disposable_staging_data,
    )
    try:
        validate_mailpit_url(mailpit_url)
        validate_test_email_domain(email_domain)
    except argparse.ArgumentTypeError as exc:
        raise ValueError(str(exc)) from exc
    if not allow_email_challenges:
        raise ValueError("--allow-email-challenges is required")
    if not confirm_intercepted_test_email:
        raise ValueError("--confirm-intercepted-test-email is required")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Run bounded guest-to-registered email auth plus reading sync. "
            "It requires disposable staging data and a loopback Mailpit SSH tunnel."
        )
    )
    parser.add_argument("--base-url", type=validate_base_url, required=True)
    parser.add_argument("--mailpit-url", type=validate_mailpit_url, required=True)
    parser.add_argument(
        "--email-domain", type=validate_test_email_domain, default="example.test"
    )
    parser.add_argument("--stage", type=bounded_stage, action="append", required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--json-report", type=Path, required=True)
    parser.add_argument("--confirm-target-host", required=True)
    parser.add_argument("--allow-stateful-writes", action="store_true")
    parser.add_argument("--confirm-disposable-staging-data", action="store_true")
    parser.add_argument("--allow-email-challenges", action="store_true")
    parser.add_argument("--confirm-intercepted-test-email", action="store_true")
    parser.add_argument("--edition", default="madani-hafs")
    parser.add_argument("--timeout-seconds", type=positive_int, default=5)
    parser.add_argument(
        "--mailpit-delivery-timeout-seconds",
        type=bounded_positive_float(
            MAX_MAILPIT_DELIVERY_SECONDS,
            "Mailpit delivery timeout",
        ),
        default=10.0,
    )
    parser.add_argument(
        "--mailpit-poll-interval-ms",
        type=bounded_positive_float(1_000, "Mailpit poll interval"),
        default=100.0,
    )
    parser.add_argument(
        "--operations-per-push",
        type=bounded_int(20, "operations per push"),
        default=1,
    )
    parser.add_argument(
        "--max-cycles-per-user",
        type=bounded_int(MAX_CYCLES_PER_USER, "cycles per user"),
        default=100,
    )
    parser.add_argument(
        "--refresh-every-cycles",
        type=bounded_int(MAX_CYCLES_PER_USER, "refresh interval"),
        default=5,
    )
    parser.add_argument("--think-time-ms", type=non_negative_float, default=15_000.0)
    parser.add_argument(
        "--max-sync-operations-per-stage",
        type=bounded_int(MAX_SYNC_OPERATIONS_PER_STAGE, "sync operations per stage"),
        default=2_000,
    )
    parser.add_argument("--max-error-rate", type=unit_interval, default=0.01)
    parser.add_argument("--max-p95-ms", type=non_negative_float, default=750.0)
    parser.add_argument("--max-p99-ms", type=non_negative_float, default=1_500.0)
    parser.add_argument(
        "--max-email-delivery-p95-ms",
        type=non_negative_float,
        default=5_000.0,
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if not args.label.strip():
            raise ValueError("--label must be non-empty")
        if sum(stage.concurrency for stage in args.stage) > MAX_TOTAL_REGISTERED_USERS:
            raise ValueError(
                "sum of registered users across stages must be at most "
                f"{MAX_TOTAL_REGISTERED_USERS}"
            )
        validate_registered_authorization(
            base_url=args.base_url,
            confirmed_host=args.confirm_target_host,
            allow_stateful_writes=args.allow_stateful_writes,
            confirm_disposable_staging_data=args.confirm_disposable_staging_data,
            allow_email_challenges=args.allow_email_challenges,
            confirm_intercepted_test_email=args.confirm_intercepted_test_email,
            mailpit_url=args.mailpit_url,
            email_domain=args.email_domain,
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
        "target": f"{parsed_base.scheme}://{parsed_base.netloc}{parsed_base.path.rstrip('/')}",
        "journey": "guest-email-register-reading-sync",
        "email_transport": "intercepted-mailpit-loopback",
        "email_domain": args.email_domain,
        "edition": args.edition,
        "operations_per_push": args.operations_per_push,
        "refresh_every_cycles": args.refresh_every_cycles,
        "think_time_ms": args.think_time_ms,
        "safety_caps": {
            "max_concurrency": MAX_CONCURRENCY,
            "max_total_registered_users": MAX_TOTAL_REGISTERED_USERS,
            "max_stage_seconds": MAX_STAGE_SECONDS,
            "max_cycles_per_user": args.max_cycles_per_user,
            "max_sync_operations_per_stage": args.max_sync_operations_per_stage,
            "max_mailpit_delivery_seconds": MAX_MAILPIT_DELIVERY_SECONDS,
        },
        "thresholds": {
            "max_error_rate": args.max_error_rate,
            "max_api_p95_ms": args.max_p95_ms,
            "max_api_p99_ms": args.max_p99_ms,
            "max_email_delivery_p95_ms": args.max_email_delivery_p95_ms,
        },
        "persistent_test_data": {
            "registered_users_created_at_most": sum(
                stage.concurrency for stage in args.stage
            ),
            "email_challenges_created_at_most": sum(
                stage.concurrency for stage in args.stage
            ),
            "reading_positions_per_user_at_most": 1,
            "device_app_version_marker": f"load.{run_tag}",
        },
        "stages": stage_payloads,
    }
    all_passed = True
    for stage in args.stage:
        summary = run_registered_stage(
            stage=stage,
            client_factory=lambda: StatefulHttpClient(
                base_url=args.base_url,
                timeout_seconds=args.timeout_seconds,
            ),
            mail_client_factory=lambda: MailpitHttpClient(
                base_url=args.mailpit_url,
                request_timeout_seconds=args.timeout_seconds,
                delivery_timeout_seconds=args.mailpit_delivery_timeout_seconds,
                poll_interval_seconds=args.mailpit_poll_interval_ms / 1_000,
            ),
            config=RegisteredRunConfig(
                run_tag=run_tag,
                email_domain=args.email_domain,
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
            max_email_delivery_p95_ms=args.max_email_delivery_p95_ms,
        )
        payload = stage_payload(summary, failures)
        print_stage(payload)
        stage_payloads.append(payload)
        all_passed = all_passed and not failures
    report["passed"] = all_passed
    args.json_report.parent.mkdir(parents=True, exist_ok=True)
    args.json_report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "PASS: all registered-user capacity stages satisfied."
        if all_passed
        else "FAIL: registered-user capacity thresholds exceeded."
    )
    return 0 if all_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
