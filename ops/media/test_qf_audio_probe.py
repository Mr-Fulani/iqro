from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest

from ops.media.qf_audio_probe import (
    AssetProbeSummary,
    ProbeObservation,
    RealAudioAsset,
    collect_assets,
    load_qf_credentials,
    report_payload,
    run_probe,
    validate_audio_url,
)


class FakeQuranFoundationClient:
    def list_chapter_reciters(self, *, language: str = "en") -> list[dict[str, Any]]:
        assert language == "en"
        return [
            {
                "id": 7,
                "translated_name": {"name": "Test Reciter"},
                "style": {"name": "Murattal"},
                "qirat": {"name": "Hafs"},
            }
        ]

    def get_chapter_audio(
        self,
        reciter_id: int,
        chapter_number: int,
    ) -> dict[str, Any]:
        assert reciter_id == 7
        assert chapter_number == 1
        return {
            "chapter_id": 1,
            "audio_url": "https://audio.qurancdn.com/test/001.mp3",
            "file_size": 1_000_000,
            "timestamps": [
                {"verse_key": "1:1", "timestamp_from": 0, "timestamp_to": 5_000},
                {"verse_key": "1:2", "timestamp_from": 5_000, "timestamp_to": 11_000},
            ],
        }

    def get_external_audio_size(self, url: str) -> int:
        raise AssertionError(f"unexpected size request for {url}")


class FakeTransport:
    def request(
        self,
        url: str,
        *,
        operation: str,
        range_start: int | None,
        range_end: int | None,
        expected_total_bytes: int,
        origin: str,
    ) -> ProbeObservation:
        assert url.startswith("https://audio.qurancdn.com/")
        assert origin == "https://staging.iqro.forum"
        body_bytes = 0 if operation == "head" else int(range_end) - int(range_start) + 1
        return ProbeObservation(
            operation=operation,
            successful=True,
            status=200 if operation == "head" else 206,
            final_host="audio.qurancdn.com",
            ttfb_ms=100,
            elapsed_ms=120,
            bytes_received=body_bytes,
            throughput_kbps=2_000 if body_bytes else None,
            content_type="audio/mpeg",
            content_length=expected_total_bytes if operation == "head" else body_bytes,
            content_range=None,
            observed_total_bytes=expected_total_bytes,
            accept_ranges="bytes",
            cors_origin="*",
            error=None,
        )


def test_collects_only_selected_real_audio_metadata() -> None:
    assets = collect_assets(
        FakeQuranFoundationClient(),
        reciter_ids=[7],
        surah_numbers=[1],
    )

    assert len(assets) == 1
    assert assets[0].label == "qf-7-surah-001"
    assert assets[0].duration_ms == 11_000
    assert assets[0].expected_bytes == 1_000_000


def test_probe_is_bounded_and_report_omits_raw_urls() -> None:
    assets = collect_assets(
        FakeQuranFoundationClient(),
        reciter_ids=[7],
        surah_numbers=[1],
    )
    summaries = run_probe(
        assets,
        transport=FakeTransport(),
        origin="https://staging.iqro.forum",
        range_bytes=64 * 1024,
        max_ttfb_ms=1_500,
        min_throughput_kbps=512,
    )
    report = report_payload(
        summaries,
        environment="production",
        origin="https://staging.iqro.forum",
        range_bytes=64 * 1024,
        max_ttfb_ms=1_500,
        min_throughput_kbps=512,
    )

    assert summaries[0].passed is True
    assert report["passed"] is True
    assert report["summary"] == {
        "assets": 1,
        "delivery_passed_assets": 1,
        "metadata_consistent_assets": 1,
        "requests": 3,
        "errors": 0,
        "range_p95_ttfb_ms": 100,
        "range_p50_throughput_kbps": 2_000,
    }
    serialized = json.dumps(report)
    assert "https://audio.qurancdn.com/test/001.mp3" not in serialized
    assert "client_secret" not in serialized


def test_failed_range_is_preserved_without_sensitive_details() -> None:
    asset = RealAudioAsset(
        7, "Test", "Murattal", 1, "https://audio.qurancdn.com/a.mp3", 1000, 5000
    )
    failed = ProbeObservation(
        "startup",
        False,
        500,
        "audio.qurancdn.com",
        100,
        110,
        0,
        None,
        "text/html",
        0,
        None,
        None,
        None,
        None,
        "unexpected_status_500",
    )
    summary = AssetProbeSummary(
        asset,
        (failed,),
        False,
        False,
        False,
        ("startup: unexpected_status_500",),
    )
    report = report_payload(
        (summary,),
        environment="production",
        origin="https://staging.iqro.forum",
        range_bytes=64,
        max_ttfb_ms=1500,
        min_throughput_kbps=512,
    )

    assert report["passed"] is False
    assert report["summary"]["errors"] == 1


def test_credentials_loader_reads_only_required_values(tmp_path: Path) -> None:
    env_file = tmp_path / "qf.env"
    env_file.write_text(
        "QF_CLIENT_ID=client\nQF_CLIENT_SECRET='secret=value'\nQF_ENV=production\nOTHER=ignored\n",
        encoding="utf-8",
    )

    assert load_qf_credentials(env_file) == ("client", "secret=value", "production")


@pytest.mark.parametrize(
    "url",
    [
        "http://audio.qurancdn.com/a.mp3",
        "https://example.com/a.mp3",
        "https://user:pass@audio.qurancdn.com/a.mp3",
    ],
)
def test_audio_url_is_restricted_to_official_https_hosts(url: str) -> None:
    with pytest.raises(ValueError, match="unapproved"):
        validate_audio_url(url)
