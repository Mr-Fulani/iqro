from __future__ import annotations

from decimal import Decimal
from typing import Any

import pytest
from django.test import override_settings
from django.urls import reverse
from rest_framework.test import APIClient

from quran_backend.modules.quran.models import AyahPageRegion, QuranEdition


@pytest.mark.django_db
def test_edition_list_exposes_only_active_published_version(
    api_client: APIClient,
    quran_dataset: dict[str, Any],
) -> None:
    response = api_client.get(reverse("quran:edition-list"))

    assert response.status_code == 200
    payload = response.json()
    assert len(payload) == 1
    assert payload[0]["code"] == "madani-hafs"
    assert payload[0]["active_version"]["version"] == "1.0.0"
    assert "status" not in payload[0]["active_version"]


@pytest.mark.django_db
def test_draft_edition_is_not_public(api_client: APIClient) -> None:
    QuranEdition.objects.create(
        code="draft",
        name_ar="مسودة",
        name_en="Draft",
        name_ru="Черновик",
        riwayah="Hafs 'an Asim",
        source_name="Test",
        license_name="Test",
    )

    response = api_client.get(reverse("quran:edition-detail", kwargs={"edition": "draft"}))

    assert response.status_code == 404
    assert response.content_type == "application/problem+json"


@pytest.mark.django_db
def test_surah_list_contains_first_page(
    api_client: APIClient,
    quran_dataset: dict[str, Any],
) -> None:
    response = api_client.get(reverse("quran:surah-list", kwargs={"edition": "madani-hafs"}))

    assert response.status_code == 200
    assert response.json()[0]["first_page"] == 1


@pytest.mark.django_db
def test_ayah_detail_contains_stable_reference(
    api_client: APIClient,
    quran_dataset: dict[str, Any],
) -> None:
    response = api_client.get(
        reverse(
            "quran:ayah-detail",
            kwargs={"edition": "madani-hafs", "surah": 1, "ayah": 1},
        )
    )

    assert response.status_code == 200
    assert response.json() == {
        "id": str(quran_dataset["first_ayah"].id),
        "edition_code": "madani-hafs",
        "content_version": "1.0.0",
        "surah_number": 1,
        "number": 1,
        "text_uthmani": "بِسْمِ اللَّهِ",
        "juz_number": 1,
        "hizb_number": 1,
        "rub_el_hizb_number": 1,
        "pages": [1],
    }


@pytest.mark.django_db
def test_ayah_pages_do_not_repeat_for_multiline_regions(
    api_client: APIClient,
    quran_dataset: dict[str, Any],
) -> None:
    AyahPageRegion.objects.create(
        page=quran_dataset["page"],
        ayah=quran_dataset["first_ayah"],
        reading_order=2,
        polygon=[[0.1, 0.3], [0.9, 0.3], [0.9, 0.4], [0.1, 0.4]],
        x=Decimal("0.1"),
        y=Decimal("0.3"),
        width=Decimal("0.8"),
        height=Decimal("0.1"),
    )

    response = api_client.get(
        reverse(
            "quran:ayah-detail",
            kwargs={"edition": "madani-hafs", "surah": 1, "ayah": 1},
        )
    )

    assert response.status_code == 200
    assert response.json()["pages"] == [1]


@pytest.mark.django_db
def test_page_returns_public_assets_and_regions(
    api_client: APIClient,
    quran_dataset: dict[str, Any],
) -> None:
    response = api_client.get(
        reverse("quran:page-detail", kwargs={"edition": "madani-hafs", "page": 1})
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["assets"][0]["url"].endswith("/media/quran/madani-hafs/1.0.0/pages/001.webp")
    assert "path" not in payload["assets"][0]
    assert payload["regions"][0]["ayah"] == {
        "id": str(quran_dataset["first_ayah"].id),
        "surah": 1,
        "number": 1,
    }


@pytest.mark.django_db
@override_settings(PUBLIC_MEDIA_BASE_URL="https://media.example.test")
def test_canonical_mushaf_offline_manifest_is_complete_and_integrity_bound(
    api_client: APIClient,
    quran_dataset: dict[str, Any],
) -> None:
    version = quran_dataset["version"]
    version.page_count = 1
    version.save(update_fields=["page_count", "updated_at"])
    url = reverse(
        "quran:edition-offline-manifest",
        kwargs={"edition": quran_dataset["edition"].code},
    )

    response = api_client.get(url, {"width": 1024})

    assert response.status_code == 200
    manifest = response.json()
    assert manifest["package_id"] == "quran-edition-madani-hafs-1.0.0-w1024"
    assert manifest["publication_checksum_sha256"] == "a" * 64
    assert manifest["mushaf"]["edition_code"] == "madani-hafs"
    assert manifest["mushaf"]["source_id"] is None
    assert manifest["page_count"] == 1
    assert manifest["total_bytes"] == 100_000
    assert manifest["pages"][0]["asset"] == {
        "url": "https://media.example.test/quran/madani-hafs/1.0.0/pages/001.webp",
        "file_name": "page-001-1024.webp",
        "content_type": "image/webp",
        "width": 1024,
        "height": 1536,
        "bytes": 100_000,
        "sha256": "b" * 64,
    }
    assert "path" not in str(manifest)

    unavailable = api_client.get(url, {"width": 640})
    assert unavailable.status_code == 404


@pytest.mark.django_db
def test_quran_api_supports_conditional_etag(
    api_client: APIClient,
    quran_dataset: dict[str, Any],
) -> None:
    url = reverse("quran:edition-list")
    first_response = api_client.get(url)

    second_response = api_client.get(url, headers={"If-None-Match": first_response.headers["ETag"]})

    assert second_response.status_code == 304
    assert second_response.headers["ETag"] == first_response.headers["ETag"]
    assert second_response.headers["Cache-Control"].startswith("public")


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("route_name", "expected"),
    [
        ("quran:juz-list", {"number": 1}),
        ("quran:hizb-list", {"number": 1}),
        (
            "quran:rub-el-hizb-list",
            {"number": 1, "hizb_number": 1, "quarter_number": 1},
        ),
    ],
)
def test_division_navigation_exposes_canonical_boundaries_and_pages(
    api_client: APIClient,
    quran_dataset: dict[str, Any],
    route_name: str,
    expected: dict[str, int],
) -> None:
    response = api_client.get(reverse(route_name, kwargs={"edition": "madani-hafs"}))

    assert response.status_code == 200
    payload = response.json()
    assert len(payload) == 1
    for key, value in expected.items():
        assert payload[0][key] == value
    assert payload[0]["start_ayah"] == {
        "id": str(quran_dataset["first_ayah"].id),
        "surah": 1,
        "number": 1,
    }
    assert payload[0]["end_ayah"] == {
        "id": str(quran_dataset["second_ayah"].id),
        "surah": 1,
        "number": 2,
    }
    assert payload[0]["start_page"] == 1
    assert payload[0]["end_page"] == 1
