from __future__ import annotations

from typing import Any

from django.core.exceptions import ImproperlyConfigured
from django.core.management.base import BaseCommand, CommandError, CommandParser
from django.db.models import Q

from quran_backend.modules.audio.models import Reciter
from quran_backend.modules.audio.portrait_upload import (
    ReciterPortraitUploadError,
    portrait_uploader,
    store_reciter_portrait_variants,
)
from quran_backend.modules.audio.serializers import public_audio_url
from quran_backend.modules.core.content_revalidation import enqueue_reciter_content_change
from quran_backend.modules.core.object_storage import ObjectStorageError


class Command(BaseCommand):
    help = (
        "Store the 640 px and 320 px WebP copies of reciter portraits uploaded before they "
        "were generated on upload. Originals stay untouched. Read-only unless --apply."
    )

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("--apply", action="store_true")

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        reciters = (
            Reciter.objects.exclude(portrait_object_key="")
            .filter(Q(portrait_display_object_key="") | Q(portrait_thumbnail_object_key=""))
            .order_by("code")
        )
        if not options["apply"]:
            for reciter in reciters:
                self.stdout.write(f"{reciter.code}: {reciter.portrait_object_key}")
            self.stdout.write(f"{reciters.count()} portraits need copies; run with --apply.")
            return

        try:
            uploader = portrait_uploader()
        except ImproperlyConfigured as exc:
            raise CommandError(str(exc)) from exc
        failed = []
        for reciter in reciters:
            try:
                variants = store_reciter_portrait_variants(
                    public_audio_url(reciter.portrait_object_key),
                    original_object_key=reciter.portrait_object_key,
                    reciter_code=reciter.code,
                    uploader=uploader,
                )
            except (ReciterPortraitUploadError, ObjectStorageError, OSError) as exc:
                failed.append(reciter.code)
                self.stderr.write(f"{reciter.code}: {exc}")
                continue
            reciter.portrait_display_object_key = variants.display_object_key
            reciter.portrait_thumbnail_object_key = variants.thumbnail_object_key
            reciter.save(
                update_fields=[
                    "portrait_display_object_key",
                    "portrait_thumbnail_object_key",
                    "updated_at",
                ]
            )
            enqueue_reciter_content_change(action="updated", reciter_id=reciter.id)
            self.stdout.write(
                f"{reciter.code}: {variants.display_object_key}, {variants.thumbnail_object_key}"
            )
        if failed:
            raise CommandError(f"Copies not stored for: {', '.join(failed)}")
