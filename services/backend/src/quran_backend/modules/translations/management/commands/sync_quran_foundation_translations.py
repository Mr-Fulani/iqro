from __future__ import annotations

from typing import Any

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.audio.quran_foundation import QuranFoundationError
from quran_backend.modules.translations.quran_foundation_sync import (
    sync_quran_foundation_translations,
)


class Command(BaseCommand):
    help = "Synchronize configured Quran translations from Quran.Foundation Content Sync."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument(
            "--resource-id",
            action="append",
            type=int,
            dest="resource_ids",
            help="Quran.Foundation translation ID. Repeat to import multiple editions.",
        )
        parser.add_argument(
            "--force",
            action="store_true",
            help="Discard the saved checkpoint and bootstrap the configured resources.",
        )

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        resource_ids = tuple(options["resource_ids"] or settings.QURAN_QF_TRANSLATION_RESOURCE_IDS)
        try:
            result = sync_quran_foundation_translations(
                resource_ids=resource_ids,
                force=options["force"],
            )
        except QuranFoundationError as exc:
            raise CommandError(str(exc)) from exc
        self.stdout.write(
            self.style.SUCCESS(
                f"Translations synchronized: {result.editions} active editions, "
                f"{result.versions_created} new versions, "
                f"{result.ayahs_imported} ayahs imported, "
                f"sequence {result.sync_sequence}."
            )
        )
