from __future__ import annotations

from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from rest_framework import serializers

from quran_backend.modules.core.serializers import StrictFieldsSerializer, UUIDv7Field
from quran_backend.modules.memorization.models import MemorizationAssessment


class MemorizationQuerySerializer(StrictFieldsSerializer):
    timezone_name = serializers.CharField(max_length=64, required=False)
    recent_days = serializers.IntegerField(min_value=1, max_value=30, default=14, required=False)

    def validate_timezone_name(self, value: str) -> str:
        return _validate_timezone_name(value)


class MemorizationPlanWriteSerializer(StrictFieldsSerializer):
    start_ayah_id = serializers.UUIDField()
    end_ayah_id = serializers.UUIDField()
    recitation_id = serializers.UUIDField(required=False, allow_null=True)
    daily_repetitions = serializers.IntegerField(min_value=1, max_value=100)
    pause_seconds = serializers.IntegerField(min_value=0, max_value=30)
    timezone_name = serializers.CharField(max_length=64)
    base_revision = serializers.IntegerField(min_value=0)
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(required=False, allow_null=True)

    def validate_timezone_name(self, value: str) -> str:
        return _validate_timezone_name(value)


class MemorizationSessionCreateSerializer(StrictFieldsSerializer):
    id = UUIDv7Field()
    plan_id = serializers.UUIDField()
    completed_repetitions = serializers.IntegerField(min_value=1, max_value=1000)
    assessment = serializers.ChoiceField(choices=MemorizationAssessment.choices)
    duration_seconds = serializers.IntegerField(min_value=0, max_value=86_400)
    timezone_name = serializers.CharField(max_length=64)
    local_date = serializers.DateField()
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(required=False, allow_null=True)

    def validate_timezone_name(self, value: str) -> str:
        return _validate_timezone_name(value)


class MemorizationAyahOutputSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    surah_number = serializers.IntegerField()
    ayah_number = serializers.IntegerField()
    text_uthmani = serializers.CharField()


class MemorizationReciterOutputSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    name_ar = serializers.CharField()
    name_en = serializers.CharField()
    name_ru = serializers.CharField()


class MemorizationPlanOutputSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    edition_code = serializers.CharField()
    content_version = serializers.CharField()
    start_ayah = MemorizationAyahOutputSerializer()
    end_ayah = MemorizationAyahOutputSerializer()
    recitation_id = serializers.UUIDField(allow_null=True)
    reciter = MemorizationReciterOutputSerializer(allow_null=True)
    daily_repetitions = serializers.IntegerField()
    pause_seconds = serializers.IntegerField()
    timezone_name = serializers.CharField()
    revision = serializers.IntegerField()
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(allow_null=True)
    created_at = serializers.DateTimeField()
    updated_at = serializers.DateTimeField()


class MemorizationSessionOutputSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    plan_id = serializers.UUIDField()
    start_ayah = MemorizationAyahOutputSerializer()
    end_ayah = MemorizationAyahOutputSerializer()
    daily_target_repetitions = serializers.IntegerField()
    completed_repetitions = serializers.IntegerField()
    assessment = serializers.ChoiceField(choices=MemorizationAssessment.choices)
    duration_seconds = serializers.IntegerField()
    timezone_name = serializers.CharField()
    local_date = serializers.DateField()
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(allow_null=True)
    created_at = serializers.DateTimeField()


class MemorizationTodayOutputSerializer(serializers.Serializer[Any]):
    local_date = serializers.DateField()
    completed_repetitions = serializers.IntegerField()
    target_repetitions = serializers.IntegerField()
    remaining_repetitions = serializers.IntegerField()
    is_completed = serializers.BooleanField()
    last_assessment = serializers.ChoiceField(
        choices=MemorizationAssessment.choices,
        allow_null=True,
    )
    sessions = MemorizationSessionOutputSerializer(many=True)


class MemorizationRecentDayOutputSerializer(serializers.Serializer[Any]):
    local_date = serializers.DateField()
    completed_repetitions = serializers.IntegerField()
    session_count = serializers.IntegerField()
    last_assessment = serializers.ChoiceField(choices=MemorizationAssessment.choices)


class MemorizationDashboardOutputSerializer(serializers.Serializer[Any]):
    timezone_name = serializers.CharField()
    plan = MemorizationPlanOutputSerializer(allow_null=True)
    today = MemorizationTodayOutputSerializer()
    recent_days = MemorizationRecentDayOutputSerializer(many=True)


def _validate_timezone_name(value: str) -> str:
    try:
        ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError) as exc:
        raise serializers.ValidationError("Use a valid IANA timezone.") from exc
    return value
