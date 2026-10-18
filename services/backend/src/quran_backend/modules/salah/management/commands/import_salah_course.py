from __future__ import annotations

from pathlib import Path
from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.salah.importer import import_salah_snapshot
from quran_backend.modules.salah.resolvers import SalahFormulaError
from quran_backend.modules.salah.snapshot import SalahSnapshotError, load_snapshot

DEFAULT_SNAPSHOT = Path(__file__).resolve().parents[2] / "data" / "hanbali-umdah-v1.json"


class Command(BaseCommand):
    help = "Импортирует снимок курса обучения намазу как черновик и собирает документы."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("snapshot", nargs="?", default=str(DEFAULT_SNAPSHOT))

    def handle(self, *_args: Any, **options: Any) -> None:
        path = Path(options["snapshot"])
        try:
            version = import_salah_snapshot(load_snapshot(path), data_dir=path.parent)
        except (SalahSnapshotError, SalahFormulaError) as error:
            raise CommandError(str(error)) from error
        self.stdout.write(
            self.style.SUCCESS(
                f"{version}: {version.status}. Подпишите и опубликуйте версию в админке."
            )
        )
