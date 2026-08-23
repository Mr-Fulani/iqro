#!/usr/bin/env python3
from __future__ import annotations

import argparse
import math
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from collections.abc import Sequence
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass

DEFAULT_ENDPOINTS = (
    "/api/v1/health/live",
    "/api/v1/quran/editions",
    "/api/v1/reciters?page_size=10",
    "/api/v1/recitations?page_size=10",
)


@dataclass(frozen=True, slots=True)
class RequestResult:
    endpoint: str
    latency_ms: float
    status: int | None
    error: str | None

    @property
    def successful(self) -> bool:
        return (
            self.error is None and self.status is not None and 200 <= self.status < 400
        )


@dataclass(frozen=True, slots=True)
class SmokeSummary:
    results: tuple[RequestResult, ...]

    @property
    def error_rate(self) -> float:
        if not self.results:
            return 1.0
        return sum(not result.successful for result in self.results) / len(self.results)

    @property
    def p95_ms(self) -> float:
        return percentile([result.latency_ms for result in self.results], 0.95)


def percentile(values: Sequence[float], quantile: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = max(0, math.ceil(len(ordered) * quantile) - 1)
    return ordered[index]


def validate_base_url(value: str) -> str:
    parsed = urllib.parse.urlsplit(value)
    if (
        parsed.scheme not in {"http", "https"}
        or parsed.hostname is None
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
    ):
        raise argparse.ArgumentTypeError(
            "base URL must be HTTP(S) without credentials, query, or fragment"
        )
    return value.rstrip("/")


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("value must be positive")
    return parsed


def non_negative_int(value: str) -> int:
    parsed = int(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("value must not be negative")
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


def validate_endpoint(value: str) -> str:
    if not value.startswith("/") or value.startswith("//"):
        raise argparse.ArgumentTypeError(
            "endpoint must be an absolute path on the target host"
        )
    return value


def request_once(base_url: str, endpoint: str, timeout_seconds: float) -> RequestResult:
    request = urllib.request.Request(
        f"{base_url}{endpoint}",
        headers={
            "Accept": "application/json",
            "User-Agent": "quran-platform-load-smoke/1",
        },
        method="GET",
    )
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            response.read(64)
            status: int | None = response.status
            error = None
    except urllib.error.HTTPError as exc:
        status = exc.code
        error = f"HTTP {exc.code}"
    except (TimeoutError, urllib.error.URLError, OSError) as exc:
        status = None
        error = type(exc).__name__
    latency_ms = (time.perf_counter() - started) * 1_000
    return RequestResult(endpoint, latency_ms, status, error)


def run_smoke(
    *,
    base_url: str,
    endpoints: Sequence[str],
    request_count: int,
    concurrency: int,
    timeout_seconds: float,
    warmup_rounds: int,
) -> SmokeSummary:
    for _ in range(warmup_rounds):
        for endpoint in endpoints:
            request_once(base_url, endpoint, timeout_seconds)

    scheduled_endpoints = [
        endpoints[index % len(endpoints)] for index in range(request_count)
    ]
    with ThreadPoolExecutor(max_workers=concurrency) as executor:
        results = tuple(
            executor.map(
                lambda endpoint: request_once(base_url, endpoint, timeout_seconds),
                scheduled_endpoints,
            )
        )
    return SmokeSummary(results)


def print_summary(summary: SmokeSummary) -> None:
    grouped: dict[str, list[RequestResult]] = defaultdict(list)
    for result in summary.results:
        grouped[result.endpoint].append(result)

    print("endpoint requests errors p50_ms p95_ms max_ms")
    for endpoint, results in grouped.items():
        latencies = [result.latency_ms for result in results]
        errors = sum(not result.successful for result in results)
        print(
            f"{endpoint} {len(results)} {errors} "
            f"{percentile(latencies, 0.50):.1f} {percentile(latencies, 0.95):.1f} "
            f"{max(latencies):.1f}"
        )
    print(
        f"TOTAL {len(summary.results)} "
        f"error_rate={summary.error_rate:.2%} p95_ms={summary.p95_ms:.1f}"
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run a bounded, read-only concurrency smoke test against public API endpoints."
    )
    parser.add_argument(
        "--base-url", type=validate_base_url, default="http://localhost:8000"
    )
    parser.add_argument(
        "--endpoint",
        action="append",
        type=validate_endpoint,
        dest="endpoints",
        help="Repeat to replace the default endpoint set.",
    )
    parser.add_argument("--requests", type=positive_int, default=120)
    parser.add_argument("--concurrency", type=positive_int, default=10)
    parser.add_argument("--timeout-seconds", type=positive_int, default=5)
    parser.add_argument("--warmup-rounds", type=non_negative_int, default=1)
    parser.add_argument("--max-error-rate", type=unit_interval, default=0.01)
    parser.add_argument("--max-p95-ms", type=non_negative_float, default=1_000.0)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    endpoints = tuple(args.endpoints or DEFAULT_ENDPOINTS)
    summary = run_smoke(
        base_url=args.base_url,
        endpoints=endpoints,
        request_count=args.requests,
        concurrency=min(args.concurrency, args.requests),
        timeout_seconds=args.timeout_seconds,
        warmup_rounds=args.warmup_rounds,
    )
    print_summary(summary)
    if summary.error_rate > args.max_error_rate:
        print("FAIL: error-rate threshold exceeded.", file=sys.stderr)
        return 1
    if summary.p95_ms > args.max_p95_ms:
        print("FAIL: p95 latency threshold exceeded.", file=sys.stderr)
        return 1
    print("PASS: smoke thresholds satisfied.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
