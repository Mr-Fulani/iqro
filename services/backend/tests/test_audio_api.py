from __future__ import annotations

import json
from typing import Any

import pytest
from django.core.exceptions import ImproperlyConfigured
from django.db import connection
from django.test import override_settings
from django.test.utils import CaptureQueriesContext
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from quran_backend.modules.audio.models import (
    AudioCodec,
    AudioTimingVersion,
    AudioTrack,
    AudioTrackScope,
    AyahAudioSegment,
    RecitationEdition,
    RecitationPublicationStatus,
    Reciter,
)
from quran_backend.modules.quran.models import (
    PublicationStatus,
    QuranEdition,
    QuranEditionVersion,
)
from quran_backend.settings.base import validate_https_base_url


@pytest.mark.parametrize(
    "value",
    [
        "http://cdn.example.test/audio",
        "https://",
        "https://user:secret@cdn.example.test/audio",
        "https://cdn.example.test/audio?token=secret",
        "https://cdn.example.test/audio#fragment",
    ],
)
def test_production_audio_base_url_requires_a_clean_https_origin(value: str) -> None:
    with pytest.raises(ImproperlyConfigured):
        validate_https_base_url("PUBLIC_AUDIO_BASE_URL", value)

    assert (
        validate_https_base_url(
            "PUBLIC_AUDIO_BASE_URL",
            "https://cdn.example.test/quran-audio/",
        )
        == "https://cdn.example.test/quran-audio/"
    )


@pytest.fixture
def published_audio_dataset(quran_dataset: dict[str, Any]) -> dict[str, Any]:
    reciter = Reciter.objects.create(
        code="test-reciter",
        name_ar="قارئ الاختبار",
        name_en="Test Reciter",
        name_ru="Тестовый чтец",
        biography_ar="سيرة تجريبية",
        biography_en="Synthetic biography.",
        biography_ru="Тестовая биография.",
        country_code="SA",
        portrait_object_key="audio/reciters/test-reciter.webp",
    )
    recitation = _create_recitation(
        reciter,
        quran_dataset["version"],
        code="test-recitation",
        version="1.0.0",
    )
    timing_version = AudioTimingVersion.objects.create(
        recitation_edition=recitation,
        version="1.0.0",
        source_name="Verified synthetic timings",
        source_version="2026-08-09",
        source_checksum_sha256="e" * 64,
        verified_at=timezone.now(),
    )
    track = _create_track(recitation, timing_version=timing_version)
    first_segment = AyahAudioSegment.objects.create(
        track=track,
        ayah=quran_dataset["first_ayah"],
        start_ms=0,
        end_ms=5_000,
    )
    second_segment = AyahAudioSegment.objects.create(
        track=track,
        ayah=quran_dataset["second_ayah"],
        start_ms=5_000,
        end_ms=10_000,
    )
    _publish(recitation)
    return {
        "reciter": reciter,
        "recitation": recitation,
        "timing_version": timing_version,
        "track": track,
        "first_segment": first_segment,
        "second_segment": second_segment,
    }


def _create_recitation(
    reciter: Reciter,
    quran_version: QuranEditionVersion,
    *,
    code: str,
    version: str,
) -> RecitationEdition:
    return RecitationEdition.objects.create(
        code=code,
        version=version,
        reciter=reciter,
        quran_edition_version=quran_version,
        source_name="Approved synthetic audio source",
        source_url="https://example.test/sources/audio",
        source_version="2026-08-09",
        source_checksum_sha256="c" * 64,
        rights_holder="Test rights holder",
        license_name="Test worldwide distribution licence",
        license_url="https://example.test/licenses/audio",
        license_spdx_id="CC0-1.0",
        license_attribution="Synthetic test audio.",
    )


def _create_track(
    recitation: RecitationEdition,
    *,
    timing_version: AudioTimingVersion | None = None,
    object_key: str = "audio/test-recitation/1.0.0/surah-001.mp3",
) -> AudioTrack:
    return AudioTrack.objects.create(
        recitation_edition=recitation,
        timing_version=timing_version,
        scope=AudioTrackScope.SURAH,
        surah_number=1,
        duration_ms=12_000,
        codec=AudioCodec.MP3,
        bitrate_kbps=128,
        size_bytes=192_000,
        checksum_sha256="d" * 64,
        object_key=object_key,
    )


def _publish(
    recitation: RecitationEdition,
    *,
    stream_allowed: bool = True,
    offline_download_allowed: bool = True,
) -> None:
    recitation.stream_allowed = stream_allowed
    recitation.offline_download_allowed = offline_download_allowed
    recitation.publish()
    recitation.save()


def _create_second_public_recitation(
    quran_dataset: dict[str, Any],
    *,
    reciter: Reciter | None = None,
    code: str = "second-recitation",
    version: str = "2.0.0",
) -> RecitationEdition:
    if reciter is None:
        reciter = Reciter.objects.create(
            code="second-reciter",
            name_ar="القارئ الثاني",
            name_en="Second Reciter",
            name_ru="Второй чтец",
            country_code="EG",
        )
    recitation = _create_recitation(
        reciter,
        quran_dataset["version"],
        code=code,
        version=version,
    )
    _create_track(
        recitation,
        object_key=f"audio/{code}/{version}/surah-001.mp3",
    )
    _publish(recitation)
    return recitation


@pytest.mark.django_db
def test_anonymous_clients_can_read_audio_catalog_and_details(
    published_audio_dataset: dict[str, Any],
) -> None:
    client = APIClient()
    reciter = published_audio_dataset["reciter"]
    recitation = published_audio_dataset["recitation"]

    reciter_list = client.get(reverse("audio:reciter-list"))
    reciter_detail = client.get(reverse("audio:reciter-detail", kwargs={"reciter_id": reciter.id}))
    recitation_list = client.get(reverse("audio:recitation-list"))
    recitation_detail = client.get(
        reverse("audio:recitation-detail", kwargs={"recitation_id": recitation.id})
    )
    track_list = client.get(reverse("audio:track-list", kwargs={"recitation_id": recitation.id}))

    assert reciter_list.status_code == 200
    assert reciter_list.json()["results"][0]["id"] == str(reciter.id)
    assert reciter_detail.status_code == 200
    assert reciter_detail.json()["slug"] == "test-reciter"
    assert recitation_list.status_code == 200
    assert recitation_list.json()["results"][0]["id"] == str(recitation.id)
    assert recitation_detail.status_code == 200
    assert recitation_detail.json()["style"] == "murattal"
    assert recitation_detail.json()["source"]["url"] == ("https://example.test/sources/audio")
    assert recitation_detail.json()["license"]["url"] == ("https://example.test/licenses/audio")
    assert recitation_detail.json()["coverage"] == {
        "track_count": 1,
        "surah_count": 1,
        "complete": False,
    }
    assert recitation_detail.json()["timings"] == {
        "available": True,
        "segment_count": 2,
    }
    assert track_list.status_code == 200
    assert track_list.json()["results"][0]["id"] == str(published_audio_dataset["track"].id)


@pytest.mark.django_db
def test_recitation_list_uses_stable_cursor_pagination(
    api_client: APIClient,
    quran_dataset: dict[str, Any],
    published_audio_dataset: dict[str, Any],
) -> None:
    second = _create_second_public_recitation(quran_dataset)
    first_response = api_client.get(reverse("audio:recitation-list"), {"page_size": 1})

    assert first_response.status_code == 200
    first_payload = first_response.json()
    assert len(first_payload["results"]) == 1
    assert first_payload["next"] is not None

    second_response = api_client.get(first_payload["next"])

    assert second_response.status_code == 200
    second_payload = second_response.json()
    assert len(second_payload["results"]) == 1
    assert second_payload["next"] is None
    assert {
        first_payload["results"][0]["id"],
        second_payload["results"][0]["id"],
    } == {
        str(published_audio_dataset["recitation"].id),
        str(second.id),
    }


@pytest.mark.django_db
def test_audio_catalog_filters_recitations_and_tracks(
    api_client: APIClient,
    quran_dataset: dict[str, Any],
    published_audio_dataset: dict[str, Any],
) -> None:
    reciter = published_audio_dataset["reciter"]
    recitation = published_audio_dataset["recitation"]
    _create_second_public_recitation(quran_dataset)

    by_reciter = api_client.get(
        reverse("audio:recitation-list"),
        {"reciter_id": str(reciter.id)},
    )
    by_quran_edition = api_client.get(
        reverse("audio:recitation-list"),
        {"quran_edition": "madani-hafs"},
    )
    missing_quran_edition = api_client.get(
        reverse("audio:recitation-list"),
        {"quran_edition": "unknown-edition"},
    )
    by_style = api_client.get(
        reverse("audio:recitation-list"),
        {"style": "murattal"},
    )
    missing_style = api_client.get(
        reverse("audio:recitation-list"),
        {"style": "mujawwad"},
    )
    surah_tracks = api_client.get(
        reverse("audio:track-list", kwargs={"recitation_id": recitation.id}),
        {"scope": AudioTrackScope.SURAH},
    )
    full_tracks = api_client.get(
        reverse("audio:track-list", kwargs={"recitation_id": recitation.id}),
        {"scope": AudioTrackScope.FULL},
    )

    assert [item["id"] for item in by_reciter.json()["results"]] == [str(recitation.id)]
    assert len(by_quran_edition.json()["results"]) == 2
    assert missing_quran_edition.json()["results"] == []
    assert len(by_style.json()["results"]) == 2
    assert missing_style.json()["results"] == []
    assert [item["scope"] for item in surah_tracks.json()["results"]] == ["surah"]
    assert full_tracks.json()["results"] == []


@pytest.mark.django_db
@override_settings(PUBLIC_AUDIO_BASE_URL="https://cdn.example.test/quran-audio/")
def test_track_response_exposes_cdn_asset_contract_without_storage_fields(
    api_client: APIClient,
    published_audio_dataset: dict[str, Any],
) -> None:
    reciter = published_audio_dataset["reciter"]
    recitation = published_audio_dataset["recitation"]
    response = api_client.get(reverse("audio:track-list", kwargs={"recitation_id": recitation.id}))
    reciter_response = api_client.get(
        reverse("audio:reciter-detail", kwargs={"reciter_id": reciter.id})
    )

    assert response.status_code == 200
    track = response.json()["results"][0]
    assert track["asset"] == {
        "url": ("https://cdn.example.test/quran-audio/audio/test-recitation/1.0.0/surah-001.mp3"),
        "content_type": "audio/mpeg",
        "codec": "mp3",
        "bitrate_kbps": 128,
        "bytes": 192_000,
        "sha256": "d" * 64,
        "etag": f'"{"d" * 64}"',
        "range_supported": True,
        "immutable": True,
    }
    assert track["offline_download_allowed"] is True
    assert reciter_response.json()["portrait_url"] == (
        "https://cdn.example.test/quran-audio/audio/reciters/test-reciter.webp"
    )

    serialized = json.dumps(
        {"track": track, "reciter": reciter_response.json()},
        sort_keys=True,
    )
    assert '"object_key"' not in serialized
    assert '"portrait_object_key"' not in serialized


@pytest.mark.django_db
def test_track_contains_verified_timing_version(
    api_client: APIClient,
    published_audio_dataset: dict[str, Any],
) -> None:
    recitation = published_audio_dataset["recitation"]
    timing_version = published_audio_dataset["timing_version"]
    response = api_client.get(reverse("audio:track-list", kwargs={"recitation_id": recitation.id}))

    assert response.status_code == 200
    timing = response.json()["results"][0]["timing_version"]
    assert timing["id"] == str(timing_version.id)
    assert timing["version"] == "1.0.0"
    assert timing["source_name"] == "Verified synthetic timings"
    assert timing["source_version"] == "2026-08-09"
    assert timing["source_checksum_sha256"] == "e" * 64
    assert timing["verified_at"] is not None


@pytest.mark.django_db
def test_external_track_exposes_non_immutable_streaming_asset(
    api_client: APIClient,
    published_audio_dataset: dict[str, Any],
) -> None:
    track = published_audio_dataset["track"]
    AudioTrack.objects.filter(pk=track.pk).update(
        object_key=None,
        external_url="https://download.quranicaudio.com/qdc/test/1.mp3",
        checksum_sha256="",
    )

    response = api_client.get(
        reverse(
            "audio:track-list",
            kwargs={"recitation_id": published_audio_dataset["recitation"].id},
        )
    )

    assert response.status_code == 200
    asset = response.json()["results"][0]["asset"]
    assert asset == {
        "url": "https://download.quranicaudio.com/qdc/test/1.mp3",
        "content_type": "audio/mpeg",
        "codec": "mp3",
        "bitrate_kbps": 128,
        "bytes": 192_000,
        "sha256": None,
        "etag": None,
        "range_supported": False,
        "immutable": False,
    }


@pytest.mark.django_db
def test_surah_and_ayah_playback_payloads_are_timeline_ready(
    api_client: APIClient,
    quran_dataset: dict[str, Any],
    published_audio_dataset: dict[str, Any],
) -> None:
    recitation = published_audio_dataset["recitation"]
    track = published_audio_dataset["track"]
    surah_response = api_client.get(
        reverse(
            "audio:surah-playback",
            kwargs={"recitation_id": recitation.id, "surah": 1},
        )
    )
    ayah_response = api_client.get(
        reverse(
            "audio:ayah-playback",
            kwargs={"recitation_id": recitation.id, "surah": 1, "ayah": 2},
        )
    )

    assert surah_response.status_code == 200
    surah_payload = surah_response.json()
    assert surah_payload["track"]["id"] == str(track.id)
    assert surah_payload["segments"] == [
        {
            "ayah_id": str(quran_dataset["first_ayah"].id),
            "surah_number": 1,
            "ayah_number": 1,
            "start_ms": 0,
            "end_ms": 5_000,
        },
        {
            "ayah_id": str(quran_dataset["second_ayah"].id),
            "surah_number": 1,
            "ayah_number": 2,
            "start_ms": 5_000,
            "end_ms": 10_000,
        },
    ]

    assert ayah_response.status_code == 200
    ayah_payload = ayah_response.json()
    assert ayah_payload["track"]["id"] == str(track.id)
    assert ayah_payload["segment"] == surah_payload["segments"][1]


@pytest.mark.django_db
def test_audio_api_supports_conditional_etag(
    api_client: APIClient,
    published_audio_dataset: dict[str, Any],
) -> None:
    recitation = published_audio_dataset["recitation"]
    url = reverse(
        "audio:surah-playback",
        kwargs={"recitation_id": recitation.id, "surah": 1},
    )
    first_response = api_client.get(url)
    assert first_response.headers["ETag"].startswith('W/"')

    second_response = api_client.get(
        url,
        headers={"If-None-Match": first_response.headers["ETag"]},
    )

    assert second_response.status_code == 304
    assert second_response.headers["ETag"] == first_response.headers["ETag"]
    assert second_response.headers["Cache-Control"].startswith("public")

    strong_form = first_response.headers["ETag"].removeprefix("W/")
    list_response = api_client.get(
        url,
        headers={"If-None-Match": f'"not-current", {strong_form}'},
    )
    wildcard_response = api_client.get(url, headers={"If-None-Match": "*"})

    assert list_response.status_code == 304
    assert wildcard_response.status_code == 304


@pytest.mark.django_db
@pytest.mark.parametrize(
    "hidden_state",
    [
        "draft",
        "withdrawn",
        "inactive_reciter",
        "non_streaming",
        "withdrawn_quran_version",
        "inactive_quran_version",
        "empty_recitation",
    ],
)
def test_non_public_recitations_and_reciters_are_hidden(
    api_client: APIClient,
    quran_dataset: dict[str, Any],
    published_audio_dataset: dict[str, Any],
    hidden_state: str,
) -> None:
    reciter = published_audio_dataset["reciter"]
    recitation = published_audio_dataset["recitation"]
    if hidden_state == "draft":
        RecitationEdition.objects.filter(pk=recitation.id).update(
            status=RecitationPublicationStatus.DRAFT,
            published_at=None,
        )
    elif hidden_state == "withdrawn":
        RecitationEdition.objects.filter(pk=recitation.id).update(
            status=RecitationPublicationStatus.WITHDRAWN
        )
    elif hidden_state == "inactive_reciter":
        Reciter.objects.filter(pk=reciter.id).update(is_active=False)
    elif hidden_state == "non_streaming":
        RecitationEdition.objects.filter(pk=recitation.id).update(stream_allowed=False)
    elif hidden_state == "withdrawn_quran_version":
        QuranEditionVersion.objects.filter(pk=quran_dataset["version"].id).update(
            status=PublicationStatus.WITHDRAWN
        )
    elif hidden_state == "inactive_quran_version":
        inactive_version = QuranEditionVersion.objects.create(
            edition=quran_dataset["edition"],
            version="2.0.0",
            checksum_sha256="f" * 64,
            status=PublicationStatus.PUBLISHED,
            page_count=604,
            surah_count=114,
            juz_count=30,
            published_at=timezone.now(),
        )
        QuranEdition.objects.filter(pk=quran_dataset["edition"].id).update(
            active_version=inactive_version
        )
    else:
        AudioTrack.objects.filter(recitation_edition=recitation).delete()

    recitation_list = api_client.get(reverse("audio:recitation-list"))
    recitation_detail = api_client.get(
        reverse("audio:recitation-detail", kwargs={"recitation_id": recitation.id})
    )
    reciter_list = api_client.get(reverse("audio:reciter-list"))
    reciter_detail = api_client.get(
        reverse("audio:reciter-detail", kwargs={"reciter_id": reciter.id})
    )

    assert recitation_list.json()["results"] == []
    assert recitation_detail.status_code == 404
    assert recitation_detail.content_type == "application/problem+json"
    assert reciter_list.json()["results"] == []
    assert reciter_detail.status_code == 404


@pytest.mark.django_db
def test_invalid_audio_catalog_filters_return_problem_details(
    api_client: APIClient,
    published_audio_dataset: dict[str, Any],
) -> None:
    recitation = published_audio_dataset["recitation"]
    invalid_reciter = api_client.get(
        reverse("audio:recitation-list"),
        {"reciter_id": "not-a-uuid"},
    )
    invalid_scope = api_client.get(
        reverse("audio:track-list", kwargs={"recitation_id": recitation.id}),
        {"scope": "podcast"},
    )
    invalid_page_size = api_client.get(
        reverse("audio:reciter-list"),
        {"page_size": 101},
    )

    for response in (invalid_reciter, invalid_scope, invalid_page_size):
        assert response.status_code == 400
        assert response.content_type == "application/problem+json"
        assert response.json()["detail"] == "Request validation failed."
        assert response.json()["field_errors"]


@pytest.mark.django_db
def test_track_list_returns_404_for_an_unknown_or_hidden_recitation(
    api_client: APIClient,
    published_audio_dataset: dict[str, Any],
) -> None:
    recitation = published_audio_dataset["recitation"]
    RecitationEdition.objects.filter(pk=recitation.id).update(
        status=RecitationPublicationStatus.WITHDRAWN
    )

    hidden = api_client.get(reverse("audio:track-list", kwargs={"recitation_id": recitation.id}))
    unknown = api_client.get(
        reverse(
            "audio:track-list",
            kwargs={"recitation_id": "00000000-0000-7000-8000-000000000000"},
        )
    )

    assert hidden.status_code == 404
    assert unknown.status_code == 404
    assert hidden.content_type == unknown.content_type == "application/problem+json"


@pytest.mark.django_db
def test_ayah_playback_returns_404_when_verified_timing_is_missing(
    api_client: APIClient,
    quran_dataset: dict[str, Any],
) -> None:
    reciter = Reciter.objects.create(
        code="untimed-reciter",
        name_ar="قارئ بلا توقيت",
        name_en="Untimed Reciter",
        name_ru="Чтец без таймингов",
    )
    recitation = _create_recitation(
        reciter,
        quran_dataset["version"],
        code="untimed-recitation",
        version="1.0.0",
    )
    _create_track(
        recitation,
        object_key="audio/untimed/1.0.0/surah-001.mp3",
    )
    _publish(recitation)

    response = api_client.get(
        reverse(
            "audio:ayah-playback",
            kwargs={"recitation_id": recitation.id, "surah": 1, "ayah": 1},
        )
    )

    assert response.status_code == 404
    assert response.content_type == "application/problem+json"
    assert response.json()["detail"] == "Verified audio timing is not available for this ayah."


@pytest.mark.django_db
def test_recitation_list_is_free_of_serializer_n_plus_one_queries(
    api_client: APIClient,
    quran_dataset: dict[str, Any],
    published_audio_dataset: dict[str, Any],
) -> None:
    _create_second_public_recitation(
        quran_dataset,
        reciter=published_audio_dataset["reciter"],
        code="query-count-recitation",
        version="2.0.0",
    )

    with CaptureQueriesContext(connection) as captured:
        response = api_client.get(reverse("audio:recitation-list"))

    assert response.status_code == 200
    assert len(response.json()["results"]) == 2
    assert len(captured) == 1
