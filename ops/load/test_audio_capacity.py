from __future__ import annotations

import argparse
import unittest

from ops.load.audio_capacity import (
    AudioOperation,
    AudioRangeHttpClient,
    AudioResult,
    AudioStageConfig,
    AudioStageSummary,
    _validate_response,
    bounded_concurrency_stage,
    bounded_request_count,
    classify_cache_outcome,
    operation_schedule,
    requested_range,
    run_audio_stage,
    stage_payload,
    threshold_failures,
)
from ops.load.capacity import StageSpec
from ops.media.contract import AssetSpec, MediaManifest


class FakeAudioClient:
    def request(
        self,
        asset: AssetSpec,
        operation: AudioOperation,
        *,
        range_bytes: int,
        origin: str,
        sequence: int,
    ) -> AudioResult:
        del origin, sequence
        body_bytes = 0 if operation.name == "head" else min(range_bytes, asset.expected_bytes)
        return AudioResult(
            asset=asset.name,
            operation=operation.name,
            latency_ms=10.0,
            ttfb_ms=5.0,
            transfer_ms=5.0,
            throughput_kbps=(body_bytes * 8 / 5 if body_bytes else None),
            status=200 if operation.name == "head" else 206,
            bytes_received=body_bytes,
            cache_outcome="hit",
            successful=True,
            error=None,
        )

    def close(self) -> None:
        return None


class FakeHttpResponse:
    status = 206

    def __init__(self) -> None:
        self.body = b"a" * 1_000

    def getheaders(self) -> list[tuple[str, str]]:
        return [
            ("Accept-Ranges", "bytes"),
            ("Access-Control-Allow-Origin", "https://www.example.test"),
            ("CF-Cache-Status", "HIT"),
            ("Content-Length", "1000"),
            ("Content-Range", "bytes 0-999/10000"),
            ("Content-Type", "audio/mpeg"),
            ("ETag", '"asset-v1"'),
        ]

    def read(self, amount: int | None = None) -> bytes:
        if not self.body:
            return b""
        size = len(self.body) if amount is None else amount
        chunk, self.body = self.body[:size], self.body[size:]
        return chunk


class FakeHttpConnection:
    def __init__(self) -> None:
        self.request_args: tuple[str, str, dict[str, str]] | None = None
        self.closed = False

    def request(self, method: str, target: str, *, headers: dict[str, str]) -> None:
        self.request_args = (method, target, headers)

    def getresponse(self) -> FakeHttpResponse:
        return FakeHttpResponse()

    def close(self) -> None:
        self.closed = True


class AudioCapacityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.asset = AssetSpec(
            name="surah-001-standard",
            url="https://media.example.test/audio/surah-001.mp3",
            expected_bytes=10_000,
            content_type="audio/mpeg",
            expected_etag='"asset-v1"',
        )
        self.manifest = MediaManifest(
            name="release-v1",
            version=1,
            origins=("https://www.example.test",),
            assets=(self.asset,),
        )

    def test_operation_schedule_preserves_weights(self) -> None:
        schedule = operation_schedule(head_weight=1, startup_weight=7, seek_weight=2)

        self.assertEqual(len(schedule), 10)
        self.assertEqual(sum(item.name == "head" for item in schedule), 1)
        self.assertEqual(sum(item.name == "startup" for item in schedule), 7)
        self.assertEqual(sum(item.name == "seek" for item in schedule), 2)

    def test_seek_range_is_bounded_and_not_the_start_chunk(self) -> None:
        self.assertEqual(requested_range(self.asset, "startup", 1_000, 1), (0, 999))
        start, end = requested_range(self.asset, "seek", 1_000, 1)

        self.assertGreater(start, 0)
        self.assertEqual(end - start + 1, 1_000)
        self.assertLess(end, self.asset.expected_bytes)

    def test_cache_outcome_is_provider_neutral_and_bounded(self) -> None:
        self.assertEqual(classify_cache_outcome({"cf-cache-status": "HIT"}), "hit")
        self.assertEqual(classify_cache_outcome({"x-cache": "MISS from edge"}), "miss")
        self.assertEqual(classify_cache_outcome({"cdn-cache-status": "bypass"}), "bypass")
        self.assertEqual(classify_cache_outcome({"age": "42"}), "hit")
        self.assertEqual(classify_cache_outcome({"server": "example"}), "unknown")

    def test_http_client_sends_bounded_identity_range_and_validates_response(self) -> None:
        connection = FakeHttpConnection()
        client = AudioRangeHttpClient(timeout_seconds=1)
        client.connections[("https", "media.example.test", None)] = connection

        result = client.request(
            self.asset,
            AudioOperation("startup", 1),
            range_bytes=1_000,
            origin=self.manifest.origins[0],
            sequence=0,
        )

        self.assertTrue(result.successful, result.error)
        self.assertEqual(result.bytes_received, 1_000)
        self.assertEqual(result.cache_outcome, "hit")
        self.assertIsNotNone(connection.request_args)
        assert connection.request_args is not None
        method, target, headers = connection.request_args
        self.assertEqual((method, target), ("GET", "/audio/surah-001.mp3"))
        self.assertEqual(headers["Range"], "bytes=0-999")
        self.assertEqual(headers["Accept-Encoding"], "identity")

    def test_valid_206_does_not_require_repeated_accept_ranges_header(self) -> None:
        _validate_response(
            status=206,
            headers={
                "access-control-allow-origin": self.manifest.origins[0],
                "content-range": "bytes 0-999/10000",
                "content-type": "audio/mpeg",
                "etag": '"asset-v1"',
            },
            body_bytes=1_000,
            method="GET",
            asset=self.asset,
            expected_body_bytes=1_000,
            expected_content_range="bytes 0-999/10000",
            origin=self.manifest.origins[0],
        )

    def test_head_still_requires_accept_ranges_advertisement(self) -> None:
        with self.assertRaisesRegex(ValueError, "missing_accept_ranges"):
            _validate_response(
                status=200,
                headers={
                    "access-control-allow-origin": self.manifest.origins[0],
                    "content-type": "audio/mpeg",
                    "etag": '"asset-v1"',
                },
                body_bytes=0,
                method="HEAD",
                asset=self.asset,
                expected_body_bytes=0,
                expected_content_range=None,
                origin=self.manifest.origins[0],
            )

    def test_audio_stage_stops_at_transfer_byte_cap(self) -> None:
        summary = run_audio_stage(
            manifest=self.manifest,
            stage=StageSpec(concurrency=2, duration_seconds=10),
            client_factory=FakeAudioClient,
            config=AudioStageConfig(
                origin=self.manifest.origins[0],
                range_bytes=1_000,
                operations=(AudioOperation("startup", 1),),
                think_time_seconds=0,
                max_requests=100,
                max_transfer_bytes=3_000,
            ),
        )

        self.assertEqual(len(summary.results), 3)
        self.assertEqual(summary.reserved_transfer_bytes, 3_000)
        self.assertEqual(summary.stop_reason, "transfer_byte_cap")

    def test_thresholds_and_payload_cover_qoe_and_cache(self) -> None:
        result = AudioResult(
            asset=self.asset.name,
            operation="startup",
            latency_ms=900.0,
            ttfb_ms=850.0,
            transfer_ms=50.0,
            throughput_kbps=100.0,
            status=206,
            bytes_received=1_000,
            cache_outcome="miss",
            successful=True,
            error=None,
        )
        summary = AudioStageSummary(
            stage=StageSpec(concurrency=1, duration_seconds=60),
            results=(result,),
            elapsed_seconds=5,
            stop_reason="request_cap",
            reserved_transfer_bytes=1_000,
        )

        failures = threshold_failures(
            summary,
            max_error_rate=0.01,
            max_p95_ttfb_ms=750,
            min_p50_throughput_kbps=200,
        )
        payload = stage_payload(summary, failures)

        self.assertTrue(any("duration" in failure for failure in failures))
        self.assertTrue(any("TTFB" in failure for failure in failures))
        self.assertTrue(any("throughput" in failure for failure in failures))
        self.assertEqual(payload["cache_outcomes"], {"miss": 1})
        self.assertEqual(payload["statuses"], {"206": 1})
        self.assertEqual(payload["errors_by_reason"], {})
        self.assertFalse(payload["passed"])

    def test_audio_concurrency_has_stricter_safety_bound(self) -> None:
        self.assertEqual(bounded_concurrency_stage("200:1"), StageSpec(200, 1.0))
        with self.assertRaises(argparse.ArgumentTypeError):
            bounded_concurrency_stage("201:1")
        self.assertEqual(bounded_request_count("100000"), 100_000)
        with self.assertRaises(argparse.ArgumentTypeError):
            bounded_request_count("100001")

    def test_operation_weight_sum_is_bounded(self) -> None:
        with self.assertRaisesRegex(ValueError, "weights"):
            operation_schedule(head_weight=10_000, startup_weight=1, seek_weight=1)


if __name__ == "__main__":
    unittest.main()
