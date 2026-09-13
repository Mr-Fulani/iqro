from __future__ import annotations

from decimal import Decimal
from typing import Any
from uuid import uuid4

import pytest
from django.core.exceptions import ValidationError

from quran_backend.modules.quran.models import AyahPageMapping, AyahPageRegion, MushafPage


@pytest.mark.django_db
def test_logical_page_mapping_cannot_cross_canonical_versions(
    quran_dataset: dict[str, Any],
) -> None:
    mapping = AyahPageMapping(page=quran_dataset["page"], ayah=quran_dataset["first_ayah"])
    mapping.clean()
    mapping.page.edition_version_id = uuid4()
    with pytest.raises(ValidationError, match="same Quran edition"):
        mapping.clean()


@pytest.mark.django_db
def test_page_rejects_unsafe_asset_path(quran_dataset: dict[str, Any]) -> None:
    page = MushafPage(
        edition_version=quran_dataset["version"],
        number=2,
        image_width=100,
        image_height=100,
        checksum_sha256="c" * 64,
        asset_variants=[
            {
                "format": "webp",
                "width": 100,
                "height": 100,
                "path": "../secret.webp",
                "sha256": "c" * 64,
                "bytes": 100,
            }
        ],
    )

    with pytest.raises(ValidationError, match="safe relative paths"):
        page.full_clean()


@pytest.mark.django_db
def test_region_rejects_box_outside_page(quran_dataset: dict[str, Any]) -> None:
    region = AyahPageRegion(
        page=quran_dataset["page"],
        ayah=quran_dataset["second_ayah"],
        reading_order=2,
        polygon=[[0.8, 0.1], [1.0, 0.1], [1.0, 0.2]],
        x=Decimal("0.8"),
        y=Decimal("0.1"),
        width=Decimal("0.3"),
        height=Decimal("0.1"),
    )

    with pytest.raises(ValidationError, match="must fit within the page"):
        region.full_clean()
