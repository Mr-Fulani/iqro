from __future__ import annotations

import json
from typing import Any

from django.core.management.base import BaseCommand, CommandParser

from quran_backend.modules.reminders.retention import prune_reminder_tombstones


class Command(BaseCommand):
    help = "Replace one bounded batch of expired reminder tombstones with retired-ID rows."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Report the eligible batch without changing reminder or ledger rows.",
        )

    def handle(self, *_args: Any, **options: Any) -> None:
        result = prune_reminder_tombstones(dry_run=bool(options["dry_run"]))
        self.stdout.write(json.dumps(result, sort_keys=True))
