from __future__ import annotations

from collections import Counter
from typing import Any

from django.core.management.base import BaseCommand, CommandParser

from quran_backend.modules.audio.mp3quran_catalog import (
    Mp3QuranCatalogClient,
    Mp3QuranCatalogError,
    apply_reciter_profiles,
    import_reading,
    plan_catalog,
    read_mp3quran_readings,
    recover_timings,
    timing_recovery_candidates,
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
        parser.add_argument(
            "--recover-timings",
            action="store_true",
            help="Retry timings of readings left listening-only, instead of adding new ones.",
        )
        parser.add_argument(
            "--apply-profiles",
            action="store_true",
            help="Write the curated reciter names and biographies, instead of adding readings.",
        )
        parser.add_argument("--limit", type=int, help="Add at most this many readings.")
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Show what would be added without reading the files or writing anything.",
        )

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        if options["apply_profiles"]:
            changed = apply_reciter_profiles()
            self.stdout.write(self.style.SUCCESS(f"done: {len(changed)} reciters updated"))
            return
        source = Mp3QuranCatalogClient()
        if options["recover_timings"]:
            self._recover_timings(source, dry_run=options["dry_run"])
            return
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

    def _recover_timings(self, source: Mp3QuranCatalogClient, *, dry_run: bool) -> None:
        candidates = timing_recovery_candidates()
        self.stdout.write(f"candidates: {len(candidates)}")
        recovered = 0
        for recitation in candidates:
            if dry_run:
                self.stdout.write(f"  {recitation.code}")
                continue
            try:
                recover_timings(recitation, source)
            except (Mp3QuranCatalogError, Mp3QuranTimingError) as exc:
                self.stderr.write(f"kept listening {recitation.code}: {exc}")
                continue
            recovered += 1
            self.stdout.write(f"recovered {recitation.code}")
        self.stdout.write(self.style.SUCCESS(f"done: {recovered} recovered"))
