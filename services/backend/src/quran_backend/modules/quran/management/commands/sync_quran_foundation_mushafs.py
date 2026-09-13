from __future__ import annotations

from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.audio.quran_foundation import QuranFoundationError
from quran_backend.modules.quran.quran_foundation_sync import sync_quran_foundation_mushafs


class Command(BaseCommand):
    help = "Synchronize every public Quran.Foundation Mushaf snapshot and checkpoint."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument(
            "--source-id",
            type=int,
            action="append",
            dest="resource_ids",
            help="Import only these Mushaf IDs with a separate checkpoint; repeat for several.",
        )
        parser.add_argument(
            "--force",
            action="store_true",
            help="Discard the saved checkpoint and bootstrap the complete catalog again.",
        )

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        try:
            result = sync_quran_foundation_mushafs(
                force=options["force"],
                resource_ids=tuple(options["resource_ids"]) if options["resource_ids"] else None,
            )
        except QuranFoundationError as exc:
            raise CommandError(str(exc)) from exc
        self.stdout.write(
            self.style.SUCCESS(
                "Quran.Foundation Mushaf sync complete: "
                f"resources={result.resources}, pages={result.pages}, words={result.words}, "
                f"removed={result.removed}, changed={str(result.changed).lower()}, "
                f"sequence={result.sync_sequence}."
            )
        )
