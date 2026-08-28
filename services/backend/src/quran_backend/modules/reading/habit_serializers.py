from __future__ import annotations

from datetime import timedelta
from decimal import Decimal
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from django.utils import timezone
from rest_framework import serializers

from quran_backend.modules.core.serializers import StrictFieldsSerializer, UUIDv7Field
from quran_backend.modules.reading.models import (
    READING_GOAL_LIMITS,
    PrayerReadingPrayer,
    ReadingGoalMetric,
    ReadingGoalStatus,
    ReadingSessionSource,
    ReadingSessionStatus,
)
from quran_backend.modules.reading.serializers import ReadingPositionOutputSerializer


class ReadingGoalWriteSerializer(StrictFieldsSerializer):
    metric = serializers.ChoiceField(choices=ReadingGoalMetric.choices)
    target_amount = serializers.DecimalField(
        max_digits=8,
        decimal_places=2,
        min_value=Decimal("0.01"),
    )
    timezone_name = serializers.CharField(max_length=64)
    base_revision = serializers.IntegerField(min_value=0)
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(required=False, allow_null=True)

    def validate_timezone_name(self, value: str) -> str:
        return _validate_timezone_name(value)

    def validate(self, attrs: dict[str, Any]) -> dict[str, Any]:
        metric = attrs["metric"]
        amount = attrs["target_amount"]
        _validate_metric_amount(metric, amount, field="target_amount")
        return attrs


class ReadingGoalDeleteSerializer(StrictFieldsSerializer):
    base_revision = serializers.IntegerField(min_value=1)
    client_updated_at = serializers.DateTimeField()


class AutomaticReadingSessionCreateSerializer(StrictFieldsSerializer):
    id = UUIDv7Field()
    timezone_name = serializers.CharField(max_length=64)
    started_at = serializers.DateTimeField()
    ended_at = serializers.DateTimeField()
    active_seconds = serializers.IntegerField(min_value=0, max_value=86_400, default=0)
    credited_pages = serializers.IntegerField(min_value=0, max_value=604, default=0)
    credited_ayahs = serializers.IntegerField(min_value=0, max_value=6_236, default=0)
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(required=False, allow_null=True)

    def validate_timezone_name(self, value: str) -> str:
        return _validate_timezone_name(value)

    def validate(self, attrs: dict[str, Any]) -> dict[str, Any]:
        started_at = attrs["started_at"]
        ended_at = attrs["ended_at"]
        if ended_at < started_at:
            raise serializers.ValidationError(
                {"ended_at": "Session end must not precede its start."}
            )
        elapsed_seconds = int((ended_at - started_at).total_seconds())
        if attrs["active_seconds"] > elapsed_seconds + 5:
            raise serializers.ValidationError(
                {"active_seconds": "Active time cannot exceed elapsed session time."}
            )
        if (
            attrs["active_seconds"] < 60
            and attrs["credited_pages"] == 0
            and attrs["credited_ayahs"] == 0
        ):
            raise serializers.ValidationError(
                "Automatic reading requires 60 active seconds or confirmed Quran progress."
            )
        if ended_at > timezone.now() + timedelta(minutes=5):
            raise serializers.ValidationError({"ended_at": "Future sessions cannot be recorded."})
        return attrs


class ManualReadingSessionFieldsSerializer(StrictFieldsSerializer):
    timezone_name = serializers.CharField(max_length=64)
    local_date = serializers.DateField()
    metric = serializers.ChoiceField(choices=ReadingGoalMetric.choices)
    amount = serializers.DecimalField(
        max_digits=8,
        decimal_places=2,
        min_value=Decimal("0.01"),
    )
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(required=False, allow_null=True)

    def validate_timezone_name(self, value: str) -> str:
        return _validate_timezone_name(value)

    def validate(self, attrs: dict[str, Any]) -> dict[str, Any]:
        _validate_metric_amount(attrs["metric"], attrs["amount"], field="amount")
        return attrs


class ManualReadingSessionCreateSerializer(ManualReadingSessionFieldsSerializer):
    id = UUIDv7Field()


class ManualReadingSessionUpdateSerializer(ManualReadingSessionFieldsSerializer):
    base_revision = serializers.IntegerField(min_value=1)


class ReadingSessionDeleteSerializer(StrictFieldsSerializer):
    base_revision = serializers.IntegerField(min_value=1)
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(required=False, allow_null=True)


class ReadingSessionListQuerySerializer(StrictFieldsSerializer):
    limit = serializers.IntegerField(min_value=1, max_value=100, required=False, default=30)
    source = serializers.ChoiceField(  # type: ignore[assignment]
        choices=ReadingSessionSource.choices,
        required=False,
    )


class ReadingPlannerQuerySerializer(StrictFieldsSerializer):
    days = serializers.IntegerField(min_value=7, max_value=90, required=False, default=30)
    timezone_name = serializers.CharField(max_length=64, required=False)

    def validate_timezone_name(self, value: str) -> str:
        return _validate_timezone_name(value)


class TodayQuerySerializer(StrictFieldsSerializer):
    timezone_name = serializers.CharField(max_length=64, required=False)

    def validate_timezone_name(self, value: str) -> str:
        return _validate_timezone_name(value)


class PrayerReadingPlanQuerySerializer(StrictFieldsSerializer):
    timezone_name = serializers.CharField(max_length=64, required=False)

    def validate_timezone_name(self, value: str) -> str:
        return _validate_timezone_name(value)


class PrayerReadingPlanWriteSerializer(StrictFieldsSerializer):
    pages_per_prayer = serializers.IntegerField(min_value=1, max_value=20)
    notifications_enabled = serializers.BooleanField(required=False, default=True)
    timezone_name = serializers.CharField(max_length=64)
    base_revision = serializers.IntegerField(min_value=0)
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(required=False, allow_null=True)

    def validate_timezone_name(self, value: str) -> str:
        return _validate_timezone_name(value)


class PrayerReadingCheckInCreateSerializer(StrictFieldsSerializer):
    id = UUIDv7Field()
    session_id = UUIDv7Field()
    prayer = serializers.ChoiceField(choices=PrayerReadingPrayer.choices)
    pages = serializers.IntegerField(min_value=1, max_value=604, required=False)
    local_date = serializers.DateField()
    timezone_name = serializers.CharField(max_length=64)
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(required=False, allow_null=True)

    def validate_timezone_name(self, value: str) -> str:
        return _validate_timezone_name(value)


class PrayerReadingCheckInUpdateSerializer(StrictFieldsSerializer):
    pages = serializers.IntegerField(min_value=1, max_value=604)
    base_revision = serializers.IntegerField(min_value=1)
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(required=False, allow_null=True)


class PrayerReadingCheckInDeleteSerializer(StrictFieldsSerializer):
    base_revision = serializers.IntegerField(min_value=1)
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(required=False, allow_null=True)


class ReadingGoalOutputSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    metric = serializers.ChoiceField(choices=ReadingGoalMetric.choices)
    target_amount = serializers.DecimalField(max_digits=8, decimal_places=2)
    timezone_name = serializers.CharField()
    started_on = serializers.DateField()
    ended_on = serializers.DateField(allow_null=True)
    status = serializers.ChoiceField(choices=ReadingGoalStatus.choices)
    revision = serializers.IntegerField()
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(allow_null=True)
    created_at = serializers.DateTimeField()
    updated_at = serializers.DateTimeField()


class PrayerReadingPlanOutputSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    pages_per_prayer = serializers.IntegerField()
    notifications_enabled = serializers.BooleanField()
    timezone_name = serializers.CharField()
    revision = serializers.IntegerField()
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(allow_null=True)
    created_at = serializers.DateTimeField()
    updated_at = serializers.DateTimeField()


class PrayerReadingCheckInOutputSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    prayer = serializers.ChoiceField(choices=PrayerReadingPrayer.choices)
    local_date = serializers.DateField()
    timezone_name = serializers.CharField()
    pages = serializers.IntegerField()
    reading_session_id = serializers.UUIDField(allow_null=True)
    revision = serializers.IntegerField()
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(allow_null=True)
    created_at = serializers.DateTimeField()
    updated_at = serializers.DateTimeField()


class PrayerReadingDayOutputSerializer(serializers.Serializer[Any]):
    local_date = serializers.DateField()
    timezone_name = serializers.CharField()
    plan = PrayerReadingPlanOutputSerializer(allow_null=True)
    check_ins = PrayerReadingCheckInOutputSerializer(many=True)
    achieved_pages = serializers.IntegerField()
    target_pages = serializers.IntegerField()
    remaining_pages = serializers.IntegerField()


class ReadingGoalEnvelopeSerializer(serializers.Serializer[Any]):
    goal = ReadingGoalOutputSerializer(allow_null=True)


class ReadingSessionOutputSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    goal_id = serializers.UUIDField(allow_null=True)
    source = serializers.ChoiceField(  # type: ignore[assignment]
        choices=ReadingSessionSource.choices
    )
    status = serializers.ChoiceField(choices=ReadingSessionStatus.choices)
    timezone_name = serializers.CharField()
    local_date = serializers.DateField()
    started_at = serializers.DateTimeField(allow_null=True)
    ended_at = serializers.DateTimeField(allow_null=True)
    active_seconds = serializers.IntegerField()
    credited_pages = serializers.IntegerField()
    credited_ayahs = serializers.IntegerField()
    manual_metric = serializers.ChoiceField(
        choices=ReadingGoalMetric.choices,
        allow_null=True,
    )
    manual_amount = serializers.DecimalField(
        max_digits=8,
        decimal_places=2,
        allow_null=True,
    )
    revision = serializers.IntegerField()
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(allow_null=True)
    deleted_at = serializers.DateTimeField(allow_null=True)
    created_at = serializers.DateTimeField()
    updated_at = serializers.DateTimeField()


class ReadingSessionListOutputSerializer(serializers.Serializer[Any]):
    results = ReadingSessionOutputSerializer(many=True)


class ReadingPlannerGoalOutputSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    metric = serializers.ChoiceField(choices=ReadingGoalMetric.choices)
    target_amount = serializers.DecimalField(max_digits=8, decimal_places=2)
    achieved_amount = serializers.DecimalField(max_digits=10, decimal_places=2)
    remaining_amount = serializers.DecimalField(max_digits=10, decimal_places=2)


class ReadingPlannerDayOutputSerializer(serializers.Serializer[Any]):
    local_date = serializers.DateField()
    state = serializers.ChoiceField(
        choices=("no_goal", "pending", "missed", "partial", "completed")
    )
    has_reading = serializers.BooleanField()
    goal = ReadingPlannerGoalOutputSerializer(allow_null=True)
    prayer_check_ins = PrayerReadingCheckInOutputSerializer(many=True)
    prayer_pages = serializers.IntegerField()
    prayer_count = serializers.IntegerField()
    automatic_sessions = serializers.IntegerField()
    automatic_active_seconds = serializers.IntegerField()
    automatic_pages = serializers.IntegerField()
    automatic_ayahs = serializers.IntegerField()


class ReadingPlannerOutputSerializer(serializers.Serializer[Any]):
    local_date = serializers.DateField()
    timezone_name = serializers.CharField()
    days = ReadingPlannerDayOutputSerializer(many=True)


class GoalProgressOutputSerializer(serializers.Serializer[Any]):
    goal_id = serializers.UUIDField()
    local_date = serializers.DateField()
    metric = serializers.ChoiceField(choices=ReadingGoalMetric.choices)
    target_amount = serializers.DecimalField(max_digits=8, decimal_places=2)
    achieved_amount = serializers.DecimalField(max_digits=10, decimal_places=2)
    remaining_amount = serializers.DecimalField(max_digits=10, decimal_places=2)
    is_completed = serializers.BooleanField()
    completed_at = serializers.DateTimeField(allow_null=True)


class ReadingStreakOutputSerializer(serializers.Serializer[Any]):
    current_count = serializers.IntegerField()
    longest_count = serializers.IntegerField()
    last_qualifying_date = serializers.DateField(allow_null=True)


class TodayOutputSerializer(serializers.Serializer[Any]):
    local_date = serializers.DateField()
    timezone_name = serializers.CharField()
    continue_reading = ReadingPositionOutputSerializer(allow_null=True)
    goal = ReadingGoalOutputSerializer(allow_null=True)
    progress = GoalProgressOutputSerializer(allow_null=True)
    streak = ReadingStreakOutputSerializer()


def _validate_timezone_name(value: str) -> str:
    try:
        ZoneInfo(value)
    except (ValueError, ZoneInfoNotFoundError) as exc:
        raise serializers.ValidationError("Use a valid IANA timezone name.") from exc
    return value


def _validate_metric_amount(metric: str, amount: Decimal, *, field: str) -> None:
    if (
        metric in {ReadingGoalMetric.PAGES, ReadingGoalMetric.AYAHS}
        and amount != amount.to_integral_value()
    ):
        raise serializers.ValidationError({field: "Pages and ayahs must use whole numbers."})
    limit = READING_GOAL_LIMITS[metric]
    if amount > limit:
        raise serializers.ValidationError({field: f"Amount must not exceed {int(limit)}."})
