"""Opt-in real bundle validation against a read-only staging page-map snapshot."""

from __future__ import annotations

import json
import os
from decimal import Decimal
from pathlib import Path
from typing import Any
from unittest.mock import Mock

import pytest
from django.test import override_settings

from quran_backend.modules.quran.models import (
    Ayah,
    AyahPageRegion,
    MushafPage,
    MushafRenditionPage,
    MushafRenditionRelease,
    Surah,
)
from quran_backend.modules.quran.rendition_publication import publish_rendition
from tests.test_mushaf_renditions import create_qf_source

BUNDLE = os.environ.get("IQRO_MUSHAF_FULL_BUNDLE_DIR")
MAPPING = os.environ.get("IQRO_CANONICAL_PAGE_MAPPING")


@pytest.mark.skipif(
    not BUNDLE or not MAPPING, reason="Full source bundle and canonical snapshot required"
)
@pytest.mark.django_db
@override_settings(MUSHAF_STAGING_PREVIEWS=True)
def test_full_bundle_publication_preserves_canonical_ids(quran_dataset: dict[str, Any]) -> None:
    assert BUNDLE
    assert MAPPING
    mapping = json.loads(Path(MAPPING).read_text())["mapping"]
    pairs = {(s, a) for _, s, a in mapping}
    assert len(pairs) == 6236
    version = quran_dataset["version"]
    # Test-owned canonical records only. No live database or text import.
    Surah.objects.bulk_create(
        [
            Surah(
                edition_version=version,
                number=s,
                name_ar="اختبار",
                name_en="Fixture",
                name_ru="Тест",
                revelation_type="meccan",
                ayah_count=max(a for ss, a in pairs if ss == s),
            )
            for s in range(2, 115)
        ]
    )
    surahs = {s.number: s for s in Surah.objects.filter(edition_version=version)}
    Ayah.objects.bulk_create(
        [
            Ayah(
                surah=surahs[s],
                number=a,
                text_uthmani="اختبار",
                text_search="fixture",
                juz_number=1,
                hizb_number=1,
                rub_el_hizb_number=1,
            )
            for s, a in sorted(pairs)
            if (s, a) not in {(1, 1), (1, 2)}
        ]
    )
    ayahs = {(s, a): pk for s, a, pk in Ayah.objects.values_list("surah__number", "number", "id")}
    MushafPage.objects.bulk_create(
        [
            MushafPage(
                edition_version=version,
                number=n,
                image_width=1000,
                image_height=1600,
                checksum_sha256="a" * 64,
                asset_variants=[],
            )
            for n in range(2, 605)
        ]
    )
    pages = dict(MushafPage.objects.values_list("number", "id"))
    AyahPageRegion.objects.bulk_create(
        [
            AyahPageRegion(
                page_id=pages[n],
                ayah_id=ayahs[(s, a)],
                reading_order=index + 10,
                x=Decimal("0.1"),
                y=Decimal("0.1"),
                width=Decimal("0.8"),
                height=Decimal("0.1"),
                polygon=[[0.1, 0.1], [0.9, 0.1], [0.9, 0.2]],
            )
            for index, (n, s, a) in enumerate(mapping)
        ]
    )
    uploader = Mock()
    manifest = Path(BUNDLE) / "manifest.json"
    if json.loads(manifest.read_bytes())["edition"] == "kfgqpc-hafs":
        create_qf_source()
    assert publish_rendition(manifest, uploader=uploader, validate_only=True) is None
    uploader.upload_path.assert_not_called()
    assert not MushafRenditionRelease.objects.exists()
    release = publish_rendition(manifest, uploader=uploader)
    assert release is not None
    assert release.canonical_version_id == version.pk
    assert MushafRenditionPage.objects.filter(release=release).count() == 604
    assert uploader.upload_path.call_count == 1812
    after = {(s, a): pk for s, a, pk in Ayah.objects.values_list("surah__number", "number", "id")}
    assert after == ayahs
    for page in release.pages.all():
        for region in page.regions:
            ref = region["ayah"]
            assert ref["id"] == str(ayahs[(ref["surah"], ref["number"])])
