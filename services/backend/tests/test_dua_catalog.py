from __future__ import annotations

from copy import deepcopy

import pytest
from rest_framework.test import APIClient

from quran_backend.modules.dua.importer import (
    DuaSnapshotError,
    bundled_starter_snapshot_path,
    import_dua_snapshot,
    load_dua_snapshot,
    validate_dua_snapshot,
)
from quran_backend.modules.dua.models import (
    DuaCollection,
    DuaCollectionVersion,
    DuaEntry,
    DuaPublicationStatus,
)


@pytest.mark.django_db
def test_seeded_dua_catalog_is_public_and_localized(api_client: APIClient) -> None:
    catalog = api_client.get("/api/v1/dua/collections?language=ru")
    categories = api_client.get("/api/v1/dua/categories?language=ru")
    entries = api_client.get("/api/v1/dua/entries?language=ru")

    assert catalog.status_code == 200
    assert catalog.json()[0]["slug"] == "hisn-al-muslim"
    assert catalog.json()[0]["entry_count"] == 10
    assert catalog.json()[0]["source"]["title"] == "Молитвы из Корана и Сунны"
    assert catalog["Cache-Control"].startswith("public")
    assert catalog["ETag"].startswith('W/"')

    assert categories.status_code == 200
    assert categories.json()[0]["title"] == "Слова поминания при пробуждении ото сна"
    assert categories.json()[0]["entry_count"] == 1

    assert entries.status_code == 200
    first = entries.json()["results"][0]
    assert first["source_number"] == 1
    assert first["translation"]["language_code"] == "ru"
    assert first["translation"]["transliteration"].startswith("Аль-хамду")
    assert first["source"]["source_url"] == "https://islamhouse.com/ru/books/888254"
    assert first["evidence"][0]["verification_status"] == "source_only"

    cached = api_client.get(
        "/api/v1/dua/collections?language=ru",
        HTTP_IF_NONE_MATCH=catalog["ETag"],
    )
    assert cached.status_code == 304


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
    snapshot = load_dua_snapshot(bundled_starter_snapshot_path())

    result = import_dua_snapshot(snapshot, publish=True)

    assert result.created is False
    assert result.published is True
    assert result.category_count == 10
    assert result.entry_count == 10

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
    previous = DuaCollectionVersion.objects.get(version="hisn-starter-2026-08-28")
    assert result.created is True
    assert result.published is True
    assert collection.active_version is not None
    assert collection.active_version.version == "hisn-starter-test-v2"
    assert previous.status == DuaPublicationStatus.WITHDRAWN
    assert DuaEntry.objects.filter(collection_version=collection.active_version).count() == 10


def test_dua_snapshot_requires_all_supported_languages() -> None:
    snapshot = load_dua_snapshot(bundled_starter_snapshot_path())
    snapshot["entries"][0]["translations"] = snapshot["entries"][0]["translations"][:-1]

    with pytest.raises(DuaSnapshotError, match="missing translations: tr"):
        validate_dua_snapshot(snapshot)
