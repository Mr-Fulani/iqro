from __future__ import annotations

from datetime import timedelta
from typing import Any

import pytest
from django.core.exceptions import ValidationError
from django.utils import timezone

from quran_backend.modules.audio.models import (
    AudioCodec,
    AudioTimingVersion,
    AudioTrack,
    AudioTrackScope,
    AyahAudioSegment,
    RecitationEdition,
    RecitationPublicationStatus,
    RecitationStyle,
    Reciter,
)
from quran_backend.modules.audio.validators import (
    validate_relative_object_key,
    validate_sha256,
    validate_version_identifier,
)
from quran_backend.modules.quran.models import (
    Ayah,
    PublicationStatus,
    QuranEditionVersion,
    RevelationType,
    Surah,
)


@pytest.fixture
def reciter(db: None) -> Reciter:
    return Reciter.objects.create(
        code="test-reciter",
        name_ar="قارئ الاختبار",
        name_en="Test Reciter",
        name_ru="Тестовый чтец",
        country_code="SA",
    )


@pytest.fixture
def draft_recitation(
    quran_dataset: dict[str, Any],
    reciter: Reciter,
) -> RecitationEdition:
    return _create_recitation(reciter, quran_dataset["version"])


@pytest.fixture
def surah_track(draft_recitation: RecitationEdition) -> AudioTrack:
    timing_version = _create_timing_version(draft_recitation)
    return _create_track(draft_recitation, timing_version=timing_version)


def _create_recitation(
    reciter: Reciter,
    quran_version: QuranEditionVersion,
    *,
    code: str = "test-recitation",
    version: str = "1.0.0",
    style: str = RecitationStyle.MURATTAL,
) -> RecitationEdition:
    return RecitationEdition.objects.create(
        code=code,
        version=version,
        style=style,
        reciter=reciter,
        quran_edition_version=quran_version,
        source_name="Approved test source",
        source_version="2026-08-09",
        source_checksum_sha256="a" * 64,
        rights_holder="Test rights holder",
        license_name="Test worldwide distribution licence",
        license_spdx_id="CC0-1.0",
        license_attribution="Synthetic test audio.",
    )


def _create_track(  # noqa: PLR0913
    recitation: RecitationEdition,
    *,
    timing_version: AudioTimingVersion | None = None,
    scope: str = AudioTrackScope.SURAH,
    surah_number: int | None = 1,
    juz_number: int | None = None,
    object_key: str = "audio/test-recitation/1.0.0/surah-001.mp3",
    duration_ms: int = 10_000,
) -> AudioTrack:
    return AudioTrack.objects.create(
        recitation_edition=recitation,
        timing_version=timing_version,
        scope=scope,
        surah_number=surah_number,
        juz_number=juz_number,
        duration_ms=duration_ms,
        codec=AudioCodec.MP3,
        bitrate_kbps=128,
        size_bytes=160_000,
        checksum_sha256="b" * 64,
        object_key=object_key,
    )


def _create_timing_version(
    recitation: RecitationEdition,
    *,
    version: str = "1.0.0",
    verified: bool = True,
) -> AudioTimingVersion:
    return AudioTimingVersion.objects.create(
        recitation_edition=recitation,
        version=version,
        source_name="Verified synthetic timing source",
        source_version="2026-08-09",
        source_checksum_sha256="e" * 64,
        verified_at=timezone.now() if verified else None,
    )


def _publish(
    recitation: RecitationEdition,
    *,
    stream_allowed: bool = True,
    offline_download_allowed: bool = True,
) -> None:
    if not recitation.tracks.exists():
        _create_track(
            recitation,
            object_key=f"audio/{recitation.code}/{recitation.version}/surah-001.mp3",
        )
    recitation.stream_allowed = stream_allowed
    recitation.offline_download_allowed = offline_download_allowed
    recitation.publish()
    recitation.save()


def _create_quran_version(
    quran_dataset: dict[str, Any],
    *,
    version: str,
    status: str,
) -> QuranEditionVersion:
    return QuranEditionVersion.objects.create(
        edition=quran_dataset["edition"],
        version=version,
        checksum_sha256="c" * 64,
        status=status,
        page_count=604,
        surah_count=114,
        juz_count=30,
        published_at=timezone.now() if status == PublicationStatus.PUBLISHED else None,
    )


def _create_ayah(
    quran_version: QuranEditionVersion,
    *,
    surah_number: int,
    ayah_number: int = 1,
    juz_number: int = 1,
) -> Ayah:
    surah = Surah.objects.create(
        edition_version=quran_version,
        number=surah_number,
        name_ar=f"سورة {surah_number}",
        name_en=f"Surah {surah_number}",
        name_ru=f"Surah {surah_number}",
        revelation_type=RevelationType.MECCAN,
        ayah_count=max(ayah_number, 1),
    )
    return Ayah.objects.create(
        surah=surah,
        number=ayah_number,
        text_uthmani="نص اختباري",
        text_search="نص اختباري",
        juz_number=juz_number,
    )


@pytest.mark.parametrize(
    "value",
    [
        "A" * 64,
        "a" * 63,
        "a" * 65,
        "g" * 64,
        " a" * 32,
    ],
)
def test_sha256_validator_requires_canonical_lowercase_digest(value: str) -> None:
    with pytest.raises(ValidationError):
        validate_sha256(value)

    validate_sha256("0123456789abcdef" * 4)


@pytest.mark.parametrize(
    "value",
    ["", ".hidden", "-version", "version/1", "version 1", "версия", "v" * 65],
)
def test_version_validator_rejects_ambiguous_or_path_unsafe_values(value: str) -> None:
    with pytest.raises(ValidationError):
        validate_version_identifier(value)

    validate_version_identifier("2026.08.09-hafs_1")


@pytest.mark.parametrize(
    "value",
    [
        "/audio/001.mp3",
        "https://cdn.example/audio.mp3",
        "audio/../secret.mp3",
        "audio/./001.mp3",
        "audio//001.mp3",
        "audio/001 mp3",
        "audio/001.mp3?token=secret",
        "аудио/001.mp3",
    ],
)
def test_object_key_validator_rejects_urls_traversal_and_ambiguous_paths(value: str) -> None:
    with pytest.raises(ValidationError):
        validate_relative_object_key(value)

    validate_relative_object_key("audio/hafs/v1/surah-001.mp3")


@pytest.mark.django_db
def test_reciter_normalizes_iso_country_and_validates_portrait_key() -> None:
    reciter = Reciter(
        code="normalization-test",
        name_ar="قارئ",
        name_en="Reciter",
        name_ru="Чтец",
        country_code="sa",
        portrait_object_key="images/reciters/reciter.webp",
    )

    reciter.full_clean()

    assert reciter.country_code == "SA"

    reciter.portrait_object_key = "../private/portrait.webp"
    with pytest.raises(ValidationError) as error:
        reciter.full_clean()
    assert "portrait_object_key" in error.value.message_dict


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("stream_allowed", "offline_download_allowed", "missing_field"),
    [
        (None, True, "stream_allowed"),
        (True, None, "offline_download_allowed"),
        (None, None, "stream_allowed"),
    ],
)
def test_publication_requires_explicit_stream_and_offline_rights_decisions(
    quran_dataset: dict[str, Any],
    reciter: Reciter,
    stream_allowed: bool | None,
    offline_download_allowed: bool | None,
    missing_field: str,
) -> None:
    recitation = _create_recitation(reciter, quran_dataset["version"])
    recitation.stream_allowed = stream_allowed
    recitation.offline_download_allowed = offline_download_allowed
    recitation.publish()

    with pytest.raises(ValidationError) as error:
        recitation.save()

    assert missing_field in error.value.message_dict
    recitation.refresh_from_db()
    assert recitation.status == RecitationPublicationStatus.DRAFT
    assert recitation.published_at is None


@pytest.mark.django_db
def test_explicit_rights_denial_is_preserved_as_a_publication_decision(
    draft_recitation: RecitationEdition,
) -> None:
    _publish(
        draft_recitation,
        stream_allowed=False,
        offline_download_allowed=False,
    )

    draft_recitation.refresh_from_db()
    assert draft_recitation.status == RecitationPublicationStatus.PUBLISHED
    assert draft_recitation.stream_allowed is False
    assert draft_recitation.offline_download_allowed is False


@pytest.mark.django_db
@pytest.mark.parametrize(
    "field",
    ["source_name", "source_version", "rights_holder", "license_name"],
)
def test_publication_requires_source_and_licensing_provenance(
    draft_recitation: RecitationEdition,
    field: str,
) -> None:
    setattr(draft_recitation, field, "")
    draft_recitation.stream_allowed = True
    draft_recitation.offline_download_allowed = True
    draft_recitation.publish()

    with pytest.raises(ValidationError) as error:
        draft_recitation.save()

    assert field in error.value.message_dict


@pytest.mark.django_db
def test_recitation_cannot_publish_against_a_draft_quran_version(
    quran_dataset: dict[str, Any],
    reciter: Reciter,
) -> None:
    quran_version = _create_quran_version(
        quran_dataset,
        version="2.0.0-draft",
        status=PublicationStatus.DRAFT,
    )
    recitation = _create_recitation(reciter, quran_version)
    recitation.stream_allowed = True
    recitation.offline_download_allowed = True
    recitation.publish()

    with pytest.raises(ValidationError) as error:
        recitation.save()

    assert "quran_edition_version" in error.value.message_dict


@pytest.mark.django_db
def test_recitation_cannot_publish_against_an_inactive_quran_version(
    quran_dataset: dict[str, Any],
    reciter: Reciter,
) -> None:
    inactive_version = _create_quran_version(
        quran_dataset,
        version="0.9.0",
        status=PublicationStatus.PUBLISHED,
    )
    recitation = _create_recitation(reciter, inactive_version)
    recitation.stream_allowed = True
    recitation.offline_download_allowed = True
    recitation.publish()

    with pytest.raises(ValidationError) as error:
        recitation.save()

    assert "quran_edition_version" in error.value.message_dict


@pytest.mark.django_db
def test_recitation_style_is_part_of_versioned_package_identity(
    quran_dataset: dict[str, Any],
    reciter: Reciter,
) -> None:
    _create_recitation(reciter, quran_dataset["version"])
    _create_recitation(
        reciter,
        quran_dataset["version"],
        code="test-recitation-mujawwad",
        version="1.0.0",
        style=RecitationStyle.MUJAWWAD,
    )

    duplicate_mujawwad = _create_recitation(
        reciter,
        quran_dataset["version"],
        code="test-recitation-mujawwad-duplicate",
        version="1.0.1",
        style=RecitationStyle.MUJAWWAD,
    )
    duplicate_mujawwad.version = "1.0.0"
    with pytest.raises(ValidationError):
        duplicate_mujawwad.save()


@pytest.mark.django_db
def test_publication_and_withdrawal_are_one_way_state_transitions(
    draft_recitation: RecitationEdition,
) -> None:
    _publish(draft_recitation)
    published_at = draft_recitation.published_at

    with pytest.raises(ValidationError):
        draft_recitation.publish()

    draft_recitation.withdraw()
    draft_recitation.save()
    draft_recitation.refresh_from_db()
    assert draft_recitation.status == RecitationPublicationStatus.WITHDRAWN
    assert draft_recitation.published_at == published_at

    draft_recitation.status = RecitationPublicationStatus.PUBLISHED
    with pytest.raises(ValidationError) as error:
        draft_recitation.save()
    assert "status" in error.value.message_dict

    draft_recitation.refresh_from_db()
    with pytest.raises(ValidationError):
        draft_recitation.withdraw()


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("field", "replacement"),
    [
        ("code", "changed-code"),
        ("version", "2.0.0"),
        ("style", "mujawwad"),
        ("source_name", "Changed source"),
        ("source_url", "https://example.test/changed-source"),
        ("source_version", "changed"),
        ("source_checksum_sha256", "d" * 64),
        ("rights_holder", "Changed rights holder"),
        ("license_name", "Changed licence"),
        ("license_url", "https://example.test/changed-license"),
        ("license_attribution", "Changed attribution"),
        ("stream_allowed", False),
        ("offline_download_allowed", False),
    ],
)
def test_published_recitation_metadata_is_immutable(
    draft_recitation: RecitationEdition,
    field: str,
    replacement: object,
) -> None:
    _publish(draft_recitation)
    setattr(draft_recitation, field, replacement)

    with pytest.raises(ValidationError) as error:
        draft_recitation.save()

    assert field in error.value.message_dict


@pytest.mark.django_db
def test_published_timestamp_is_immutable(draft_recitation: RecitationEdition) -> None:
    _publish(draft_recitation)
    assert draft_recitation.published_at is not None
    draft_recitation.published_at += timedelta(seconds=1)

    with pytest.raises(ValidationError) as error:
        draft_recitation.save()

    assert "published_at" in error.value.message_dict


@pytest.mark.django_db
def test_published_and_withdrawn_recitations_cannot_be_deleted(
    draft_recitation: RecitationEdition,
) -> None:
    _publish(draft_recitation)
    with pytest.raises(ValidationError, match="cannot be deleted"):
        draft_recitation.delete()

    draft_recitation.withdraw()
    draft_recitation.save()
    with pytest.raises(ValidationError, match="cannot be deleted"):
        draft_recitation.delete()


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("scope", "surah_number", "juz_number"),
    [
        (AudioTrackScope.SURAH, None, None),
        (AudioTrackScope.SURAH, 1, 1),
        (AudioTrackScope.SURAH, 115, None),
        (AudioTrackScope.JUZ, None, None),
        (AudioTrackScope.JUZ, 1, 1),
        (AudioTrackScope.JUZ, None, 31),
        (AudioTrackScope.FULL, 1, None),
        (AudioTrackScope.FULL, None, 1),
        ("unknown", None, None),
    ],
)
def test_track_scope_requires_exactly_the_matching_canonical_target(
    draft_recitation: RecitationEdition,
    scope: str,
    surah_number: int | None,
    juz_number: int | None,
) -> None:
    track = AudioTrack(
        recitation_edition=draft_recitation,
        scope=scope,
        surah_number=surah_number,
        juz_number=juz_number,
        duration_ms=10_000,
        codec=AudioCodec.MP3,
        bitrate_kbps=128,
        size_bytes=160_000,
        checksum_sha256="b" * 64,
        object_key="audio/invalid-scope.mp3",
    )

    with pytest.raises(ValidationError):
        track.save()


@pytest.mark.django_db
def test_all_track_scopes_accept_only_their_valid_target(
    draft_recitation: RecitationEdition,
) -> None:
    surah = _create_track(draft_recitation)
    juz = _create_track(
        draft_recitation,
        scope=AudioTrackScope.JUZ,
        surah_number=None,
        juz_number=1,
        object_key="audio/test-recitation/1.0.0/juz-001.mp3",
    )
    full = _create_track(
        draft_recitation,
        scope=AudioTrackScope.FULL,
        surah_number=None,
        object_key="audio/test-recitation/1.0.0/full.mp3",
    )

    assert (surah.surah_number, surah.juz_number) == (1, None)
    assert (juz.surah_number, juz.juz_number) == (None, 1)
    assert (full.surah_number, full.juz_number) == (None, None)


@pytest.mark.django_db
@pytest.mark.parametrize(
    "object_key",
    ["/audio/001.mp3", "audio/../001.mp3", "https://cdn.example/001.mp3"],
)
def test_track_rejects_unsafe_object_keys(
    draft_recitation: RecitationEdition,
    object_key: str,
) -> None:
    with pytest.raises(ValidationError) as error:
        _create_track(draft_recitation, object_key=object_key)

    assert "object_key" in error.value.message_dict


@pytest.mark.django_db
def test_track_content_type_must_match_codec(
    draft_recitation: RecitationEdition,
) -> None:
    track = AudioTrack(
        recitation_edition=draft_recitation,
        scope=AudioTrackScope.SURAH,
        surah_number=1,
        duration_ms=10_000,
        codec=AudioCodec.MP3,
        bitrate_kbps=128,
        size_bytes=160_000,
        checksum_sha256="b" * 64,
        object_key="audio/001.mp3",
        content_type="audio/ogg",
    )

    with pytest.raises(ValidationError) as error:
        track.save()

    assert "content_type" in error.value.message_dict


@pytest.mark.django_db
def test_track_identity_is_unique_inside_a_recitation(
    draft_recitation: RecitationEdition,
) -> None:
    _create_track(draft_recitation)

    with pytest.raises(ValidationError):
        _create_track(
            draft_recitation,
            object_key="audio/test-recitation/1.0.0/duplicate-surah-001.mp3",
        )


@pytest.mark.django_db
def test_track_timing_version_must_belong_to_the_exact_same_recitation(
    quran_dataset: dict[str, Any],
    reciter: Reciter,
    draft_recitation: RecitationEdition,
) -> None:
    other_recitation = _create_recitation(
        reciter,
        quran_dataset["version"],
        code="other-recitation",
        version="2.0.0",
    )
    foreign_timing_version = _create_timing_version(other_recitation)

    with pytest.raises(ValidationError) as error:
        _create_track(draft_recitation, timing_version=foreign_timing_version)

    assert "timing_version" in error.value.message_dict


@pytest.mark.django_db
def test_segment_requires_versioned_timing_provenance(
    quran_dataset: dict[str, Any],
    draft_recitation: RecitationEdition,
) -> None:
    track_without_timings = _create_track(draft_recitation)
    segment = AyahAudioSegment(
        track=track_without_timings,
        ayah=quran_dataset["first_ayah"],
        start_ms=0,
        end_ms=1000,
    )

    with pytest.raises(ValidationError) as error:
        segment.save()

    assert "track" in error.value.message_dict


@pytest.mark.django_db
def test_segment_rejects_an_unverified_timing_version(
    quran_dataset: dict[str, Any],
    draft_recitation: RecitationEdition,
) -> None:
    unverified_timing = _create_timing_version(draft_recitation, verified=False)
    track = _create_track(draft_recitation, timing_version=unverified_timing)
    segment = AyahAudioSegment(
        track=track,
        ayah=quran_dataset["first_ayah"],
        start_ms=0,
        end_ms=1000,
    )

    with pytest.raises(ValidationError) as error:
        segment.save()

    assert "track" in error.value.message_dict


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("start_ms", "end_ms", "error_field"),
    [(1000, 1000, "end_ms"), (2000, 1000, "end_ms"), (9000, 10_001, "end_ms")],
)
def test_segment_must_be_a_positive_range_inside_track_duration(
    quran_dataset: dict[str, Any],
    surah_track: AudioTrack,
    start_ms: int,
    end_ms: int,
    error_field: str,
) -> None:
    segment = AyahAudioSegment(
        track=surah_track,
        ayah=quran_dataset["first_ayah"],
        start_ms=start_ms,
        end_ms=end_ms,
    )

    with pytest.raises(ValidationError) as error:
        segment.save()

    assert error_field in error.value.message_dict


@pytest.mark.django_db
def test_segment_ayah_must_match_the_exact_quran_edition_version(
    quran_dataset: dict[str, Any],
    surah_track: AudioTrack,
) -> None:
    other_version = _create_quran_version(
        quran_dataset,
        version="2.0.0-draft",
        status=PublicationStatus.DRAFT,
    )
    ayah_from_other_version = _create_ayah(other_version, surah_number=1)
    segment = AyahAudioSegment(
        track=surah_track,
        ayah=ayah_from_other_version,
        start_ms=0,
        end_ms=1000,
    )

    with pytest.raises(ValidationError) as error:
        segment.save()

    assert "ayah" in error.value.message_dict


@pytest.mark.django_db
def test_segment_ayah_must_match_surah_track_scope(
    quran_dataset: dict[str, Any],
    surah_track: AudioTrack,
) -> None:
    other_surah_ayah = _create_ayah(quran_dataset["version"], surah_number=2)
    segment = AyahAudioSegment(
        track=surah_track,
        ayah=other_surah_ayah,
        start_ms=0,
        end_ms=1000,
    )

    with pytest.raises(ValidationError) as error:
        segment.save()

    assert "ayah" in error.value.message_dict


@pytest.mark.django_db
def test_segment_ayah_must_match_juz_track_scope(
    quran_dataset: dict[str, Any],
    draft_recitation: RecitationEdition,
) -> None:
    timing_version = _create_timing_version(draft_recitation)
    juz_track = _create_track(
        draft_recitation,
        timing_version=timing_version,
        scope=AudioTrackScope.JUZ,
        surah_number=None,
        juz_number=2,
        object_key="audio/test-recitation/1.0.0/juz-002.mp3",
    )
    segment = AyahAudioSegment(
        track=juz_track,
        ayah=quran_dataset["first_ayah"],
        start_ms=0,
        end_ms=1000,
    )

    with pytest.raises(ValidationError) as error:
        segment.save()

    assert "ayah" in error.value.message_dict


@pytest.mark.django_db
def test_adjacent_segments_are_allowed_but_overlap_is_rejected(
    quran_dataset: dict[str, Any],
    surah_track: AudioTrack,
) -> None:
    first = AyahAudioSegment.objects.create(
        track=surah_track,
        ayah=quran_dataset["first_ayah"],
        start_ms=0,
        end_ms=1000,
    )
    second = AyahAudioSegment.objects.create(
        track=surah_track,
        ayah=quran_dataset["second_ayah"],
        start_ms=1000,
        end_ms=2000,
    )

    assert first.end_ms == second.start_ms

    second.start_ms = 999
    with pytest.raises(ValidationError, match="must not overlap"):
        second.save()

    second.refresh_from_db()
    assert second.start_ms == 1000


@pytest.mark.django_db
def test_tracks_cannot_be_created_changed_or_deleted_after_publication(
    draft_recitation: RecitationEdition,
    surah_track: AudioTrack,
) -> None:
    _publish(draft_recitation)

    surah_track.duration_ms += 1
    with pytest.raises(ValidationError, match="immutable"):
        surah_track.save()
    surah_track.refresh_from_db()

    with pytest.raises(ValidationError, match="immutable"):
        _create_track(
            draft_recitation,
            surah_number=2,
            object_key="audio/test-recitation/1.0.0/surah-002.mp3",
        )

    with pytest.raises(ValidationError, match="immutable"):
        surah_track.delete()


@pytest.mark.django_db
def test_timing_versions_and_track_binding_are_immutable_after_publication(
    draft_recitation: RecitationEdition,
    surah_track: AudioTrack,
) -> None:
    timing_version = surah_track.timing_version
    assert timing_version is not None
    alternative = _create_timing_version(draft_recitation, version="1.0.1")
    _publish(draft_recitation)

    timing_version.source_name = "Changed timing source"
    with pytest.raises(ValidationError, match="immutable"):
        timing_version.save()
    timing_version.refresh_from_db()

    with pytest.raises(ValidationError, match="immutable"):
        _create_timing_version(draft_recitation, version="2.0.0")

    with pytest.raises(ValidationError, match="immutable"):
        timing_version.delete()

    surah_track.timing_version = alternative
    with pytest.raises(ValidationError, match="immutable"):
        surah_track.save()


@pytest.mark.django_db
def test_segments_cannot_be_created_changed_or_deleted_after_publication(
    quran_dataset: dict[str, Any],
    draft_recitation: RecitationEdition,
    surah_track: AudioTrack,
) -> None:
    segment = AyahAudioSegment.objects.create(
        track=surah_track,
        ayah=quran_dataset["first_ayah"],
        start_ms=0,
        end_ms=1000,
    )
    _publish(draft_recitation)

    segment.end_ms = 900
    with pytest.raises(ValidationError, match="immutable"):
        segment.save()
    segment.refresh_from_db()

    with pytest.raises(ValidationError, match="immutable"):
        AyahAudioSegment.objects.create(
            track=surah_track,
            ayah=quran_dataset["second_ayah"],
            start_ms=1000,
            end_ms=2000,
        )

    with pytest.raises(ValidationError, match="immutable"):
        segment.delete()


@pytest.mark.django_db
def test_empty_recitation_cannot_be_published(draft_recitation: RecitationEdition) -> None:
    draft_recitation.stream_allowed = True
    draft_recitation.offline_download_allowed = True
    draft_recitation.publish()

    with pytest.raises(ValidationError) as error:
        draft_recitation.save()

    assert "status" in error.value.message_dict
    assert "At least one surah audio track" in error.value.message_dict["status"][0]


@pytest.mark.django_db
def test_timing_provenance_cannot_change_after_segments_use_it(
    quran_dataset: dict[str, Any],
    surah_track: AudioTrack,
) -> None:
    AyahAudioSegment.objects.create(
        track=surah_track,
        ayah=quran_dataset["first_ayah"],
        start_ms=0,
        end_ms=1000,
    )
    timing_version = surah_track.timing_version
    assert timing_version is not None
    timing_version.verified_at = None

    with pytest.raises(ValidationError) as error:
        timing_version.save()

    assert "verified_at" in error.value.message_dict


@pytest.mark.django_db
def test_segment_bound_track_structure_is_immutable_while_still_draft(
    quran_dataset: dict[str, Any],
    surah_track: AudioTrack,
) -> None:
    AyahAudioSegment.objects.create(
        track=surah_track,
        ayah=quran_dataset["first_ayah"],
        start_ms=0,
        end_ms=1000,
    )
    surah_track.duration_ms += 1

    with pytest.raises(ValidationError) as error:
        surah_track.save()

    assert "duration_ms" in error.value.message_dict


@pytest.mark.django_db
def test_publication_revalidates_timing_children_after_bypassed_bulk_change(
    quran_dataset: dict[str, Any],
    draft_recitation: RecitationEdition,
    surah_track: AudioTrack,
) -> None:
    AyahAudioSegment.objects.create(
        track=surah_track,
        ayah=quran_dataset["first_ayah"],
        start_ms=0,
        end_ms=1000,
    )
    assert surah_track.timing_version_id is not None
    AudioTimingVersion.objects.filter(pk=surah_track.timing_version_id).update(verified_at=None)
    draft_recitation.stream_allowed = True
    draft_recitation.offline_download_allowed = True
    draft_recitation.publish()

    with pytest.raises(ValidationError) as error:
        draft_recitation.save()

    assert "status" in error.value.message_dict
    assert "verified timing provenance" in error.value.message_dict["status"][0]


@pytest.mark.django_db
def test_in_memory_status_spoof_cannot_delete_a_published_recitation(
    draft_recitation: RecitationEdition,
) -> None:
    _publish(draft_recitation)
    draft_recitation.status = RecitationPublicationStatus.DRAFT

    with pytest.raises(ValidationError, match="cannot be deleted"):
        draft_recitation.delete()

    assert RecitationEdition.objects.filter(pk=draft_recitation.pk).exists()


@pytest.mark.django_db
def test_in_memory_parent_spoof_cannot_move_or_delete_a_published_track(
    quran_dataset: dict[str, Any],
    reciter: Reciter,
    draft_recitation: RecitationEdition,
) -> None:
    track = _create_track(draft_recitation)
    _publish(draft_recitation)
    other_recitation = _create_recitation(
        reciter,
        quran_dataset["version"],
        code="other-draft-recitation",
        version="2.0.0",
    )
    track.recitation_edition = other_recitation

    with pytest.raises(ValidationError, match="immutable"):
        track.save()
    with pytest.raises(ValidationError, match="immutable"):
        track.delete()

    track.refresh_from_db()
    assert track.recitation_edition_id == draft_recitation.id
