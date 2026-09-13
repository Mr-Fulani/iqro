from __future__ import annotations

from pathlib import Path
from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.quran.rendition_publication import publish_rendition


class Command(BaseCommand):
    help = (
        "Validate all 604 pages and connect a local or preview visual Mushaf, "
        "preserving canonical/audio data."
    )

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("manifest", type=Path)
        parser.add_argument("--validate-only", action="store_true")
        parser.add_argument("--upload-workers", type=int, choices=(1, 2, 3, 4), default=1)

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        try:
            release = publish_rendition(
                options["manifest"],
                validate_only=options["validate_only"],
                upload_workers=options["upload_workers"],
            )
        except (ValueError, OSError, KeyError, TypeError) as exc:
            raise CommandError(str(exc)) from exc
        self.stdout.write(
            self.style.SUCCESS(
                "604 pages verified; no writes"
                if release is None
                else f"Mushaf rendition connected: {release}",
            )
        )
