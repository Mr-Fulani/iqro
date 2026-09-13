from pathlib import Path
from typing import Any

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.dua.models import DuaCollection, DuaPublicationStatus
from quran_backend.modules.quran.models import Ayah, PublicationStatus, QuranEdition
from quran_backend.modules.quran.publication import _validate_complete_version
from quran_backend.modules.quran.rendition_api import visible_releases
from quran_backend.modules.quran.selectors import public_quran_foundation_mushafs


class Command(BaseCommand):
    help = "Check usable local Quran, Dua and mobile artwork; never prints credentials."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("--require-mobile", action="store_true")

    def handle(self, *_args: Any, **options: Any) -> None:
        if not (settings.DEBUG and getattr(settings, "LOCAL_DEVELOPMENT", False)):
            raise CommandError("This check is for local development settings only")
        edition = (
            QuranEdition.objects.select_related("active_version")
            .filter(
                code="madani-hafs",
                active_version__status=PublicationStatus.PUBLISHED,
            )
            .first()
        )
        if edition is None or edition.active_version is None:
            raise CommandError("Canonical Quran missing. Run make dev-data after migrations.")
        version = edition.active_version
        try:
            _validate_complete_version(version)
        except ValueError as exc:
            raise CommandError(str(exc)) from exc
        if (
            version.page_count != 604
            or Ayah.objects.filter(surah__edition_version=version).count() != 6236
        ):
            raise CommandError("Canonical corpus must contain 604 pages and 6236 ayahs")
        self.stdout.write("Canonical Quran: 114 surahs, 6236 ayahs, 604 logical pages")
        source = public_quran_foundation_mushafs(settings.QURAN_QF_ENV).filter(source_id=5).first()
        if source is None or source.cached_pages.count() != 604:
            raise CommandError("QF source 5 missing/incomplete. Run make dev-data.")
        self.stdout.write("Quran.Foundation source 5: 604 pages available to web")
        for slug, minimum in (("hisn-al-muslim", 267), ("supplications-from-quran", 54)):
            collection = (
                DuaCollection.objects.select_related("active_version")
                .filter(slug=slug, active_version__status=DuaPublicationStatus.PUBLISHED)
                .first()
            )
            dua_version = collection.active_version if collection else None
            if (
                dua_version is None
                or dua_version.entry_count < minimum
                or dua_version.entries.count() != dua_version.entry_count
            ):
                raise CommandError(f"Dua catalog missing/incomplete: {slug}. Run make dev-data.")
            self.stdout.write(f"Dua {slug}: {dua_version.entry_count} published entries")
        release = visible_releases().filter(rendition__code="kfgqpc-hafs").first()
        if release is None or release.pages.count() != 604:
            message = "Mobile pages missing. Run make dev-data without --web-only."
            if options["require_mobile"]:
                raise CommandError(message)
            self.stdout.write(message)
            return
        root = Path(settings.MEDIA_ROOT).resolve()
        for page in release.pages.all().iterator():
            for asset in page.assets:
                path = (root / asset["path"]).resolve()
                if (
                    not path.is_relative_to(root)
                    or not path.is_file()
                    or path.stat().st_size != asset["bytes"]
                ):
                    raise CommandError(f"Missing/incomplete local artwork: page {page.number}")
        self.stdout.write("Mobile KFGQPC: 604 pages with local media")
