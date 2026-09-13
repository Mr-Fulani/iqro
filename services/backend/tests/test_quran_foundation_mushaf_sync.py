from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

import pytest
from django.test import override_settings
from rest_framework.test import APIClient

from quran_backend.modules.audio.quran_foundation import (
    ENVIRONMENTS,
    QuranFoundationError,
    QuranFoundationMushafSyncResult,
)
from quran_backend.modules.quran.models import (
    QuranFoundationMushaf,
    QuranFoundationMushafPage,
    QuranFoundationMushafSyncState,
)
from quran_backend.modules.quran.quran_foundation_rendering import (
    quran_foundation_rendering,
)
from quran_backend.modules.quran.quran_foundation_sync import (
    _attach_verse_references,
    _replace_snapshot,
    sync_quran_foundation_mushafs,
)


@pytest.mark.django_db
def test_sequence_only_refresh_preserves_content_identity() -> None:
    sync_quran_foundation_mushafs(client=FakeMushafClient())
    before = QuranFoundationMushaf.objects.get().source_checksum_sha256
    snapshot = _snapshot()
    snapshot["sync_sequence"] = 999
    sync_quran_foundation_mushafs(client=FakeMushafClient(snapshot=snapshot), force=True)
    assert QuranFoundationMushaf.objects.get().source_checksum_sha256 == before


@pytest.mark.django_db
def test_late_snapshot_failure_rolls_back_the_entire_catalog() -> None:
    sync_quran_foundation_mushafs(client=FakeMushafClient())
    original = QuranFoundationMushaf.objects.get().source_checksum_sha256

    class BrokenCatalog(FakeMushafClient):
        def get_mushaf_snapshot(self, resource_id: int) -> dict[str, Any]:
            if resource_id == 2:
                raise QuranFoundationError("Late download failure")
            snapshot = _snapshot()
            snapshot["records"][0]["name"] = "Should roll back"
            return snapshot

    client = BrokenCatalog(
        mutations=(
            _create_mutation(),
            {**_create_mutation(), "resource_id": 2},
        )
    )
    with pytest.raises(QuranFoundationError, match="Late download"):
        sync_quran_foundation_mushafs(client=client, force=True)
    assert QuranFoundationMushaf.objects.count() == 1
    assert QuranFoundationMushaf.objects.get().source_checksum_sha256 == original
    assert QuranFoundationMushafSyncState.objects.get().sync_token == "checkpoint-1"


@pytest.mark.django_db
@pytest.mark.parametrize("complete", [True, False])
def test_nastaleeq_14_corrects_only_the_verified_610_page_metadata_defect(complete: bool) -> None:
    snapshot = _snapshot()
    snapshot["resource_id"] = 14
    metadata = {**snapshot["records"][0], "id": 14, "pages_count": 604}
    records = [metadata]
    verse_id = 1
    for number in range(1, 611 if complete else 610):
        mapping: dict[str, list[int]] = {}
        for position in range(1, (11 if number <= 136 else 10) + 1):
            chapter, offset = divmod(verse_id - 1, 55)
            mapping.setdefault(str(chapter + 1), []).append(offset + 1)
            records.append(
                {**_word(verse_id, page=number, position=position, text="نَصّ"), "verse_id": verse_id}
            )
            verse_id += 1
        records.append(
            {
                **_snapshot()["records"][1],
                "id": number,
                "page_number": number,
                "verse_mapping": {
                    key: f"{min(values)}-{max(values)}" for key, values in mapping.items()
                },
                "last_verse_id": verse_id - 1,
            }
        )
    snapshot["records"] = records
    if complete:
        _replace_snapshot(
            environment="production", resource_id=14, snapshot=snapshot, current=datetime.now(UTC)
        )
        assert QuranFoundationMushaf.objects.get().pages_count == 610
        assert QuranFoundationMushafPage.objects.count() == 610
    else:
        with pytest.raises(QuranFoundationError, match="incomplete pages"):
            _replace_snapshot(
                environment="production",
                resource_id=14,
                snapshot=snapshot,
                current=datetime.now(UTC),
            )


def test_split_boundary_verses_are_recovered_from_global_word_references() -> None:
    # Small words, full 6236-ID corpus: the second page omits its leading
    # partial verse in metadata, as nine pages of QF 15 do in production.
    mapping = {str(chapter): f"1-{55 if chapter < 114 else 21}" for chapter in range(1, 115)}
    pages = {1: {"verse_mapping": mapping}, 2: {"verse_mapping": {"114": "21-21"}}}
    words = {
        1: [{"verse_id": n} for n in range(1, 6237)],
        2: [{"verse_id": 6235}, {"verse_id": 6236}],
    }
    _attach_verse_references({"qirat": {"name": "Hafs"}, "mapping_mode": "reference"}, pages, words)
    assert pages[2]["verse_mapping"] == {"114": "20-21"}
    assert pages[2]["verses_count"] == 2
    assert [word["verse_key"] for word in words[2]] == ["114:20", "114:21"]


@pytest.mark.django_db
@override_settings(QURAN_QF_ENV="production")
def test_page_index_includes_both_fragments_of_a_split_verse(api_client: APIClient) -> None:
    sync_quran_foundation_mushafs(client=FakeMushafClient())
    QuranFoundationMushafPage.objects.filter(page_number=2).update(
        verse_mapping={"1": "2-2", "2": "1-1"}
    )
    response = api_client.get("/api/v1/quran/foundation/mushafs/1/page-index")
    assert response.status_code == 200
    assert response.json()["verse_pages"] == {"1:1": [1], "1:2": [1, 2], "2:1": [2]}
    assert (
        response.json()["source_checksum_sha256"]
        == QuranFoundationMushaf.objects.get().source_checksum_sha256
    )


@pytest.mark.django_db
def test_word_outside_declared_lines_is_rejected_before_publication() -> None:
    snapshot = _snapshot()
    snapshot["records"][-1]["line_number"] = 16
    with pytest.raises(QuranFoundationError, match="line count"):
        sync_quran_foundation_mushafs(client=FakeMushafClient(snapshot=snapshot))
    assert not QuranFoundationMushaf.objects.exists()


def test_full_size_hafs_snapshot_cannot_skip_reference_validation() -> None:
    pages = {number: {"verse_mapping": {"1": "1-7"}} for number in range(1, 605)}
    with pytest.raises(QuranFoundationError, match="Incomplete Hafs verse mapping"):
        _attach_verse_references(
            {"qirat": {"name": "Hafs"}, "mapping_mode": "reference"}, pages, {}
        )


class FakeMushafClient:
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

    def sync_mushaf_catalog(
        self,
        *,
        sync_token: str = "",
        resource_ids: tuple[int, ...] | None = None,
    ) -> QuranFoundationMushafSyncResult:
        assert resource_ids is None or resource_ids == (1,)
        assert sync_token == self.expected_token
        return QuranFoundationMushafSyncResult(
            next_sync_token="checkpoint-2" if sync_token else "checkpoint-1",
            sync_until_sequence=52 if sync_token else 50,
            mutations=self.mutations,
        )

    def get_mushaf_snapshot(self, resource_id: int) -> dict[str, Any]:
        assert resource_id == 1
        self.snapshot_requests.append(resource_id)
        return self.snapshot


@pytest.mark.django_db
def test_scoped_mushaf_import_uses_its_own_checkpoint() -> None:
    scoped = FakeMushafClient()
    sync_quran_foundation_mushafs(client=scoped, resource_ids=(1,))
    assert scoped.snapshot_requests == [1]
    state = QuranFoundationMushafSyncState.objects.get(resources_filter="mushafs:1")
    assert state.sync_token == "checkpoint-1"
    assert not QuranFoundationMushafSyncState.objects.filter(resources_filter="mushafs:*").exists()
    incremental = FakeMushafClient(expected_token="checkpoint-1", mutations=())
    sync_quran_foundation_mushafs(client=incremental, resource_ids=(1,))
    assert not incremental.snapshot_requests
    # The full catalog still starts with an independent bootstrap.
    sync_quran_foundation_mushafs(client=FakeMushafClient())
    assert QuranFoundationMushafSyncState.objects.count() == 2


@pytest.mark.django_db
def test_scoped_mushaf_import_rejects_unrequested_mutations() -> None:
    client = FakeMushafClient(mutations=({**_create_mutation(), "resource_id": 99},))
    with pytest.raises(QuranFoundationError, match="unrequested"):
        sync_quran_foundation_mushafs(client=client, resource_ids=(1,))
    assert not QuranFoundationMushaf.objects.exists()
    assert QuranFoundationMushafSyncState.objects.get().sync_token == ""


def _create_mutation() -> dict[str, Any]:
    return {
        "sequence": 50,
        "type": "RESOURCE_CREATE",
        "resource_group": "mushafs",
        "resource_id": 1,
        "snapshot_url": "/api/v4/resources/snapshots/mushafs/1",
    }


def _snapshot() -> dict[str, Any]:
    return {
        "resource_group": "mushafs",
        "resource_id": 1,
        "resource_content_id": 382,
        "schema_version": "1",
        "sync_sequence": 50,
        "records": [
            {
                "id": 1,
                "record_type": "mushaf",
                "name": "QCF V2",
                "description": "Test Mushaf",
                "pages_count": 2,
                "lines_per_page": 15,
                "default_font_name": "v2",
                "mapping_mode": "reference",
                "qirat": {"id": 1, "name": "Hafs"},
            },
            {
                "id": 101,
                "record_type": "mushaf_page",
                "page_number": 1,
                "verse_mapping": {"1": "1-2"},
                "first_verse_id": 1,
                "last_verse_id": 2,
                "first_word_id": 1,
                "last_word_id": 2,
                "verses_count": 2,
            },
            {
                "id": 102,
                "record_type": "mushaf_page",
                "page_number": 2,
                "verse_mapping": {"2": "1-1"},
                "first_verse_id": 3,
                "last_verse_id": 3,
                "first_word_id": 3,
                "last_word_id": 3,
                "verses_count": 1,
            },
            _word(1, page=1, position=1, text="ﱁ"),
            _word(2, page=1, position=2, text="ﱂ"),
            _word(3, page=2, position=1, text="ﲀ"),
        ],
    }


def _word(source_id: int, *, page: int, position: int, text: str) -> dict[str, Any]:
    return {
        "id": source_id,
        "record_type": "mushaf_word",
        "word_id": source_id,
        "verse_id": 1 if page == 1 else 3,
        "page_number": page,
        "line_number": 1,
        "position_in_line": position,
        "position_in_page": position,
        "position_in_verse": position,
        "char_type_id": 1,
        "char_type_name": "word",
        "text": text,
        "css_class": "",
        "css_style": "",
    }


@pytest.mark.django_db
def test_bootstrap_caches_complete_mushaf_pages_and_checkpoint() -> None:
    now = datetime(2026, 8, 25, 9, tzinfo=UTC)
    client = FakeMushafClient()

    result = sync_quran_foundation_mushafs(client=client, now=now)

    assert result.resources == 1
    assert result.pages == 2
    assert result.words == 3
    assert result.changed is True
    mushaf = QuranFoundationMushaf.objects.get(source_id=1)
    assert mushaf.name == "QCF V2"
    assert mushaf.qirat_name == "Hafs"
    assert mushaf.pages_count == 2
    page = QuranFoundationMushafPage.objects.get(mushaf=mushaf, page_number=1)
    assert [word["text"] for word in page.words] == ["ﱁ", "ﱂ"]
    state = QuranFoundationMushafSyncState.objects.get(environment="production")
    assert state.sync_token == "checkpoint-1"
    assert state.last_sync_sequence == 50
    assert state.last_success_at == now


@pytest.mark.django_db
def test_incremental_no_change_advances_checkpoint_without_snapshot_download() -> None:
    sync_quran_foundation_mushafs(client=FakeMushafClient())
    client = FakeMushafClient(mutations=(), expected_token="checkpoint-1")

    result = sync_quran_foundation_mushafs(client=client)

    assert result.changed is False
    assert result.pages == 0
    assert client.snapshot_requests == []
    state = QuranFoundationMushafSyncState.objects.get(environment="production")
    assert state.sync_token == "checkpoint-2"
    assert state.last_sync_sequence == 52


@pytest.mark.django_db
def test_resource_update_reloads_complete_snapshot() -> None:
    sync_quran_foundation_mushafs(client=FakeMushafClient())
    update = {
        "sequence": 51,
        "type": "RESOURCE_UPDATE",
        "resource_group": "mushafs",
        "resource_id": 1,
        "snapshot_url": "/api/v4/resources/snapshots/mushafs/1",
    }
    snapshot = _snapshot()
    snapshot["records"][0]["name"] = "QCF V2 Updated"
    client = FakeMushafClient(
        mutations=(update,),
        expected_token="checkpoint-1",
        snapshot=snapshot,
    )

    result = sync_quran_foundation_mushafs(client=client)

    assert result.changed is True
    assert client.snapshot_requests == [1]
    assert QuranFoundationMushaf.objects.get(source_id=1).name == "QCF V2 Updated"


@pytest.mark.django_db
def test_resource_delete_removes_cached_quran_foundation_content() -> None:
    sync_quran_foundation_mushafs(client=FakeMushafClient())
    delete = {
        "sequence": 51,
        "type": "RESOURCE_DELETE",
        "resource_group": "mushafs",
        "resource_id": 1,
        "snapshot_url": None,
    }

    result = sync_quran_foundation_mushafs(
        client=FakeMushafClient(mutations=(delete,), expected_token="checkpoint-1")
    )

    assert result.removed == 1
    assert not QuranFoundationMushaf.objects.exists()
    assert not QuranFoundationMushafPage.objects.exists()


@pytest.mark.django_db
def test_invalid_snapshot_does_not_advance_checkpoint() -> None:
    snapshot = _snapshot()
    snapshot["records"] = [
        row
        for row in snapshot["records"]
        if not (row.get("record_type") == "mushaf_page" and row.get("page_number") == 2)
    ]

    with pytest.raises(QuranFoundationError, match="incomplete pages"):
        sync_quran_foundation_mushafs(client=FakeMushafClient(snapshot=snapshot))

    state = QuranFoundationMushafSyncState.objects.get(environment="production")
    assert state.sync_token == ""
    assert state.last_success_at is None
    assert state.consecutive_failures == 1


@pytest.mark.django_db
@override_settings(QURAN_QF_ENV="production")
def test_public_mushaf_catalog_and_page_api(api_client: APIClient) -> None:
    sync_quran_foundation_mushafs(client=FakeMushafClient())

    catalog = api_client.get("/api/v1/quran/foundation/mushafs")
    page = api_client.get("/api/v1/quran/foundation/mushafs/1/pages/1")

    assert catalog.status_code == 200
    assert catalog.json()[0]["source_id"] == 1
    assert catalog.json()[0]["source"]["attribution"] == (
        "Quran data provided by Quran Foundation."
    )
    assert catalog.json()[0]["rendering"] == {
        "available": True,
        "version": 2,
        "native_font_url_template": "https://verses.quran.foundation/fonts/quran/hafs/v2/ttf/p{page}.ttf",
        "mode": "page-font",
        "font_format": "woff2",
        "font_url_template": (
            "https://verses.quran.foundation/fonts/quran/hafs/v2/woff2/p{page}.woff2"
        ),
    }
    assert page.status_code == 200
    assert page.json()["font_name"] == "v2"
    assert page.json()["rendering"]["font_url"].endswith("/p1.woff2")
    assert [word["text"] for word in page.json()["words"]] == ["ﱁ", "ﱂ"]


@pytest.mark.parametrize(
    ("source_id", "available", "mode"),
    [
        (1, True, "page-font"),
        (5, True, "unicode-font"),
        (11, True, "word-images"),
        (19, True, "page-font"),
    ],
)
def test_rendering_contract_covers_production_mushaf_catalog(
    source_id: int,
    available: bool,
    mode: str,
) -> None:
    rendering = quran_foundation_rendering(source_id, page_number=42)

    assert rendering["available"] is available
    assert rendering["mode"] == mode
    if source_id in {1, 19}:
        assert rendering["font_url"].endswith("/p42.woff2")
