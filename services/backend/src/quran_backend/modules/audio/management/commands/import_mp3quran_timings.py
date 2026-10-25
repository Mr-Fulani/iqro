from __future__ import annotations

from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.audio.models import RecitationEdition
from quran_backend.modules.audio.mp3quran_timings import (
    Mp3QuranTimingError,
    import_mp3quran_timings,
    prepare_mp3quran_timings,
)


class Command(BaseCommand):
    help = (
        "Attach MP3Quran ayah timings to a recitation whose surah files come from an "
        "MP3Quran folder, after checking every file is the MP3Quran one."
    )

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("code", help="RecitationEdition code, e.g. idris-abkar-murattal.")
        parser.add_argument(
            "--recitation-version",
            dest="recitation_version",
            help="Recitation version; required when the code has several.",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Check the files and timings without writing anything.",
        )

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        recitations = RecitationEdition.objects.filter(code=options["code"])
        if options["recitation_version"]:
            recitations = recitations.filter(version=options["recitation_version"])
        found = list(recitations.select_related("quran_edition_version__edition"))
        if not found:
            raise CommandError("No recitation has this code and version.")
        if len(found) > 1:
            versions = ", ".join(sorted(item.version for item in found))
            raise CommandError(f"Several versions exist ({versions}); pass --recitation-version.")
        recitation = found[0]
        try:
            prepared = prepare_mp3quran_timings(recitation)
            if options["dry_run"]:
                self.stdout.write(
                    f"{recitation}: files match MP3Quran read {prepared.read.read_id}; "
                    f"{len(prepared.tracks)} surahs, {prepared.ayah_count} ayahs ready. "
                    "Nothing written (--dry-run)."
                )
                return
            result = import_mp3quran_timings(prepared)
        except Mp3QuranTimingError as exc:
            raise CommandError(str(exc)) from exc
        self.stdout.write(
            self.style.SUCCESS(
                f"{recitation}: timing version {result.timing_version.version} attached to "
                f"{result.surah_count} surahs, {result.ayah_count} ayahs."
            )
        )
