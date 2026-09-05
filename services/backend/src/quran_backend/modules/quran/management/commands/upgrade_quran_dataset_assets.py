from __future__ import annotations

from pathlib import Path
from typing import Any

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.quran.dataset_asset_upgrade import (
    QuranDatasetAssetUpgradeError,
    upgrade_quran_dataset_assets,
)
from quran_backend.modules.quran.importer import QuranDatasetError, validate_quran_dataset
from quran_backend.modules.quran.mushaf_publication import (
    MushafPublicationError,
    load_prepared_mushaf_catalog,
)


class Command(BaseCommand):
    help = "Create a complete Quran dataset with a new immutable Mushaf rendition set."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("source_dataset", type=Path)
        parser.add_argument("asset_manifest", type=Path)
        parser.add_argument("output", type=Path)
        parser.add_argument("--content-version", required=True, dest="content_version")

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        try:
            source = validate_quran_dataset(options["source_dataset"])
            catalog = load_prepared_mushaf_catalog(
                options["asset_manifest"],
                media_root=Path(settings.MEDIA_ROOT),
            )
            upgraded = upgrade_quran_dataset_assets(
                source,
                catalog,
                output=options["output"],
                version_value=options["content_version"],
            )
        except (
            MushafPublicationError,
            QuranDatasetAssetUpgradeError,
            QuranDatasetError,
            OSError,
        ) as exc:
            raise CommandError(str(exc)) from exc

        self.stdout.write(
            self.style.SUCCESS(
                f"Prepared complete Quran dataset {upgraded.manifest['edition']['code']}@"
                f"{upgraded.manifest['edition']['version']} with "
                f"{len(upgraded.pages)} multi-resolution pages."
            )
        )
