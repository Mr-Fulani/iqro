from __future__ import annotations

import unittest
from pathlib import Path

CONFIG = Path(__file__).with_name("default.conf")


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

    def test_gateway_does_not_add_unpurgeable_public_json_cache(self) -> None:
        self.assertNotIn("proxy_cache", self.config)


if __name__ == "__main__":
    unittest.main()
