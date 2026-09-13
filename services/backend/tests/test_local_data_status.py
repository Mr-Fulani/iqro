from __future__ import annotations

import hashlib
import io
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from django.conf import settings
from django.core.management import call_command
from django.test import override_settings
from django.utils import timezone

from quran_backend.modules.quran.management.commands import dev_data_status as status
from quran_backend.modules.tafsirs.models import AyahTafsir, TafsirEdition, TafsirEditionVersion
from quran_backend.modules.translations.models import (
    AyahTranslation,
    TranslationEdition,
    TranslationEditionVersion,
)


@pytest.mark.django_db
@override_settings(DEBUG=True, LOCAL_DEVELOPMENT=True)
def test_json_reports_missing_content_without_secrets_or_false_readiness() -> None:
    output = io.StringIO()
    call_command("dev_data_status", "--json", "--require-mobile", stdout=output)
    report = json.loads(output.getvalue())
    assert report["ready"] is False
    assert not report["checks"]["translations"]
    assert not report["checks"]["tafsirs"]
    assert not report["checks"]["mobile"]
    assert report["missing_translations"] == sorted(settings.QURAN_QF_TRANSLATION_RESOURCE_IDS)
    assert report["missing_tafsirs"] == sorted(settings.QURAN_QF_TAFSIR_RESOURCE_IDS)
    assert "secret" not in output.getvalue().lower()


@pytest.mark.django_db
@override_settings(QURAN_QF_TRANSLATION_RESOURCE_IDS=(45,), QURAN_QF_TAFSIR_RESOURCE_IDS=(170,))
def test_readiness_requires_complete_active_snapshots_in_current_environment() -> None:
    translation = TranslationEdition.objects.create(
        environment=settings.QURAN_QF_ENV, source_id=45, slug="fixture", language_code="ru"
    )
    version = TranslationEditionVersion.objects.create(
        edition=translation,
        sync_sequence=1,
        schema_version="1",
        checksum_sha256="a" * 64,
        ayah_count=6236,
        status="published",
        published_at=timezone.now(),
    )
    translation.active_version = version
    translation.save()
    rows = [
        AyahTranslation(
            edition_version=version,
            source_id=n,
            verse_key=f"1:{n}",
            surah_number=1,
            ayah_number=n,
            text="fixture",
            source_text="fixture",
        )
        for n in range(1, 6237)
    ]
    AyahTranslation.objects.bulk_create(rows[:-1])
    assert status.collect_status(require_mobile=False)["missing_translations"] == [45]
    rows[-1].save()
    assert status.collect_status(require_mobile=False)["missing_translations"] == []
    translation.is_available = False
    translation.save()
    assert status.collect_status(require_mobile=False)["missing_translations"] == [45]
    translation.is_available = True
    translation.environment = "prelive" if settings.QURAN_QF_ENV == "production" else "production"
    translation.save()
    assert status.collect_status(require_mobile=False)["missing_translations"] == [45]

    tafsir = TafsirEdition.objects.create(
        environment=settings.QURAN_QF_ENV, source_id=170, slug="fixture", language_code="ru"
    )
    tafsir_version = TafsirEditionVersion.objects.create(
        edition=tafsir,
        sync_sequence=1,
        schema_version="1",
        checksum_sha256="b" * 64,
        record_count=1,
        covered_ayah_count=1,
        status="published",
        published_at=timezone.now(),
    )
    tafsir.active_version = tafsir_version
    tafsir.save()
    assert status.collect_status(require_mobile=False)["missing_tafsirs"] == [170]
    AyahTafsir.objects.create(
        edition_version=tafsir_version,
        source_id=1,
        verse_key="1:1",
        surah_number=1,
        ayah_number=1,
        start_verse_id=1,
        end_verse_id=1,
        start_verse_key="1:1",
        end_verse_key="1:1",
        start_surah_number=1,
        start_ayah_number=1,
        end_surah_number=1,
        end_ayah_number=1,
        group_verses_count=1,
        text="fixture",
        source_text="fixture",
    )
    # A genuinely partial source is complete as published; no fabricated coverage.
    assert status.collect_status(require_mobile=False)["missing_tafsirs"] == []
    tafsir_version.status = "withdrawn"
    tafsir_version.save()
    assert status.collect_status(require_mobile=False)["missing_tafsirs"] == [170]


def test_mobile_readiness_detects_same_size_corruption_and_missing_assets(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    artwork = tmp_path / "page.webp"
    artwork.write_bytes(b"verified")
    asset = {
        "path": artwork.name,
        "width": 720,
        "bytes": 8,
        "sha256": hashlib.sha256(b"verified").hexdigest(),
    }
    pages = Mock()
    pages.count.return_value = 604
    pages.all.return_value.iterator.side_effect = lambda: iter(
        [SimpleNamespace(number=1, assets=[asset])]
    )
    catalog = Mock()
    catalog.filter.return_value.first.return_value = SimpleNamespace(
        page_count=604, pages=pages, widths=[720]
    )
    monkeypatch.setattr(status, "visible_releases", lambda: catalog)
    with override_settings(MEDIA_ROOT=tmp_path):
        assert status.mobile_status() == ""
        artwork.write_bytes(b"modified")
        assert "checksum" in status.mobile_status()
        asset["path"] = "missing.webp"
        assert "Missing" in status.mobile_status()
        asset["path"] = "../outside.webp"
        assert "Missing" in status.mobile_status()
        pages.count.return_value = 603
        assert "Mobile pages missing" in status.mobile_status()
