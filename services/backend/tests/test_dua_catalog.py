from __future__ import annotations

import re
from copy import deepcopy
from urllib.parse import parse_qs, urlparse

import pytest
from django.contrib.postgres.indexes import GinIndex
from django.core.cache import caches
from django.urls import reverse
from django.utils import timezone
from rest_framework.request import Request
from rest_framework.test import APIClient, APIRequestFactory

from quran_backend.modules.accounts.models import User
from quran_backend.modules.core.privacy import PRIVATE_NO_STORE_CACHE_CONTROL
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
    DuaCategory,
    DuaCategoryTranslation,
    DuaCollection,
    DuaCollectionVersion,
    DuaEntry,
    DuaEntryTranslation,
    DuaFavorite,
    DuaPublicationStatus,
)
from quran_backend.modules.dua.pagination import DuaEntryCursorPagination
from quran_backend.modules.dua.throttling import DuaSearchRateThrottle


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
    assert categories.json()[0]["collection"] == "hisn-al-muslim"
    assert categories.json()[0]["collection_title"] == "Молитвы из Корана и Сунны"
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
def test_dua_search_never_matches_a_translation_from_another_locale(
    api_client: APIClient,
) -> None:
    collection = DuaCollection.objects.get(slug="hisn-al-muslim")
    entry = DuaEntry.objects.get(
        collection_version=collection.active_version,
        source_number=1,
    )
    english_meaning = "englishmeaningneedleonly"
    english_category = "englishcategoryneedleonly"
    russian_meaning = "русскийтексттолькоэтойлокали"
    russian_category = "русскаякатегориятолькоэтойлокали"
    DuaEntryTranslation.objects.filter(entry=entry, language_code="en").update(
        meaning_text=english_meaning
    )
    DuaEntryTranslation.objects.filter(entry=entry, language_code="ru").update(
        meaning_text=russian_meaning
    )
    DuaCategoryTranslation.objects.filter(category=entry.category, language_code="en").update(
        title=english_category
    )
    DuaCategoryTranslation.objects.filter(category=entry.category, language_code="ru").update(
        title=russian_category
    )

    english_meaning_result = api_client.get(
        "/api/v1/dua/entries",
        {"language": "ru", "q": english_meaning},
    )
    english_category_result = api_client.get(
        "/api/v1/dua/entries",
        {"language": "ru", "q": english_category},
    )
    russian_meaning_result = api_client.get(
        "/api/v1/dua/entries",
        {"language": "ru", "q": russian_meaning},
    )
    russian_category_result = api_client.get(
        "/api/v1/dua/entries",
        {"language": "ru", "q": russian_category},
    )

    assert english_meaning_result.status_code == 200
    assert english_meaning_result.json()["results"] == []
    assert english_category_result.status_code == 200
    assert english_category_result.json()["results"] == []
    assert russian_meaning_result.status_code == 200
    assert [item["id"] for item in russian_meaning_result.json()["results"]] == [str(entry.id)]
    assert russian_category_result.status_code == 200
    assert str(entry.id) in {item["id"] for item in russian_category_result.json()["results"]}


@pytest.mark.django_db
def test_dua_search_rejects_single_character_query(api_client: APIClient) -> None:
    response = api_client.get(
        "/api/v1/dua/entries",
        {"language": "ru", "q": "x"},
    )

    assert response.status_code == 400
    assert "q" in response.json()["field_errors"]


@pytest.mark.django_db
def test_dua_search_throttle_hashes_ip_skips_browse_and_returns_private_429(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    throttle_cache = caches["throttling"]
    throttle_cache.clear()
    monkeypatch.setattr(DuaSearchRateThrottle, "get_rate", lambda _self: "1/minute")
    remote_address = "203.0.113.91"
    request = Request(
        APIRequestFactory().get(
            "/api/v1/dua/entries",
            {"language": "en", "q": "sleep"},
            REMOTE_ADDR=remote_address,
        )
    )
    key = DuaSearchRateThrottle().get_cache_key(request, object())
    assert key is not None
    assert remote_address not in key
    assert "sleep" not in key
    assert re.fullmatch(r"throttle_dua_search_[0-9a-f]{64}", key)

    client = APIClient(REMOTE_ADDR=remote_address)
    browse_first = client.get("/api/v1/dua/entries?language=en&page_size=1")
    browse_second = client.get("/api/v1/dua/entries?language=en&page_size=1")
    first_search = client.get("/api/v1/dua/entries?language=en&q=sleep&page_size=1")
    limited = client.get("/api/v1/dua/entries?language=en&q=morning&page_size=1")

    assert browse_first.status_code == 200
    assert browse_second.status_code == 200
    assert first_search.status_code == 200
    assert limited.status_code == 429
    assert limited["Cache-Control"] == PRIVATE_NO_STORE_CACHE_CONTROL
    assert limited["Pragma"] == "no-cache"
    assert limited.json()["code"] == "dua_search_rate_limited"
    assert int(limited["Retry-After"]) >= 1
    throttle_cache.clear()


@pytest.mark.django_db
def test_dua_category_count_includes_only_entries_available_in_locale(
    api_client: APIClient,
) -> None:
    collection = DuaCollection.objects.get(slug="hisn-al-muslim")
    category = DuaCategory.objects.get(
        collection_version=collection.active_version,
        source_number=1,
    )
    total_entries = category.entries.count()
    entry_without_russian = category.entries.order_by("source_number").first()
    assert entry_without_russian is not None
    DuaEntryTranslation.objects.filter(
        entry=entry_without_russian,
        language_code="ru",
    ).delete()

    russian = api_client.get(
        "/api/v1/dua/categories",
        {"language": "ru", "collection": "hisn-al-muslim"},
    )
    english = api_client.get(
        "/api/v1/dua/categories",
        {"language": "en", "collection": "hisn-al-muslim"},
    )

    assert russian.status_code == 200
    russian_category = next(item for item in russian.json() if item["id"] == str(category.id))
    assert russian_category["entry_count"] == total_entries - 1
    assert english.status_code == 200
    english_category = next(item for item in english.json() if item["id"] == str(category.id))
    assert english_category["entry_count"] == total_entries

    DuaCategoryTranslation.objects.filter(category=category, language_code="ru").delete()
    missing_category_locale = api_client.get(
        "/api/v1/dua/categories",
        {"language": "ru", "collection": "hisn-al-muslim"},
    )
    assert str(category.id) not in {item["id"] for item in missing_category_locale.json()}


@pytest.mark.django_db
def test_dua_cursor_uses_unique_position_without_offset(api_client: APIClient) -> None:
    response = api_client.get(
        "/api/v1/dua/entries",
        {"language": "en", "page_size": 1},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["next"] is not None
    cursor_token = parse_qs(urlparse(payload["next"]).query)["cursor"][0]
    cursor_request = Request(APIRequestFactory().get("/", {"cursor": cursor_token}))
    cursor = DuaEntryCursorPagination().decode_cursor(cursor_request)
    assert cursor.offset == 0
    assert cursor.position == payload["results"][0]["id"]


def test_dua_search_fields_declare_postgresql_trigram_indexes() -> None:
    indexes = {
        index.name: index
        for model in (DuaEntry, DuaEntryTranslation, DuaCategoryTranslation)
        for index in model._meta.indexes
        if isinstance(index, GinIndex)
    }

    assert {
        name: (tuple(index.fields), tuple(index.opclasses)) for name, index in indexes.items()
    } == {
        "dua_entry_arabic_trgm_gin": (("arabic_text",), ("gin_trgm_ops",)),
        "dua_entry_meaning_trgm_gin": (("meaning_text",), ("gin_trgm_ops",)),
        "dua_entry_translit_trgm_gin": (("transliteration",), ("gin_trgm_ops",)),
        "dua_category_title_trgm_gin": (("title",), ("gin_trgm_ops",)),
    }


@pytest.mark.django_db
def test_dua_collection_filter_disambiguates_duplicate_category_slugs(
    api_client: APIClient,
) -> None:
    def create_collection(
        collection_slug: str,
        version_name: str,
        entry_slug: str,
        meaning: str,
    ) -> tuple[DuaCategory, DuaEntry]:
        collection = DuaCollection.objects.create(slug=collection_slug)
        version = DuaCollectionVersion.objects.create(
            collection=collection,
            version=version_name,
            checksum_sha256=collection_slug.ljust(64, "a"),
            status=DuaPublicationStatus.PUBLISHED,
            category_count=1,
            entry_count=1,
            published_at=timezone.now(),
        )
        collection.active_version = version
        collection.save(update_fields=("active_version", "updated_at"))
        category = DuaCategory.objects.create(
            collection_version=version,
            source_number=1,
            slug="shared-mobile-category",
            sort_order=1,
        )
        DuaCategoryTranslation.objects.create(
            category=category,
            language_code="en",
            title=f"Category from {collection_slug}",
        )
        entry = DuaEntry.objects.create(
            collection_version=version,
            category=category,
            source_number=1,
            slug=entry_slug,
            arabic_text="دعاء",
            repetitions=1,
            sort_order=1,
        )
        DuaEntryTranslation.objects.create(
            entry=entry,
            language_code="en",
            meaning_text=meaning,
        )
        return category, entry

    first_category, first_entry = create_collection(
        "mobile-first",
        "first-v1",
        "first-entry",
        "First collection meaning",
    )
    _, second_entry = create_collection(
        "mobile-second",
        "second-v1",
        "second-entry",
        "Second collection meaning",
    )

    categories = api_client.get("/api/v1/dua/categories?language=en&collection=mobile-first")
    scoped = api_client.get(
        "/api/v1/dua/entries?language=en&collection=mobile-first&category=shared-mobile-category"
    )
    category_only = api_client.get(
        "/api/v1/dua/entries?language=en&category=shared-mobile-category&page_size=100"
    )

    assert categories.status_code == 200
    assert categories.json() == [
        {
            "id": str(first_category.id),
            "collection": "mobile-first",
            "collection_title": "mobile-first",
            "collection_version": "first-v1",
            "source_number": 1,
            "slug": "shared-mobile-category",
            "title": "Category from mobile-first",
            "entry_count": 1,
        }
    ]
    assert scoped.status_code == 200
    assert [item["id"] for item in scoped.json()["results"]] == [str(first_entry.id)]
    assert scoped.json()["results"][0]["collection"] == "mobile-first"
    assert category_only.status_code == 200
    assert {item["id"] for item in category_only.json()["results"]} == {
        str(first_entry.id),
        str(second_entry.id),
    }


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("path", "field"),
    [
        ("/api/v1/dua/categories?language=en&collection=not%20a%20slug", "collection"),
        (f"/api/v1/dua/entries?language=en&collection={'a' * 101}", "collection"),
    ],
)
def test_dua_collection_filter_rejects_invalid_slug(
    api_client: APIClient,
    path: str,
    field: str,
) -> None:
    response = api_client.get(path)

    assert response.status_code == 400
    assert field in response.json()["field_errors"]


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
def test_dua_snapshot_import_publishes_new_version_and_resolves_canonical_entry(
    api_client: APIClient,
) -> None:
    collection = DuaCollection.objects.get(slug="hisn-al-muslim")
    old_entry = DuaEntry.objects.get(
        collection_version=collection.active_version,
        source_number=1,
    )
    snapshot = load_dua_snapshot(bundled_starter_snapshot_path())
    snapshot["version"] = "hisn-starter-test-v2"

    result = import_dua_snapshot(snapshot, publish=True)

    collection.refresh_from_db()
    previous = DuaCollectionVersion.objects.get(version="hisn-full-2026-08-28")
    assert result.created is True
    assert result.published is True
    assert collection.active_version is not None
    assert collection.active_version.version == "hisn-starter-test-v2"
    assert previous.status == DuaPublicationStatus.WITHDRAWN
    assert DuaEntry.objects.filter(collection_version=collection.active_version).count() == 10

    old_detail = api_client.get(f"/api/v1/dua/entries/{old_entry.id}?language=en")
    resolved = api_client.get(
        "/api/v1/dua/entries/resolve",
        {"language": "en", "collection": "hisn-al-muslim", "source_number": 1},
    )
    assert old_detail.status_code == 404
    assert resolved.status_code == 200
    assert resolved.json()["id"] != str(old_entry.id)
    assert resolved.json()["collection"] == "hisn-al-muslim"
    assert resolved.json()["collection_version"] == "hisn-starter-test-v2"
    assert resolved.json()["source_number"] == 1


@pytest.mark.django_db
@pytest.mark.parametrize(
    "query",
    [
        {},
        {"collection": "not a slug", "source_number": 1},
        {"collection": "hisn-al-muslim", "source_number": 0},
        {"collection": "hisn-al-muslim", "source_number": 32768},
    ],
)
def test_dua_canonical_resolver_validates_identity(
    api_client: APIClient,
    query: dict[str, object],
) -> None:
    response = api_client.get("/api/v1/dua/entries/resolve", query)

    assert response.status_code == 400


@pytest.mark.django_db
def test_dua_canonical_resolver_hides_unknown_identity(api_client: APIClient) -> None:
    response = api_client.get(
        "/api/v1/dua/entries/resolve",
        {"language": "en", "collection": "hisn-al-muslim", "source_number": 32767},
    )

    assert response.status_code == 404
    assert response.json()["code"] == "not_found"


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
