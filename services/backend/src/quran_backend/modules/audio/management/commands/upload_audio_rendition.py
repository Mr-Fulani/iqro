from __future__ import annotations

import uuid
from pathlib import Path
from typing import Any

from django.core.exceptions import ImproperlyConfigured
from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.audio.media_upload import (
    AudioMediaUploadError,
    upload_audio_rendition,
)
from quran_backend.modules.core.object_storage import ObjectStorageError


class Command(BaseCommand):
    help = "Upload one draft managed AudioRendition to immutable S3-compatible storage."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("rendition_id", type=uuid.UUID)
        parser.add_argument("source", type=Path)

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        try:
            result = upload_audio_rendition(
                options["rendition_id"],
                options["source"],
            )
        except (AudioMediaUploadError, ObjectStorageError, ImproperlyConfigured, OSError) as exc:
            raise CommandError(str(exc)) from exc

        action = "created" if result.created else "verified existing"
        self.stdout.write(
            self.style.SUCCESS(
                f"Audio rendition {result.rendition_id}: {action} {result.object_key} "
                f"with ETag {result.etag}."
            )
        )
