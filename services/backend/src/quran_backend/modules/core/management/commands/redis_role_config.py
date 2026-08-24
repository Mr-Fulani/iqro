from __future__ import annotations

import json

from django.conf import settings
from django.core.management.base import BaseCommand

from quran_backend.redis_roles import RedisRoleConfig


class Command(BaseCommand):
    help = "Validate and print redacted Redis endpoints for each runtime role."

    def handle(self, *_args: object, **_options: object) -> None:
        config: RedisRoleConfig = settings.REDIS_ROLE_CONFIG
        self.stdout.write(json.dumps(config.report(), indent=2, sort_keys=True))
