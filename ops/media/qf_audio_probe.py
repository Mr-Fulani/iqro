#!/usr/bin/env python3
from __future__ import annotations

import argparse
import http.client
import json
import re
import ssl
import sys
import time
from collections.abc import Mapping, Sequence
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Protocol
from urllib.parse import urljoin, urlsplit

MAX_RECITERS = 5
MAX_SURAHS = 3
MAX_ASSETS = MAX_RECITERS * MAX_SURAHS
MAX_RANGE_BYTES = 256 * 1024
MAX_REDIRECTS = 3
MAX_TIMEOUT_SECONDS = 30
ALLOWED_AUDIO_HOSTS = frozenset({"audio.qurancdn.com", "download.quranicaudio.com"})
QF_TERMS_URL = "https://api-docs.quran.foundation/legal/developer-terms/"
CONTENT_RANGE_PATTERN = re.compile(r"bytes (\d+)-(\d+)/(\d+)\Z")


class QuranFoundationSource(Protocol):
    def list_chapter_reciters(
        self, *, language: str = "en"
    ) -> list[dict[str, Any]]: ...

    def get_chapter_audio(
        self,
        reciter_id: int,
        chapter_number: int,
    ) -> dict[str, Any]: ...

    def get_external_audio_size(self, url: str) -> int: ...


@dataclass(frozen=True, slots=True)
class RealAudioAsset:
    source_reciter_id: int
    reciter_name: str
    style: str
    surah_number: int
    url: str
    expected_bytes: int
    duration_ms: int

    @property
    def label(self) -> str:
        return f"qf-{self.source_reciter_id}-surah-{self.surah_number:03d}"


@dataclass(frozen=True, slots=True)
class ProbeObservation:
    operation: str
    successful: bool
    status: int | None
    final_host: str | None
    ttfb_ms: float
    elapsed_ms: float
    bytes_received: int
    throughput_kbps: float | None
    content_type: str | None
    content_length: int | None
    content_range: str | None
    observed_total_bytes: int | None
    accept_ranges: str | None
    cors_origin: str | None
    error: str | None


@dataclass(frozen=True, slots=True)
class AssetProbeSummary:
    asset: RealAudioAsset
    observations: tuple[ProbeObservation, ...]
    delivery_passed: bool
    metadata_consistent: bool
    passed: bool
    failures: tuple[str, ...]


class AudioProbeTransport(Protocol):
    def request(
        self,
        url: str,
        *,
        operation: str,
        range_start: int | None,
        range_end: int | None,
        expected_total_bytes: int,
        origin: str,
    ) -> ProbeObservation: ...


def _positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("value must be positive")
    return parsed


def bounded_timeout(value: str) -> int:
    parsed = _positive_int(value)
    if parsed > MAX_TIMEOUT_SECONDS:
        raise argparse.ArgumentTypeError(
            f"timeout must be at most {MAX_TIMEOUT_SECONDS} seconds"
        )
    return parsed


def bounded_range_bytes(value: str) -> int:
    parsed = _positive_int(value)
    if parsed > MAX_RANGE_BYTES:
        raise argparse.ArgumentTypeError(
            f"range bytes must be at most {MAX_RANGE_BYTES}"
        )
    return parsed


def non_negative_float(value: str) -> float:
    parsed = float(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("value must not be negative")
    return parsed


def validate_origin(value: str) -> str:
    parsed = urlsplit(value)
    if (
        parsed.scheme != "https"
        or parsed.hostname is None
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path not in {"", "/"}
        or parsed.query
        or parsed.fragment
    ):
        raise argparse.ArgumentTypeError(
            "origin must be a credential-free HTTPS origin"
        )
    return f"https://{parsed.netloc}"


def validate_audio_url(value: str) -> str:
    parsed = urlsplit(value)
    if (
        parsed.scheme != "https"
        or parsed.hostname not in ALLOWED_AUDIO_HOSTS
        or parsed.username is not None
        or parsed.password is not None
        or not parsed.path.startswith("/")
        or parsed.path == "/"
        or parsed.fragment
    ):
        raise ValueError("Quran.Foundation returned an unapproved audio URL")
    return value


def _mapping_name(value: object) -> str:
    if isinstance(value, Mapping):
        name = value.get("name")
        return name.strip() if isinstance(name, str) else ""
    return value.strip() if isinstance(value, str) else ""


def _reciter_name(row: Mapping[str, object]) -> str:
    for value in (
        row.get("translated_name"),
        row.get("reciter_name"),
        row.get("name"),
    ):
        name = _mapping_name(value)
        if name:
            return name
    raise ValueError("Quran.Foundation reciter has no display name")


def _duration_ms(audio_file: Mapping[str, object]) -> int:
    timestamps = audio_file.get("timestamps")
    if not isinstance(timestamps, list) or not timestamps:
        raise ValueError("Quran.Foundation audio has no verse timestamps")
    ends: list[int] = []
    for row in timestamps:
        if not isinstance(row, Mapping):
            raise TypeError("Quran.Foundation returned invalid verse timestamps")
        try:
            end = int(row["timestamp_to"])
        except (KeyError, TypeError, ValueError) as exc:
            raise ValueError(
                "Quran.Foundation returned invalid verse timestamps"
            ) from exc
        if end <= 0:
            raise ValueError("Quran.Foundation returned invalid verse timestamps")
        ends.append(end)
    return max(ends)


def collect_assets(
    client: QuranFoundationSource,
    *,
    reciter_ids: Sequence[int],
    surah_numbers: Sequence[int],
) -> tuple[RealAudioAsset, ...]:
    if not reciter_ids or len(reciter_ids) > MAX_RECITERS:
        raise ValueError(f"select between 1 and {MAX_RECITERS} reciters")
    if len(set(reciter_ids)) != len(reciter_ids) or any(
        value <= 0 for value in reciter_ids
    ):
        raise ValueError("reciter IDs must be unique positive integers")
    if not surah_numbers or len(surah_numbers) > MAX_SURAHS:
        raise ValueError(f"select between 1 and {MAX_SURAHS} surahs")
    if len(set(surah_numbers)) != len(surah_numbers) or any(
        value < 1 or value > 114 for value in surah_numbers
    ):
        raise ValueError("surah numbers must be unique and between 1 and 114")

    catalog = client.list_chapter_reciters(language="en")
    by_id = {
        int(row["id"]): row
        for row in catalog
        if isinstance(row, Mapping) and isinstance(row.get("id"), int)
    }
    assets: list[RealAudioAsset] = []
    for reciter_id in reciter_ids:
        reciter = by_id.get(reciter_id)
        if reciter is None:
            raise ValueError(f"Quran.Foundation reciter {reciter_id} was not found")
        qirat = _mapping_name(reciter.get("qirat")).lower()
        if qirat and "hafs" not in qirat:
            raise ValueError(
                f"Quran.Foundation reciter {reciter_id} is not marked as Hafs"
            )
        name = _reciter_name(reciter)
        style = _mapping_name(reciter.get("style")) or "unspecified"
        for surah_number in surah_numbers:
            audio_file = client.get_chapter_audio(reciter_id, surah_number)
            try:
                observed_surah = int(audio_file.get("chapter_id", 0))
            except (TypeError, ValueError) as exc:
                raise ValueError(
                    "Quran.Foundation returned invalid chapter metadata"
                ) from exc
            if observed_surah != surah_number:
                raise ValueError("Quran.Foundation returned audio for the wrong surah")
            url = validate_audio_url(str(audio_file.get("audio_url", "")))
            try:
                expected_bytes = int(audio_file.get("file_size") or 0)
            except (TypeError, ValueError) as exc:
                raise ValueError(
                    "Quran.Foundation returned invalid audio size"
                ) from exc
            if expected_bytes <= 0:
                expected_bytes = client.get_external_audio_size(url)
            if expected_bytes <= 0:
                raise ValueError("Quran.Foundation returned invalid audio size")
            assets.append(
                RealAudioAsset(
                    source_reciter_id=reciter_id,
                    reciter_name=name,
                    style=style,
                    surah_number=surah_number,
                    url=url,
                    expected_bytes=expected_bytes,
                    duration_ms=_duration_ms(audio_file),
                )
            )
    if len(assets) > MAX_ASSETS:
        raise ValueError(f"probe cannot inspect more than {MAX_ASSETS} assets")
    return tuple(assets)


def _header_int(headers: Mapping[str, str], name: str) -> int | None:
    value = headers.get(name)
    if value is None:
        return None
    try:
        return int(value)
    except ValueError:
        return None


class BoundedAudioHttpClient:
    def __init__(self, *, timeout_seconds: int) -> None:
        self.timeout_seconds = timeout_seconds

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
        started = time.perf_counter()
        current_url = validate_audio_url(url)
        status: int | None = None
        final_host: str | None = None
        response_started: float | None = None
        headers: dict[str, str] = {}
        body_bytes = 0
        observed_total_bytes: int | None = None
        error: str | None = None
        expected_body_bytes = 0
        if operation != "head":
            if range_start is None or range_end is None or range_end < range_start:
                raise ValueError("Range operation requires a valid byte interval")
            expected_body_bytes = range_end - range_start + 1

        try:
            for redirect_index in range(MAX_REDIRECTS + 1):
                parsed = urlsplit(current_url)
                final_host = parsed.hostname
                target = parsed.path or "/"
                if parsed.query:
                    target = f"{target}?{parsed.query}"
                request_headers = {
                    "Accept": "audio/*",
                    "Accept-Encoding": "identity",
                    "Origin": origin,
                    "User-Agent": "iqro.forum-real-audio-probe/1",
                }
                if operation != "head":
                    request_headers["Range"] = f"bytes={range_start}-{range_end}"
                connection = http.client.HTTPSConnection(
                    parsed.hostname,
                    parsed.port,
                    timeout=self.timeout_seconds,
                    context=ssl.create_default_context(),
                )
                try:
                    connection.request(
                        "HEAD" if operation == "head" else "GET",
                        target,
                        headers=request_headers,
                    )
                    response = connection.getresponse()
                    response_started = time.perf_counter()
                    status = response.status
                    headers = {
                        key.lower(): value.strip()
                        for key, value in response.getheaders()
                    }
                    if status in {301, 302, 303, 307, 308}:
                        location = headers.get("location")
                        response.read(1024)
                        if not location or redirect_index >= MAX_REDIRECTS:
                            error = "invalid_or_excessive_redirect"
                            break
                        current_url = validate_audio_url(urljoin(current_url, location))
                        continue
                    if operation == "head":
                        response.read(1)
                    else:
                        while chunk := response.read(
                            min(64 * 1024, expected_body_bytes + 1 - body_bytes)
                        ):
                            body_bytes += len(chunk)
                            if body_bytes > expected_body_bytes:
                                error = "response_too_large"
                                break
                    break
                finally:
                    connection.close()
            else:  # pragma: no cover - loop always exits via redirect cap
                error = "redirect_limit"
        except (
            OSError,
            TimeoutError,
            ValueError,
            http.client.HTTPException,
            ssl.SSLError,
        ) as exc:
            error = str(exc) if isinstance(exc, ValueError) else type(exc).__name__

        finished = time.perf_counter()
        effective_response_started = response_started or finished
        transfer_ms = max(0.0, (finished - effective_response_started) * 1_000)
        throughput_kbps = None
        if body_bytes and transfer_ms > 0:
            throughput_kbps = body_bytes * 8 / transfer_ms

        if error is None:
            expected_status = 200 if operation == "head" else 206
            if status != expected_status:
                error = f"unexpected_status_{status}"
            elif operation != "head" and body_bytes != expected_body_bytes:
                error = "truncated_response"
            elif operation != "head":
                content_range = headers.get("content-range", "")
                range_match = CONTENT_RANGE_PATTERN.fullmatch(content_range)
                if range_match is None:
                    error = "unexpected_content_range"
                else:
                    observed_start, observed_end, observed_total_bytes = (
                        int(value) for value in range_match.groups()
                    )
                    if observed_start != range_start or observed_end != range_end:
                        error = "unexpected_content_range"
            content_type = headers.get("content-type", "").split(";", 1)[0].lower()
            if error is None and content_type not in {"audio/mpeg", "audio/mp3"}:
                error = "unexpected_content_type"

        return ProbeObservation(
            operation=operation,
            successful=error is None,
            status=status,
            final_host=final_host,
            ttfb_ms=(effective_response_started - started) * 1_000,
            elapsed_ms=(finished - started) * 1_000,
            bytes_received=body_bytes,
            throughput_kbps=throughput_kbps,
            content_type=headers.get("content-type"),
            content_length=_header_int(headers, "content-length"),
            content_range=headers.get("content-range"),
            observed_total_bytes=observed_total_bytes,
            accept_ranges=headers.get("accept-ranges"),
            cors_origin=headers.get("access-control-allow-origin"),
            error=error,
        )


def _percentile(values: Sequence[float], quantile: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, int((len(ordered) - 1) * quantile + 0.999999)))
    return ordered[index]


def run_probe(
    assets: Sequence[RealAudioAsset],
    *,
    transport: AudioProbeTransport,
    origin: str,
    range_bytes: int,
    max_ttfb_ms: float,
    min_throughput_kbps: float,
) -> tuple[AssetProbeSummary, ...]:
    summaries: list[AssetProbeSummary] = []
    for asset in assets:
        length = min(range_bytes, asset.expected_bytes)
        startup_start = 0
        startup_end = length - 1
        seek_start = max(0, (asset.expected_bytes - length) // 2)
        seek_end = seek_start + length - 1
        observations = (
            transport.request(
                asset.url,
                operation="head",
                range_start=None,
                range_end=None,
                expected_total_bytes=asset.expected_bytes,
                origin=origin,
            ),
            transport.request(
                asset.url,
                operation="startup",
                range_start=startup_start,
                range_end=startup_end,
                expected_total_bytes=asset.expected_bytes,
                origin=origin,
            ),
            transport.request(
                asset.url,
                operation="seek",
                range_start=seek_start,
                range_end=seek_end,
                expected_total_bytes=asset.expected_bytes,
                origin=origin,
            ),
        )
        delivery_failures: list[str] = []
        for observation in observations:
            if not observation.successful:
                delivery_failures.append(
                    f"{observation.operation}: {observation.error or 'request_failed'}"
                )
            if observation.ttfb_ms > max_ttfb_ms:
                delivery_failures.append(
                    f"{observation.operation}: TTFB {observation.ttfb_ms:.1f}ms exceeds "
                    f"{max_ttfb_ms:.1f}ms"
                )
        for observation in observations[1:]:
            if (
                observation.successful
                and min_throughput_kbps > 0
                and (observation.throughput_kbps or 0) < min_throughput_kbps
            ):
                delivery_failures.append(
                    f"{observation.operation}: throughput "
                    f"{(observation.throughput_kbps or 0):.1f}kbps is below "
                    f"{min_throughput_kbps:.1f}kbps"
                )
        observed_sizes = {
            value
            for value in (
                observations[0].content_length,
                *(observation.observed_total_bytes for observation in observations[1:]),
            )
            if value is not None
        }
        metadata_consistent = observed_sizes == {asset.expected_bytes}
        metadata_failures = (
            ()
            if metadata_consistent
            else (
                (
                    "origin byte size differs from Quran.Foundation metadata: "
                    f"metadata={asset.expected_bytes}, observed={sorted(observed_sizes)}"
                ),
            )
        )
        failures = (*delivery_failures, *metadata_failures)
        summaries.append(
            AssetProbeSummary(
                asset=asset,
                observations=observations,
                delivery_passed=not delivery_failures,
                metadata_consistent=metadata_consistent,
                passed=not failures,
                failures=tuple(failures),
            )
        )
    return tuple(summaries)


def report_payload(
    summaries: Sequence[AssetProbeSummary],
    *,
    environment: str,
    origin: str,
    range_bytes: int,
    max_ttfb_ms: float,
    min_throughput_kbps: float,
) -> dict[str, object]:
    range_observations = [
        observation
        for summary in summaries
        for observation in summary.observations
        if observation.operation != "head"
    ]
    throughputs = [
        observation.throughput_kbps
        for observation in range_observations
        if observation.throughput_kbps is not None
    ]
    assets: list[dict[str, object]] = []
    for summary in summaries:
        assets.append(
            {
                "label": summary.asset.label,
                "source_reciter_id": summary.asset.source_reciter_id,
                "reciter_name": summary.asset.reciter_name,
                "style": summary.asset.style,
                "surah_number": summary.asset.surah_number,
                "source_host": urlsplit(summary.asset.url).hostname,
                "expected_bytes": summary.asset.expected_bytes,
                "duration_ms": summary.asset.duration_ms,
                "delivery_passed": summary.delivery_passed,
                "metadata_consistent": summary.metadata_consistent,
                "passed": summary.passed,
                "failures": list(summary.failures),
                "observations": [
                    {
                        key: value
                        for key, value in asdict(observation).items()
                        if key not in {"content_range"}
                    }
                    for observation in summary.observations
                ],
            }
        )
    return {
        "schema_version": 1,
        "generated_at": datetime.now(UTC).isoformat(),
        "probe": "bounded-quran-foundation-real-audio",
        "qf_environment": environment,
        "qf_terms_url": QF_TERMS_URL,
        "origin": origin,
        "safety": {
            "provider_load_test": False,
            "database_writes": False,
            "r2_copy": False,
            "audio_content_persisted": False,
            "raw_asset_urls_recorded": False,
            "requests_per_asset": 3,
            "max_assets": MAX_ASSETS,
            "range_bytes": range_bytes,
        },
        "thresholds": {
            "max_ttfb_ms": max_ttfb_ms,
            "min_range_throughput_kbps": min_throughput_kbps,
        },
        "summary": {
            "assets": len(summaries),
            "delivery_passed_assets": sum(
                summary.delivery_passed for summary in summaries
            ),
            "metadata_consistent_assets": sum(
                summary.metadata_consistent for summary in summaries
            ),
            "requests": sum(len(summary.observations) for summary in summaries),
            "errors": sum(
                not observation.successful
                for summary in summaries
                for observation in summary.observations
            ),
            "range_p95_ttfb_ms": round(
                _percentile(
                    [observation.ttfb_ms for observation in range_observations],
                    0.95,
                ),
                2,
            ),
            "range_p50_throughput_kbps": (
                round(_percentile(throughputs, 0.50), 2) if throughputs else None
            ),
        },
        "assets": assets,
        "passed": all(summary.passed for summary in summaries),
    }


def load_qf_credentials(path: Path) -> tuple[str, str, str]:
    values: dict[str, str] = {}
    for line_number, raw_line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError(f"{path}:{line_number}: malformed environment entry")
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
            value = value[1:-1]
        if key in {"QF_CLIENT_ID", "QF_CLIENT_SECRET", "QF_ENV"}:
            values[key] = value
    client_id = values.get("QF_CLIENT_ID", "")
    client_secret = values.get("QF_CLIENT_SECRET", "")
    environment = values.get("QF_ENV", "prelive")
    if not client_id or not client_secret:
        raise ValueError("QF_CLIENT_ID and QF_CLIENT_SECRET are required")
    if environment not in {"prelive", "production"}:
        raise ValueError("QF_ENV must be prelive or production")
    return client_id, client_secret, environment


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Run one bounded HEAD/startup/seek probe per selected Quran.Foundation asset. "
            "This is normal integration verification, never a provider load test."
        )
    )
    parser.add_argument(
        "--env-file",
        type=Path,
        default=Path("services/backend/.env"),
    )
    parser.add_argument(
        "--reciter-id",
        type=_positive_int,
        action="append",
        required=True,
    )
    parser.add_argument("--surah", type=_positive_int, action="append")
    parser.add_argument(
        "--origin",
        type=validate_origin,
        default="https://staging.iqro.forum",
    )
    parser.add_argument("--range-bytes", type=bounded_range_bytes, default=64 * 1024)
    parser.add_argument("--timeout-seconds", type=bounded_timeout, default=15)
    parser.add_argument("--max-ttfb-ms", type=non_negative_float, default=1_500.0)
    parser.add_argument(
        "--min-throughput-kbps",
        type=non_negative_float,
        default=512.0,
    )
    parser.add_argument("--confirm-bounded-provider-probe", action="store_true")
    parser.add_argument("--json-report", type=Path, required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if not args.confirm_bounded_provider_probe:
            raise ValueError("--confirm-bounded-provider-probe is required")
        surah_numbers = args.surah or [1]
        client_id, client_secret, environment_name = load_qf_credentials(args.env_file)
        backend_src = (
            Path(__file__).resolve().parents[2] / "services" / "backend" / "src"
        )
        sys.path.insert(0, str(backend_src))
        from quran_backend.modules.audio.quran_foundation import (
            ENVIRONMENTS,
            QuranFoundationClient,
        )

        client = QuranFoundationClient(
            client_id=client_id,
            client_secret=client_secret,
            environment=ENVIRONMENTS[environment_name],
            timeout_seconds=args.timeout_seconds,
        )
        assets = collect_assets(
            client,
            reciter_ids=args.reciter_id,
            surah_numbers=surah_numbers,
        )
        summaries = run_probe(
            assets,
            transport=BoundedAudioHttpClient(timeout_seconds=args.timeout_seconds),
            origin=args.origin,
            range_bytes=args.range_bytes,
            max_ttfb_ms=args.max_ttfb_ms,
            min_throughput_kbps=args.min_throughput_kbps,
        )
        report = report_payload(
            summaries,
            environment=environment_name,
            origin=args.origin,
            range_bytes=args.range_bytes,
            max_ttfb_ms=args.max_ttfb_ms,
            min_throughput_kbps=args.min_throughput_kbps,
        )
    except (OSError, TypeError, ValueError, KeyError) as exc:
        parser.error(str(exc))

    args.json_report.parent.mkdir(parents=True, exist_ok=True)
    args.json_report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    summary = report["summary"]
    assert isinstance(summary, dict)
    print(
        "REAL AUDIO PROBE "
        f"assets={summary['assets']} requests={summary['requests']} "
        f"errors={summary['errors']} p95_ttfb={summary['range_p95_ttfb_ms']}ms "
        f"p50_throughput={summary['range_p50_throughput_kbps']}kbps"
    )
    print(
        "PASS: bounded real-audio probe satisfied."
        if report["passed"]
        else "FAIL: bounded real-audio probe thresholds exceeded."
    )
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
