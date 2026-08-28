from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

import pytest
from django.test import override_settings
from rest_framework.test import APIClient

from quran_backend.modules.audio.quran_foundation import (
    ENVIRONMENTS,
    QuranFoundationError,
    QuranFoundationTranslationSyncResult,
)
from quran_backend.modules.translations.models import (
    AyahTranslation,
    QuranFoundationTranslationSyncState,
    TranslationEdition,
    TranslationEditionVersion,
)
from quran_backend.modules.translations.quran_foundation_sync import (
    sync_quran_foundation_translations,
    translation_plain_text,
)


class FakeTranslationClient:
    environment = ENVIRONMENTS["production"]

    def __init__(
        self,
        *,
        mutations: tuple[dict[str, Any], ...] | None = None,
        expected_token: str = "",
        snapshot: dict[str, Any] | None = None,
    ) -> None:
        self.mutations = mutations if mutations is not None else (_create_mutation(),)
        self.expected_token = expected_token
        self.snapshot = snapshot or _snapshot()
        self.snapshot_requests: list[int] = []

    def list_translations(self, *, language: str = "en") -> list[dict[str, Any]]:
        assert language == "en"
        return [
            {
                "id": 45,
                "name": "Elmir Kuliev",
                "author_name": "Elmir Kuliev",
                "slug": "quran.ru.kuliev",
                "language_name": "russian",
            }
        ]

    def sync_translation_catalog(
        self,
        resource_ids: tuple[int, ...],
        *,
        sync_token: str = "",
    ) -> QuranFoundationTranslationSyncResult:
        assert resource_ids == (45,)
        assert sync_token == self.expected_token
        next_token = "translation-checkpoint-2" if sync_token else "translation-checkpoint-1"
        return QuranFoundationTranslationSyncResult(
            next_sync_token=next_token,
            sync_until_sequence=1409 if sync_token else 1408,
            mutations=self.mutations,
        )

    def get_translation_snapshot(self, resource_id: int) -> dict[str, Any]:
        assert resource_id == 45
        self.snapshot_requests.append(resource_id)
        return self.snapshot


class MultiTranslationClient(FakeTranslationClient):
    def __init__(self) -> None:
        super().__init__()
        self.sync_requests: list[tuple[int, ...]] = []

    def list_translations(self, *, language: str = "en") -> list[dict[str, Any]]:
        rows = super().list_translations(language=language)
        return [
            {
                "id": 20,
                "name": "Saheeh International",
                "author_name": "Saheeh International",
                "slug": "en-sahih-international",
                "language_name": "english",
            },
            *rows,
        ]

    def sync_translation_catalog(
        self,
        resource_ids: tuple[int, ...],
        *,
        sync_token: str = "",
    ) -> QuranFoundationTranslationSyncResult:
        assert sync_token == ""
        assert len(resource_ids) == 1
        self.sync_requests.append(resource_ids)
        resource_id = resource_ids[0]
        return QuranFoundationTranslationSyncResult(
            next_sync_token=f"checkpoint-{resource_id}",
            sync_until_sequence=1_400 + resource_id,
            mutations=(
                {
                    "sequence": 1_400 + resource_id,
                    "type": "RESOURCE_CREATE",
                    "resource_group": "translations",
                    "resource_id": resource_id,
                    "snapshot_url": (f"/api/v4/resources/snapshots/translations/{resource_id}"),
                },
            ),
        )

    def get_translation_snapshot(self, resource_id: int) -> dict[str, Any]:
        snapshot = _snapshot()
        snapshot["resource_id"] = resource_id
        snapshot["resource_content_id"] = resource_id
        snapshot["sync_sequence"] = 1_400 + resource_id
        for record in snapshot["records"]:
            record["resource_id"] = resource_id
            record["resource_content_id"] = resource_id
        return snapshot


def _create_mutation() -> dict[str, Any]:
    return {
        "sequence": 1408,
        "type": "RESOURCE_CREATE",
        "resource_group": "translations",
        "resource_id": 45,
        "snapshot_url": "/api/v4/resources/snapshots/translations/45",
    }


def _snapshot() -> dict[str, Any]:
    return {
        "resource_group": "translations",
        "resource_id": 45,
        "resource_content_id": 45,
        "schema_version": 1,
        "sync_sequence": 1408,
        "records": [
            {
                "id": 256690,
                "resource_id": 45,
                "resource_content_id": 45,
                "verse_key": "1:1",
                "text": "Во имя <b>Аллаха</b><sup foot_note=1>1</sup>",  # noqa: RUF001
                "foot_notes": [{"id": 1, "text": "<b>Примечание</b>"}],
            },
            {
                "id": 256691,
                "resource_id": 45,
                "resource_content_id": 45,
                "verse_key": "1:2",
                "text": "Хвала Аллаху",
                "foot_notes": [],
            },
        ],
    }


@pytest.mark.django_db
def test_bootstrap_publishes_immutable_translation_and_checkpoint() -> None:
    now = datetime(2026, 8, 28, 10, tzinfo=UTC)

    result = sync_quran_foundation_translations(
        resource_ids=(45,),
        client=FakeTranslationClient(),
        now=now,
        expected_verse_keys={"1:1", "1:2"},
    )

    assert result.editions == 1
    assert result.versions_created == 1
    assert result.ayahs_imported == 2
    edition = TranslationEdition.objects.get(source_id=45)
    assert edition.language_code == "ru"
    assert edition.active_version is not None
    assert edition.active_version.status == "published"
    assert edition.active_version.published_at == now
    first = AyahTranslation.objects.get(edition_version=edition.active_version, verse_key="1:1")
    assert first.text == "Во имя Аллаха [1]"  # noqa: RUF001
    assert "<b>" in first.source_text
    assert first.foot_notes == [{"id": 1, "text": "Примечание"}]
    state = QuranFoundationTranslationSyncState.objects.get(environment="production")
    assert state.sync_token == "translation-checkpoint-1"
    assert state.last_success_at == now


@pytest.mark.django_db
def test_bootstrap_generates_stable_slug_when_provider_slug_is_blank() -> None:
    client = FakeTranslationClient()
    original_list = client.list_translations

    def list_without_slug(*, language: str = "en") -> list[dict[str, Any]]:
        rows = original_list(language=language)
        rows[0]["slug"] = ""
        return rows

    client.list_translations = list_without_slug  # type: ignore[method-assign]

    sync_quran_foundation_translations(
        resource_ids=(45,),
        client=client,
        expected_verse_keys={"1:1", "1:2"},
    )

    assert TranslationEdition.objects.get().slug == "quran-foundation-translation-45"


@pytest.mark.django_db
def test_incremental_no_change_keeps_version_and_advances_checkpoint() -> None:
    sync_quran_foundation_translations(
        resource_ids=(45,),
        client=FakeTranslationClient(),
        expected_verse_keys={"1:1", "1:2"},
    )
    client = FakeTranslationClient(mutations=(), expected_token="translation-checkpoint-1")

    result = sync_quran_foundation_translations(resource_ids=(45,), client=client)

    assert result.changed is False
    assert result.versions_created == 0
    assert client.snapshot_requests == []
    assert TranslationEditionVersion.objects.count() == 1
    state = QuranFoundationTranslationSyncState.objects.get(environment="production")
    assert state.sync_token == "translation-checkpoint-2"


@pytest.mark.django_db
def test_empty_provider_bootstrap_self_heals_missing_local_translation() -> None:
    client = FakeTranslationClient(mutations=())

    result = sync_quran_foundation_translations(
        resource_ids=(45,),
        client=client,
        expected_verse_keys={"1:1", "1:2"},
    )

    assert result.versions_created == 1
    assert client.snapshot_requests == [45]
    assert TranslationEdition.objects.get(source_id=45).active_version is not None


@pytest.mark.django_db
def test_multiple_editions_use_independent_content_sync_checkpoints() -> None:
    client = MultiTranslationClient()

    result = sync_quran_foundation_translations(
        resource_ids=(45, 20),
        client=client,
        expected_verse_keys={"1:1", "1:2"},
    )

    assert result.editions == 2
    assert result.versions_created == 2
    assert client.sync_requests == [(20,), (45,)]
    assert set(
        QuranFoundationTranslationSyncState.objects.values_list("resources_filter", flat=True)
    ) == {"translations:20", "translations:45"}


@pytest.mark.django_db
def test_incomplete_snapshot_does_not_publish_or_advance_checkpoint() -> None:
    snapshot = _snapshot()
    snapshot["records"] = snapshot["records"][:1]

    with pytest.raises(QuranFoundationError, match="does not match the published Quran"):
        sync_quran_foundation_translations(
            resource_ids=(45,),
            client=FakeTranslationClient(snapshot=snapshot),
            expected_verse_keys={"1:1", "1:2"},
        )

    assert not TranslationEdition.objects.exists()
    state = QuranFoundationTranslationSyncState.objects.get(environment="production")
    assert state.sync_token == ""
    assert state.consecutive_failures == 1


@pytest.mark.django_db
def test_deleted_translation_is_hidden_without_deleting_immutable_history() -> None:
    sync_quran_foundation_translations(
        resource_ids=(45,),
        client=FakeTranslationClient(),
        expected_verse_keys={"1:1", "1:2"},
    )
    deletion = {
        "sequence": 1409,
        "type": "RESOURCE_DELETE",
        "resource_group": "translations",
        "resource_id": 45,
        "snapshot_url": None,
    }

    result = sync_quran_foundation_translations(
        resource_ids=(45,),
        client=FakeTranslationClient(
            mutations=(deletion,),
            expected_token="translation-checkpoint-1",
        ),
    )

    edition = TranslationEdition.objects.get(source_id=45)
    assert result.removed == 1
    assert edition.is_available is False
    assert edition.active_version is None
    assert TranslationEditionVersion.objects.count() == 1
    assert AyahTranslation.objects.count() == 2


@pytest.mark.django_db
@override_settings(QURAN_QF_ENV="production")
def test_public_translation_catalog_and_surah_api(api_client: APIClient) -> None:
    sync_quran_foundation_translations(
        resource_ids=(45,),
        client=FakeTranslationClient(),
        expected_verse_keys={"1:1", "1:2"},
    )

    catalog = api_client.get("/api/v1/quran/translations?language=ru")
    surah = api_client.get("/api/v1/quran/translations/45/surahs/1")

    assert catalog.status_code == 200
    assert catalog.json()[0]["source_id"] == 45
    assert catalog.json()[0]["source"]["attribution"] == (
        "Quran data provided by Quran Foundation."
    )
    assert catalog["Cache-Control"].startswith("public")
    assert surah.status_code == 200
    assert [row["verse_key"] for row in surah.json()] == ["1:1", "1:2"]
    assert "source_text" not in surah.json()[0]


def test_translation_plain_text_removes_untrusted_markup() -> None:
    assert (
        translation_plain_text(
            '<p>Hello&nbsp;<script>alert("x")</script><sup>2</sup></p><p>Next</p>'
        )
        == "Hello [2]\nNext"
    )
