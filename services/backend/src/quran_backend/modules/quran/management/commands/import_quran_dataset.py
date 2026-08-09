from __future__ import annotations

from pathlib import Path
from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.quran.importer import (
    QuranDatasetError,
    import_quran_dataset,
    validate_quran_dataset,
)


class Command(BaseCommand):
    help = "Validate and import an immutable Quran dataset as a draft edition version."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("dataset", type=Path)
        parser.add_argument(
            "--validate-only",
            action="store_true",
            help="Validate checksums and content without writing to the database.",
        )

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        dataset_path: Path = options["dataset"]
        try:
            dataset = validate_quran_dataset(dataset_path)
            self.stdout.write(
                self.style.SUCCESS(
                    f"Dataset is valid: {dataset.manifest['edition']['code']}@"
                    f"{dataset.manifest['edition']['version']} ({dataset.aggregate_checksum})."
                )
            )
            if options["validate_only"]:
                return
            result = import_quran_dataset(dataset)
        except QuranDatasetError as exc:
            raise CommandError(str(exc)) from exc

        outcome = "created" if result.created else "already exists"
        self.stdout.write(
            self.style.SUCCESS(
                f"Draft version {result.version} {outcome}; no content was published."
            )
        )
