from __future__ import annotations

from copy import deepcopy

import pytest
from django.urls import reverse
from rest_framework.test import APIClient

from quran_backend.modules.accounts.models import User
from quran_backend.modules.dua.importer import (
    DuaSnapshotError,
    bundled_full_snapshot_path,
    bundled_starter_snapshot_path,
    import_dua_snapshot,
    load_dua_snapshot,
    validate_dua_snapshot,
)
from quran_backend.modules.dua.models import (
    DuaAudioAsset,
    DuaCollection,
    DuaCollectionVersion,
    DuaEntry,
    DuaFavorite,
    DuaPublicationStatus,
)


@pytest.mark.django_db
def test_seeded_dua_catalog_is_public_and_localized(api_client: APIClient) -> None:
    catalog = api_client.get("/api/v1/dua/collections?language=ru")
    categories = api_client.get("/api/v1/dua/categories?language=ru")
    entries = api_client.get("/api/v1/dua/entries?language=ru")

    assert catalog.status_code == 200
    assert catalog.json()[0]["slug"] == "hisn-al-muslim"
    assert catalog.json()[0]["version"] == "hisn-full-2026-08-28"
    assert catalog.json()[0]["category_count"] == 132
    assert catalog.json()[0]["entry_count"] == 267
    assert catalog.json()[0]["source"]["title"] == "Молитвы из Корана и Сунны"
    assert catalog["Cache-Control"].startswith("public")
    assert catalog["ETag"].startswith('W/"')

    assert categories.status_code == 200
    assert categories.json()[0]["title"] == "Слова поминания при пробуждении ото сна"
    assert categories.json()[0]["entry_count"] == 4

    assert entries.status_code == 200
    first = entries.json()["results"][0]
    assert first["source_number"] == 1
    assert first["translation"]["language_code"] == "ru"
    assert first["translation"]["transliteration"].startswith("Аль-хамду")
    assert first["source"]["source_url"] == "https://islamhouse.com/ru/books/888254"
    assert first["evidence"][0]["verification_status"] == "source_only"
    assert first["audio"] == [
        {
            "id": str(DuaAudioAsset.objects.get(source_number=1).id),
            "language_code": "ar",
            "provider": "hisnmuslim",
            "reader_name": "Hamad Al-Duraihem",
            "reader_name_ar": "حمد الدريهم",
            "url": "https://www.hisnmuslim.com/audio/ar/1.mp3",
            "source_url": "https://hisnmuslim.com/",
            "rights_url": "",
            "source_version": "hisnmuslim-audio-2026-08-29",
        }
    ]

    repeated_entry = DuaEntry.objects.get(
        collection_version__collection__active_version__isnull=False,
        collection_version__version="hisn-full-2026-08-28",
        source_number=106,
    )
    repeated = api_client.get(f"/api/v1/dua/entries/{repeated_entry.pk}?language=ru")
    assert repeated.status_code == 200
    assert repeated.json()["repetitions"] == 33
    assert repeated.json()["repetition_label"] == "33 · 33 · 34"

    cached = api_client.get(
        "/api/v1/dua/collections?language=ru",
        HTTP_IF_NONE_MATCH=catalog["ETag"],
    )
    assert cached.status_code == 304


@pytest.mark.django_db
def test_dua_audio_catalog_covers_every_published_entry() -> None:
    assets = DuaAudioAsset.objects.filter(
        collection__slug="hisn-al-muslim",
        is_active=True,
    )

    assert assets.count() == 267
    assert list(assets.values_list("source_number", flat=True)) == list(range(1, 268))
    assert assets.get(source_number=153).url.endswith("/153.mp3")


@pytest.mark.django_db
def test_dua_favorites_are_account_scoped_idempotent_and_removable(
    api_client: APIClient,
) -> None:
    user = User.objects.create_user()
    other_user = User.objects.create_user()
    detail_url = reverse(
        "dua-personal:favorite-detail",
        kwargs={"collection_slug": "hisn-al-muslim", "source_number": 1},
    )
    list_url = reverse("dua-personal:favorite-list")

    assert api_client.get(list_url).status_code == 401
    api_client.force_authenticate(user=user)
    created = api_client.put(detail_url, {"is_favorite": True}, format="json")
    repeated = api_client.put(detail_url, {"is_favorite": True}, format="json")
    listed = api_client.get(list_url)
    expanded = api_client.get(f"{list_url}?include=entry&language=ru")

    assert created.status_code == 200
    assert created.json()["is_favorite"] is True
    assert repeated.status_code == 200
    assert repeated.json()["id"] == created.json()["id"]
    assert listed.status_code == 200
    assert listed["Cache-Control"] == "private, no-store, max-age=0"
    assert listed.json()["results"] == [created.json()]
    expanded_favorite = expanded.json()["results"][0]
    assert expanded.status_code == 200
    assert expanded_favorite["collection"] == "hisn-al-muslim"
    assert expanded_favorite["entry"]["source_number"] == 1
    assert expanded_favorite["entry"]["category"]["title"] == (
        "Слова поминания при пробуждении ото сна"
    )
    assert expanded_favorite["entry"]["translation"]["language_code"] == "ru"
    assert expanded_favorite["entry"]["audio"][0]["url"].endswith("/1.mp3")
    assert DuaFavorite.objects.filter(user=user).count() == 1
    assert DuaFavorite.objects.filter(user=other_user).count() == 0

    invalid_include = api_client.get(f"{list_url}?include=everything")
    invalid_language = api_client.get(f"{list_url}?include=entry&language=de")
    assert invalid_include.status_code == 400
    assert invalid_language.status_code == 400

    removed = api_client.put(detail_url, {"is_favorite": False}, format="json")

    assert removed.status_code == 200
    assert removed.json()["is_favorite"] is False
    assert removed.json()["id"] is None
    assert DuaFavorite.objects.filter(user=user).count() == 0


@pytest.mark.django_db
def test_dua_favorite_rejects_unknown_published_entry(api_client: APIClient) -> None:
    api_client.force_authenticate(user=User.objects.create_user())
    response = api_client.put(
        reverse(
            "dua-personal:favorite-detail",
            kwargs={"collection_slug": "hisn-al-muslim", "source_number": 999},
        ),
        {"is_favorite": True},
        format="json",
    )

    assert response.status_code == 404
    assert response.content_type == "application/problem+json"


@pytest.mark.django_db
def test_dua_entries_support_locale_category_search_and_detail(api_client: APIClient) -> None:
    filtered = api_client.get("/api/v1/dua/entries?language=tr&category=leaving-home&q=tevekkül")

    assert filtered.status_code == 200
    assert len(filtered.json()["results"]) == 1
    item = filtered.json()["results"][0]
    assert item["slug"] == "leaving-home-trust"
    assert item["category"]["title"] == "Evden çıkarken yapılan dua"  # noqa: RUF001
    assert item["translation"]["language_code"] == "tr"
    assert item["translation"]["transliteration"] == ""

    detail = api_client.get(f"/api/v1/dua/entries/{item['id']}?language=en")
    assert detail.status_code == 200
    assert detail.json()["translation"]["meaning_text"].startswith("In the name of Allah")
    assert detail.json()["source"]["language_code"] == "en"


@pytest.mark.django_db
def test_dua_api_rejects_unsupported_language_and_hides_drafts(api_client: APIClient) -> None:
    collection = DuaCollection.objects.create(slug="editorial-draft")
    DuaCollectionVersion.objects.create(
        collection=collection,
        version="draft-1",
        checksum_sha256="f" * 64,
    )

    invalid = api_client.get("/api/v1/dua/entries?language=de")
    catalog = api_client.get("/api/v1/dua/collections?language=en")

    assert invalid.status_code == 400
    assert "language" in invalid.json()["field_errors"]
    assert [item["slug"] for item in catalog.json()] == ["hisn-al-muslim"]


@pytest.mark.django_db
def test_dua_snapshot_import_is_idempotent_and_checksum_protected() -> None:
    snapshot = load_dua_snapshot(bundled_full_snapshot_path())

    result = import_dua_snapshot(snapshot, publish=True)

    assert result.created is False
    assert result.published is True
    assert result.category_count == 132
    assert result.entry_count == 267

    modified = deepcopy(snapshot)
    modified["sources"][0]["title"] = "Changed after publication"
    with pytest.raises(DuaSnapshotError, match="different checksum"):
        import_dua_snapshot(modified, publish=True)


@pytest.mark.django_db
def test_dua_snapshot_import_publishes_new_version_and_withdraws_previous() -> None:
    snapshot = load_dua_snapshot(bundled_starter_snapshot_path())
    snapshot["version"] = "hisn-starter-test-v2"

    result = import_dua_snapshot(snapshot, publish=True)

    collection = DuaCollection.objects.get(slug="hisn-al-muslim")
    previous = DuaCollectionVersion.objects.get(version="hisn-full-2026-08-28")
    assert result.created is True
    assert result.published is True
    assert collection.active_version is not None
    assert collection.active_version.version == "hisn-starter-test-v2"
    assert previous.status == DuaPublicationStatus.WITHDRAWN
    assert DuaEntry.objects.filter(collection_version=collection.active_version).count() == 10


def test_dua_snapshot_requires_all_supported_languages() -> None:
    snapshot = load_dua_snapshot(bundled_full_snapshot_path())
    snapshot["entries"][0]["translations"] = snapshot["entries"][0]["translations"][:-1]

    with pytest.raises(DuaSnapshotError, match="missing translations: tr"):
        validate_dua_snapshot(snapshot)


def test_full_dua_snapshot_has_complete_numbering_and_locales() -> None:
    snapshot = load_dua_snapshot(bundled_full_snapshot_path())

    assert snapshot["version"] == "hisn-full-2026-08-28"
    assert [item["source_number"] for item in snapshot["categories"]] == list(range(1, 133))
    assert [item["source_number"] for item in snapshot["entries"]] == list(range(1, 268))
    assert all(
        {translation["language"] for translation in item["translations"]}
        == {"ar", "en", "ru", "tr"}
        for item in [*snapshot["categories"], *snapshot["entries"]]
    )
    assert snapshot["entries"][105]["repetition_label"] == "33 · 33 · 34"
    validate_dua_snapshot(snapshot)
