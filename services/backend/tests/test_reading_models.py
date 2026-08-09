from __future__ import annotations

from typing import Any

import pytest
from django.core.exceptions import ValidationError
from django.utils import timezone

from quran_backend.modules.accounts.models import Device, DevicePlatform, User
from quran_backend.modules.quran.models import (
    MushafPage,
    PublicationStatus,
    QuranEdition,
    QuranEditionVersion,
)
from quran_backend.modules.reading.models import Bookmark, ReadingPosition


@pytest.mark.django_db
def test_reading_position_rejects_page_from_another_edition(
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    other_edition = QuranEdition.objects.create(
        code="other-hafs",
        name_ar="اختبار",
        name_en="Other",
        name_ru="Другой",
        riwayah="Hafs 'an Asim",
        source_name="Test",
        license_name="Test",
    )
    other_version = QuranEditionVersion.objects.create(
        edition=other_edition,
        version="1.0.0",
        checksum_sha256="c" * 64,
        status=PublicationStatus.PUBLISHED,
        published_at=timezone.now(),
    )
    other_edition.active_version = other_version
    other_edition.save(update_fields=["active_version", "updated_at"])
    other_page = MushafPage.objects.create(
        edition_version=other_version,
        number=1,
        image_width=100,
        image_height=100,
        checksum_sha256="d" * 64,
        asset_variants=[
            {
                "format": "webp",
                "width": 100,
                "height": 100,
                "path": "test/001.webp",
                "sha256": "d" * 64,
                "bytes": 100,
            }
        ],
    )
    position = ReadingPosition(
        user=user,
        edition=quran_dataset["edition"],
        page=other_page,
        client_updated_at=timezone.now(),
    )

    with pytest.raises(ValidationError, match="selected Quran edition"):
        position.full_clean()


@pytest.mark.django_db
def test_bookmark_rejects_device_owned_by_another_user(
    quran_dataset: dict[str, Any],
) -> None:
    owner = User.objects.create_user()
    another_user = User.objects.create_user()
    another_device = Device.objects.create(
        user=another_user,
        platform=DevicePlatform.WEB,
        installation_id_hash="f" * 64,
    )
    bookmark = Bookmark(
        user=owner,
        edition=quran_dataset["edition"],
        page=quran_dataset["page"],
        client_updated_at=timezone.now(),
        device=another_device,
    )

    with pytest.raises(ValidationError, match="same user"):
        bookmark.full_clean()
