from __future__ import annotations

from pathlib import Path
from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.audio.media_contract import (
    AudioMediaContractError,
    record_audio_media_contract,
)


class Command(BaseCommand):
    help = "Record a successful bounded CDN contract report for draft audio renditions."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("report", type=Path)

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        try:
            result = record_audio_media_contract(options["report"])
        except AudioMediaContractError as exc:
            raise CommandError(str(exc)) from exc
        self.stdout.write(
            self.style.SUCCESS(
                f"Recorded CDN contract evidence for {result.verified} audio rendition(s) "
                f"from {result.generated_at.isoformat()}."
            )
        )
