from __future__ import annotations

import json
from typing import Any

from django.core.management.base import BaseCommand, CommandParser

from quran_backend.modules.reading.retention import prune_sync_history


class Command(BaseCommand):
    help = "Prune one bounded batch of expired reading sync history."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Report the eligible batch without changing cursor floors or deleting rows.",
        )

    def handle(self, *_args: Any, **options: Any) -> None:
        result = prune_sync_history(dry_run=bool(options["dry_run"]))
        self.stdout.write(json.dumps(result, sort_keys=True))
