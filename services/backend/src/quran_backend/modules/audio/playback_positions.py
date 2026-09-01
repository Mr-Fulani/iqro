from __future__ import annotations

from typing import Any

from django.db import transaction
from rest_framework import status
from rest_framework.exceptions import APIException, ValidationError

from quran_backend.modules.accounts.models import Device, User
from quran_backend.modules.audio.models import (
    AudioPlaybackPosition,
    AudioTrack,
    AudioTrackScope,
    RecitationPublicationStatus,
)


class AudioPlaybackPositionRevisionConflict(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The audio playback position changed on another client."
    default_code = "audio_playback_position_revision_conflict"


def get_audio_playback_position(user: User) -> AudioPlaybackPosition | None:
    return (
        AudioPlaybackPosition.objects.filter(user=user)
        .select_related("track__recitation_edition__reciter")
        .first()
    )


@transaction.atomic
def put_audio_playback_position(
    *,
    user: User,
    device: Device | None,
    data: dict[str, Any],
) -> AudioPlaybackPosition:
    User.objects.select_for_update().only("id").get(pk=user.pk)
    current = (
        AudioPlaybackPosition.objects.select_for_update()
        .filter(user=user)
        .select_related("track__recitation_edition__reciter")
        .first()
    )
    track = (
        AudioTrack.objects.select_related("recitation_edition__reciter")
        .filter(pk=data["track_id"])
        .first()
    )
    _validate_track_and_position(track=track, data=data)
    assert track is not None

    desired = _desired_state(track=track, data=data)
    if current is not None and _stored_state(current) == desired:
        return current
    if current is None:
        if data["base_revision"] != 0:
            raise AudioPlaybackPositionRevisionConflict
        current = AudioPlaybackPosition(user=user, revision=1)
    else:
        if data["base_revision"] != current.revision:
            raise AudioPlaybackPositionRevisionConflict
        current.revision += 1

    current.device = device
    current.track = track
    current.position_ms = data["position_ms"]
    current.speed = data["speed"]
    current.repeat_enabled = data["repeat_enabled"]
    current.range_start_ayah = data["range_start_ayah"]
    current.range_end_ayah = data["range_end_ayah"]
    current.client_updated_at = data["client_updated_at"]
    current.full_clean()
    current.save()
    return current


def _validate_track_and_position(*, track: AudioTrack | None, data: dict[str, Any]) -> None:
    if (
        track is None
        or track.scope != AudioTrackScope.SURAH
        or track.recitation_edition.status != RecitationPublicationStatus.PUBLISHED
        or not track.recitation_edition.stream_allowed
    ):
        raise ValidationError({"track_id": "Select a published, streamable surah track."})
    if data["position_ms"] > track.duration_ms:
        raise ValidationError({"position_ms": "The position exceeds the track duration."})
    start = data["range_start_ayah"]
    end = data["range_end_ayah"]
    if start is None or end is None:
        return
    available = set(
        track.segments.filter(ayah__number__in=(start, end)).values_list(
            "ayah__number",
            flat=True,
        )
    )
    if available != {start, end}:
        raise ValidationError(
            {"range_start_ayah": "Both range boundaries require verified audio timings."}
        )


def _desired_state(*, track: AudioTrack, data: dict[str, Any]) -> tuple[Any, ...]:
    return (
        track.id,
        data["position_ms"],
        data["speed"],
        data["repeat_enabled"],
        data["range_start_ayah"],
        data["range_end_ayah"],
        data["client_updated_at"],
    )


def _stored_state(position: AudioPlaybackPosition) -> tuple[Any, ...]:
    return (
        position.track_id,
        position.position_ms,
        position.speed,
        position.repeat_enabled,
        position.range_start_ayah,
        position.range_end_ayah,
        position.client_updated_at,
    )
