from __future__ import annotations

import argparse
import unittest
from unittest.mock import patch

from ops.load.smoke import RequestResult, percentile, run_smoke, validate_base_url


class LoadSmokeTests(unittest.TestCase):
    def test_percentile_uses_nearest_rank(self) -> None:
        self.assertEqual(percentile([40, 10, 30, 20], 0.50), 20)
        self.assertEqual(percentile([40, 10, 30, 20], 0.95), 40)

    def test_bounded_smoke_succeeds_against_healthy_server(self) -> None:
        with patch(
            "ops.load.smoke.request_once",
            side_effect=lambda _base, endpoint, _timeout: RequestResult(
                endpoint=endpoint,
                latency_ms=10,
                status=200,
                error=None,
            ),
        ) as request_once:
            summary = run_smoke(
                base_url="http://127.0.0.1:8000",
                endpoints=("/health",),
                request_count=12,
                concurrency=4,
                timeout_seconds=1,
                warmup_rounds=1,
            )

        self.assertEqual(len(summary.results), 12)
        self.assertEqual(summary.error_rate, 0)
        self.assertEqual(request_once.call_count, 13)

    def test_base_url_rejects_credentials(self) -> None:
        with self.assertRaises(argparse.ArgumentTypeError):
            validate_base_url("https://user:secret@example.test")


if __name__ == "__main__":
    unittest.main()
