from __future__ import annotations

from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.audio.quran_foundation import QuranFoundationError
from quran_backend.modules.audio.quran_foundation_ayah_sync import (
    sync_quran_foundation_ayah_recitations,
)
from quran_backend.modules.quran.models import QuranEdition


class Command(BaseCommand):
    help = "Sync all Quran.Foundation ayah-by-ayah streaming recitations."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument(
            "--edition",
            default="madani-hafs",
            help="Active Hafs Quran edition to which verse keys are bound.",
        )

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        try:
            edition = QuranEdition.objects.select_related("active_version").get(
                code=options["edition"]
            )
            quran_version = edition.active_version
            if quran_version is None:
                raise QuranFoundationError("The selected Quran edition has no active version.")
            result = sync_quran_foundation_ayah_recitations(quran_version=quran_version)
        except QuranEdition.DoesNotExist as exc:
            raise CommandError("The selected Quran edition does not exist.") from exc
        except QuranFoundationError as exc:
            raise CommandError(str(exc)) from exc

        self.stdout.write(
            self.style.SUCCESS(
                "Quran.Foundation ayah catalog result: "
                f"selected={result.selected}, available={result.available}, "
                f"created={result.created}, updated={result.updated}, "
                f"unchanged={result.unchanged}, chapters={result.chapters}, "
                f"audio_files={result.audio_files}, "
                f"delivery_samples={result.delivery_samples}, "
                f"failed={len(result.failures)}."
            )
        )
        if result.failures:
            for source_id, error in result.failures:
                self.stderr.write(
                    self.style.ERROR(
                        f"Quran.Foundation ayah recitation {source_id} failed: {error}"
                    )
                )
            raise CommandError(
                "Ayah catalog sync was incomplete for source IDs: "
                + ", ".join(str(source_id) for source_id, _error in result.failures)
            )
