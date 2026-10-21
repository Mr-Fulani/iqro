from __future__ import annotations

from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.audio.quran_foundation import QuranFoundationError
from quran_backend.modules.tajweed.quran_foundation_sync import sync_quran_foundation_tajweed


class Command(BaseCommand):
    help = (
        "Import Quran.Foundation Uthmani tajweed markup bound to QF word positions. "
        "Any unknown rule or word mismatch on any of the 6236 verses aborts the import."
    )

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Download and validate everything without writing to the database.",
        )

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        try:
            result = sync_quran_foundation_tajweed(dry_run=options["dry_run"])
        except QuranFoundationError as exc:
            raise CommandError(str(exc)) from exc
        if options["dry_run"]:
            status = "validated, nothing written"
        else:
            status = "published" if result.changed else "unchanged"
        self.stdout.write(
            self.style.SUCCESS(
                f"Tajweed {status}: {result.ayahs} ayahs, {result.words} words with rules, "
                f"{result.fragments} rule fragments, checksum {result.checksum_sha256[:12]}."
            )
        )
