#!/usr/bin/env python3
from __future__ import annotations

import argparse
import http.client
import json
import ssl
import sys
import threading
import time
from collections import defaultdict
from collections.abc import Callable, Mapping, Sequence
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Protocol
from urllib.parse import SplitResult, urlsplit

if __package__:
    from ops.load.smoke import percentile, validate_base_url
else:  # Allow the documented `python3 ops/load/capacity.py ...` invocation.
    from smoke import percentile, validate_base_url

DEFAULT_WORKLOAD = Path(__file__).with_name("workloads") / "web-public-read.json"
ALLOWED_HEADERS = {"accept", "cache-control", "if-none-match", "range"}
MAX_CONCURRENCY = 500
MAX_STAGE_SECONDS = 3_600.0


@dataclass(frozen=True, slots=True)
class EndpointSpec:
    name: str
    path: str
    weight: int
    expected_statuses: tuple[int, ...]
    headers: Mapping[str, str]


@dataclass(frozen=True, slots=True)
class Workload:
    name: str
    version: int
    endpoints: tuple[EndpointSpec, ...]


@dataclass(frozen=True, slots=True)
class StageSpec:
    concurrency: int
    duration_seconds: float


@dataclass(frozen=True, slots=True)
class CapacityResult:
    endpoint: str
    latency_ms: float
    status: int | None
    bytes_received: int
    successful: bool
    error: str | None


@dataclass(frozen=True, slots=True)
class StageSummary:
    stage: StageSpec
    results: tuple[CapacityResult, ...]
    elapsed_seconds: float
    stop_reason: str

    @property
    def error_rate(self) -> float:
        if not self.results:
            return 1.0
        return sum(not result.successful for result in self.results) / len(self.results)

    @property
    def requests_per_second(self) -> float:
        return (
            len(self.results) / self.elapsed_seconds
            if self.elapsed_seconds > 0
            else 0.0
        )

    def latency_percentile(self, quantile: float) -> float:
        return percentile([result.latency_ms for result in self.results], quantile)


class CapacityClient(Protocol):
    def request(self, endpoint: EndpointSpec) -> CapacityResult: ...

    def close(self) -> None: ...


class ReadOnlyHttpClient:
    def __init__(
        self,
        *,
        base_url: str,
        timeout_seconds: float,
        max_response_bytes: int,
    ) -> None:
        self.parsed = urlsplit(base_url)
        self.timeout_seconds = timeout_seconds
        self.max_response_bytes = max_response_bytes
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
            host, self.parsed.port, timeout=self.timeout_seconds
        )

    def _target(self, endpoint: EndpointSpec) -> str:
        prefix = self.parsed.path.rstrip("/")
        return f"{prefix}{endpoint.path}" or "/"

    def close(self) -> None:
        if self.connection is not None:
            self.connection.close()
            self.connection = None

    def request(self, endpoint: EndpointSpec) -> CapacityResult:
        headers = {
            "Accept": "application/json",
            "Accept-Encoding": "gzip",
            "User-Agent": "quran-platform-capacity/1",
            **{key.title(): value for key, value in endpoint.headers.items()},
        }
        started = time.perf_counter()
        status: int | None = None
        bytes_received = 0
        error: str | None = None
        try:
            if self.connection is None:
                self.connection = self._new_connection()
            self.connection.request("GET", self._target(endpoint), headers=headers)
            response = self.connection.getresponse()
            status = response.status
            declared_size = response.getheader("Content-Length")
            if declared_size and int(declared_size) > self.max_response_bytes:
                raise ValueError("response_too_large")
            while chunk := response.read(64 * 1024):
                bytes_received += len(chunk)
                if bytes_received > self.max_response_bytes:
                    raise ValueError("response_too_large")
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
        successful = error is None and status in endpoint.expected_statuses
        if error is None and not successful:
            error = f"unexpected_status_{status}"
        return CapacityResult(
            endpoint=endpoint.name,
            latency_ms=latency_ms,
            status=status,
            bytes_received=bytes_received,
            successful=successful,
            error=error,
        )


def _positive_int(value: object, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ValueError(f"{field} must be a positive integer")
    return value


def load_workload(path: Path) -> Workload:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise TypeError("workload root must be an object")
    name = raw.get("name")
    version = raw.get("version")
    endpoint_rows = raw.get("endpoints")
    if not isinstance(name, str) or not name.strip():
        raise ValueError("workload name must be a non-empty string")
    if version != 1:
        raise ValueError("only workload version 1 is supported")
    if not isinstance(endpoint_rows, list) or not endpoint_rows:
        raise ValueError("workload endpoints must be a non-empty array")

    endpoints: list[EndpointSpec] = []
    names: set[str] = set()
    for index, row in enumerate(endpoint_rows):
        field = f"endpoints[{index}]"
        if not isinstance(row, dict):
            raise TypeError(f"{field} must be an object")
        endpoint_name = row.get("name")
        endpoint_path = row.get("path")
        if not isinstance(endpoint_name, str) or not endpoint_name.strip():
            raise ValueError(f"{field}.name must be a non-empty string")
        if endpoint_name in names:
            raise ValueError(f"duplicate endpoint name: {endpoint_name}")
        names.add(endpoint_name)
        if (
            not isinstance(endpoint_path, str)
            or not endpoint_path.startswith("/")
            or endpoint_path.startswith("//")
        ):
            raise ValueError(
                f"{field}.path must be an absolute path on the target host"
            )

        statuses = row.get("expected_statuses", [200])
        if (
            not isinstance(statuses, list)
            or not statuses
            or any(
                isinstance(status, bool)
                or not isinstance(status, int)
                or not 100 <= status <= 599
                for status in statuses
            )
        ):
            raise ValueError(
                f"{field}.expected_statuses must contain HTTP status integers"
            )
        raw_headers = row.get("headers", {})
        if not isinstance(raw_headers, dict) or any(
            not isinstance(key, str) or not isinstance(value, str)
            for key, value in raw_headers.items()
        ):
            raise ValueError(f"{field}.headers must be a string map")
        disallowed_headers = sorted(
            key for key in raw_headers if key.lower() not in ALLOWED_HEADERS
        )
        if disallowed_headers:
            raise ValueError(
                f"{field}.headers contains disallowed names: {', '.join(disallowed_headers)}"
            )
        endpoints.append(
            EndpointSpec(
                name=endpoint_name,
                path=endpoint_path,
                weight=_positive_int(row.get("weight"), f"{field}.weight"),
                expected_statuses=tuple(statuses),
                headers=dict(raw_headers),
            )
        )
    if sum(endpoint.weight for endpoint in endpoints) > 10_000:
        raise ValueError("sum of endpoint weights must not exceed 10000")
    return Workload(name=name, version=version, endpoints=tuple(endpoints))


def parse_stage(value: str) -> StageSpec:
    try:
        concurrency_raw, duration_raw = value.split(":", 1)
        concurrency = int(concurrency_raw)
        duration = float(duration_raw)
    except (TypeError, ValueError) as exc:
        raise argparse.ArgumentTypeError("stage must use CONCURRENCY:SECONDS") from exc
    if not 1 <= concurrency <= MAX_CONCURRENCY:
        raise argparse.ArgumentTypeError(
            f"concurrency must be between 1 and {MAX_CONCURRENCY}"
        )
    if not 0 < duration <= MAX_STAGE_SECONDS:
        raise argparse.ArgumentTypeError(
            f"stage duration must be above 0 and at most {MAX_STAGE_SECONDS:g} seconds"
        )
    return StageSpec(concurrency=concurrency, duration_seconds=duration)


def weighted_schedule(workload: Workload) -> tuple[EndpointSpec, ...]:
    total_weight = sum(endpoint.weight for endpoint in workload.endpoints)
    current = [0] * len(workload.endpoints)
    schedule: list[EndpointSpec] = []
    for _ in range(total_weight):
        for index, endpoint in enumerate(workload.endpoints):
            current[index] += endpoint.weight
        selected = max(range(len(current)), key=current.__getitem__)
        current[selected] -= total_weight
        schedule.append(workload.endpoints[selected])
    return tuple(schedule)


def run_stage(
    *,
    workload: Workload,
    stage: StageSpec,
    client_factory: Callable[[], CapacityClient],
    think_time_seconds: float,
    max_requests: int,
) -> StageSummary:
    schedule = weighted_schedule(workload)
    start_event = threading.Event()
    issue_lock = threading.Lock()
    issued = 0
    deadline = 0.0

    def claim_request() -> bool:
        nonlocal issued
        with issue_lock:
            if issued >= max_requests:
                return False
            issued += 1
            return True

    def worker(worker_index: int) -> list[CapacityResult]:
        client = client_factory()
        results: list[CapacityResult] = []
        schedule_index = worker_index % len(schedule)
        start_event.wait()
        try:
            while time.perf_counter() < deadline and claim_request():
                results.append(client.request(schedule[schedule_index]))
                schedule_index = (schedule_index + 1) % len(schedule)
                if think_time_seconds > 0:
                    time.sleep(think_time_seconds)
        finally:
            client.close()
        return results

    with ThreadPoolExecutor(max_workers=stage.concurrency) as executor:
        futures = [executor.submit(worker, index) for index in range(stage.concurrency)]
        started = time.perf_counter()
        deadline = started + stage.duration_seconds
        start_event.set()
        result_groups = [future.result() for future in futures]
    elapsed = time.perf_counter() - started
    results = tuple(result for group in result_groups for result in group)
    stop_reason = (
        "request_cap"
        if issued >= max_requests and elapsed < stage.duration_seconds
        else "duration"
    )
    return StageSummary(stage, results, elapsed, stop_reason)


def threshold_failures(
    summary: StageSummary,
    *,
    max_error_rate: float,
    max_p95_ms: float,
    max_p99_ms: float,
) -> tuple[str, ...]:
    failures: list[str] = []
    if (
        summary.stop_reason != "duration"
        or summary.elapsed_seconds < summary.stage.duration_seconds * 0.95
    ):
        failures.append("stage ended before the requested duration")
    if summary.error_rate > max_error_rate:
        failures.append(
            f"error rate {summary.error_rate:.2%} exceeds {max_error_rate:.2%}"
        )
    if summary.latency_percentile(0.95) > max_p95_ms:
        failures.append(
            f"p95 {summary.latency_percentile(0.95):.1f}ms exceeds {max_p95_ms:.1f}ms"
        )
    if summary.latency_percentile(0.99) > max_p99_ms:
        failures.append(
            f"p99 {summary.latency_percentile(0.99):.1f}ms exceeds {max_p99_ms:.1f}ms"
        )
    return tuple(failures)


def stage_payload(summary: StageSummary, failures: Sequence[str]) -> dict[str, object]:
    grouped: dict[str, list[CapacityResult]] = defaultdict(list)
    for result in summary.results:
        grouped[result.endpoint].append(result)
    endpoint_payload = {}
    for endpoint, results in sorted(grouped.items()):
        latencies = [result.latency_ms for result in results]
        endpoint_payload[endpoint] = {
            "requests": len(results),
            "errors": sum(not result.successful for result in results),
            "bytes_received": sum(result.bytes_received for result in results),
            "p50_ms": round(percentile(latencies, 0.50), 2),
            "p95_ms": round(percentile(latencies, 0.95), 2),
            "p99_ms": round(percentile(latencies, 0.99), 2),
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
        "passed": not failures,
        "failures": list(failures),
        "endpoints": endpoint_payload,
    }


def print_stage(payload: Mapping[str, object]) -> None:
    print(
        "STAGE "
        f"concurrency={payload['concurrency']} duration={payload['elapsed_seconds']}s "
        f"requests={payload['requests']} rps={payload['requests_per_second']} "
        f"errors={float(payload['error_rate']):.2%} p95={payload['p95_ms']}ms "
        f"p99={payload['p99_ms']}ms stop={payload['stop_reason']}"
    )
    endpoints = payload["endpoints"]
    if isinstance(endpoints, dict):
        for name, row in endpoints.items():
            print(
                f"  {name}: requests={row['requests']} errors={row['errors']} "
                f"p95={row['p95_ms']}ms p99={row['p99_ms']}ms"
            )
    for failure in payload["failures"]:
        print(f"  FAIL: {failure}", file=sys.stderr)


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("value must be positive")
    return parsed


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


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run bounded, read-only staged capacity checks against a public workload."
    )
    parser.add_argument("--base-url", type=validate_base_url, required=True)
    parser.add_argument("--workload", type=Path, default=DEFAULT_WORKLOAD)
    parser.add_argument("--stage", type=parse_stage, action="append", required=True)
    parser.add_argument("--timeout-seconds", type=positive_int, default=5)
    parser.add_argument("--think-time-ms", type=non_negative_float, default=0.0)
    parser.add_argument("--max-requests-per-stage", type=positive_int, default=100_000)
    parser.add_argument("--max-response-bytes", type=positive_int, default=5_000_000)
    parser.add_argument("--max-error-rate", type=unit_interval, default=0.01)
    parser.add_argument("--max-p95-ms", type=non_negative_float, default=750.0)
    parser.add_argument("--max-p99-ms", type=non_negative_float, default=1_500.0)
    parser.add_argument("--label", default="unlabelled")
    parser.add_argument("--json-report", type=Path)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    workload = load_workload(args.workload)
    parsed_base: SplitResult = urlsplit(args.base_url)
    report: dict[str, object] = {
        "schema_version": 1,
        "generated_at": datetime.now(UTC).isoformat(),
        "label": args.label,
        "target": f"{parsed_base.scheme}://{parsed_base.netloc}{parsed_base.path.rstrip('/')}",
        "workload": {"name": workload.name, "version": workload.version},
        "thresholds": {
            "max_error_rate": args.max_error_rate,
            "max_p95_ms": args.max_p95_ms,
            "max_p99_ms": args.max_p99_ms,
        },
        "stages": [],
    }
    all_passed = True
    for stage in args.stage:
        summary = run_stage(
            workload=workload,
            stage=stage,
            client_factory=lambda: ReadOnlyHttpClient(
                base_url=args.base_url,
                timeout_seconds=args.timeout_seconds,
                max_response_bytes=args.max_response_bytes,
            ),
            think_time_seconds=args.think_time_ms / 1_000,
            max_requests=args.max_requests_per_stage,
        )
        failures = threshold_failures(
            summary,
            max_error_rate=args.max_error_rate,
            max_p95_ms=args.max_p95_ms,
            max_p99_ms=args.max_p99_ms,
        )
        payload = stage_payload(summary, failures)
        print_stage(payload)
        report["stages"].append(payload)
        all_passed = all_passed and not failures
    report["passed"] = all_passed
    if args.json_report:
        args.json_report.parent.mkdir(parents=True, exist_ok=True)
        args.json_report.write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    print(
        "PASS: all capacity stages satisfied."
        if all_passed
        else "FAIL: capacity thresholds exceeded."
    )
    return 0 if all_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
