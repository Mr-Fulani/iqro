from __future__ import annotations

import argparse
import contextlib
import io
import unittest

from ops.scaling.validate import MAX_SINGLE_HOST_REPLICAS, main, parse_replica_count


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
            with self.subTest(value=value), self.assertRaises(argparse.ArgumentTypeError):
                parse_replica_count(value)


if __name__ == "__main__":
    unittest.main()
