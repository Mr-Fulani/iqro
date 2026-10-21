from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

import pytest
from django.db import connection
from django.test import override_settings
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APIClient

from quran_backend.modules.audio.quran_foundation import (
    ENVIRONMENTS,
    QuranFoundationClient,
    QuranFoundationError,
    QuranFoundationTafsirSyncResult,
)
from quran_backend.modules.tafsirs.models import (
    AyahTafsir,
    QuranFoundationTafsirSyncState,
    TafsirEdition,
    TafsirEditionVersion,
)
from quran_backend.modules.tafsirs.quran_foundation_sync import sync_quran_foundation_tafsirs


def test_tafsir_client_uses_canonical_content_sync_filter(monkeypatch: Any) -> None:
    client = QuranFoundationClient(
        client_id="test-client",
        client_secret="test-secret",
        environment=ENVIRONMENTS["production"],
    )
    calls: list[tuple[str, dict[str, str]]] = []

    def fake_get_json(path: str, *, query: dict[str, str]) -> dict[str, Any]:
        calls.append((path, query))
        return {
            "sync": {
                "sync_until_sequence": 1408,
                "has_more": False,
                "next_page_url": None,
                "next_sync_token": "tafsir-checkpoint",
                "mutations": [
                    {
                        "sequence": 1408,
                        "type": "RESOURCE_CREATE",
                        "resource_group": "tafsirs",
                        "resource_id": 16,
                        "snapshot_url": "/api/v4/resources/snapshots/tafsirs/16",
                    }
                ],
            }
        }

    monkeypatch.setattr(client, "_get_json", fake_get_json)

    result = client.sync_tafsir_catalog((16,))

    assert result.next_sync_token == "tafsir-checkpoint"
    assert result.mutations[0]["resource_id"] == 16
    assert calls == [
        (
            "/content/api/v4/resources/sync",
            {"resources": "tafsirs:16", "per_page": "100", "bootstrap": "true"},
        )
    ]


class FakeTafsirClient:
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

    def list_tafsirs(self, *, language: str = "en") -> list[dict[str, Any]]:
        assert language == "en"
        return [
            {
                "id": 16,
                "name": "Tafsir Muyassar",
                "author_name": "Al-Muyassar",
                "slug": "ar-tafsir-muyassar",
                "language_name": "arabic",
            }
        ]

    def sync_tafsir_catalog(
        self,
        resource_ids: tuple[int, ...],
        *,
        sync_token: str = "",
    ) -> QuranFoundationTafsirSyncResult:
        assert resource_ids == (16,)
        assert sync_token == self.expected_token
        next_token = "tafsir-checkpoint-2" if sync_token else "tafsir-checkpoint-1"
        return QuranFoundationTafsirSyncResult(
            next_sync_token=next_token,
            sync_until_sequence=1409 if sync_token else 1408,
            mutations=self.mutations,
        )

    def get_tafsir_snapshot(self, resource_id: int) -> dict[str, Any]:
        assert resource_id == 16
        self.snapshot_requests.append(resource_id)
        return self.snapshot


def _create_mutation() -> dict[str, Any]:
    return {
        "sequence": 1408,
        "type": "RESOURCE_CREATE",
        "resource_group": "tafsirs",
        "resource_id": 16,
        "snapshot_url": "/api/v4/resources/snapshots/tafsirs/16",
    }


def _snapshot() -> dict[str, Any]:
    return {
        "resource_group": "tafsirs",
        "resource_id": 16,
        "resource_content_id": 16,
        "schema_version": 1,
        "sync_sequence": 1408,
        "records": [
            {
                "id": 1001,
                "resource_id": 16,
                "resource_content_id": 16,
                "verse_id": 1,
                "verse_key": "1:1",
                "group_tafsir_id": 77,
                "group_verse_key_from": "1:1",
                "group_verse_key_to": "1:2",
                "group_verses_count": 2,
                "start_verse_id": 1,
                "end_verse_id": 2,
                "text": "<p>Краткое <b>объяснение</b></p><script>bad()</script>",
            }
        ],
    }


def _record(**overrides: Any) -> dict[str, Any]:
    return _snapshot()["records"][0] | overrides


@pytest.mark.django_db
def test_bootstrap_publishes_grouped_tafsir_and_checkpoint() -> None:
    now = datetime(2026, 8, 28, 10, tzinfo=UTC)

    result = sync_quran_foundation_tafsirs(
        resource_ids=(16,),
        client=FakeTafsirClient(),
        now=now,
        expected_verse_keys={"1:1", "1:2"},
    )

    assert result.editions == 1
    assert result.versions_created == 1
    assert result.records_imported == 1
    edition = TafsirEdition.objects.get(source_id=16)
    assert edition.language_code == "ar"
    assert edition.active_version is not None
    assert edition.active_version.record_count == 1
    assert edition.active_version.covered_ayah_count == 2
    tafsir = AyahTafsir.objects.get(edition_version=edition.active_version)
    assert tafsir.text == "Краткое объяснение"
    assert tafsir.start_verse_key == "1:1"
    assert tafsir.end_verse_key == "1:2"
    state = QuranFoundationTafsirSyncState.objects.get(environment="production")
    assert state.sync_token == "tafsir-checkpoint-1"
    assert state.last_success_at == now


@pytest.mark.django_db
@override_settings(QURAN_QF_ENV="production")
def test_bootstrap_resolves_empty_group_rows_to_their_source_text(
    api_client: APIClient,
) -> None:
    snapshot = _snapshot()
    source = snapshot["records"][0]
    source["id"] = 1001
    source["group_tafsir_id"] = 1001
    snapshot["records"].append(
        {
            "id": 1002,
            "resource_id": 16,
            "resource_content_id": 16,
            "verse_id": 2,
            "verse_key": "1:2",
            "group_tafsir_id": 1001,
            "group_verse_key_from": "1:1",
            "group_verse_key_to": "1:2",
            "group_verses_count": 2,
            "start_verse_id": 1,
            "end_verse_id": 2,
            "text": "",
        }
    )

    sync_quran_foundation_tafsirs(
        resource_ids=(16,),
        client=FakeTafsirClient(snapshot=snapshot),
        expected_verse_keys={"1:1", "1:2"},
    )

    follower = AyahTafsir.objects.get(verse_key="1:2")
    assert follower.text == ""
    assert follower.source_text == ""
    response = api_client.get("/api/v1/quran/tafsirs/16/surahs/1")
    assert response.status_code == 200
    assert response.json()[1]["text"] == "Краткое объяснение"


@pytest.mark.django_db
@override_settings(QURAN_QF_ENV="production")
def test_bootstrap_resolves_unreferenced_range_members_to_the_range_text(
    api_client: APIClient,
) -> None:
    # Ibn Kathir (Abridged, 169) 104:2-9 and 105:2-5 carry no group_tafsir_id.
    snapshot = _snapshot()
    snapshot["records"].append(
        _record(id=1002, verse_id=2, verse_key="1:2", group_tafsir_id=None, text="")
    )

    sync_quran_foundation_tafsirs(
        resource_ids=(16,),
        client=FakeTafsirClient(snapshot=snapshot),
        expected_verse_keys={"1:1", "1:2"},
    )

    assert AyahTafsir.objects.get(verse_key="1:2").provider_group_id == 1001
    response = api_client.get("/api/v1/quran/tafsirs/16/surahs/1")
    assert response.json()[1]["text"] == "Краткое объяснение"


@pytest.mark.django_db
def test_bootstrap_skips_an_ayah_the_provider_left_without_text() -> None:
    # Al-Sa'di (91) 16:64 is empty and its group_tafsir_id is its own verse ID.
    snapshot = _snapshot()
    snapshot["records"][0].update(group_verse_key_to="1:1", group_verses_count=1, end_verse_id=1)
    snapshot["records"].append(
        _record(
            id=1002,
            verse_id=2,
            verse_key="1:2",
            group_tafsir_id=2,
            group_verse_key_from="1:2",
            group_verse_key_to="1:2",
            group_verses_count=1,
            start_verse_id=2,
            end_verse_id=2,
            text="",
        )
    )

    result = sync_quran_foundation_tafsirs(
        resource_ids=(16,),
        client=FakeTafsirClient(snapshot=snapshot),
        expected_verse_keys={"1:1", "1:2"},
    )

    assert result.records_imported == 1
    version = TafsirEditionVersion.objects.get()
    assert version.record_count == 1
    assert version.covered_ayah_count == 1
    assert list(AyahTafsir.objects.values_list("verse_key", flat=True)) == ["1:1"]


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("second_text", "group_tafsir_id"),
    [
        ("", 1002),  # names an empty row instead of the range text
        ("Другое объяснение", None),  # two range texts and no reference
    ],
)
def test_bootstrap_rejects_an_unresolved_empty_group_row(
    second_text: str,
    group_tafsir_id: int | None,
) -> None:
    group = {
        "group_verse_key_to": "1:3",
        "group_verses_count": 3,
        "end_verse_id": 3,
    }
    snapshot = _snapshot()
    snapshot["records"] = [
        _record(**group),
        _record(id=1002, verse_id=2, verse_key="1:2", group_tafsir_id=1001, text=second_text)
        | group,
        _record(id=1003, verse_id=3, verse_key="1:3", group_tafsir_id=group_tafsir_id, text="")
        | group,
    ]

    with pytest.raises(QuranFoundationError, match=r"unresolved grouped Tafsir text for 1:3\."):
        sync_quran_foundation_tafsirs(
            resource_ids=(16,),
            client=FakeTafsirClient(snapshot=snapshot),
            expected_verse_keys={"1:1", "1:2", "1:3"},
        )
    assert not TafsirEditionVersion.objects.exists()


@pytest.mark.django_db
def test_bootstrap_rejects_a_snapshot_without_any_tafsir_text() -> None:
    snapshot = _snapshot()
    snapshot["records"][0]["text"] = ""

    with pytest.raises(QuranFoundationError, match="has no Tafsir text"):
        sync_quran_foundation_tafsirs(
            resource_ids=(16,),
            client=FakeTafsirClient(snapshot=snapshot),
            expected_verse_keys={"1:1", "1:2"},
        )


@pytest.mark.django_db
def test_incremental_no_change_keeps_version_and_advances_checkpoint() -> None:
    sync_quran_foundation_tafsirs(
        resource_ids=(16,),
        client=FakeTafsirClient(),
        expected_verse_keys={"1:1", "1:2"},
    )
    client = FakeTafsirClient(mutations=(), expected_token="tafsir-checkpoint-1")

    result = sync_quran_foundation_tafsirs(resource_ids=(16,), client=client)

    assert result.changed is False
    assert result.versions_created == 0
    assert client.snapshot_requests == []
    assert TafsirEditionVersion.objects.count() == 1
    assert QuranFoundationTafsirSyncState.objects.get().sync_token == "tafsir-checkpoint-2"


@pytest.mark.django_db
def test_empty_provider_bootstrap_self_heals_missing_local_tafsir() -> None:
    client = FakeTafsirClient(mutations=())

    result = sync_quran_foundation_tafsirs(
        resource_ids=(16,),
        client=client,
        expected_verse_keys={"1:1", "1:2"},
    )

    assert result.versions_created == 1
    assert client.snapshot_requests == [16]


@pytest.mark.django_db
def test_partial_provider_tafsir_publishes_reported_coverage() -> None:
    snapshot = _snapshot()
    snapshot["records"][0]["group_verse_key_to"] = "1:1"
    snapshot["records"][0]["group_verses_count"] = 1
    snapshot["records"][0]["end_verse_id"] = 1

    result = sync_quran_foundation_tafsirs(
        resource_ids=(16,),
        client=FakeTafsirClient(snapshot=snapshot),
        expected_verse_keys={"1:1", "1:2"},
    )

    assert result.versions_created == 1
    assert TafsirEditionVersion.objects.get().covered_ayah_count == 1
    state = QuranFoundationTafsirSyncState.objects.get(environment="production")
    assert state.sync_token == "tafsir-checkpoint-1"
    assert state.consecutive_failures == 0


@pytest.mark.django_db
@override_settings(QURAN_QF_ENV="production")
def test_public_tafsir_catalog_and_surah_api(api_client: APIClient) -> None:
    sync_quran_foundation_tafsirs(
        resource_ids=(16,),
        client=FakeTafsirClient(),
        expected_verse_keys={"1:1", "1:2"},
    )

    catalog = api_client.get("/api/v1/quran/tafsirs?language=ar")
    with CaptureQueriesContext(connection) as queries:
        surah = api_client.get("/api/v1/quran/tafsirs/16/surahs/1")

    assert catalog.status_code == 200
    assert catalog.json()[0]["source_id"] == 16
    assert catalog.json()[0]["active_version"]["covered_ayah_count"] == 2
    assert catalog["Cache-Control"].startswith("public")
    assert surah.status_code == 200
    assert surah.json()[0]["verse_key"] == "1:1"
    assert surah.json()[0]["end_verse_key"] == "1:2"
    assert "source_text" not in surah.json()[0]
    # The provider HTML is never serialized, so it is not read from the database.
    assert not any("source_text" in query["sql"] for query in queries.captured_queries)
