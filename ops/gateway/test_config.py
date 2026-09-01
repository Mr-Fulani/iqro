from __future__ import annotations

import unittest
from pathlib import Path

CONFIG = Path(__file__).with_name("default.conf")
DOCKERFILE = Path(__file__).with_name("Dockerfile")
SECURITY_HEADERS = Path(__file__).with_name("security-headers.conf")
PRODUCTION_COMPOSE = CONFIG.parents[2] / "compose.production.yaml"


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
            "font-src 'self' data: https://fonts.gstatic.com https://verses.quran.foundation",
            security_headers,
        )


if __name__ == "__main__":
    unittest.main()
