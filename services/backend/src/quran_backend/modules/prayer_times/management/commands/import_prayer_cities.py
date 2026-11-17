from __future__ import annotations

from pathlib import Path
from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.prayer_times.cities import (
    DEFAULT_CITIES_FILE,
    PrayerCitiesFileError,
    import_prayer_cities,
)


class Command(BaseCommand):
    help = "Загружает города для поиска во времени намаза из файла данных (GeoNames)."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("file", nargs="?", default=str(DEFAULT_CITIES_FILE))

    def handle(self, *_args: Any, **options: Any) -> None:
        try:
            count = import_prayer_cities(Path(options["file"]))
        except PrayerCitiesFileError as error:
            raise CommandError(str(error)) from error
        self.stdout.write(self.style.SUCCESS(f"Городов загружено: {count}."))
