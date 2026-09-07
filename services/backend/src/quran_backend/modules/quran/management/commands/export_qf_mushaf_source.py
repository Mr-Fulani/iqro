"""Read-only public-content snapshot for reproducible native page preparation."""

from __future__ import annotations

import json
from typing import Any

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import connection, transaction

from quran_backend.modules.quran.models import QuranEdition, QuranFoundationMushaf, Surah


class Command(BaseCommand):
    help = "Export existing QF Hafs words/layout to stdout; no credentials or user data."

    def add_arguments(self, parser: Any) -> None:
        parser.add_argument("--mushaf", type=int, choices=(1, 5, 19), required=True)

    def handle(self, *_args: Any, **options: Any) -> None:
        with transaction.atomic():
            if connection.vendor == "postgresql":
                with connection.cursor() as cursor:
                    cursor.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
            source = QuranFoundationMushaf.objects.filter(
                environment=settings.QURAN_QF_ENV,
                source_id=options["mushaf"],
                is_available=True,
            ).first()
            canonical = (
                QuranEdition.objects.select_related("active_version")
                .filter(code="madani-hafs")
                .first()
            )
            if source is None or canonical is None or canonical.active_version is None:
                raise CommandError("Published source and canonical Quran are required.")
            payload: dict[str, Any] = {
                "schema_version": 1,
                "source_id": source.source_id,
                "source_checksum_sha256": source.source_checksum_sha256,
                "name": source.name,
                "qirat_name": source.qirat_name,
                "pages_count": source.pages_count,
                "lines_per_page": source.lines_per_page,
                "surahs": list(
                    Surah.objects.filter(edition_version=canonical.active_version)
                    .order_by("number")
                    .values("number", "name_ar", "ayah_count")
                ),
                "pages": list(
                    source.cached_pages.order_by("page_number").values(
                        "page_number", "verse_mapping", "words"
                    )
                ),
            }
            if len(payload["pages"]) != source.pages_count:
                raise CommandError("Incomplete source pages; no snapshot exported.")
            self.stdout.write(
                json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
            )
