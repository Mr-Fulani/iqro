from __future__ import annotations

from pathlib import Path
from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.quran.importer import QuranDatasetError, validate_quran_dataset


class Command(BaseCommand):
    help = "Validate checksums, coverage, geometry, ordering and asset registration for a dataset."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("dataset", type=Path, help="Versioned Quran dataset directory.")

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        try:
            dataset = validate_quran_dataset(options["dataset"])
        except (OSError, QuranDatasetError) as exc:
            raise CommandError(str(exc)) from exc
        report = dataset.region_audit
        self.stdout.write(
            self.style.SUCCESS(
                f"Region audit passed: {report.pages} pages, {report.ayahs} ayahs, "
                f"{report.region_segments} segments, "
                f"{report.multi_segment_ayahs} multi-segment ayahs."
            )
        )
