from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from ops.media.contract import (
    DEFAULT_MIN_CACHE_SECONDS,
    AssetSpec,
    HttpResponse,
    load_manifest,
    verify_asset,
)


class FakeClient:
    def __init__(self, *, weak_etag: bool = False, immutable: bool = True) -> None:
        self.weak_etag = weak_etag
        self.immutable = immutable
        self.requests: list[tuple[str, str, dict[str, str]]] = []

    def request(
        self,
        method: str,
        url: str,
        headers: dict[str, str],
    ) -> HttpResponse:
        request_headers = dict(headers)
        self.requests.append((method, url, request_headers))
        origin = request_headers["Origin"]
        etag = 'W/"asset-v1"' if self.weak_etag else '"asset-v1"'
        response_headers = {
            "accept-ranges": "bytes",
            "access-control-allow-origin": origin,
            "access-control-expose-headers": (
                "Accept-Ranges, Content-Length, Content-Range, ETag, Last-Modified"
            ),
            "cache-control": (
                f"public, max-age={DEFAULT_MIN_CACHE_SECONDS}, immutable"
                if self.immutable
                else f"public, max-age={DEFAULT_MIN_CACHE_SECONDS}"
            ),
            "content-length": "10",
            "content-disposition": "inline",
            "content-type": "audio/mpeg",
            "etag": etag,
            "last-modified": "Mon, 24 Aug 2026 12:00:00 GMT",
            "vary": "Origin",
            "x-content-type-options": "nosniff",
        }
        if method == "HEAD":
            return HttpResponse(200, response_headers, b"")
        if request_headers.get("Range") == "bytes=0-0":
            response_headers["content-length"] = "1"
            response_headers["content-range"] = "bytes 0-0/10"
            return HttpResponse(206, response_headers, b"a")
        if request_headers.get("Range") == "bytes=10-":
            response_headers["content-range"] = "bytes */10"
            return HttpResponse(416, response_headers, b"")
        if request_headers.get("If-None-Match") == etag:
            return HttpResponse(304, response_headers, b"")
        raise AssertionError("unexpected request")


class MediaContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.asset = AssetSpec(
            name="surah-001-standard",
            url="https://media.example.test/audio/v1/surah-001.mp3",
            expected_bytes=10,
            content_type="audio/mpeg",
            expected_etag='"asset-v1"',
        )
        self.origins = (
            "https://www.example.test",
            "https://mini.example.test",
        )

    def test_valid_contract_exercises_all_read_only_requests(self) -> None:
        client = FakeClient()

        result = verify_asset(self.asset, self.origins, client)

        self.assertTrue(result.passed, result.failures)
        self.assertEqual(result.observed_etag, '"asset-v1"')
        self.assertEqual(
            [(method, headers) for method, _, headers in client.requests],
            [
                ("HEAD", {"Origin": self.origins[0]}),
                ("HEAD", {"Origin": self.origins[1]}),
                ("GET", {"Origin": self.origins[0], "Range": "bytes=0-0"}),
                ("GET", {"Origin": self.origins[0], "Range": "bytes=10-"}),
                (
                    "GET",
                    {"Origin": self.origins[0], "If-None-Match": '"asset-v1"'},
                ),
            ],
        )

    def test_weak_etag_and_missing_immutable_fail(self) -> None:
        result = verify_asset(
            AssetSpec(
                name=self.asset.name,
                url=self.asset.url,
                expected_bytes=self.asset.expected_bytes,
                content_type=self.asset.content_type,
            ),
            self.origins,
            FakeClient(weak_etag=True, immutable=False),
        )

        self.assertFalse(result.passed)
        self.assertTrue(any("strong" in failure for failure in result.failures))
        self.assertTrue(any("immutable" in failure for failure in result.failures))

    def test_manifest_is_bounded_and_https_by_default(self) -> None:
        raw = {
            "name": "release-v1",
            "version": 1,
            "origins": ["http://localhost:3000"],
            "assets": [
                {
                    "name": "surah-001",
                    "url": "http://localhost:9000/audio/surah-001.mp3",
                    "bytes": 10,
                    "content_type": "audio/mpeg",
                }
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manifest.json"
            path.write_text(json.dumps(raw), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "HTTPS"):
                load_manifest(path)

            manifest = load_manifest(path, allow_http=True)

        self.assertEqual(manifest.assets[0].expected_bytes, 10)
        self.assertEqual(manifest.origins, ("http://localhost:3000",))

    def test_manifest_rejects_weak_expected_etag(self) -> None:
        raw = {
            "name": "release-v1",
            "version": 1,
            "origins": ["https://www.example.test"],
            "assets": [
                {
                    "name": "surah-001",
                    "url": "https://media.example.test/audio/surah-001.mp3",
                    "bytes": 10,
                    "content_type": "audio/mpeg",
                    "etag": 'W/"asset-v1"',
                }
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manifest.json"
            path.write_text(json.dumps(raw), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "strong ETag"):
                load_manifest(path)


if __name__ == "__main__":
    unittest.main()
