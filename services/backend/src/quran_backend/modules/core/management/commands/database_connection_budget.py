from __future__ import annotations

import json

from django.conf import settings
from django.core.management.base import BaseCommand

from quran_backend.database_budget import DatabaseConnectionBudget


class Command(BaseCommand):
    help = "Validate and print the declared PostgreSQL/PgBouncer connection budget."

    def handle(self, *_args: object, **_options: object) -> None:
        budget: DatabaseConnectionBudget = settings.DATABASE_CONNECTION_BUDGET
        budget.validate()
        self.stdout.write(json.dumps(budget.report(), indent=2, sort_keys=True))
