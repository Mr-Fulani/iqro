from __future__ import annotations

import argparse
import contextlib
import io
import unittest
from pathlib import Path

from ops.scaling.validate import (
    MAX_SINGLE_HOST_REPLICAS,
    main,
    parse_replica_count,
    validate_replica_plan,
)

ROOT = Path(__file__).resolve().parents[2]


class ScalingValidationTests(unittest.TestCase):
    def test_accepts_positive_bounded_replica_counts(self) -> None:
        self.assertEqual(parse_replica_count("1"), 1)
        self.assertEqual(
            parse_replica_count(str(MAX_SINGLE_HOST_REPLICAS)),
            MAX_SINGLE_HOST_REPLICAS,
        )
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main(["--api-replicas", "2", "--web-replicas", "3"]), 0)

    def test_rejects_zero_negative_non_integer_and_excessive_counts(self) -> None:
        for value in ("0", "-1", "many", str(MAX_SINGLE_HOST_REPLICAS + 1)):
            with (
                self.subTest(value=value),
                self.assertRaises(argparse.ArgumentTypeError),
            ):
                parse_replica_count(value)

    def test_profile_limit_rejects_replica_plan_before_compose(self) -> None:
        validate_replica_plan(
            api_replicas=2,
            web_replicas=2,
            max_api_replicas=2,
            max_web_replicas=2,
        )
        with self.assertRaises(argparse.ArgumentTypeError):
            validate_replica_plan(
                api_replicas=3,
                web_replicas=2,
                max_api_replicas=2,
                max_web_replicas=2,
            )
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            main(
                [
                    "--api-replicas",
                    "2",
                    "--web-replicas",
                    "3",
                    "--max-api-replicas",
                    "2",
                    "--max-web-replicas",
                    "2",
                ]
            )

    def test_budget_staging_scale_uses_preflight_and_existing_images(self) -> None:
        makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
        budget_overlay = (ROOT / "compose.staging.budget.yaml").read_text(
            encoding="utf-8"
        )

        scale_target = makefile.split("staging-budget-scale:", maxsplit=1)[1].split(
            "staging-budget-down:", maxsplit=1
        )[0]
        self.assertIn("staging-budget-scale-preflight", scale_target)
        self.assertIn("--max-api-replicas 2", makefile)
        self.assertIn("--max-web-replicas 2", makefile)
        self.assertIn("DATABASE_API_REPLICAS=$(API_REPLICAS)", scale_target)
        self.assertIn("--no-build", scale_target)
        self.assertIn("--scale backend=$(API_REPLICAS)", scale_target)
        self.assertIn("--scale web=$(WEB_REPLICAS)", scale_target)
        self.assertIn(
            'DATABASE_API_REPLICAS: "${DATABASE_API_REPLICAS:-1}"',
            budget_overlay,
        )


if __name__ == "__main__":
    unittest.main()
