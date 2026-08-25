from __future__ import annotations

from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.audio.models import RecitationEdition
from quran_backend.modules.audio.quran_foundation import (
    QuranFoundationClient,
    QuranFoundationError,
)
from quran_backend.modules.audio.quran_foundation_importer import (
    compatible_quran_foundation_reciter_ids,
    import_quran_foundation_recitation,
    prepare_quran_foundation_recitation,
)
from quran_backend.modules.quran.models import QuranEdition


class Command(BaseCommand):
    help = "Import versioned Quran.Foundation chapter audio and ayah timings."

    def add_arguments(self, parser: CommandParser) -> None:
        reciters = parser.add_mutually_exclusive_group(required=True)
        reciters.add_argument(
            "--reciter-id",
            action="append",
            type=int,
            dest="reciter_ids",
            help="Quran.Foundation chapter-reciter ID; repeat for multiple variants.",
        )
        reciters.add_argument(
            "--all-reciters",
            action="store_true",
            help="Import every chapter-reciter compatible with the selected Quran edition.",
        )
        surah_selection = parser.add_mutually_exclusive_group()
        surah_selection.add_argument(
            "--surah",
            action="append",
            type=int,
            dest="surahs",
            help="Surah number to import; repeat as needed. Defaults to surah 1 for a pilot.",
        )
        surah_selection.add_argument(
            "--all-surahs",
            action="store_true",
            help="Import all 114 surahs for every selected reciter.",
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
        parser.add_argument(
            "--resume",
            action="store_true",
            help="Skip reciters that already have this local content version.",
        )
        parser.add_argument(
            "--confirm-full-catalog",
            action="store_true",
            help="Required with --all-reciters --all-surahs to confirm the bounded bulk import.",
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
            if (
                options["all_reciters"]
                and options["all_surahs"]
                and not options["confirm_full_catalog"]
            ):
                raise QuranFoundationError(
                    "--confirm-full-catalog is required with --all-reciters --all-surahs."
                )
            surahs = list(range(1, 115)) if options["all_surahs"] else options["surahs"] or [1]
            catalogs = {
                language: client.list_chapter_reciters(language=language)
                for language in ("en", "ar", "ru")
            }
            reciter_ids = options["reciter_ids"] or []
            if options["all_reciters"]:
                reciter_ids = compatible_quran_foundation_reciter_ids(
                    catalogs["en"],
                    quran_version=quran_version,
                )
            if not reciter_ids:
                raise QuranFoundationError(
                    "No Quran.Foundation chapter reciters match the selected edition."
                )

            created = 0
            existing = 0
            failed: list[int] = []
            for reciter_id in reciter_ids:
                if (
                    options["resume"]
                    and RecitationEdition.objects.filter(
                        code__startswith=f"qf-{reciter_id}-",
                        version=options["content_version"],
                        quran_edition_version=quran_version,
                    ).exists()
                ):
                    existing += 1
                    self.stdout.write(f"Skipping Quran.Foundation reciter {reciter_id}: exists.")
                    continue
                self.stdout.write(f"Preparing Quran.Foundation reciter {reciter_id}...")
                try:
                    prepared = prepare_quran_foundation_recitation(
                        client,
                        reciter_id=reciter_id,
                        surah_numbers=surahs,
                        quran_version=quran_version,
                        localized_catalogs=catalogs,
                    )
                    result = import_quran_foundation_recitation(
                        prepared,
                        quran_version=quran_version,
                        content_version=options["content_version"],
                        environment_name=client.environment.name,
                        publish=options["publish"],
                    )
                except QuranFoundationError as exc:
                    if not options["all_reciters"]:
                        raise
                    failed.append(reciter_id)
                    self.stderr.write(
                        self.style.ERROR(
                            f"Quran.Foundation reciter {reciter_id} failed validation: {exc}"
                        )
                    )
                    continue
                outcome = "created" if result.created else "already exists"
                created += int(result.created)
                existing += int(not result.created)
                status = result.recitation.status
                self.stdout.write(
                    self.style.SUCCESS(
                        f"{result.recitation} {outcome}: {len(prepared.tracks)} surah track(s), "
                        f"status={status}."
                    )
                )
            self.stdout.write(
                f"Quran.Foundation catalog result: selected={len(reciter_ids)}, "
                f"created={created}, existing={existing}, failed={len(failed)}."
            )
            if failed:
                raise QuranFoundationError(
                    "Full catalog import was incomplete for reciter IDs: "
                    + ", ".join(str(source_id) for source_id in failed)
                )
        except QuranEdition.DoesNotExist as exc:
            raise CommandError("The selected Quran edition does not exist.") from exc
        except QuranFoundationError as exc:
            raise CommandError(str(exc)) from exc
