from __future__ import annotations

from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.audio.quran_foundation import (
    QuranFoundationClient,
    QuranFoundationError,
)
from quran_backend.modules.audio.quran_foundation_importer import (
    import_quran_foundation_recitation,
    prepare_quran_foundation_recitation,
)
from quran_backend.modules.quran.models import QuranEdition


class Command(BaseCommand):
    help = "Import versioned Quran.Foundation chapter audio and ayah timings."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument(
            "--reciter-id",
            action="append",
            type=int,
            required=True,
            dest="reciter_ids",
            help="Quran.Foundation chapter-reciter ID; repeat for multiple variants.",
        )
        parser.add_argument(
            "--surah",
            action="append",
            type=int,
            dest="surahs",
            help="Surah number to import; repeat as needed. Defaults to surah 1 for a pilot.",
        )
        parser.add_argument(
            "--content-version",
            required=True,
            help="Immutable local recitation version, for example 2026.08.21-prelive.",
        )
        parser.add_argument(
            "--edition",
            default="madani-hafs",
            help="Active Quran edition to which the audio timings are bound.",
        )
        parser.add_argument(
            "--publish",
            action="store_true",
            help="Publish after validation. External tracks remain streaming-only.",
        )

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        try:
            edition = QuranEdition.objects.select_related("active_version").get(
                code=options["edition"]
            )
            quran_version = edition.active_version
            if quran_version is None:
                raise QuranFoundationError("The selected Quran edition has no active version.")
            client = QuranFoundationClient.from_environment()
            surahs = options["surahs"] or [1]
            for reciter_id in options["reciter_ids"]:
                self.stdout.write(f"Preparing Quran.Foundation reciter {reciter_id}...")
                prepared = prepare_quran_foundation_recitation(
                    client,
                    reciter_id=reciter_id,
                    surah_numbers=surahs,
                    quran_version=quran_version,
                )
                result = import_quran_foundation_recitation(
                    prepared,
                    quran_version=quran_version,
                    content_version=options["content_version"],
                    environment_name=client.environment.name,
                    publish=options["publish"],
                )
                outcome = "created" if result.created else "already exists"
                status = result.recitation.status
                self.stdout.write(
                    self.style.SUCCESS(
                        f"{result.recitation} {outcome}: {len(prepared.tracks)} surah track(s), "
                        f"status={status}."
                    )
                )
        except QuranEdition.DoesNotExist as exc:
            raise CommandError("The selected Quran edition does not exist.") from exc
        except QuranFoundationError as exc:
            raise CommandError(str(exc)) from exc
