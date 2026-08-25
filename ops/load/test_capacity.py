from __future__ import annotations

import argparse
import json
import tempfile
import unittest
from pathlib import Path

from ops.load.capacity import (
    CapacityResult,
    EndpointSpec,
    StageSpec,
    StageSummary,
    Workload,
    load_workload,
    parse_stage,
    run_stage,
    threshold_failures,
    weighted_schedule,
)


class FakeClient:
    def request(self, endpoint: EndpointSpec) -> CapacityResult:
        return CapacityResult(endpoint.name, 10.0, 200, 100, True, None)

    def close(self) -> None:
        return None


class CapacityHarnessTests(unittest.TestCase):
    def test_repository_workload_is_valid_and_weighted(self) -> None:
        workload = load_workload(
            Path(__file__).with_name("workloads") / "web-public-read.json"
        )
        schedule = weighted_schedule(workload)

        self.assertEqual(workload.name, "web-public-read")
        self.assertEqual(len(schedule), 100)
        self.assertEqual(
            sum(endpoint.name == "quran-editions-api" for endpoint in schedule), 20
        )

    def test_prepublication_staging_workload_is_valid_and_omits_content_routes(self) -> None:
        workload = load_workload(
            Path(__file__).with_name("workloads")
            / "web-staging-prepublication-read.json"
        )
        schedule = weighted_schedule(workload)

        self.assertEqual(workload.name, "web-staging-prepublication-read")
        self.assertEqual(len(schedule), 100)
        self.assertNotIn("published-surah", {endpoint.name for endpoint in schedule})

    def test_workload_rejects_credential_headers(self) -> None:
        raw = {
            "name": "unsafe",
            "version": 1,
            "endpoints": [
                {
                    "name": "private",
                    "path": "/api/private",
                    "weight": 1,
                    "headers": {"Authorization": "Bearer secret"},
                }
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "workload.json"
            path.write_text(json.dumps(raw), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "disallowed"):
                load_workload(path)

    def test_stage_parser_applies_safety_bounds(self) -> None:
        self.assertEqual(parse_stage("25:60"), StageSpec(25, 60.0))
        for value in ("0:60", "501:60", "10:0", "10:3601", "broken"):
            with (
                self.subTest(value=value),
                self.assertRaises(argparse.ArgumentTypeError),
            ):
                parse_stage(value)

    def test_stage_is_bounded_by_request_cap(self) -> None:
        workload = Workload(
            name="test",
            version=1,
            endpoints=(EndpointSpec("health", "/health", 1, (200,), {}),),
        )
        summary = run_stage(
            workload=workload,
            stage=StageSpec(concurrency=4, duration_seconds=10),
            client_factory=FakeClient,
            think_time_seconds=0,
            max_requests=12,
        )

        self.assertEqual(len(summary.results), 12)
        self.assertEqual(summary.error_rate, 0)
        self.assertEqual(summary.stop_reason, "request_cap")

    def test_thresholds_include_duration_errors_and_latency(self) -> None:
        results = tuple(
            CapacityResult("health", 900.0, 200, 100, True, None) for _ in range(100)
        )
        summary = StageSummary(
            stage=StageSpec(10, 60),
            results=results,
            elapsed_seconds=5,
            stop_reason="request_cap",
        )

        failures = threshold_failures(
            summary,
            max_error_rate=0.01,
            max_p95_ms=750,
            max_p99_ms=800,
        )

        self.assertTrue(any("duration" in failure for failure in failures))
        self.assertTrue(any("p95" in failure for failure in failures))
        self.assertTrue(any("p99" in failure for failure in failures))


if __name__ == "__main__":
    unittest.main()
