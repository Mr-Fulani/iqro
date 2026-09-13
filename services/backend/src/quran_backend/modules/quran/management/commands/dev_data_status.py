from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError, CommandParser
from django.db.models import Count, F, Q

from quran_backend.modules.audio.selectors import public_recitations
from quran_backend.modules.dua.models import DuaCollection, DuaPublicationStatus
from quran_backend.modules.quran.models import Ayah, PublicationStatus, QuranEdition
from quran_backend.modules.quran.publication import _validate_complete_version
from quran_backend.modules.quran.rendition_api import visible_releases
from quran_backend.modules.quran.selectors import public_quran_foundation_mushafs
from quran_backend.modules.tafsirs.selectors import published_tafsir_editions
from quran_backend.modules.translations.selectors import published_translation_editions

DUA_CATALOGS = (
    ("hisn-al-muslim", 267, "hisn_al_muslim_full_v1.json"),
    ("supplications-from-quran", 54, "supplications_from_quran_jmapps_v1.json"),
)


def canonical_status() -> str:
    edition = (
        QuranEdition.objects.select_related("active_version")
        .filter(code="madani-hafs", active_version__status=PublicationStatus.PUBLISHED)
        .first()
    )
    if edition is None or edition.active_version is None:
        return "Canonical Quran missing"
    version = edition.active_version
    try:
        _validate_complete_version(version)
    except ValueError as exc:
        return str(exc)
    if (
        version.page_count != 604
        or version.surah_count != 114
        or Ayah.objects.filter(surah__edition_version=version).count() != 6236
    ):
        return "Canonical corpus must contain 114 surahs, 604 pages and 6236 ayahs"
    return ""


def mobile_status() -> str:
    release = visible_releases().filter(rendition__code="kfgqpc-hafs").first()
    if release is None or release.page_count != 604 or release.pages.count() != 604:
        return "Mobile pages missing or source changed"
    root = Path(settings.MEDIA_ROOT).resolve()
    try:
        for page in release.pages.all().iterator():
            if not page.assets or [asset["width"] for asset in page.assets] != release.widths:
                return f"Incomplete local artwork: page {page.number}"
            for asset in page.assets:
                path = (root / asset["path"]).resolve()
                if not path.is_relative_to(root) or path.stat().st_size != asset["bytes"]:
                    return f"Missing/incomplete local artwork: page {page.number}"
                with path.open("rb") as stream:
                    if hashlib.file_digest(stream, "sha256").hexdigest() != asset["sha256"]:
                        return f"Local artwork checksum differs: page {page.number}"
    except OSError, KeyError, TypeError, ValueError:
        return "Missing/invalid local artwork"
    return ""


def collect_status(*, require_mobile: bool) -> dict[str, Any]:
    errors = {"canonical": canonical_status()}
    source = public_quran_foundation_mushafs(settings.QURAN_QF_ENV).filter(source_id=5).first()
    errors["mushaf"] = (
        ""
        if source is not None
        and source.pages_count == 604
        and list(source.cached_pages.values_list("page_number", flat=True)) == list(range(1, 605))
        and not source.cached_pages.filter(words=[]).exists()
        else "QF source 5 missing/incomplete"
    )
    missing_dua = []
    for slug, minimum, snapshot in DUA_CATALOGS:
        collection = (
            DuaCollection.objects.select_related("active_version")
            .filter(slug=slug, active_version__status=DuaPublicationStatus.PUBLISHED)
            .first()
        )
        version = collection.active_version if collection else None
        if (
            version is None
            or version.entry_count < minimum
            or version.entries.count() != version.entry_count
        ):
            missing_dua.append(snapshot)
    errors["dua"] = "Dua catalog missing/incomplete" if missing_dua else ""
    translations = set(
        published_translation_editions(settings.QURAN_QF_ENV)
        .annotate(actual_count=Count("active_version__ayah_translations"))
        .filter(active_version__ayah_count=6236, actual_count=6236)
        .values_list("source_id", flat=True)
    )
    # Some provider Tafsirs intentionally cover part of the Quran. Require their
    # complete published snapshot, not a fabricated full-coverage replacement.
    tafsirs = set(
        published_tafsir_editions(settings.QURAN_QF_ENV)
        .annotate(actual_count=Count("active_version__ayah_tafsirs"))
        .filter(actual_count=F("active_version__record_count"), actual_count__gt=0)
        .values_list("source_id", flat=True)
    )
    missing_translations = sorted(set(settings.QURAN_QF_TRANSLATION_RESOURCE_IDS) - translations)
    missing_tafsirs = sorted(set(settings.QURAN_QF_TAFSIR_RESOURCE_IDS) - tafsirs)
    errors["translations"] = (
        "Translations missing/incomplete: " + ", ".join(map(str, missing_translations))
        if missing_translations
        else ""
    )
    errors["tafsirs"] = (
        "Tafsirs missing/incomplete: " + ", ".join(map(str, missing_tafsirs))
        if missing_tafsirs
        else ""
    )
    errors["audio"] = (
        ""
        if public_recitations().filter(Q(timing_segment_count__gte=6236)).exists()
        else "Complete streaming audio and ayah timings missing"
    )
    if require_mobile:
        errors["mobile"] = mobile_status()
    return {
        "ready": not any(errors.values()),
        "checks": {name: not error for name, error in errors.items()},
        "errors": {name: error for name, error in errors.items() if error},
        "missing_dua": missing_dua,
        "configured_translations": list(settings.QURAN_QF_TRANSLATION_RESOURCE_IDS),
        "configured_tafsirs": list(settings.QURAN_QF_TAFSIR_RESOURCE_IDS),
        "missing_translations": missing_translations,
        "missing_tafsirs": missing_tafsirs,
    }


class Command(BaseCommand):
    help = "Check actual local content, including configured translations, Tafsirs and audio."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("--require-mobile", action="store_true")
        parser.add_argument(
            "--json",
            action="store_true",
            help="Machine-readable report, including missing resources",
        )

    def handle(self, *_args: Any, **options: Any) -> None:
        if not (settings.DEBUG and getattr(settings, "LOCAL_DEVELOPMENT", False)):
            raise CommandError("This check is for local development settings only")
        report = collect_status(require_mobile=options["require_mobile"])
        if options["json"]:
            self.stdout.write(json.dumps(report))
            return
        for name, ready in report["checks"].items():
            self.stdout.write(f"{name}: {'ready' if ready else report['errors'][name]}")
        if not report["ready"]:
            raise CommandError(
                "; ".join(report["errors"].values()) + ". Run make up to resume setup."
            )
