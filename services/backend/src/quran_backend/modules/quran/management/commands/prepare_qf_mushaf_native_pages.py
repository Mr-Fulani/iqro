from __future__ import annotations

from pathlib import Path
from typing import Any

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.core.object_storage import ObjectStorageError
from quran_backend.modules.quran.models import QuranFoundationMushaf
from quran_backend.modules.quran.quran_foundation_native import (
    DEFAULT_NATIVE_WIDTHS,
    ExternalCommandQuranFoundationRenderer,
    QuranFoundationNativeError,
    prepare_quran_foundation_native_pages,
)


class Command(BaseCommand):
    help = (
        "Render and upload a bounded, resumable batch of immutable native "
        "Quran.Foundation Mushaf page assets."
    )

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("--mushaf", type=int, required=True, help="QF Mushaf resource ID.")
        parser.add_argument(
            "--render-version",
            required=True,
            help="Immutable lowercase rendition version, for example chromium-1.0.0.",
        )
        parser.add_argument(
            "--renderer",
            type=Path,
            required=True,
            help="Pinned external renderer executable implementing the documented JSON contract.",
        )
        parser.add_argument("--first-page", type=int, default=1)
        parser.add_argument("--limit", type=int, default=25)
        parser.add_argument(
            "--widths",
            default=",".join(str(width) for width in DEFAULT_NATIVE_WIDTHS),
            help="Comma-separated lossless WebP widths.",
        )

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        try:
            widths = tuple(int(value) for value in options["widths"].split(","))
            mushaf = QuranFoundationMushaf.objects.get(
                environment=settings.QURAN_QF_ENV,
                source_id=options["mushaf"],
                is_available=True,
            )
            result = prepare_quran_foundation_native_pages(
                mushaf,
                render_version=options["render_version"],
                renderer=ExternalCommandQuranFoundationRenderer(options["renderer"]),
                first_page=options["first_page"],
                limit=options["limit"],
                widths=widths,
            )
        except QuranFoundationMushaf.DoesNotExist as exc:
            raise CommandError("Requested Quran.Foundation Mushaf is not available.") from exc
        except (QuranFoundationNativeError, ObjectStorageError, OSError, ValueError) as exc:
            raise CommandError(str(exc)) from exc

        self.stdout.write(
            self.style.SUCCESS(
                "Native Mushaf batch prepared: "
                f"requested={result.requested_pages}, rendered={result.rendered_pages}, "
                f"resumed={result.resumed_pages}, created_assets={result.created_assets}, "
                f"verified_assets={result.verified_assets}, "
                f"coverage={result.publication.prepared_pages}/"
                f"{result.publication.expected_pages}."
            )
        )
