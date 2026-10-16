from __future__ import annotations

import re
import unittest
from pathlib import Path

CONFIG = Path(__file__).with_name("default.conf")
DOCKERFILE = Path(__file__).with_name("Dockerfile")
SECURITY_HEADERS = Path(__file__).with_name("security-headers.conf")
PRODUCTION_COMPOSE = CONFIG.parents[2] / "compose.production.yaml"
NEXT_CONFIG = CONFIG.parents[2] / "services" / "web" / "next.config.mjs"


def _font_sources(policy: str) -> set[str]:
    match = re.search(r"font-src ([^;\"]+)", policy)
    if match is None:
        raise AssertionError("font-src directive is missing")
    return set(match.group(1).split())


class GatewayConfigTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = CONFIG.read_text(encoding="utf-8")

    def test_docker_dns_refreshes_backend_and_web_upstreams(self) -> None:
        self.assertIn("resolver 127.0.0.11 valid=5s ipv6=off;", self.config)
        self.assertIn("zone quran_backend 64k;", self.config)
        self.assertIn("server backend:8000 resolve;", self.config)
        self.assertIn("zone quran_web 64k;", self.config)
        self.assertIn("server web:3000 resolve;", self.config)

    def test_idle_upstream_connections_fit_api_slots_and_close_first(self) -> None:
        dockerfile = DOCKERFILE.read_text(encoding="utf-8")
        compose = PRODUCTION_COMPOSE.read_text(encoding="utf-8")
        workers = int(re.search(r"worker_processes (\d+);", dockerfile).group(1))
        keepalive = int(re.search(r"upstream quran_backend \{[^}]*keepalive (\d+);", self.config).group(1))
        api_workers = int(re.search(r"GUNICORN_WORKERS: \$\{GUNICORN_WORKERS:-(\d+)\}", compose).group(1))
        api_slots = int(
            re.search(
                r"API_MAX_CONCURRENT_REQUESTS_PER_WORKER: \$\{API_MAX_CONCURRENT_REQUESTS_PER_WORKER:-(\d+)\}",
                compose,
            ).group(1)
        )
        self.assertLessEqual(workers * keepalive, api_workers * api_slots // 2)
        self.assertEqual(self.config.count("keepalive_timeout 4s;"), 2)

    def test_logs_go_to_docker_as_json_with_a_shared_request_id(self) -> None:
        dockerfile = DOCKERFILE.read_text(encoding="utf-8")
        self.assertIn("access_log /dev/stdout quran_json;", self.config)
        self.assertIn("log_format quran_json escape=json", self.config)
        for field in ("$request_time", "$upstream_cache_status", "$quran_request_id"):
            self.assertIn(field, self.config)
        self.assertIn("error_log /dev/stderr warn;", dockerfile)
        self.assertEqual(
            self.config.count("proxy_set_header X-Request-ID $quran_request_id;"),
            self.config.count("proxy_set_header Host $host;"),
        )

    def test_public_cache_is_bounded_and_varies_by_cors_and_representation(self) -> None:
        self.assertIn("keys_zone=quran_public_api:4m", self.config)
        self.assertIn("max_size=24m", self.config)
        self.assertIn("$http_origin|accept=$http_accept", self.config)
        self.assertIn("$quran_public_api_authorization_bypass", self.config)
        self.assertIn("$quran_public_api_cookie_bypass", self.config)
        self.assertIn("$quran_public_api_response_no_cache", self.config)
        self.assertIn("proxy_cache_lock on;", self.config)
        self.assertIn("proxy_cache_convert_head off;", self.config)

    def test_public_cache_has_authenticated_wildcard_purge(self) -> None:
        self.assertIn("nginx-mod-http-cache-purge", DOCKERFILE.read_text(encoding="utf-8"))
        self.assertIn("auth_request /internal/cache/purge-auth;", self.config)
        self.assertIn(
            "proxy_cache_purge PURGE purge_all from all;",
            self.config,
        )
        self.assertIn(
            "proxy_pass http://quran_backend/api/v1/internal/gateway-cache-purge-auth;",
            self.config,
        )
        self.assertIn("proxy_set_header X-Forwarded-Proto https;", self.config)
        self.assertIn(
            "DJANGO_ALLOWED_HOSTS: ${DJANGO_ALLOWED_HOSTS:?Set DJANGO_ALLOWED_HOSTS in the production env file},gateway,backend",
            PRODUCTION_COMPOSE.read_text(encoding="utf-8"),
        )

    def test_generic_api_proxy_remains_uncached(self) -> None:
        generic_api = self.config.split("location /api/ {", maxsplit=1)[1].split(
            "location /admin/ {", maxsplit=1
        )[0]
        self.assertNotIn("proxy_cache ", generic_api)

    def test_large_uploads_have_writable_bounded_temp_storage(self) -> None:
        production_compose = PRODUCTION_COMPOSE.read_text(encoding="utf-8")
        self.assertIn("client_max_body_size 55m;", self.config)
        self.assertIn(
            "/var/lib/nginx/tmp:size=64m,mode=0750,uid=100,gid=101",
            production_compose,
        )

    def test_web_auth_namespace_is_routed_to_next_bff(self) -> None:
        web_auth_location = "location /api/web-auth/ {"
        generic_api_location = "location /api/ {"
        self.assertIn(web_auth_location, self.config)
        self.assertLess(
            self.config.index(web_auth_location),
            self.config.index(generic_api_location),
        )
        web_auth = self.config.split(web_auth_location, maxsplit=1)[1].split(
            generic_api_location, maxsplit=1
        )[0]
        self.assertIn("proxy_pass http://quran_web;", web_auth)
        self.assertNotIn("proxy_cache ", web_auth)

    def test_quran_foundation_fonts_are_allowed_by_gateway_csp(self) -> None:
        security_headers = SECURITY_HEADERS.read_text(encoding="utf-8")
        self.assertIn(
            "font-src 'self' data: https://verses.quran.foundation",
            security_headers,
        )

    def test_gateway_font_sources_match_next_csp(self) -> None:
        # The gateway replaces the Next.js CSP, so every font host the web
        # client loads (including the Nastaleeq CDN) must be listed here too.
        gateway_sources = _font_sources(SECURITY_HEADERS.read_text(encoding="utf-8"))
        next_sources = _font_sources(NEXT_CONFIG.read_text(encoding="utf-8"))
        self.assertEqual(gateway_sources, next_sources)
        self.assertIn("https://static-cdn.tarteel.ai", gateway_sources)

    def test_text_responses_are_compressed(self) -> None:
        self.assertIn("gzip on;", self.config)
        self.assertIn("gzip_proxied any;", self.config)
        self.assertIn("gzip_vary on;", self.config)
        gzip_types = self.config.split("gzip_types ", maxsplit=1)[1].split(";", maxsplit=1)[0]
        for media_type in ("application/json", "application/problem+json", "text/css"):
            self.assertIn(media_type, gzip_types.split())

    def test_api_and_web_are_rate_limited_per_forwarded_client(self) -> None:
        self.assertIn("map $http_x_forwarded_for $quran_client_address {", self.config)
        self.assertIn("limit_req_zone $quran_client_address zone=quran_api_rate:", self.config)
        self.assertIn("limit_req_zone $quran_client_address zone=quran_web_rate:", self.config)
        self.assertIn("limit_req_status 429;", self.config)
        for location in (
            "location ~ ^/api/v1/",
            "location /api/web-auth/ {",
            "location /api/ {",
        ):
            block = self.config.split(location, maxsplit=1)[1].split("location ", maxsplit=1)[0]
            self.assertIn("limit_req zone=quran_api_rate ", block, location)
        site = self.config.split("    location / {", maxsplit=1)[1]
        self.assertIn("limit_req zone=quran_web_rate ", site)


if __name__ == "__main__":
    unittest.main()
