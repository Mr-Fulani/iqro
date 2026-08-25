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
    sync_quran_foundation_mushafs,
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
    ) -> QuranFoundationMushafSyncResult:
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
        (11, False, "word-images"),
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
