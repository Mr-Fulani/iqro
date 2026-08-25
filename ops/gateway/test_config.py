from __future__ import annotations

import unittest
from pathlib import Path

CONFIG = Path(__file__).with_name("default.conf")
DOCKERFILE = Path(__file__).with_name("Dockerfile")
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
            "DJANGO_ALLOWED_HOSTS: ${DJANGO_ALLOWED_HOSTS:?Set DJANGO_ALLOWED_HOSTS in the production env file},gateway",
            PRODUCTION_COMPOSE.read_text(encoding="utf-8"),
        )

    def test_generic_api_proxy_remains_uncached(self) -> None:
        generic_api = self.config.split("location /api/ {", maxsplit=1)[1].split(
            "location /admin/ {", maxsplit=1
        )[0]
        self.assertNotIn("proxy_cache ", generic_api)


if __name__ == "__main__":
    unittest.main()
