from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

import pytest
from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.core.management.base import CommandError
from django.db import connection
from django.db.migrations.executor import MigrationExecutor
from django.test import override_settings
from django.utils import timezone

from quran_backend.modules.dua.models import DuaCollection
from quran_backend.modules.quran import corpus_import
from quran_backend.modules.quran.models import (
    Ayah,
    AyahPageMapping,
    AyahPageRegion,
    QuranEdition,
    QuranFoundationMushaf,
    QuranFoundationMushafPage,
)
from quran_backend.modules.reading.models import ReadingPosition


@pytest.mark.django_db
@override_settings(DEBUG=True, LOCAL_DEVELOPMENT=True)
def test_readiness_distinguishes_missing_corpus_dua_and_mobile(
    corpus: tuple[Path, QuranFoundationMushaf],
) -> None:
    with pytest.raises(CommandError, match="Canonical Quran missing"):
        call_command("dev_data_status")
    with override_settings(DEBUG=False):
        corpus_import.import_canonical_corpus(corpus[0])
    DuaCollection.objects.update(active_version=None)
    with pytest.raises(CommandError, match="Dua catalog missing"):
        call_command("dev_data_status")
    for snapshot in ("hisn_al_muslim_full_v1.json", "supplications_from_quran_jmapps_v1.json"):
        path = Path(__file__).resolve().parents[1] / "src/quran_backend/modules/dua/data" / snapshot
        call_command("import_dua_catalog", path, "--publish")
    call_command("dev_data_status")
    with pytest.raises(CommandError, match="Mobile pages missing"):
        call_command("dev_data_status", "--require-mobile")
    with override_settings(DEBUG=False), pytest.raises(CommandError, match="local development"):
        call_command("dev_data_status")


@pytest.fixture
def corpus(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, db: None
) -> tuple[Path, QuranFoundationMushaf]:
    # Synthetic structure only: never published outside this isolated test DB.
    surahs, verses = [], []
    for surah in range(1, 115):
        rows = []
        for number in range(1, (55 if surah <= 80 else 54) + 1):
            index = len(verses)
            rows.append(
                {
                    "number": number,
                    "text": f"fixture {surah}:{number}",
                    "juz": index * 30 // 6236 + 1,
                    "hizb": index * 60 // 6236 + 1,
                    "hizb_quarter": index * 240 // 6236 + 1,
                }
            )
            verses.append((surah, number))
        surahs.append(
            {
                "number": surah,
                "name_arabic": "fixture",
                "name_transliteration": "fixture",
                "revelation": {"type": "Meccan"},
                "ayahs": rows,
            }
        )
    raw = json.dumps({"surahs": surahs}).encode()
    path = tmp_path / "corpus.json"
    path.write_bytes(raw)
    monkeypatch.setattr(corpus_import, "CORPUS_SHA256", hashlib.sha256(raw).hexdigest())
    source = QuranFoundationMushaf.objects.create(
        source_id=5,
        environment=settings.QURAN_QF_ENV,
        name="KFGQPC",
        qirat_name="Hafs",
        pages_count=604,
        lines_per_page=15,
        default_font_name="fixture",
        mapping_mode="fixture",
        schema_version="1",
        sync_sequence=1,
        source_checksum_sha256="a" * 64,
        last_synced_at=timezone.now(),
    )
    pages = []
    for number in range(1, 605):
        members = verses[(number - 1) * 6236 // 604 : number * 6236 // 604]
        mapping: dict[str, str] = {}
        for surah in sorted({s for s, _ in members}):
            ids = [a for s, a in members if s == surah]
            mapping[str(surah)] = f"{ids[0]}-{ids[-1]}"
        pages.append(
            QuranFoundationMushafPage(
                mushaf=source,
                source_id=number,
                page_number=number,
                verse_mapping=mapping,
                verses_count=len(members),
            )
        )
    QuranFoundationMushafPage.objects.bulk_create(pages)
    return path, source


@pytest.mark.django_db
def test_corpus_import_is_complete_without_images_and_repeat_preserves_ids(
    corpus: tuple[Path, QuranFoundationMushaf],
) -> None:
    path, _ = corpus
    version = corpus_import.import_canonical_corpus(path)
    pages = list(version.pages.values_list("number", "id"))
    ayahs = list(Ayah.objects.values_list("id", "text_uthmani"))
    assert len(pages) == 604
    assert len(ayahs) == 6236
    assert version.surahs.count() == 114
    assert version.juz.count() == 30
    assert version.hizb.count() == 60
    assert version.rub_el_hizb.count() == 240
    assert AyahPageMapping.objects.count() == 6236
    assert not AyahPageRegion.objects.exists()
    assert all(page.asset_variants == [] for page in version.pages.all())
    assert corpus_import.import_canonical_corpus(path).pk == version.pk
    assert list(version.pages.values_list("number", "id")) == pages
    assert list(Ayah.objects.values_list("id", "text_uthmani")) == ayahs


@pytest.mark.django_db
def test_corpus_rejects_changed_text_without_replacing_existing_data(
    corpus: tuple[Path, QuranFoundationMushaf],
) -> None:
    path, _ = corpus
    version = corpus_import.import_canonical_corpus(path)
    first = Ayah.objects.order_by("surah__number", "number").first()
    assert first is not None
    first.text_uthmani = "existing different content"
    first.save()
    with pytest.raises(ValueError, match="Existing canonical corpus differs"):
        corpus_import.import_canonical_corpus(path)
    first.refresh_from_db()
    assert first.text_uthmani == "existing different content"
    assert QuranEdition.objects.get(code="madani-hafs").active_version_id == version.pk


@pytest.mark.django_db
@pytest.mark.parametrize("fault", ["missing-page", "unknown-verse", "gap", "checksum"])
def test_incomplete_sources_never_publish(
    corpus: tuple[Path, QuranFoundationMushaf], fault: str
) -> None:
    path, source = corpus
    if fault == "checksum":
        path.write_bytes(path.read_bytes() + b" ")
    elif fault == "missing-page":
        source.cached_pages.filter(page_number=604).delete()
    else:
        page = source.cached_pages.get(page_number=1)
        page.verse_mapping = {"115": "1"} if fault == "unknown-verse" else {"1": "1,3"}
        page.save()
    with pytest.raises(ValueError, match=r"checksum|coverage|Unknown|Non-contiguous"):
        corpus_import.import_canonical_corpus(path)
    assert not QuranEdition.objects.exists()
    assert not Ayah.objects.exists()


@pytest.mark.django_db(transaction=True)
def test_page_mapping_migration_preserves_reading_position_and_deduplicates(
    quran_dataset: dict[str, Any],
) -> None:
    user = get_user_model().objects.create_user(email="mapping-migration@example.test")
    position = ReadingPosition.objects.create(
        user=user,
        edition=quran_dataset["edition"],
        page=quran_dataset["page"],
        ayah=quran_dataset["first_ayah"],
        client_updated_at=timezone.now(),
        revision=7,
    )
    before = (position.page_id, position.ayah_id, position.revision)
    executor = MigrationExecutor(connection)
    executor.migrate([("quran", "0006_rendition_source_metadata")])
    try:
        region = AyahPageRegion.objects.first()
        assert region is not None
        region.pk = None
        region.reading_order += 100
        region.save()
    finally:
        MigrationExecutor(connection).migrate([("quran", "0007_canonical_page_mapping")])
    position.refresh_from_db()
    assert (position.page_id, position.ayah_id, position.revision) == before
    assert AyahPageMapping.objects.count() == 2
    assert AyahPageRegion.objects.count() == 3
