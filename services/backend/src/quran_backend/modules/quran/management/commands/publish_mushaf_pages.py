from __future__ import annotations

from pathlib import Path
from typing import Any

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.core.object_storage import ObjectStorageError
from quran_backend.modules.quran.mushaf_publication import (
    MushafPublicationError,
    load_prepared_mushaf_catalog,
    publish_prepared_mushaf_catalog,
    upload_prepared_mushaf_catalog,
)


class Command(BaseCommand):
    help = (
        "Verify prepared Mushaf WebP assets, register all 604 pages, and optionally activate them."
    )

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("manifest", type=Path, help="Path to prepared manifest.json.")
        parser.add_argument("--edition", default="madani-hafs", help="Quran edition code.")
        parser.add_argument(
            "--content-version",
            default="mushaf-pages-1.0.0",
            dest="content_version",
            help="Page-only edition version.",
        )
        parser.add_argument(
            "--activate",
            action="store_true",
            help="Publish the page-only version and make it active for the edition.",
        )
        parser.add_argument(
            "--upload",
            action="store_true",
            help="Create or verify every immutable page object before database publication.",
        )

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        if options["activate"] and settings.MEDIA_OBJECT_STORAGE_REQUIRED and not options["upload"]:
            raise CommandError(
                "Production activation requires --upload to verify immutable object storage."
            )
        try:
            catalog = load_prepared_mushaf_catalog(
                options["manifest"],
                media_root=Path(settings.MEDIA_ROOT),
            )
            upload_result = None
            if options["upload"]:
                upload_result = upload_prepared_mushaf_catalog(
                    catalog,
                    media_root=Path(settings.MEDIA_ROOT),
                )
            result = publish_prepared_mushaf_catalog(
                catalog,
                edition_code=options["edition"],
                version_value=options["content_version"],
                activate=options["activate"],
            )
        except (MushafPublicationError, ObjectStorageError, OSError) as exc:
            raise CommandError(str(exc)) from exc

        outcome = "created" if result.created else "already exists"
        state = "published and active" if result.activated else "draft"
        self.stdout.write(
            self.style.SUCCESS(
                f"Mushaf page version {result.version} {outcome}: "
                f"{len(catalog.pages)} verified pages, {state}."
            )
        )
        if upload_result is not None:
            self.stdout.write(
                self.style.SUCCESS(
                    "Immutable media: "
                    f"assets={upload_result.assets}, created={upload_result.created}, "
                    f"verified_existing={upload_result.verified_existing}."
                )
            )
