#!/usr/bin/env python3
from __future__ import annotations

import argparse
import http.client
import json
import re
import ssl
import sys
from collections.abc import Mapping, Sequence
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Protocol
from urllib.parse import urlsplit

MAX_ASSETS = 100
MAX_ORIGINS = 10
MAX_RESPONSE_BYTES = 64
DEFAULT_MIN_CACHE_SECONDS = 31_536_000
REQUIRED_EXPOSED_HEADERS = {
    "accept-ranges",
    "content-length",
    "content-range",
    "etag",
    "last-modified",
}
STRONG_ETAG_PATTERN = re.compile(r'"[^"\r\n]+"\Z')
CONTENT_TYPE_PATTERN = re.compile(r"[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+\Z")


class MediaContractRequestError(RuntimeError):
    """A bounded media contract request could not be completed."""


@dataclass(frozen=True, slots=True)
class AssetSpec:
    name: str
    url: str
    expected_bytes: int
    content_type: str
    expected_etag: str | None = None


@dataclass(frozen=True, slots=True)
class MediaManifest:
    name: str
    version: int
    origins: tuple[str, ...]
    assets: tuple[AssetSpec, ...]


@dataclass(frozen=True, slots=True)
class HttpResponse:
    status: int
    headers: Mapping[str, str]
    body: bytes


@dataclass(frozen=True, slots=True)
class AssetResult:
    name: str
    url: str
    passed: bool
    failures: tuple[str, ...]
    observed_etag: str | None
    observed_bytes: int | None
    observed_content_type: str | None


class MediaHttpClient(Protocol):
    def request(
        self,
        method: str,
        url: str,
        headers: Mapping[str, str],
    ) -> HttpResponse: ...


class StdlibMediaHttpClient:
    def __init__(self, timeout_seconds: float) -> None:
        self.timeout_seconds = timeout_seconds

    def request(
        self,
        method: str,
        url: str,
        headers: Mapping[str, str],
    ) -> HttpResponse:
        parsed = urlsplit(url)
        host = parsed.hostname
        if host is None:  # Manifest validation prevents this.
            raise MediaContractRequestError("URL has no hostname")
        connection: http.client.HTTPConnection
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
        request_headers = {
            "Accept": "*/*",
            "Accept-Encoding": "identity",
            "User-Agent": "quran-platform-media-contract/1",
            **headers,
        }
        target = parsed.path or "/"
        try:
            connection.request(method, target, headers=request_headers)
            response = connection.getresponse()
            body = _read_bounded_body(response, method)
            response_headers = {
                key.lower(): value.strip() for key, value in response.getheaders()
            }
            return HttpResponse(response.status, response_headers, body)
        except MediaContractRequestError:
            raise
        except (
            OSError,
            TimeoutError,
            ValueError,
            http.client.HTTPException,
            ssl.SSLError,
        ) as exc:
            raise MediaContractRequestError(type(exc).__name__) from exc
        finally:
            connection.close()


def _read_bounded_body(
    response: http.client.HTTPResponse,
    method: str,
) -> bytes:
    # The contract validates headers for responses that must not carry a useful
    # representation. R2 may still attach a provider error document to 416;
    # reading it would add no evidence and must not turn a correct Range result
    # into a false failure.
    if method == "HEAD" or response.status in {304, 416}:
        return b""
    body = response.read(MAX_RESPONSE_BYTES + 1)
    if len(body) > MAX_RESPONSE_BYTES:
        raise MediaContractRequestError("response body exceeded the safety cap")
    return body


def _positive_int(value: object, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ValueError(f"{field} must be a positive integer")
    return value


def _validate_origin(value: object, field: str, *, allow_http: bool) -> str:
    if not isinstance(value, str):
        raise TypeError(f"{field} must be a string")
    parsed = urlsplit(value)
    allowed_schemes = {"https", "http"} if allow_http else {"https"}
    if (
        parsed.scheme not in allowed_schemes
        or parsed.hostname is None
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path not in {"", "/"}
        or parsed.query
        or parsed.fragment
    ):
        protocol = "HTTP(S)" if allow_http else "HTTPS"
        raise ValueError(f"{field} must be a credential-free {protocol} origin")
    hostname = f"[{parsed.hostname}]" if ":" in parsed.hostname else parsed.hostname
    port = f":{parsed.port}" if parsed.port is not None else ""
    return f"{parsed.scheme}://{hostname}{port}"


def _validate_asset_url(value: object, field: str, *, allow_http: bool) -> str:
    if not isinstance(value, str):
        raise TypeError(f"{field} must be a string")
    parsed = urlsplit(value)
    allowed_schemes = {"https", "http"} if allow_http else {"https"}
    if (
        parsed.scheme not in allowed_schemes
        or parsed.hostname is None
        or parsed.username is not None
        or parsed.password is not None
        or not parsed.path.startswith("/")
        or parsed.path == "/"
        or parsed.query
        or parsed.fragment
    ):
        protocol = "HTTP(S)" if allow_http else "HTTPS"
        raise ValueError(
            f"{field} must be a stable, credential-free {protocol} object URL without query"
        )
    return value


def load_manifest(path: Path, *, allow_http: bool = False) -> MediaManifest:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise TypeError("manifest root must be an object")
    name = raw.get("name")
    if not isinstance(name, str) or not name.strip():
        raise ValueError("manifest name must be a non-empty string")
    if raw.get("version") != 1:
        raise ValueError("only media manifest version 1 is supported")

    raw_origins = raw.get("origins")
    if not isinstance(raw_origins, list) or not raw_origins:
        raise ValueError("manifest origins must be a non-empty array")
    if len(raw_origins) > MAX_ORIGINS:
        raise ValueError(f"manifest must contain at most {MAX_ORIGINS} origins")
    origins = tuple(
        _validate_origin(value, f"origins[{index}]", allow_http=allow_http)
        for index, value in enumerate(raw_origins)
    )
    if len(set(origins)) != len(origins):
        raise ValueError("manifest origins must be unique")

    raw_assets = raw.get("assets")
    if not isinstance(raw_assets, list) or not raw_assets:
        raise ValueError("manifest assets must be a non-empty array")
    if len(raw_assets) > MAX_ASSETS:
        raise ValueError(f"manifest must contain at most {MAX_ASSETS} assets")
    assets: list[AssetSpec] = []
    names: set[str] = set()
    urls: set[str] = set()
    for index, row in enumerate(raw_assets):
        field = f"assets[{index}]"
        if not isinstance(row, dict):
            raise TypeError(f"{field} must be an object")
        asset_name = row.get("name")
        if not isinstance(asset_name, str) or not asset_name.strip():
            raise ValueError(f"{field}.name must be a non-empty string")
        if asset_name in names:
            raise ValueError(f"duplicate asset name: {asset_name}")
        names.add(asset_name)
        asset_url = _validate_asset_url(
            row.get("url"),
            f"{field}.url",
            allow_http=allow_http,
        )
        if asset_url in urls:
            raise ValueError(f"duplicate asset URL: {asset_url}")
        urls.add(asset_url)
        content_type = row.get("content_type")
        if (
            not isinstance(content_type, str)
            or CONTENT_TYPE_PATTERN.fullmatch(content_type) is None
        ):
            raise ValueError(f"{field}.content_type must be a lowercase MIME type")
        expected_etag = row.get("etag")
        if expected_etag is not None and (
            not isinstance(expected_etag, str)
            or STRONG_ETAG_PATTERN.fullmatch(expected_etag) is None
        ):
            raise ValueError(f"{field}.etag must be a quoted strong ETag")
        assets.append(
            AssetSpec(
                name=asset_name,
                url=asset_url,
                expected_bytes=_positive_int(row.get("bytes"), f"{field}.bytes"),
                content_type=content_type,
                expected_etag=expected_etag,
            )
        )
    return MediaManifest(name, 1, origins, tuple(assets))


def _integer_header(response: HttpResponse, name: str) -> int | None:
    value = response.headers.get(name)
    if value is None:
        return None
    try:
        return int(value)
    except ValueError:
        return None


def _content_type(response: HttpResponse) -> str | None:
    value = response.headers.get("content-type")
    return value.split(";", 1)[0].strip().lower() if value else None


def _cors_failures(response: HttpResponse, origin: str) -> list[str]:
    failures: list[str] = []
    if response.headers.get("access-control-allow-credentials", "").lower() == "true":
        failures.append("managed public media must not enable credentialed CORS")
    allowed_origin = response.headers.get("access-control-allow-origin")
    if allowed_origin not in {"*", origin}:
        failures.append(f"CORS does not allow origin {origin}")
    if allowed_origin == origin:
        vary = {
            token.strip().lower()
            for token in response.headers.get("vary", "").split(",")
            if token.strip()
        }
        if "origin" not in vary:
            failures.append("origin-specific CORS response must include Vary: Origin")
    exposed = {
        token.strip().lower()
        for token in response.headers.get("access-control-expose-headers", "").split(
            ","
        )
        if token.strip()
    }
    if "*" not in exposed:
        missing = sorted(REQUIRED_EXPOSED_HEADERS - exposed)
        if missing:
            failures.append(f"CORS does not expose headers: {', '.join(missing)}")
    return failures


def _cache_failures(response: HttpResponse, min_cache_seconds: int) -> list[str]:
    directives = {
        token.strip().lower()
        for token in response.headers.get("cache-control", "").split(",")
        if token.strip()
    }
    failures: list[str] = []
    if "public" not in directives:
        failures.append("Cache-Control must include public")
    if "immutable" not in directives:
        failures.append("Cache-Control must include immutable")
    max_age: int | None = None
    for directive in directives:
        if directive.startswith("max-age="):
            try:
                max_age = int(directive.removeprefix("max-age="))
            except ValueError:
                max_age = None
    if max_age is None or max_age < min_cache_seconds:
        failures.append(f"Cache-Control max-age must be at least {min_cache_seconds}")
    return failures


def _request(
    client: MediaHttpClient,
    method: str,
    asset: AssetSpec,
    headers: Mapping[str, str],
    label: str,
    failures: list[str],
) -> HttpResponse | None:
    try:
        return client.request(method, asset.url, headers)
    except MediaContractRequestError as exc:
        failures.append(f"{label} request failed: {exc}")
        return None


def verify_asset(
    asset: AssetSpec,
    origins: Sequence[str],
    client: MediaHttpClient,
    *,
    min_cache_seconds: int = DEFAULT_MIN_CACHE_SECONDS,
) -> AssetResult:
    failures: list[str] = []
    observed_etag: str | None = None
    observed_bytes: int | None = None
    observed_content_type: str | None = None
    primary_origin = origins[0]
    head = _request(
        client,
        "HEAD",
        asset,
        {"Origin": primary_origin},
        "HEAD",
        failures,
    )
    if head is not None:
        if head.status != 200:
            failures.append(f"HEAD returned {head.status}, expected 200")
        observed_bytes = _integer_header(head, "content-length")
        if observed_bytes != asset.expected_bytes:
            failures.append(
                f"Content-Length is {observed_bytes}, expected {asset.expected_bytes}"
            )
        observed_content_type = _content_type(head)
        if observed_content_type != asset.content_type:
            failures.append(
                f"Content-Type is {observed_content_type}, expected {asset.content_type}"
            )
        if head.headers.get("accept-ranges", "").lower() != "bytes":
            failures.append("Accept-Ranges must be bytes")
        last_modified = head.headers.get("last-modified")
        try:
            parsed_last_modified = (
                parsedate_to_datetime(last_modified)
                if last_modified is not None
                else None
            )
        except (TypeError, ValueError):
            parsed_last_modified = None
        if parsed_last_modified is None or parsed_last_modified.utcoffset() is None:
            failures.append("Last-Modified must be a valid timezone-aware HTTP date")
        content_disposition = head.headers.get("content-disposition", "")
        if content_disposition.split(";", 1)[0].strip().lower() != "inline":
            failures.append("Content-Disposition must be inline")
        if head.headers.get("x-content-type-options", "").lower() != "nosniff":
            failures.append("X-Content-Type-Options must be nosniff")
        observed_etag = head.headers.get("etag")
        if (
            observed_etag is None
            or STRONG_ETAG_PATTERN.fullmatch(observed_etag) is None
        ):
            failures.append("ETag must be quoted and strong")
        elif asset.expected_etag is not None and observed_etag != asset.expected_etag:
            failures.append(f"ETag is {observed_etag}, expected {asset.expected_etag}")
        failures.extend(_cache_failures(head, min_cache_seconds))
        failures.extend(_cors_failures(head, primary_origin))

    for origin in origins[1:]:
        origin_head = _request(
            client,
            "HEAD",
            asset,
            {"Origin": origin},
            f"HEAD origin {origin}",
            failures,
        )
        if origin_head is None:
            continue
        if origin_head.status != 200:
            failures.append(f"HEAD for origin {origin} returned {origin_head.status}")
        failures.extend(_cors_failures(origin_head, origin))
        if observed_etag and origin_head.headers.get("etag") != observed_etag:
            failures.append(f"ETag changed for origin {origin}")

    range_response = _request(
        client,
        "GET",
        asset,
        {"Origin": primary_origin, "Range": "bytes=0-0"},
        "Range",
        failures,
    )
    if range_response is not None:
        if range_response.status != 206:
            failures.append(f"Range returned {range_response.status}, expected 206")
        expected_content_range = f"bytes 0-0/{asset.expected_bytes}"
        if range_response.headers.get("content-range") != expected_content_range:
            failures.append(f"Content-Range must be {expected_content_range}")
        if _integer_header(range_response, "content-length") != 1:
            failures.append("single-byte Range Content-Length must be 1")
        if len(range_response.body) != 1:
            failures.append("single-byte Range body must contain exactly one byte")
        if observed_etag and range_response.headers.get("etag") != observed_etag:
            failures.append("ETag changed between HEAD and Range")
        failures.extend(_cors_failures(range_response, primary_origin))

    unsatisfied_response = _request(
        client,
        "GET",
        asset,
        {
            "Origin": primary_origin,
            "Range": f"bytes={asset.expected_bytes}-",
        },
        "Unsatisfied Range",
        failures,
    )
    if unsatisfied_response is not None:
        if unsatisfied_response.status != 416:
            failures.append(
                f"unsatisfied Range returned {unsatisfied_response.status}, expected 416"
            )
        expected_unsatisfied_range = f"bytes */{asset.expected_bytes}"
        observed_unsatisfied_range = unsatisfied_response.headers.get("content-range")
        if observed_unsatisfied_range not in {None, expected_unsatisfied_range}:
            failures.append(f"416 Content-Range must be {expected_unsatisfied_range}")
        failures.extend(_cors_failures(unsatisfied_response, primary_origin))

    if observed_etag is not None:
        conditional_response = _request(
            client,
            "GET",
            asset,
            {"Origin": primary_origin, "If-None-Match": observed_etag},
            "Conditional GET",
            failures,
        )
        if conditional_response is not None:
            if conditional_response.status != 304:
                failures.append(
                    f"conditional GET returned {conditional_response.status}, expected 304"
                )
            if conditional_response.headers.get("etag") != observed_etag:
                failures.append("304 response did not preserve ETag")
            failures.extend(_cors_failures(conditional_response, primary_origin))

    return AssetResult(
        name=asset.name,
        url=asset.url,
        passed=not failures,
        failures=tuple(failures),
        observed_etag=observed_etag,
        observed_bytes=observed_bytes,
        observed_content_type=observed_content_type,
    )


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("value must be positive")
    return parsed


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Verify bounded HEAD/Range/CORS/ETag/cache behavior for immutable managed media."
        )
    )
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--timeout-seconds", type=positive_int, default=5)
    parser.add_argument(
        "--min-cache-seconds",
        type=positive_int,
        default=DEFAULT_MIN_CACHE_SECONDS,
    )
    parser.add_argument("--json-report", type=Path)
    parser.add_argument(
        "--allow-http",
        action="store_true",
        help="Allow HTTP targets for local contract testing only.",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        manifest = load_manifest(args.manifest, allow_http=args.allow_http)
    except (OSError, TypeError, ValueError, json.JSONDecodeError) as exc:
        parser.error(str(exc))
    client = StdlibMediaHttpClient(args.timeout_seconds)
    results = tuple(
        verify_asset(
            asset,
            manifest.origins,
            client,
            min_cache_seconds=args.min_cache_seconds,
        )
        for asset in manifest.assets
    )
    for result in results:
        status = "PASS" if result.passed else "FAIL"
        print(f"{status}: {result.name} etag={result.observed_etag}")
        for failure in result.failures:
            print(f"  {failure}", file=sys.stderr)
    passed = all(result.passed for result in results)
    report = {
        "schema_version": 1,
        "generated_at": datetime.now(UTC).isoformat(),
        "manifest": {"name": manifest.name, "version": manifest.version},
        "origins": list(manifest.origins),
        "min_cache_seconds": args.min_cache_seconds,
        "passed": passed,
        "assets": [asdict(result) for result in results],
    }
    if args.json_report:
        args.json_report.parent.mkdir(parents=True, exist_ok=True)
        args.json_report.write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    print(
        "PASS: media contract satisfied."
        if passed
        else "FAIL: media contract violated."
    )
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
