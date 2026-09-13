from __future__ import annotations

from decimal import Decimal
from typing import Any

import pytest
from django.utils import timezone
from rest_framework.test import APIClient

from quran_backend.modules.quran.models import (
    Ayah,
    AyahPageMapping,
    AyahPageRegion,
    Hizb,
    Juz,
    MushafPage,
    PublicationStatus,
    QuranEdition,
    QuranEditionVersion,
    RevelationType,
    RubElHizb,
    Surah,
)


@pytest.fixture
def api_client() -> APIClient:
    return APIClient()


@pytest.fixture
def quran_dataset(db: None) -> dict[str, Any]:
    edition = QuranEdition.objects.create(
        code="madani-hafs",
        name_ar="مصحف المدينة",
        name_en="Madani Mushaf",
        name_ru="Мединский мусхаф",
        riwayah="Hafs 'an Asim",
        source_name="Approved test source",
        license_name="Test license",
    )
    version = QuranEditionVersion.objects.create(
        edition=edition,
        version="1.0.0",
        checksum_sha256="a" * 64,
        status=PublicationStatus.PUBLISHED,
        page_count=604,
        surah_count=114,
        juz_count=30,
        hizb_count=1,
        rub_el_hizb_count=1,
        published_at=timezone.now(),
    )
    edition.active_version = version
    edition.full_clean()
    edition.save(update_fields=["active_version", "updated_at"])
    surah = Surah.objects.create(
        edition_version=version,
        number=1,
        name_ar="الفاتحة",
        name_en="Al-Fatihah",
        name_ru="Аль-Фатиха",
        revelation_type=RevelationType.MECCAN,
        ayah_count=2,
    )
    first_ayah = Ayah.objects.create(
        surah=surah,
        number=1,
        text_uthmani="بِسْمِ اللَّهِ",
        text_search="بسم الله",
        juz_number=1,
        hizb_number=1,
        rub_el_hizb_number=1,
    )
    second_ayah = Ayah.objects.create(
        surah=surah,
        number=2,
        text_uthmani="الْحَمْدُ لِلَّهِ",
        text_search="الحمد لله",
        juz_number=1,
        hizb_number=1,
        rub_el_hizb_number=1,
    )
    page = MushafPage.objects.create(
        edition_version=version,
        number=1,
        image_width=1024,
        image_height=1536,
        checksum_sha256="b" * 64,
        asset_variants=[
            {
                "format": "webp",
                "width": 1024,
                "height": 1536,
                "path": "quran/madani-hafs/1.0.0/pages/001.webp",
                "sha256": "b" * 64,
                "bytes": 100_000,
            }
        ],
    )
    AyahPageRegion.objects.create(
        page=page,
        ayah=first_ayah,
        reading_order=1,
        polygon=[[0.1, 0.1], [0.9, 0.1], [0.9, 0.2], [0.1, 0.2]],
        x=Decimal("0.1"),
        y=Decimal("0.1"),
        width=Decimal("0.8"),
        height=Decimal("0.1"),
    )
    AyahPageRegion.objects.create(
        page=page,
        ayah=second_ayah,
        reading_order=2,
        polygon=[[0.1, 0.3], [0.9, 0.3], [0.9, 0.4], [0.1, 0.4]],
        x=Decimal("0.1"),
        y=Decimal("0.3"),
        width=Decimal("0.8"),
        height=Decimal("0.1"),
    )
    AyahPageMapping.objects.bulk_create(
        [
            AyahPageMapping(page=page, ayah=first_ayah),
            AyahPageMapping(page=page, ayah=second_ayah),
        ]
    )
    Juz.objects.create(
        edition_version=version,
        number=1,
        start_ayah=first_ayah,
        end_ayah=second_ayah,
    )
    hizb = Hizb.objects.create(
        edition_version=version,
        number=1,
        start_ayah=first_ayah,
        end_ayah=second_ayah,
    )
    rub_el_hizb = RubElHizb.objects.create(
        edition_version=version,
        hizb=hizb,
        number=1,
        start_ayah=first_ayah,
        end_ayah=second_ayah,
    )
    return {
        "edition": edition,
        "version": version,
        "surah": surah,
        "first_ayah": first_ayah,
        "second_ayah": second_ayah,
        "page": page,
        "hizb": hizb,
        "rub_el_hizb": rub_el_hizb,
    }
