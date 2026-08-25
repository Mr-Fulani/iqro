from __future__ import annotations

import argparse
import unittest

from ops.load.capacity import CapacityResult, StageSpec, StageSummary
from ops.load.mixed_capacity import (
    MixedStageSpec,
    MixedStageSummary,
    mixed_stage_payload,
    parse_mixed_stage,
)
from ops.load.sync_capacity import JourneyResult, SyncStageSummary


class MixedCapacityTests(unittest.TestCase):
    def test_stage_parser_accepts_bounded_mixed_stage(self) -> None:
        self.assertEqual(parse_mixed_stage("20:4:120"), MixedStageSpec(20, 4, 120.0))

    def test_stage_parser_rejects_unbounded_or_incomplete_values(self) -> None:
        for value in ("0:1:60", "1:0:60", "201:1:60", "1:51:60", "1:1:0", "1:1"):
            with (
                self.subTest(value=value),
                self.assertRaises(argparse.ArgumentTypeError),
            ):
                parse_mixed_stage(value)

    def test_payload_requires_both_read_and_sync_to_pass(self) -> None:
        read_summary = StageSummary(
            stage=StageSpec(2, 60),
            results=(CapacityResult("quran", 100.0, 200, 10, True, None),),
            elapsed_seconds=60,
            stop_reason="duration",
        )
        sync_summary = SyncStageSummary(
            stage=StageSpec(1, 60),
            results=(JourneyResult("sync-push", 900.0, 200, 10, True, None),),
            elapsed_seconds=60,
            stop_reason="duration",
            users_bootstrapped=1,
            cycles_completed=1,
            sync_operations_completed=1,
            refreshes_completed=0,
        )

        payload = mixed_stage_payload(
            MixedStageSummary(MixedStageSpec(2, 1, 60), read_summary, sync_summary, 60),
            max_error_rate=0.01,
            max_p95_ms=750,
            max_p99_ms=1_500,
        )

        self.assertFalse(payload["passed"])
        self.assertIn("sync: p95 900.0ms exceeds 750.0ms", payload["failures"])
        self.assertEqual(payload["combined_requests"], 2)


if __name__ == "__main__":
    unittest.main()
