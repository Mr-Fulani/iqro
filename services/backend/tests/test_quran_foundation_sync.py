from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

import pytest

from quran_backend.modules.audio.models import (
    AudioCodec,
    AudioContentType,
    AudioTrack,
    AudioTrackScope,
    QuranFoundationSyncState,
    RecitationEdition,
    Reciter,
)
from quran_backend.modules.audio.quran_foundation import (
    ENVIRONMENTS,
    QuranFoundationClient,
    QuranFoundationError,
    QuranFoundationSyncResult,
)
from quran_backend.modules.audio.quran_foundation_sync import (
    refresh_quran_foundation_audio,
)


def test_content_sync_follows_server_cursor_and_fetches_snapshot(monkeypatch: Any) -> None:
    client = QuranFoundationClient(
        client_id="test-client",
        client_secret="test-secret",
        environment=ENVIRONMENTS["prelive"],
    )
    responses = iter(
        [
            {
                "sync": {
                    "sync_until_sequence": 42,
                    "has_more": True,
                    "next_page_url": "/api/v4/resources/sync?cursor=opaque-cursor",
                    "next_sync_token": None,
                    "mutations": [
                        {
                            "sequence": 40,
                            "type": "RESOURCE_CREATE",
                            "resource_group": "recitations",
                            "resource_id": 7,
                            "snapshot_url": "/api/v4/resources/snapshots/recitations/7",
                        }
                    ],
                }
            },
            {
                "resource_group": "recitations",
                "resource_id": 7,
                "records": [{"record_type": "chapter_audio_file", "chapter_id": 1}],
            },
            {
                "sync": {
                    "sync_until_sequence": 42,
                    "has_more": False,
                    "next_page_url": None,
                    "next_sync_token": "next-token",
                    "mutations": [],
                }
            },
        ]
    )
    calls: list[tuple[str, dict[str, str]]] = []

    def fake_get_json(path: str, *, query: dict[str, str]) -> dict[str, Any]:
        calls.append((path, query))
        return next(responses)

    monkeypatch.setattr(client, "_get_json", fake_get_json)

    result = client.sync_recitation_content(7)

    assert result.next_sync_token == "next-token"
    assert result.sync_until_sequence == 42
    assert result.mutations[0]["snapshot"]["records"][0]["chapter_id"] == 1
    assert calls == [
        (
            "/content/api/v4/resources/sync",
            {"resources": "recitations:7", "per_page": "100", "bootstrap": "true"},
        ),
        ("/content/api/v4/resources/snapshots/recitations/7", {}),
        ("/content/api/v4/resources/sync", {"cursor": "opaque-cursor"}),
    ]


def test_content_sync_rejects_untrusted_next_page_url(monkeypatch: Any) -> None:
    client = QuranFoundationClient(
        client_id="test-client",
        client_secret="test-secret",
        environment=ENVIRONMENTS["prelive"],
    )
    monkeypatch.setattr(
        client,
        "_get_json",
        lambda _path, **_kwargs: {
            "sync": {
                "sync_until_sequence": 42,
                "has_more": True,
                "next_page_url": "https://attacker.example/api/v4/resources/sync?cursor=x",
                "next_sync_token": None,
                "mutations": [],
            }
        },
    )

    with pytest.raises(QuranFoundationError, match="invalid next sync URL"):
        client.sync_recitation_content(7)


class SyncOnlyClient:
    environment = ENVIRONMENTS["production"]

    def list_ayah_recitations(self, *, language: str = "en") -> list[dict[str, Any]]:
        assert language == "en"
        return [{"id": 7, "reciter_name": "Mishari Rashid al-`Afasy", "style": None}]

    def sync_recitation_content(
        self,
        resource_id: int,
        *,
        sync_token: str = "",
    ) -> QuranFoundationSyncResult:
        assert resource_id == 7
        assert sync_token == ""
        return QuranFoundationSyncResult(
            next_sync_token="checkpoint-1",
            sync_until_sequence=123,
            mutations=(),
        )


@pytest.mark.django_db
def test_refresh_uses_content_sync_checkpoint_without_reimporting_unchanged_audio(
    quran_dataset: dict[str, Any],
) -> None:
    _complete_qf_recitation(
        quran_dataset,
        source_id=7,
        name="Mishari Rashid al-`Afasy",
    )
    now = datetime(2026, 8, 22, 12, tzinfo=UTC)

    result = refresh_quran_foundation_audio(
        client=SyncOnlyClient(),  # type: ignore[arg-type]
        force=True,
        now=now,
    )

    assert result.checked == 1
    assert result.changed == 0
    state = QuranFoundationSyncState.objects.get(source_reciter_id=7)
    assert state.content_sync_resource_id == 7
    assert state.sync_token == "checkpoint-1"
    assert state.last_sync_sequence == 123
    assert state.last_success_at == now


@pytest.mark.django_db
def test_refresh_falls_back_to_full_check_when_content_sync_has_no_matching_resource(
    quran_dataset: dict[str, Any],
    monkeypatch: Any,
) -> None:
    recitation = _complete_qf_recitation(
        quran_dataset,
        source_id=159,
        name="Maher al-Muaiqly",
    )
    checked: list[int] = []

    def fake_refresh(*args: Any, source_id: int, **kwargs: Any) -> bool:
        checked.append(source_id)
        return False

    monkeypatch.setattr(
        "quran_backend.modules.audio.quran_foundation_sync._refresh_recitation_version",
        fake_refresh,
    )
    now = datetime(2026, 8, 22, 12, tzinfo=UTC)

    result = refresh_quran_foundation_audio(
        client=SyncOnlyClient(),  # type: ignore[arg-type]
        force=True,
        now=now,
    )

    assert recitation.status == "published"
    assert result.checked == 1
    assert checked == [159]
    state = QuranFoundationSyncState.objects.get(source_reciter_id=159)
    assert state.content_sync_resource_id is None
    assert state.last_success_at == now


@pytest.mark.django_db
def test_refresh_falls_back_to_full_check_when_content_sync_is_not_permitted(
    quran_dataset: dict[str, Any],
    monkeypatch: Any,
) -> None:
    _complete_qf_recitation(
        quran_dataset,
        source_id=7,
        name="Mishari Rashid al-`Afasy",
    )
    checked: list[int] = []

    class DeniedSyncClient(SyncOnlyClient):
        def sync_recitation_content(
            self,
            resource_id: int,
            *,
            sync_token: str = "",
        ) -> QuranFoundationSyncResult:
            assert resource_id == 7
            assert sync_token == ""
            raise QuranFoundationError("Quran.Foundation request failed with HTTP 403.")

    def fake_refresh(*args: Any, source_id: int, **kwargs: Any) -> bool:
        checked.append(source_id)
        return False

    monkeypatch.setattr(
        "quran_backend.modules.audio.quran_foundation_sync._refresh_recitation_version",
        fake_refresh,
    )

    result = refresh_quran_foundation_audio(
        client=DeniedSyncClient(),  # type: ignore[arg-type]
        force=True,
        now=datetime(2026, 8, 22, 12, tzinfo=UTC),
    )

    assert result.checked == 1
    assert checked == [7]
    state = QuranFoundationSyncState.objects.get(source_reciter_id=7)
    assert state.content_sync_resource_id is None
    assert state.sync_token == ""


def _complete_qf_recitation(
    quran_dataset: dict[str, Any],
    *,
    source_id: int,
    name: str,
) -> RecitationEdition:
    reciter = Reciter.objects.create(
        code=f"qf-{source_id}-test",
        name_ar=name,
        name_en=name,
        name_ru=name,
    )
    recitation = RecitationEdition.objects.create(
        code=f"qf-{source_id}-murattal",
        version="2026.08.21-production",
        style="murattal",
        reciter=reciter,
        quran_edition_version=quran_dataset["version"],
        source_name="Quran.Foundation Content API",
        source_url="https://api-docs.quran.foundation/docs/category/content-apis/",
        source_version="content-api-v4-production",
        source_checksum_sha256="a" * 64,
        rights_holder="Quran.Foundation and source rights holders",
        license_name="Quran Foundation Developer Terms",
        license_url="https://api-docs.quran.foundation/legal/developer-terms/",
        stream_allowed=True,
        offline_download_allowed=False,
    )
    AudioTrack.objects.bulk_create(
        [
            AudioTrack(
                recitation_edition=recitation,
                scope=AudioTrackScope.SURAH,
                surah_number=surah,
                duration_ms=1_000,
                codec=AudioCodec.MP3,
                content_type=AudioContentType.MPEG,
                bitrate_kbps=128,
                size_bytes=16_000,
                checksum_sha256="",
                object_key=None,
                external_url=f"https://download.quranicaudio.com/test/{source_id}/{surah}.mp3",
            )
            for surah in range(1, 115)
        ]
    )
    recitation.publish()
    recitation.save()
    return recitation
