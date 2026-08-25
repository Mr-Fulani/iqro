#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import threading
import time
from collections.abc import Callable, Mapping, Sequence
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from urllib.parse import SplitResult, urlsplit

if __package__:
    from ops.load.capacity import (
        DEFAULT_WORKLOAD,
        ReadOnlyHttpClient,
        StageSpec,
        StageSummary,
        Workload,
        load_workload,
        run_stage,
    )
    from ops.load.capacity import (
        stage_payload as read_stage_payload,
    )
    from ops.load.capacity import (
        threshold_failures as read_threshold_failures,
    )
    from ops.load.smoke import validate_base_url
    from ops.load.sync_capacity import (
        MAX_CYCLES_PER_USER,
        MAX_SYNC_OPERATIONS_PER_STAGE,
        StatefulHttpClient,
        SyncRunConfig,
        SyncStageSummary,
        run_sync_stage,
        validate_stateful_authorization,
    )
    from ops.load.sync_capacity import (
        stage_payload as sync_stage_payload,
    )
    from ops.load.sync_capacity import (
        threshold_failures as sync_threshold_failures,
    )
else:  # Allow the documented `python3 ops/load/mixed_capacity.py ...` invocation.
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from ops.load.capacity import (
        DEFAULT_WORKLOAD,
        ReadOnlyHttpClient,
        StageSpec,
        StageSummary,
        Workload,
        load_workload,
        run_stage,
    )
    from ops.load.capacity import (
        stage_payload as read_stage_payload,
    )
    from ops.load.capacity import (
        threshold_failures as read_threshold_failures,
    )
    from ops.load.smoke import validate_base_url
    from ops.load.sync_capacity import (
        MAX_CYCLES_PER_USER,
        MAX_SYNC_OPERATIONS_PER_STAGE,
        StatefulHttpClient,
        SyncRunConfig,
        SyncStageSummary,
        run_sync_stage,
        validate_stateful_authorization,
    )
    from ops.load.sync_capacity import (
        stage_payload as sync_stage_payload,
    )
    from ops.load.sync_capacity import (
        threshold_failures as sync_threshold_failures,
    )


MAX_READ_CONCURRENCY = 200
MAX_SYNC_CONCURRENCY = 50
MAX_STAGE_SECONDS = 900.0


@dataclass(frozen=True, slots=True)
class MixedStageSpec:
    read_concurrency: int
    sync_concurrency: int
    duration_seconds: float


@dataclass(frozen=True, slots=True)
class MixedRunConfig:
    base_url: str
    timeout_seconds: float
    max_response_bytes: int
    read_think_time_seconds: float
    max_read_requests: int
    sync: SyncRunConfig
    max_error_rate: float
    max_p95_ms: float
    max_p99_ms: float


@dataclass(frozen=True, slots=True)
class MixedStageSummary:
    stage: MixedStageSpec
    read: StageSummary
    sync: SyncStageSummary
    elapsed_seconds: float


def parse_mixed_stage(value: str) -> MixedStageSpec:
    try:
        read_raw, sync_raw, duration_raw = value.split(":", 2)
        read_concurrency = int(read_raw)
        sync_concurrency = int(sync_raw)
        duration_seconds = float(duration_raw)
    except (TypeError, ValueError) as exc:
        raise argparse.ArgumentTypeError(
            "stage must use READ_CONCURRENCY:SYNC_CONCURRENCY:SECONDS"
        ) from exc
    if not 1 <= read_concurrency <= MAX_READ_CONCURRENCY:
        raise argparse.ArgumentTypeError(
            f"read concurrency must be between 1 and {MAX_READ_CONCURRENCY}"
        )
    if not 1 <= sync_concurrency <= MAX_SYNC_CONCURRENCY:
        raise argparse.ArgumentTypeError(
            f"sync concurrency must be between 1 and {MAX_SYNC_CONCURRENCY}"
        )
    if not 0 < duration_seconds <= MAX_STAGE_SECONDS:
        raise argparse.ArgumentTypeError(
            f"stage duration must be above 0 and at most {MAX_STAGE_SECONDS:g} seconds"
        )
    return MixedStageSpec(read_concurrency, sync_concurrency, duration_seconds)


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("value must be positive")
    return parsed


def bounded_positive_int(maximum: int, field: str) -> Callable[[str], int]:
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


def run_mixed_stage(
    *,
    stage: MixedStageSpec,
    workload: Workload,
    config: MixedRunConfig,
) -> MixedStageSummary:
    start_event = threading.Event()

    def read_worker() -> StageSummary:
        start_event.wait()
        return run_stage(
            workload=workload,
            stage=StageSpec(stage.read_concurrency, stage.duration_seconds),
            client_factory=lambda: ReadOnlyHttpClient(
                base_url=config.base_url,
                timeout_seconds=config.timeout_seconds,
                max_response_bytes=config.max_response_bytes,
            ),
            think_time_seconds=config.read_think_time_seconds,
            max_requests=config.max_read_requests,
        )

    def sync_worker() -> SyncStageSummary:
        start_event.wait()
        return run_sync_stage(
            stage=StageSpec(stage.sync_concurrency, stage.duration_seconds),
            client_factory=lambda: StatefulHttpClient(
                base_url=config.base_url,
                timeout_seconds=config.timeout_seconds,
            ),
            config=config.sync,
        )

    with ThreadPoolExecutor(max_workers=2) as executor:
        read_future = executor.submit(read_worker)
        sync_future = executor.submit(sync_worker)
        started = time.perf_counter()
        start_event.set()
        read_summary = read_future.result()
        sync_summary = sync_future.result()
    return MixedStageSummary(
        stage=stage,
        read=read_summary,
        sync=sync_summary,
        elapsed_seconds=time.perf_counter() - started,
    )


def mixed_stage_payload(
    summary: MixedStageSummary,
    *,
    max_error_rate: float,
    max_p95_ms: float,
    max_p99_ms: float,
) -> dict[str, object]:
    read_failures = read_threshold_failures(
        summary.read,
        max_error_rate=max_error_rate,
        max_p95_ms=max_p95_ms,
        max_p99_ms=max_p99_ms,
    )
    sync_failures = sync_threshold_failures(
        summary.sync,
        max_error_rate=max_error_rate,
        max_p95_ms=max_p95_ms,
        max_p99_ms=max_p99_ms,
    )
    read_payload = read_stage_payload(summary.read, read_failures)
    sync_payload = sync_stage_payload(summary.sync, sync_failures)
    combined_requests = len(summary.read.results) + len(summary.sync.results)
    return {
        "read_concurrency": summary.stage.read_concurrency,
        "sync_concurrency": summary.stage.sync_concurrency,
        "requested_duration_seconds": summary.stage.duration_seconds,
        "elapsed_seconds": round(summary.elapsed_seconds, 3),
        "combined_requests": combined_requests,
        "combined_requests_per_second": round(
            combined_requests / summary.elapsed_seconds
            if summary.elapsed_seconds > 0
            else 0.0,
            2,
        ),
        "passed": not read_failures and not sync_failures,
        "failures": [
            *(f"read: {failure}" for failure in read_failures),
            *(f"sync: {failure}" for failure in sync_failures),
        ],
        "read": read_payload,
        "sync": sync_payload,
    }


def print_mixed_stage(payload: Mapping[str, Any]) -> None:
    read = payload["read"]
    sync = payload["sync"]
    print(
        "MIXED STAGE "
        f"read={payload['read_concurrency']} sync={payload['sync_concurrency']} "
        f"duration={payload['elapsed_seconds']}s combined_rps="
        f"{payload['combined_requests_per_second']} passed={payload['passed']}"
    )
    print(
        f"  read: requests={read['requests']} errors={float(read['error_rate']):.2%} "
        f"p95={read['p95_ms']}ms p99={read['p99_ms']}ms"
    )
    print(
        f"  sync: requests={sync['requests']} errors={float(sync['error_rate']):.2%} "
        f"p95={sync['p95_ms']}ms p99={sync['p99_ms']}ms "
        f"users={sync['users_bootstrapped']}"
    )
    for failure in payload["failures"]:
        print(f"  FAIL: {failure}", file=sys.stderr)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Run public reads and disposable guest auth/reading sync concurrently. "
            "The stateful side creates persistent rows and is only for disposable staging."
        )
    )
    parser.add_argument("--base-url", type=validate_base_url, required=True)
    parser.add_argument("--confirm-target-host", required=True)
    parser.add_argument("--allow-stateful-writes", action="store_true")
    parser.add_argument("--confirm-disposable-staging-data", action="store_true")
    parser.add_argument("--workload", type=Path, default=DEFAULT_WORKLOAD)
    parser.add_argument(
        "--stage", type=parse_mixed_stage, action="append", required=True
    )
    parser.add_argument("--label", required=True)
    parser.add_argument("--json-report", type=Path, required=True)
    parser.add_argument("--edition", default="madani-hafs")
    parser.add_argument("--timeout-seconds", type=positive_int, default=5)
    parser.add_argument(
        "--read-think-time-ms", type=non_negative_float, default=5_000.0
    )
    parser.add_argument(
        "--sync-think-time-ms", type=non_negative_float, default=15_000.0
    )
    parser.add_argument(
        "--max-read-requests-per-stage", type=positive_int, default=20_000
    )
    parser.add_argument("--max-response-bytes", type=positive_int, default=5_000_000)
    parser.add_argument(
        "--max-cycles-per-user",
        type=bounded_positive_int(MAX_CYCLES_PER_USER, "cycles per user"),
        default=100,
    )
    parser.add_argument(
        "--refresh-every-cycles",
        type=bounded_positive_int(MAX_CYCLES_PER_USER, "refresh interval"),
        default=5,
    )
    parser.add_argument(
        "--max-sync-operations-per-stage",
        type=bounded_positive_int(
            MAX_SYNC_OPERATIONS_PER_STAGE, "sync operations per stage"
        ),
        default=2_000,
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
        workload = load_workload(args.workload)
    except (OSError, TypeError, ValueError, json.JSONDecodeError) as exc:
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
        "journey": "mixed-public-read-guest-auth-reading-sync",
        "workload": {"name": workload.name, "version": workload.version},
        "read_think_time_ms": args.read_think_time_ms,
        "sync_think_time_ms": args.sync_think_time_ms,
        "refresh_every_cycles": args.refresh_every_cycles,
        "thresholds": {
            "max_error_rate": args.max_error_rate,
            "max_p95_ms": args.max_p95_ms,
            "max_p99_ms": args.max_p99_ms,
        },
        "persistent_test_data": {
            "guest_users_created_at_most": sum(
                stage.sync_concurrency for stage in args.stage
            ),
            "device_app_version_marker": f"load.{run_tag}",
        },
        "stages": stage_payloads,
    }
    all_passed = True
    for stage in args.stage:
        summary = run_mixed_stage(
            stage=stage,
            workload=workload,
            config=MixedRunConfig(
                base_url=args.base_url,
                timeout_seconds=args.timeout_seconds,
                max_response_bytes=args.max_response_bytes,
                read_think_time_seconds=args.read_think_time_ms / 1_000,
                max_read_requests=args.max_read_requests_per_stage,
                sync=SyncRunConfig(
                    run_tag=run_tag,
                    edition=args.edition,
                    operations_per_push=1,
                    max_cycles_per_user=args.max_cycles_per_user,
                    refresh_every_cycles=args.refresh_every_cycles,
                    think_time_seconds=args.sync_think_time_ms / 1_000,
                    max_sync_operations=args.max_sync_operations_per_stage,
                ),
                max_error_rate=args.max_error_rate,
                max_p95_ms=args.max_p95_ms,
                max_p99_ms=args.max_p99_ms,
            ),
        )
        payload = mixed_stage_payload(
            summary,
            max_error_rate=args.max_error_rate,
            max_p95_ms=args.max_p95_ms,
            max_p99_ms=args.max_p99_ms,
        )
        print_mixed_stage(payload)
        stage_payloads.append(payload)
        all_passed = all_passed and bool(payload["passed"])
    report["passed"] = all_passed
    args.json_report.parent.mkdir(parents=True, exist_ok=True)
    args.json_report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        "PASS: all mixed capacity stages satisfied."
        if all_passed
        else "FAIL: mixed capacity thresholds exceeded."
    )
    return 0 if all_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
