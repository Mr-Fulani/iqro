from __future__ import annotations

from decimal import Decimal
from typing import Any

from rest_framework import serializers

from quran_backend.modules.audio.models import AudioPlaybackPosition
from quran_backend.modules.audio.serializers import ReciterSummarySerializer
from quran_backend.modules.core.serializers import StrictFieldsSerializer
from quran_backend.modules.quran.models import Surah


class AudioPlaybackPositionWriteSerializer(StrictFieldsSerializer):
    base_revision = serializers.IntegerField(min_value=0)
    track_id = serializers.UUIDField()
    position_ms = serializers.IntegerField(min_value=0)
    speed = serializers.DecimalField(
        max_digits=3,
        decimal_places=2,
        min_value=Decimal("0.50"),
        max_value=Decimal("2.00"),
    )
    repeat_enabled = serializers.BooleanField()
    range_start_ayah = serializers.IntegerField(min_value=1, max_value=286, allow_null=True)
    range_end_ayah = serializers.IntegerField(min_value=1, max_value=286, allow_null=True)
    client_updated_at = serializers.DateTimeField()

    def validate(self, attrs: dict[str, Any]) -> dict[str, Any]:
        attrs = super().validate(attrs)
        start = attrs["range_start_ayah"]
        end = attrs["range_end_ayah"]
        if (start is None) != (end is None):
            raise serializers.ValidationError(
                {"range_end_ayah": "Provide both ayah range boundaries or neither."}
            )
        if start is not None and end is not None and start > end:
            raise serializers.ValidationError(
                {"range_end_ayah": "The range end must not precede the range start."}
            )
        return attrs


class AudioPlaybackPositionSerializer(serializers.ModelSerializer[AudioPlaybackPosition]):
    track_id = serializers.UUIDField(source="track.id", read_only=True)
    recitation_id = serializers.UUIDField(
        source="track.recitation_edition.id",
        read_only=True,
    )
    surah_number = serializers.IntegerField(source="track.surah_number", read_only=True)
    duration_ms = serializers.IntegerField(source="track.duration_ms", read_only=True)
    speed = serializers.SerializerMethodField()
    playback_available = serializers.SerializerMethodField()
    reciter = ReciterSummarySerializer(source="track.recitation_edition.reciter", read_only=True)
    surah_names = serializers.SerializerMethodField()

    class Meta:
        model = AudioPlaybackPosition
        fields = (
            "id",
            "track_id",
            "recitation_id",
            "surah_number",
            "duration_ms",
            "position_ms",
            "speed",
            "repeat_enabled",
            "range_start_ayah",
            "range_end_ayah",
            "revision",
            "client_updated_at",
            "updated_at",
            "playback_available",
            "reciter",
            "surah_names",
        )

    def get_speed(self, obj: AudioPlaybackPosition) -> float:
        return float(obj.speed)

    def get_playback_available(self, obj: AudioPlaybackPosition) -> bool:
        recitation = obj.track.recitation_edition
        return bool(recitation.status == "published" and recitation.stream_allowed)

    def get_surah_names(self, obj: AudioPlaybackPosition) -> dict[str, str]:
        if obj.track.surah_number is None:
            return {}
        names = (
            Surah.objects.filter(
                edition_version_id=obj.track.recitation_edition.quran_edition_version_id,
                number=obj.track.surah_number,
            )
            .values("name_ar", "name_en", "name_ru")
            .first()
        )
        if names is None:
            return {}
        return {
            "ar": str(names["name_ar"]),
            "en": str(names["name_en"]),
            "ru": str(names["name_ru"]),
            "tr": str(names["name_en"]),
        }


class AudioPlaybackPositionEnvelopeSerializer(serializers.Serializer[Any]):
    position = AudioPlaybackPositionSerializer(allow_null=True)
