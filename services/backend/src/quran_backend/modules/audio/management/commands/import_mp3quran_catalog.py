from __future__ import annotations

from collections import Counter
from typing import Any

from django.core.management.base import BaseCommand, CommandParser

from quran_backend.modules.audio.mp3quran_catalog import (
    Mp3QuranCatalogClient,
    Mp3QuranCatalogError,
    import_reading,
    plan_catalog,
    read_mp3quran_readings,
)
from quran_backend.modules.audio.mp3quran_timings import Mp3QuranTimingError


class Command(BaseCommand):
    help = (
        "Add the MP3Quran readings our catalog lacks; the audio stays on the MP3Quran CDN. "
        "Safe to repeat: what is already here is skipped."
    )

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument(
            "--include-untimed",
            action="store_true",
            help="Also add readings without full ayah timings, as listening-only.",
        )
        parser.add_argument("--limit", type=int, help="Add at most this many readings.")
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Show what would be added without reading the files or writing anything.",
        )

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        source = Mp3QuranCatalogClient()
        plan = plan_catalog(
            read_mp3quran_readings(source),
            include_untimed=options["include_untimed"],
        )
        for reason, count in Counter(reason for _, reason in plan.skipped).most_common():
            self.stdout.write(f"skip {count}: {reason}")
        additions = plan.additions[: options["limit"]]
        self.stdout.write(f"to add: {len(additions)} of {len(plan.additions)}")
        if options["dry_run"]:
            for reading, reciter in additions:
                kind = "timed" if reading.fully_timed else "listening"
                who = f"existing {reciter.code}" if reciter else "new reciter"
                self.stdout.write(f"  {reading.name_en} | {reading.style} | {kind} | {who}")
            return
        failed = 0
        for reading, reciter in additions:
            try:
                imported = import_reading(reading, reciter, source)
            except (Mp3QuranCatalogError, Mp3QuranTimingError) as exc:
                failed += 1
                self.stderr.write(f"failed {reading.name_en}: {exc}")
                continue
            kind = "timed" if imported.timed else "listening"
            self.stdout.write(f"added {imported.recitation.code} ({kind}) {imported.note}".rstrip())
        self.stdout.write(
            self.style.SUCCESS(f"done: {len(additions) - failed} added, {failed} failed")
        )
