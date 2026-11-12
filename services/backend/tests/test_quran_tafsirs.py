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
from quran_backend.modules.tafsirs import quran_foundation_sync
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


END_ANCHORED_VERSE_KEYS = {"1:1", "1:2", "2:1", "2:2", "2:3"}


def _end_anchored_snapshot() -> dict[str, Any]:
    # Russian Al-Sa'di (170): the text of surah 111 is published as 111:5-112:3
    # and the text of surah 112 as 112:4-113:4, so 112:1-3 show surah 111.
    surah_one = {
        "group_tafsir_id": 1002,
        "group_verse_key_from": "1:2",
        "group_verse_key_to": "2:2",
        "group_verses_count": 3,
        "start_verse_id": 2,
        "end_verse_id": 4,
    }
    snapshot = _snapshot()
    snapshot["records"] = [
        _record(id=1002, verse_id=2, verse_key="1:2", text="Surah one", **surah_one),
        _record(id=1003, verse_id=3, verse_key="2:1", text="", **surah_one),
        _record(id=1004, verse_id=4, verse_key="2:2", text="", **surah_one),
        _record(
            id=1005,
            verse_id=5,
            verse_key="2:3",
            group_tafsir_id=1005,
            group_verse_key_from="2:3",
            group_verse_key_to="2:3",
            group_verses_count=1,
            start_verse_id=5,
            end_verse_id=5,
            text="Surah two",
        ),
    ]
    return snapshot


@pytest.mark.django_db
@override_settings(QURAN_QF_ENV="production")
def test_bootstrap_moves_end_anchored_texts_back_onto_their_passages(
    api_client: APIClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(quran_foundation_sync, "END_ANCHORED_TAFSIR_IDS", {16})

    sync_quran_foundation_tafsirs(
        resource_ids=(16,),
        client=FakeTafsirClient(snapshot=_end_anchored_snapshot()),
        expected_verse_keys=END_ANCHORED_VERSE_KEYS,
    )

    surah_one = api_client.get("/api/v1/quran/tafsirs/16/surahs/1").json()
    assert [(row["verse_key"], row["text"]) for row in surah_one] == [("1:2", "Surah one")]
    assert (surah_one[0]["start_verse_key"], surah_one[0]["end_verse_key"]) == ("1:1", "1:2")
    surah_two = api_client.get("/api/v1/quran/tafsirs/16/surahs/2").json()
    assert [(row["verse_key"], row["text"]) for row in surah_two] == [
        ("2:1", "Surah two"),
        ("2:2", "Surah two"),
        ("2:3", "Surah two"),
    ]
    assert {(row["start_verse_key"], row["end_verse_key"]) for row in surah_two} == {("2:1", "2:3")}
    assert {row["group_verses_count"] for row in surah_two} == {3}
    assert TafsirEditionVersion.objects.get().covered_ayah_count == 5


@pytest.mark.django_db
def test_end_anchored_edition_keeps_ranges_that_stay_inside_a_surah(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(quran_foundation_sync, "END_ANCHORED_TAFSIR_IDS", {16})

    sync_quran_foundation_tafsirs(
        resource_ids=(16,),
        client=FakeTafsirClient(),
        expected_verse_keys={"1:1", "1:2"},
    )

    tafsir = AyahTafsir.objects.get()
    assert (tafsir.verse_key, tafsir.start_verse_key, tafsir.end_verse_key) == ("1:1", "1:1", "1:2")


@pytest.mark.django_db
def test_force_reimports_an_unchanged_snapshot_with_the_current_rules(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def sync(*, force: bool) -> None:
        sync_quran_foundation_tafsirs(
            resource_ids=(16,),
            client=FakeTafsirClient(
                snapshot=_end_anchored_snapshot(),
                expected_token="" if force else "tafsir-checkpoint-1",
            ),
            force=force,
            expected_verse_keys=END_ANCHORED_VERSE_KEYS,
        )

    def text_of_2_1() -> str:
        row = AyahTafsir.objects.get(verse_key="2:1")
        return AyahTafsir.objects.get(source_id=row.provider_group_id).text

    sync(force=True)
    assert text_of_2_1() == "Surah one"
    monkeypatch.setattr(quran_foundation_sync, "END_ANCHORED_TAFSIR_IDS", {16})

    sync(force=False)
    assert text_of_2_1() == "Surah one"

    sync(force=True)
    assert text_of_2_1() == "Surah two"
    assert TafsirEditionVersion.objects.count() == 1
    assert AyahTafsir.objects.count() == 4


def _surah_overrunning_snapshot() -> dict[str, Any]:
    # Ma'arif al-Qur'an (168): the closing commentary of surah 81 is published
    # as 81:19-82:4, so 82:1-4 show the end of surah 81.
    surah_one = {
        "group_tafsir_id": 1001,
        "group_verse_key_from": "1:1",
        "group_verse_key_to": "2:1",
        "group_verses_count": 3,
        "start_verse_id": 1,
        "end_verse_id": 3,
    }
    surah_two = {
        "group_tafsir_id": 1004,
        "group_verse_key_from": "2:2",
        "group_verse_key_to": "2:3",
        "group_verses_count": 2,
        "start_verse_id": 4,
        "end_verse_id": 5,
    }
    snapshot = _snapshot()
    snapshot["records"] = [
        _record(id=1001, verse_id=1, verse_key="1:1", text="Surah one", **surah_one),
        _record(id=1002, verse_id=2, verse_key="1:2", text="", **surah_one),
        _record(id=1003, verse_id=3, verse_key="2:1", text="", **surah_one),
        _record(id=1004, verse_id=4, verse_key="2:2", text="Surah two", **surah_two),
        _record(id=1005, verse_id=5, verse_key="2:3", text="", **surah_two),
    ]
    return snapshot


def _surah_rows(api_client: APIClient, surah: int) -> list[tuple[str, str, str, str, int]]:
    return [
        (
            row["verse_key"],
            row["text"],
            row["start_verse_key"],
            row["end_verse_key"],
            row["group_verses_count"],
        )
        for row in api_client.get(f"/api/v1/quran/tafsirs/16/surahs/{surah}").json()
    ]


@pytest.mark.django_db
@override_settings(QURAN_QF_ENV="production")
def test_other_editions_keep_a_surah_overrunning_range_as_the_provider_sends_it(
    api_client: APIClient,
) -> None:
    sync_quran_foundation_tafsirs(
        resource_ids=(16,),
        client=FakeTafsirClient(snapshot=_surah_overrunning_snapshot()),
        expected_verse_keys=END_ANCHORED_VERSE_KEYS,
    )

    # The defect: 2:1 shows the text of surah 1.
    assert _surah_rows(api_client, 2) == [
        ("2:1", "Surah one", "1:1", "2:1", 3),
        ("2:2", "Surah two", "2:2", "2:3", 2),
        ("2:3", "Surah two", "2:2", "2:3", 2),
    ]


@pytest.mark.django_db
@override_settings(QURAN_QF_ENV="production")
def test_bootstrap_keeps_a_surah_overrunning_text_inside_its_surah(
    api_client: APIClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(quran_foundation_sync, "SURAH_OVERRUNNING_TAFSIR_IDS", {16})

    sync_quran_foundation_tafsirs(
        resource_ids=(16,),
        client=FakeTafsirClient(snapshot=_surah_overrunning_snapshot()),
        expected_verse_keys=END_ANCHORED_VERSE_KEYS,
    )

    assert _surah_rows(api_client, 1) == [
        ("1:1", "Surah one", "1:1", "1:2", 2),
        ("1:2", "Surah one", "1:1", "1:2", 2),
    ]
    assert _surah_rows(api_client, 2) == [
        ("2:1", "Surah two", "2:1", "2:3", 3),
        ("2:2", "Surah two", "2:1", "2:3", 3),
        ("2:3", "Surah two", "2:1", "2:3", 3),
    ]
    assert TafsirEditionVersion.objects.get().covered_ayah_count == 5


@pytest.mark.django_db
def test_surah_overrunning_edition_keeps_ranges_that_stay_inside_a_surah(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(quran_foundation_sync, "SURAH_OVERRUNNING_TAFSIR_IDS", {16})

    sync_quran_foundation_tafsirs(
        resource_ids=(16,),
        client=FakeTafsirClient(),
        expected_verse_keys={"1:1", "1:2"},
    )

    tafsir = AyahTafsir.objects.get()
    assert (tafsir.verse_key, tafsir.start_verse_key, tafsir.end_verse_key) == ("1:1", "1:1", "1:2")


@pytest.mark.django_db
@override_settings(QURAN_QF_ENV="production")
def test_surah_overrunning_text_leaves_ayahs_without_a_following_text_uncovered(
    api_client: APIClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(quran_foundation_sync, "SURAH_OVERRUNNING_TAFSIR_IDS", {16})
    snapshot = _surah_overrunning_snapshot()
    snapshot["records"] = snapshot["records"][:3]

    sync_quran_foundation_tafsirs(
        resource_ids=(16,),
        client=FakeTafsirClient(snapshot=snapshot),
        expected_verse_keys=END_ANCHORED_VERSE_KEYS,
    )

    assert [row[0] for row in _surah_rows(api_client, 1)] == ["1:1", "1:2"]
    assert _surah_rows(api_client, 2) == []
    assert TafsirEditionVersion.objects.get().covered_ayah_count == 2


@pytest.mark.django_db
def test_bootstrap_rejects_a_surah_overrunning_range_with_a_text_in_the_next_surah(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(quran_foundation_sync, "SURAH_OVERRUNNING_TAFSIR_IDS", {16})
    snapshot = _surah_overrunning_snapshot()
    snapshot["records"][2]["text"] = "Whose text is this?"

    with pytest.raises(QuranFoundationError, match=r"range 1:1-2:1 has a text outside"):
        sync_quran_foundation_tafsirs(
            resource_ids=(16,),
            client=FakeTafsirClient(snapshot=snapshot),
            expected_verse_keys=END_ANCHORED_VERSE_KEYS,
        )
    assert not TafsirEditionVersion.objects.exists()


@pytest.mark.django_db
@override_settings(QURAN_QF_ENV="production")
def test_force_reimport_clips_surah_overrunning_ranges_once_and_republishes(
    api_client: APIClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def sync(*, force: bool, day: int) -> None:
        sync_quran_foundation_tafsirs(
            resource_ids=(16,),
            client=FakeTafsirClient(
                snapshot=_surah_overrunning_snapshot(),
                expected_token="" if force else "tafsir-checkpoint-1",
            ),
            force=force,
            now=datetime(2026, 11, day, tzinfo=UTC),
            expected_verse_keys=END_ANCHORED_VERSE_KEYS,
        )

    def published_day() -> int:
        published_at = TafsirEditionVersion.objects.get().published_at
        assert published_at is not None
        return published_at.day

    sync(force=True, day=1)
    assert _surah_rows(api_client, 2)[0][:2] == ("2:1", "Surah one")
    monkeypatch.setattr(quran_foundation_sync, "SURAH_OVERRUNNING_TAFSIR_IDS", {16})

    sync(force=False, day=2)
    assert _surah_rows(api_client, 2)[0][:2] == ("2:1", "Surah one")
    assert published_day() == 1

    sync(force=True, day=3)
    fixed = _surah_rows(api_client, 1) + _surah_rows(api_client, 2)
    assert fixed[2] == ("2:1", "Surah two", "2:1", "2:3", 3)
    # Clients learn about the rebuilt rows from the new publication time.
    assert published_day() == 3

    sync(force=True, day=4)
    assert _surah_rows(api_client, 1) + _surah_rows(api_client, 2) == fixed
    assert AyahTafsir.objects.count() == 5
