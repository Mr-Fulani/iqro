from __future__ import annotations

from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.audio.quran_foundation import QuranFoundationError
from quran_backend.modules.audio.quran_foundation_word_timings import (
    backfill_quran_foundation_word_timings,
)


class Command(BaseCommand):
    help = (
        "Add Quran.Foundation word timings to published QF recitations whose ayah "
        "timeline is unchanged. Ayah boundaries are never modified."
    )

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument(
            "--recitation-code",
            action="append",
            default=[],
            dest="recitation_codes",
            help="Limit to one recitation code. Repeat for several.",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Compare with Quran.Foundation without writing to the database.",
        )

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        try:
            result = backfill_quran_foundation_word_timings(
                recitation_codes=tuple(options["recitation_codes"]),
                dry_run=options["dry_run"],
            )
        except QuranFoundationError as exc:
            raise CommandError(str(exc)) from exc
        prefix = "Dry run" if options["dry_run"] else "Word timings"
        self.stdout.write(
            self.style.SUCCESS(
                f"{prefix}: recitations={result.recitations}, "
                f"tracks_updated={result.tracks_updated}, "
                f"tracks_unchanged={result.tracks_unchanged}, "
                f"tracks_skipped={result.tracks_skipped}, "
                f"segments_updated={result.segments_updated}."
            )
        )
