from __future__ import annotations

from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.audio.quran_foundation import QuranFoundationError
from quran_backend.modules.audio.quran_foundation_sync import refresh_quran_foundation_audio


class Command(BaseCommand):
    help = "Refresh complete published Quran.Foundation audio catalogs."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument(
            "--force",
            action="store_true",
            help="Refresh even when the last successful check is still fresh.",
        )

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        try:
            result = refresh_quran_foundation_audio(force=options["force"])
        except QuranFoundationError as exc:
            raise CommandError(str(exc)) from exc

        self.stdout.write(
            self.style.SUCCESS(
                "Quran.Foundation audio refresh complete: "
                f"checked={result.checked}, changed={result.changed}, "
                f"withdrawn={result.withdrawn}, skipped_fresh={result.skipped_fresh}."
            )
        )
