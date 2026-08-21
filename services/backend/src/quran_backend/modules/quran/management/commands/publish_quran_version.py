from __future__ import annotations

from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.quran.publication import (
    QuranPublicationError,
    publish_quran_version,
)


class Command(BaseCommand):
    help = "Validate and publish a complete imported Quran version."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("--edition", default="madani-hafs", help="Quran edition code.")
        parser.add_argument("--content-version", default="1.0.0", dest="content_version")
        parser.add_argument(
            "--activate",
            action="store_true",
            help="Make the published version active for public API reads.",
        )

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        try:
            result = publish_quran_version(
                edition_code=options["edition"],
                version_value=options["content_version"],
                activate=options["activate"],
            )
        except QuranPublicationError as exc:
            raise CommandError(str(exc)) from exc
        actions = ["validated"]
        if result.published:
            actions.append("published")
        if result.activated:
            actions.append("activated")
        self.stdout.write(self.style.SUCCESS(f"{result.version}: {', '.join(actions)}."))
