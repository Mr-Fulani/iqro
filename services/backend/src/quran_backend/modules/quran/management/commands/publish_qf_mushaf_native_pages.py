from __future__ import annotations

from typing import Any

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.quran.models import QuranFoundationMushaf
from quran_backend.modules.quran.quran_foundation_native import (
    QuranFoundationNativeError,
    publish_quran_foundation_native_pages,
)


class Command(BaseCommand):
    help = (
        "Validate and activate one complete QF native page rendition, or explicitly "
        "reactivate a previously published version for rollback."
    )

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("--mushaf", type=int, required=True, help="QF Mushaf resource ID.")
        parser.add_argument("--render-version", required=True)
        parser.add_argument(
            "--activate-existing",
            action="store_true",
            help="Rollback by reactivating an already published immutable rendition.",
        )

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        try:
            mushaf = QuranFoundationMushaf.objects.get(
                environment=settings.QURAN_QF_ENV,
                source_id=options["mushaf"],
                is_available=True,
            )
            result = publish_quran_foundation_native_pages(
                mushaf,
                render_version=options["render_version"],
                activate_existing=options["activate_existing"],
            )
        except QuranFoundationMushaf.DoesNotExist as exc:
            raise CommandError("Requested Quran.Foundation Mushaf is not available.") from exc
        except QuranFoundationNativeError as exc:
            raise CommandError(str(exc)) from exc

        outcome = "activated" if result.activated else "already active"
        self.stdout.write(
            self.style.SUCCESS(
                f"Native Mushaf rendition {result.publication.render_version} {outcome}; "
                f"manifest={result.publication.manifest_checksum_sha256}."
            )
        )
