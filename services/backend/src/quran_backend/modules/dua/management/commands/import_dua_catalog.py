from __future__ import annotations

from pathlib import Path
from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.dua.importer import (
    DuaSnapshotError,
    bundled_starter_snapshot_path,
    import_dua_snapshot,
    load_dua_snapshot,
)


class Command(BaseCommand):
    help = "Import a versioned Dua catalog snapshot and optionally publish it."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument(
            "snapshot",
            nargs="?",
            type=Path,
            default=bundled_starter_snapshot_path(),
            help="Path to a schema_version=1 JSON snapshot (defaults to bundled starter data).",
        )
        parser.add_argument(
            "--publish",
            action="store_true",
            help="Publish the imported version and make it active.",
        )

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        try:
            snapshot = load_dua_snapshot(options["snapshot"])
            result = import_dua_snapshot(snapshot, publish=options["publish"])
        except DuaSnapshotError as exc:
            raise CommandError(str(exc)) from exc
        verb = "Imported" if result.created else "Found unchanged"
        publication = "published" if result.published else "draft"
        self.stdout.write(
            self.style.SUCCESS(
                f"{verb} {result.version}: {result.category_count} categories, "
                f"{result.entry_count} entries, {result.audio_count} audio assets, "
                f"{publication}, sha256={result.checksum_sha256}."
            )
        )
