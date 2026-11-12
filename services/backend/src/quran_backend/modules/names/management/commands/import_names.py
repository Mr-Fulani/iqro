# ruff: noqa: RUF001
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.names.publication import NamesError, import_names

DEFAULT_FILE = Path(__file__).resolve().parents[2] / "data" / "asma-al-husna.json"


class Command(BaseCommand):
    help = "Импортирует список имён Аллаха как черновик. Публикует его владелец в админке."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("file", nargs="?", default=str(DEFAULT_FILE))

    def handle(self, *_args: Any, **options: Any) -> None:
        try:
            data = json.loads(Path(options["file"]).read_text(encoding="utf-8"))
            version = import_names(data)
        except (OSError, ValueError, NamesError) as error:
            raise CommandError(str(error)) from error
        self.stdout.write(
            self.style.SUCCESS(
                f"{version}: {version.status}, имён: {version.names.count()}. "
                "Проверьте, подпишите и опубликуйте версию в админке."
            )
        )
