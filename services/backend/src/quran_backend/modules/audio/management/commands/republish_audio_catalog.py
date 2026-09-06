from __future__ import annotations

import json
from typing import Any

from django.core.exceptions import ObjectDoesNotExist, ValidationError
from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.audio.catalog_republication import republish_audio_catalog


class Command(BaseCommand):
    help = (
        "Republish an existing external audio catalog for an identical active Quran corpus. "
        "Read-only unless --apply."
    )

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("--edition", required=True)
        parser.add_argument("--source-version", required=True)
        parser.add_argument("--target-version", required=True)
        parser.add_argument("--source-release", required=True)
        parser.add_argument("--release-version", required=True)
        parser.add_argument("--apply", action="store_true")

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        try:
            result = republish_audio_catalog(
                edition_code=options["edition"],
                source_version=options["source_version"],
                target_version=options["target_version"],
                source_release=options["source_release"],
                release_version=options["release_version"],
                apply=options["apply"],
            )
        except (ObjectDoesNotExist, ValidationError) as exc:
            raise CommandError(str(exc)) from exc
        self.stdout.write(json.dumps({"applied": options["apply"], **result}, sort_keys=True))
