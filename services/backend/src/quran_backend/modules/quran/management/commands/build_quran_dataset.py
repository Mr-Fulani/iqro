from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.quran.dataset_builder import (
    QuranDatasetBuildError,
    build_madani_hafs_dataset,
    build_quran_dataset,
    load_quran_dataset_build_spec,
)


class Command(BaseCommand):
    help = "Build a checksummed Quran edition dataset from pinned local sources."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("corpus", type=Path, help="Pinned quran.json corpus path.")
        parser.add_argument("polygons", type=Path, help="Directory containing page JSON files.")
        parser.add_argument("asset_manifest", type=Path, help="Prepared page manifest.json.")
        parser.add_argument("output", type=Path, help="Output directory for the import dataset.")
        parser.add_argument(
            "--spec",
            type=Path,
            help=(
                "Checksummed edition build spec. Without it, the pinned legacy "
                "madani-hafs profile is used."
            ),
        )

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        try:
            arguments = {
                "corpus_path": options["corpus"],
                "polygons_dir": options["polygons"],
                "asset_manifest_path": options["asset_manifest"],
                "output": options["output"],
            }
            if options["spec"] is None:
                result = build_madani_hafs_dataset(**arguments)
            else:
                result = build_quran_dataset(
                    spec=load_quran_dataset_build_spec(options["spec"]),
                    **arguments,
                )
        except (OSError, json.JSONDecodeError, QuranDatasetBuildError) as exc:
            raise CommandError(str(exc)) from exc
        self.stdout.write(
            self.style.SUCCESS(
                f"Built {result.output} ({result.content_sha256}); "
                f"{result.page_mapping_differences} source page mappings were resolved "
                "by the configured authoritative geometry."
            )
        )
