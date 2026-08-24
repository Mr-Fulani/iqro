#!/usr/bin/env python3
from __future__ import annotations

import argparse
import http.client
import json
import ssl
import sys
import threading
import time
from collections import Counter, defaultdict
from collections.abc import Callable, Mapping, Sequence
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Protocol
from urllib.parse import urlsplit

if __package__:
    from ops.load.capacity import StageSpec, parse_stage
    from ops.load.smoke import percentile
    from ops.media.contract import AssetSpec, MediaManifest, load_manifest
else:  # Allow the documented `python3 ops/load/audio_capacity.py ...` invocation.
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from ops.load.capacity import StageSpec, parse_stage
    from ops.load.smoke import percentile
    from ops.media.contract import AssetSpec, MediaManifest, load_manifest


DEFAULT_MANIFEST = Path(__file__).parents[1] / "media" / "manifest.example.json"
MAX_CONCURRENCY = 200
MAX_RANGE_BYTES = 1024 * 1024
MAX_STAGE_TRANSFER_BYTES = 20 * 1024 * 1024 * 1024
DEFAULT_STAGE_TRANSFER_BYTES = 512 * 1024 * 1024
MAX_REQUESTS_PER_STAGE = 100_000
CACHE_STATUS_HEADERS = (
    "cf-cache-status",
    "cdn-cache-status",
    "x-cache",
    "x-cache-status",
)


@dataclass(frozen=True, slots=True)
class AudioOperation:
    name: str
    weight: int


@dataclass(frozen=True, slots=True)
class AudioResult:
    asset: str
    operation: str
    latency_ms: float
    ttfb_ms: float
    transfer_ms: float
    throughput_kbps: float | None
    status: int | None
    bytes_received: int
    cache_outcome: str
    successful: bool
    error: str | None


@dataclass(frozen=True, slots=True)
class AudioStageSummary:
    stage: StageSpec
    results: tuple[AudioResult, ...]
    elapsed_seconds: float
    stop_reason: str
    reserved_transfer_bytes: int

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

    def ttfb_percentile(self, quantile: float) -> float:
        return percentile([result.ttfb_ms for result in self.results], quantile)


@dataclass(frozen=True, slots=True)
class AudioStageConfig:
    origin: str
    range_bytes: int
    operations: tuple[AudioOperation, ...]
    think_time_seconds: float
    max_requests: int
    max_transfer_bytes: int


class AudioClient(Protocol):
    def request(
        self,
        asset: AssetSpec,
        operation: AudioOperation,
        *,
        range_bytes: int,
        origin: str,
        sequence: int,
    ) -> AudioResult: ...

    def close(self) -> None: ...


def classify_cache_outcome(headers: Mapping[str, str]) -> str:
    values = [headers[name].lower() for name in CACHE_STATUS_HEADERS if name in headers]
    joined = " ".join(values)
    if "hit" in joined:
        outcome = "hit"
    elif "miss" in joined:
        outcome = "miss"
    elif any(token in joined for token in ("bypass", "dynamic", "pass")):
        outcome = "bypass"
    elif any(token in joined for token in ("expired", "stale", "revalidated")):
        outcome = "revalidated"
    elif (age := headers.get("age")) is not None:
        try:
            outcome = "hit" if int(age) > 0 else "unknown"
        except ValueError:
            outcome = "unknown"
    else:
        outcome = "unknown"
    return outcome


def operation_schedule(
    *, head_weight: int, startup_weight: int, seek_weight: int
) -> tuple[AudioOperation, ...]:
    operations = (
        AudioOperation("head", head_weight),
        AudioOperation("startup", startup_weight),
        AudioOperation("seek", seek_weight),
    )
    schedule: list[AudioOperation] = []
    total_weight = sum(operation.weight for operation in operations)
    if total_weight > 10_000:
        raise ValueError("sum of audio operation weights must not exceed 10000")
    current = [0] * len(operations)
    for _ in range(total_weight):
        for index, operation in enumerate(operations):
            current[index] += operation.weight
        selected = max(range(len(current)), key=current.__getitem__)
        current[selected] -= total_weight
        schedule.append(operations[selected])
    return tuple(schedule)


def requested_range(
    asset: AssetSpec, operation: str, range_bytes: int, sequence: int
) -> tuple[int, int]:
    length = min(range_bytes, asset.expected_bytes)
    if operation == "startup" or asset.expected_bytes <= length:
        return 0, length - 1
    available_starts = max(1, (asset.expected_bytes - length) // length)
    slot = 1 + ((sequence * 17) % available_starts)
    start = min(slot * length, asset.expected_bytes - length)
    return start, start + length - 1


def _request_spec(
    asset: AssetSpec,
    operation: AudioOperation,
    *,
    range_bytes: int,
    origin: str,
    sequence: int,
) -> tuple[str, dict[str, str], int, str | None]:
    method = "HEAD" if operation.name == "head" else "GET"
    headers = {
        "Accept": asset.content_type,
        "Accept-Encoding": "identity",
        "Origin": origin,
        "User-Agent": "quran-platform-audio-capacity/1",
    }
    if method == "HEAD":
        return method, headers, 0, None
    range_start, range_end = requested_range(asset, operation.name, range_bytes, sequence)
    headers["Range"] = f"bytes={range_start}-{range_end}"
    expected_body_bytes = range_end - range_start + 1
    content_range = f"bytes {range_start}-{range_end}/{asset.expected_bytes}"
    return method, headers, expected_body_bytes, content_range


def _read_bounded_response(
    response: http.client.HTTPResponse,
    *,
    method: str,
    asset: AssetSpec,
    expected_body_bytes: int,
) -> tuple[dict[str, str], int]:
    response_headers = {key.lower(): value.strip() for key, value in response.getheaders()}
    declared_length = response_headers.get("content-length")
    if declared_length is not None:
        try:
            parsed_length = int(declared_length)
        except ValueError as exc:
            raise ValueError("invalid_content_length") from exc
        expected_length = asset.expected_bytes if method == "HEAD" else expected_body_bytes
        if parsed_length != expected_length:
            raise ValueError("unexpected_content_length")
    elif method == "HEAD":
        raise ValueError("missing_content_length")

    body_bytes = 0
    if method == "HEAD":
        response.read()
    else:
        while chunk := response.read(min(64 * 1024, expected_body_bytes + 1)):
            body_bytes += len(chunk)
            if body_bytes > expected_body_bytes:
                raise ValueError("response_too_large")
    return response_headers, body_bytes


def _validate_response(
    *,
    status: int,
    headers: Mapping[str, str],
    body_bytes: int,
    method: str,
    asset: AssetSpec,
    expected_body_bytes: int,
    expected_content_range: str | None,
    origin: str,
) -> None:
    expected_status = 200 if method == "HEAD" else 206
    if status != expected_status:
        raise ValueError(f"unexpected_status_{status}")
    if method == "GET" and body_bytes != expected_body_bytes:
        raise ValueError("truncated_response")
    if method == "GET" and headers.get("content-range") != expected_content_range:
        raise ValueError("unexpected_content_range")
    if headers.get("accept-ranges", "").lower() != "bytes":
        raise ValueError("missing_accept_ranges")
    observed_type = headers.get("content-type", "").split(";", 1)[0].lower()
    if observed_type != asset.content_type.lower():
        raise ValueError("unexpected_content_type")
    if asset.expected_etag is not None and headers.get("etag") != asset.expected_etag:
        raise ValueError("unexpected_etag")
    if headers.get("access-control-allow-origin") not in {origin, "*"}:
        raise ValueError("unexpected_cors_origin")


class AudioRangeHttpClient:
    def __init__(self, timeout_seconds: float) -> None:
        self.timeout_seconds = timeout_seconds
        self.connections: dict[tuple[str, str, int | None], http.client.HTTPConnection] = {}

    def _connection(self, asset: AssetSpec) -> http.client.HTTPConnection:
        parsed = urlsplit(asset.url)
        host = parsed.hostname
        if host is None:  # Manifest validation prevents this.
            raise ValueError("asset URL has no hostname")
        key = (parsed.scheme, host, parsed.port)
        connection = self.connections.get(key)
        if connection is not None:
            return connection
        if parsed.scheme == "https":
            connection = http.client.HTTPSConnection(
                host,
                parsed.port,
                timeout=self.timeout_seconds,
                context=ssl.create_default_context(),
            )
        else:
            connection = http.client.HTTPConnection(
                host,
                parsed.port,
                timeout=self.timeout_seconds,
            )
        self.connections[key] = connection
        return connection

    def _drop_connection(self, asset: AssetSpec) -> None:
        parsed = urlsplit(asset.url)
        host = parsed.hostname
        if host is None:
            return
        connection = self.connections.pop((parsed.scheme, host, parsed.port), None)
        if connection is not None:
            connection.close()

    def close(self) -> None:
        for connection in self.connections.values():
            connection.close()
        self.connections.clear()

    def request(
        self,
        asset: AssetSpec,
        operation: AudioOperation,
        *,
        range_bytes: int,
        origin: str,
        sequence: int,
    ) -> AudioResult:
        parsed = urlsplit(asset.url)
        target = parsed.path or "/"
        method, headers, expected_body_bytes, expected_content_range = _request_spec(
            asset,
            operation,
            range_bytes=range_bytes,
            origin=origin,
            sequence=sequence,
        )

        started = time.perf_counter()
        response_started: float | None = None
        transfer_finished = started
        status: int | None = None
        response_headers: dict[str, str] = {}
        body_bytes = 0
        error: str | None = None
        try:
            connection = self._connection(asset)
            connection.request(method, target, headers=headers)
            response = connection.getresponse()
            response_started = time.perf_counter()
            status = response.status
            response_headers, body_bytes = _read_bounded_response(
                response,
                method=method,
                asset=asset,
                expected_body_bytes=expected_body_bytes,
            )
            transfer_finished = time.perf_counter()
            _validate_response(
                status=status,
                headers=response_headers,
                body_bytes=body_bytes,
                method=method,
                asset=asset,
                expected_body_bytes=expected_body_bytes,
                expected_content_range=expected_content_range,
                origin=origin,
            )
        except (
            OSError,
            TimeoutError,
            ValueError,
            http.client.HTTPException,
            ssl.SSLError,
        ) as exc:
            error = str(exc) if isinstance(exc, ValueError) else type(exc).__name__
            transfer_finished = time.perf_counter()
            self._drop_connection(asset)

        latency_ms = (transfer_finished - started) * 1_000
        effective_response_started = response_started or transfer_finished
        ttfb_ms = (effective_response_started - started) * 1_000
        transfer_ms = max(0.0, (transfer_finished - effective_response_started) * 1_000)
        throughput_kbps = None
        if body_bytes > 0 and transfer_ms > 0:
            throughput_kbps = body_bytes * 8 / transfer_ms
        return AudioResult(
            asset=asset.name,
            operation=operation.name,
            latency_ms=latency_ms,
            ttfb_ms=ttfb_ms,
            transfer_ms=transfer_ms,
            throughput_kbps=throughput_kbps,
            status=status,
            bytes_received=body_bytes,
            cache_outcome=classify_cache_outcome(response_headers),
            successful=error is None,
            error=error,
        )


def _reserved_bytes(asset: AssetSpec, operation: AudioOperation, range_bytes: int) -> int:
    if operation.name == "head":
        return 0
    return min(range_bytes, asset.expected_bytes)


def run_audio_stage(
    *,
    manifest: MediaManifest,
    stage: StageSpec,
    client_factory: Callable[[], AudioClient],
    config: AudioStageConfig,
) -> AudioStageSummary:
    start_event = threading.Event()
    issue_lock = threading.Lock()
    issued = 0
    reserved_transfer_bytes = 0
    byte_cap_reached = False
    deadline = 0.0

    def claim_request(asset: AssetSpec, operation: AudioOperation) -> tuple[bool, int]:
        nonlocal issued, reserved_transfer_bytes, byte_cap_reached
        reservation = _reserved_bytes(asset, operation, config.range_bytes)
        with issue_lock:
            if issued >= config.max_requests:
                return False, issued
            if reserved_transfer_bytes + reservation > config.max_transfer_bytes:
                byte_cap_reached = True
                return False, issued
            sequence = issued
            issued += 1
            reserved_transfer_bytes += reservation
            return True, sequence

    def worker(worker_index: int) -> list[AudioResult]:
        client = client_factory()
        results: list[AudioResult] = []
        operation_index = worker_index % len(config.operations)
        asset_index = worker_index % len(manifest.assets)
        start_event.wait()
        try:
            while time.perf_counter() < deadline:
                operation = config.operations[operation_index]
                asset = manifest.assets[asset_index]
                claimed, sequence = claim_request(asset, operation)
                if not claimed:
                    break
                results.append(
                    client.request(
                        asset,
                        operation,
                        range_bytes=config.range_bytes,
                        origin=config.origin,
                        sequence=sequence,
                    )
                )
                operation_index = (operation_index + 1) % len(config.operations)
                asset_index = (asset_index + 1) % len(manifest.assets)
                if config.think_time_seconds > 0:
                    time.sleep(config.think_time_seconds)
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
    if byte_cap_reached:
        stop_reason = "transfer_byte_cap"
    elif issued >= config.max_requests and elapsed < stage.duration_seconds:
        stop_reason = "request_cap"
    else:
        stop_reason = "duration"
    return AudioStageSummary(
        stage=stage,
        results=tuple(result for group in result_groups for result in group),
        elapsed_seconds=elapsed,
        stop_reason=stop_reason,
        reserved_transfer_bytes=reserved_transfer_bytes,
    )


def warm_assets(
    manifest: MediaManifest,
    *,
    client: AudioClient,
    origin: str,
    range_bytes: int,
) -> tuple[AudioResult, ...]:
    operation = AudioOperation("startup", 1)
    return tuple(
        client.request(
            asset,
            operation,
            range_bytes=range_bytes,
            origin=origin,
            sequence=index,
        )
        for index, asset in enumerate(manifest.assets)
    )


def threshold_failures(
    summary: AudioStageSummary,
    *,
    max_error_rate: float,
    max_p95_ttfb_ms: float,
    min_p50_throughput_kbps: float,
) -> tuple[str, ...]:
    failures: list[str] = []
    if (
        summary.stop_reason != "duration"
        or summary.elapsed_seconds < summary.stage.duration_seconds * 0.95
    ):
        failures.append("stage ended before the requested duration")
    if summary.error_rate > max_error_rate:
        failures.append(f"error rate {summary.error_rate:.2%} exceeds {max_error_rate:.2%}")
    if summary.ttfb_percentile(0.95) > max_p95_ttfb_ms:
        failures.append(
            f"p95 TTFB {summary.ttfb_percentile(0.95):.1f}ms exceeds {max_p95_ttfb_ms:.1f}ms"
        )
    throughputs = [
        result.throughput_kbps
        for result in summary.results
        if result.successful and result.throughput_kbps is not None
    ]
    if min_p50_throughput_kbps > 0:
        if not throughputs:
            failures.append("no successful Range samples for throughput threshold")
        elif percentile(throughputs, 0.50) < min_p50_throughput_kbps:
            failures.append(
                f"p50 throughput {percentile(throughputs, 0.50):.1f}kbps is below "
                f"{min_p50_throughput_kbps:.1f}kbps"
            )
    return tuple(failures)


def stage_payload(summary: AudioStageSummary, failures: Sequence[str]) -> dict[str, object]:
    grouped: dict[str, list[AudioResult]] = defaultdict(list)
    for result in summary.results:
        grouped[f"{result.asset}:{result.operation}"].append(result)
    endpoint_payload: dict[str, object] = {}
    for name, results in sorted(grouped.items()):
        latencies = [result.latency_ms for result in results]
        ttfb = [result.ttfb_ms for result in results]
        throughputs = [
            result.throughput_kbps for result in results if result.throughput_kbps is not None
        ]
        endpoint_payload[name] = {
            "requests": len(results),
            "errors": sum(not result.successful for result in results),
            "errors_by_reason": dict(
                sorted(
                    Counter(
                        result.error or "unspecified_error"
                        for result in results
                        if not result.successful
                    ).items()
                )
            ),
            "statuses": dict(sorted(Counter(str(result.status) for result in results).items())),
            "bytes_received": sum(result.bytes_received for result in results),
            "p95_ms": round(percentile(latencies, 0.95), 2),
            "p95_ttfb_ms": round(percentile(ttfb, 0.95), 2),
            "p50_throughput_kbps": (
                round(percentile(throughputs, 0.50), 2) if throughputs else None
            ),
            "cache_outcomes": dict(
                sorted(Counter(result.cache_outcome for result in results).items())
            ),
        }
    throughputs = [
        result.throughput_kbps for result in summary.results if result.throughput_kbps is not None
    ]
    return {
        "concurrency": summary.stage.concurrency,
        "requested_duration_seconds": summary.stage.duration_seconds,
        "elapsed_seconds": round(summary.elapsed_seconds, 3),
        "stop_reason": summary.stop_reason,
        "requests": len(summary.results),
        "requests_per_second": round(summary.requests_per_second, 2),
        "error_rate": round(summary.error_rate, 6),
        "p95_ms": round(summary.latency_percentile(0.95), 2),
        "p95_ttfb_ms": round(summary.ttfb_percentile(0.95), 2),
        "p50_throughput_kbps": (round(percentile(throughputs, 0.50), 2) if throughputs else None),
        "bytes_received": sum(result.bytes_received for result in summary.results),
        "reserved_transfer_bytes": summary.reserved_transfer_bytes,
        "cache_outcomes": dict(
            sorted(Counter(result.cache_outcome for result in summary.results).items())
        ),
        "errors_by_reason": dict(
            sorted(
                Counter(
                    result.error or "unspecified_error"
                    for result in summary.results
                    if not result.successful
                ).items()
            )
        ),
        "statuses": dict(sorted(Counter(str(result.status) for result in summary.results).items())),
        "passed": not failures,
        "failures": list(failures),
        "samples": endpoint_payload,
    }


def print_stage(payload: Mapping[str, Any]) -> None:
    print(
        "AUDIO STAGE "
        f"concurrency={payload['concurrency']} duration={payload['elapsed_seconds']}s "
        f"requests={payload['requests']} rps={payload['requests_per_second']} "
        f"errors={float(payload['error_rate']):.2%} "
        f"ttfb_p95={payload['p95_ttfb_ms']}ms "
        f"throughput_p50={payload['p50_throughput_kbps']}kbps "
        f"bytes={payload['bytes_received']} stop={payload['stop_reason']}"
    )
    for failure in payload["failures"]:
        print(f"  FAIL: {failure}", file=sys.stderr)


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("value must be positive")
    return parsed


def bounded_concurrency_stage(value: str) -> StageSpec:
    stage = parse_stage(value)
    if stage.concurrency > MAX_CONCURRENCY:
        raise argparse.ArgumentTypeError(f"audio concurrency must be at most {MAX_CONCURRENCY}")
    return stage


def bounded_range_bytes(value: str) -> int:
    parsed = positive_int(value)
    if parsed > MAX_RANGE_BYTES:
        raise argparse.ArgumentTypeError(f"range bytes must be at most {MAX_RANGE_BYTES}")
    return parsed


def bounded_transfer_bytes(value: str) -> int:
    parsed = positive_int(value)
    if parsed > MAX_STAGE_TRANSFER_BYTES:
        raise argparse.ArgumentTypeError(
            f"stage transfer cap must be at most {MAX_STAGE_TRANSFER_BYTES}"
        )
    return parsed


def bounded_request_count(value: str) -> int:
    parsed = positive_int(value)
    if parsed > MAX_REQUESTS_PER_STAGE:
        raise argparse.ArgumentTypeError(
            f"requests per stage must be at most {MAX_REQUESTS_PER_STAGE}"
        )
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
        description=(
            "Run bounded HEAD/Range capacity checks against immutable audio assets. "
            "Use only with an approved staging/CDN load-test window."
        )
    )
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--stage", type=bounded_concurrency_stage, action="append", required=True)
    parser.add_argument("--target-role", choices=("cdn", "origin"), default="cdn")
    parser.add_argument(
        "--cache-mode",
        choices=("uncontrolled", "cold-start", "warm"),
        default="uncontrolled",
    )
    parser.add_argument("--allow-http", action="store_true")
    parser.add_argument("--timeout-seconds", type=positive_int, default=10)
    parser.add_argument("--range-bytes", type=bounded_range_bytes, default=256 * 1024)
    parser.add_argument("--head-weight", type=positive_int, default=1)
    parser.add_argument("--startup-weight", type=positive_int, default=7)
    parser.add_argument("--seek-weight", type=positive_int, default=2)
    parser.add_argument("--think-time-ms", type=non_negative_float, default=0.0)
    parser.add_argument(
        "--max-requests-per-stage",
        type=bounded_request_count,
        default=MAX_REQUESTS_PER_STAGE,
    )
    parser.add_argument(
        "--max-transfer-bytes-per-stage",
        type=bounded_transfer_bytes,
        default=DEFAULT_STAGE_TRANSFER_BYTES,
    )
    parser.add_argument("--max-error-rate", type=unit_interval, default=0.01)
    parser.add_argument("--max-p95-ttfb-ms", type=non_negative_float, default=750.0)
    parser.add_argument("--min-p50-throughput-kbps", type=non_negative_float, default=0.0)
    parser.add_argument("--label", default="unlabelled")
    parser.add_argument("--json-report", type=Path)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        manifest = load_manifest(args.manifest, allow_http=args.allow_http)
        operations = operation_schedule(
            head_weight=args.head_weight,
            startup_weight=args.startup_weight,
            seek_weight=args.seek_weight,
        )
    except (OSError, TypeError, ValueError, json.JSONDecodeError) as exc:
        parser.error(str(exc))
    origin = manifest.origins[0]
    stage_payloads: list[dict[str, object]] = []
    report: dict[str, object] = {
        "schema_version": 1,
        "generated_at": datetime.now(UTC).isoformat(),
        "label": args.label,
        "manifest": {"name": manifest.name, "version": manifest.version},
        "target_role": args.target_role,
        "cache_mode": args.cache_mode,
        "cors_origin": origin,
        "assets": len(manifest.assets),
        "range_bytes": args.range_bytes,
        "operation_weights": {
            "head": args.head_weight,
            "startup": args.startup_weight,
            "seek": args.seek_weight,
        },
        "safety_caps": {
            "max_requests_per_stage": args.max_requests_per_stage,
            "max_transfer_bytes_per_stage": args.max_transfer_bytes_per_stage,
        },
        "thresholds": {
            "max_error_rate": args.max_error_rate,
            "max_p95_ttfb_ms": args.max_p95_ttfb_ms,
            "min_p50_throughput_kbps": args.min_p50_throughput_kbps,
        },
        "warmup": None,
        "stages": stage_payloads,
    }
    all_passed = True
    if args.cache_mode == "warm":
        warmup_client = AudioRangeHttpClient(args.timeout_seconds)
        try:
            warmup_results = warm_assets(
                manifest,
                client=warmup_client,
                origin=origin,
                range_bytes=args.range_bytes,
            )
        finally:
            warmup_client.close()
        warmup_errors = sum(not result.successful for result in warmup_results)
        report["warmup"] = {
            "requests": len(warmup_results),
            "errors": warmup_errors,
            "errors_by_reason": dict(
                sorted(
                    Counter(
                        result.error or "unspecified_error"
                        for result in warmup_results
                        if not result.successful
                    ).items()
                )
            ),
            "bytes_received": sum(result.bytes_received for result in warmup_results),
            "cache_outcomes": dict(
                sorted(Counter(result.cache_outcome for result in warmup_results).items())
            ),
        }
        all_passed = warmup_errors == 0
        if warmup_errors:
            print(
                f"FAIL: audio warmup had {warmup_errors}/{len(warmup_results)} errors.",
                file=sys.stderr,
            )

    for stage in args.stage:
        summary = run_audio_stage(
            manifest=manifest,
            stage=stage,
            client_factory=lambda: AudioRangeHttpClient(args.timeout_seconds),
            config=AudioStageConfig(
                origin=origin,
                range_bytes=args.range_bytes,
                operations=operations,
                think_time_seconds=args.think_time_ms / 1_000,
                max_requests=args.max_requests_per_stage,
                max_transfer_bytes=args.max_transfer_bytes_per_stage,
            ),
        )
        failures = threshold_failures(
            summary,
            max_error_rate=args.max_error_rate,
            max_p95_ttfb_ms=args.max_p95_ttfb_ms,
            min_p50_throughput_kbps=args.min_p50_throughput_kbps,
        )
        payload = stage_payload(summary, failures)
        print_stage(payload)
        stage_payloads.append(payload)
        all_passed = all_passed and not failures
    report["passed"] = all_passed
    if args.json_report:
        args.json_report.parent.mkdir(parents=True, exist_ok=True)
        args.json_report.write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    print(
        "PASS: all audio capacity stages satisfied."
        if all_passed
        else "FAIL: audio capacity thresholds exceeded."
    )
    return 0 if all_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
