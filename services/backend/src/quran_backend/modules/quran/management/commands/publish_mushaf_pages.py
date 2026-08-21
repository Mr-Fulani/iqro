from __future__ import annotations

from pathlib import Path
from typing import Any

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.quran.mushaf_publication import (
    MushafPublicationError,
    load_prepared_mushaf_catalog,
    publish_prepared_mushaf_catalog,
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

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        try:
            catalog = load_prepared_mushaf_catalog(
                options["manifest"],
                media_root=Path(settings.MEDIA_ROOT),
            )
            result = publish_prepared_mushaf_catalog(
                catalog,
                edition_code=options["edition"],
                version_value=options["content_version"],
                activate=options["activate"],
            )
        except (MushafPublicationError, OSError) as exc:
            raise CommandError(str(exc)) from exc

        outcome = "created" if result.created else "already exists"
        state = "published and active" if result.activated else "draft"
        self.stdout.write(
            self.style.SUCCESS(
                f"Mushaf page version {result.version} {outcome}: "
                f"{len(catalog.pages)} verified pages, {state}."
            )
        )
