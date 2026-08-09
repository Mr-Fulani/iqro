from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from drf_spectacular.utils import PolymorphicProxySerializer, extend_schema_field
from rest_framework import serializers

from quran_backend.modules.core.serializers import StrictFieldsSerializer, UUIDv7Field
from quran_backend.modules.prayer_times.timezones import (
    InvalidPrayerTimezoneError,
    get_prayer_timezone,
)
from quran_backend.modules.reminders.models import (
    ALL_WEEKDAYS_MASK,
    MAX_PRAYER_OFFSET_MINUTES,
    MIN_PRAYER_OFFSET_MINUTES,
    ReminderDeliveryMode,
    ReminderPrayerEvent,
    ReminderSignal,
    ReminderTimezoneMode,
    ReminderType,
)


class ReminderPrayerScheduleSerializer(StrictFieldsSerializer):
    kind = serializers.ChoiceField(choices=["prayer"])
    prayer_event = serializers.ChoiceField(choices=ReminderPrayerEvent.choices)
    prayer_offset_minutes = serializers.IntegerField(
        min_value=MIN_PRAYER_OFFSET_MINUTES,
        max_value=MAX_PRAYER_OFFSET_MINUTES,
    )


class ReminderLocalTimeScheduleSerializer(StrictFieldsSerializer):
    kind = serializers.ChoiceField(choices=["local_time"])
    local_time = serializers.TimeField()


@extend_schema_field(
    PolymorphicProxySerializer(
        component_name="ReminderSchedule",
        serializers={
            "prayer": ReminderPrayerScheduleSerializer,
            "local_time": ReminderLocalTimeScheduleSerializer,
        },
        resource_type_field_name="kind",
    )
)
class ReminderScheduleField(serializers.Field[Any, Any, Any, Any]):
    def to_internal_value(self, data: Any) -> dict[str, Any]:
        serializer_class = _discriminated_serializer(
            data,
            discriminator="kind",
            serializers_by_value={
                "prayer": ReminderPrayerScheduleSerializer,
                "local_time": ReminderLocalTimeScheduleSerializer,
            },
        )
        serializer = serializer_class(data=data, context=self.context)
        serializer.is_valid(raise_exception=True)
        return dict(serializer.validated_data)

    def to_representation(self, value: Any) -> Any:
        return value


class ReminderDeviceLocalTimezoneSerializer(StrictFieldsSerializer):
    mode = serializers.ChoiceField(choices=[ReminderTimezoneMode.DEVICE_LOCAL])


class ReminderFixedTimezoneSerializer(StrictFieldsSerializer):
    mode = serializers.ChoiceField(choices=[ReminderTimezoneMode.FIXED])
    name = serializers.CharField(min_length=1, max_length=64)

    def validate_name(self, value: str) -> str:
        if value != value.strip() or ".." in value or "\\" in value or value.startswith("/"):
            raise serializers.ValidationError("Use a canonical IANA timezone identifier.")
        try:
            get_prayer_timezone(value)
        except InvalidPrayerTimezoneError as exc:
            raise serializers.ValidationError(
                "Use a timezone identifier available in the pinned IANA database."
            ) from exc
        return value


@extend_schema_field(
    PolymorphicProxySerializer(
        component_name="ReminderTimezone",
        serializers={
            "device_local": ReminderDeviceLocalTimezoneSerializer,
            "fixed": ReminderFixedTimezoneSerializer,
        },
        resource_type_field_name="mode",
    )
)
class ReminderTimezoneField(serializers.Field[Any, Any, Any, Any]):
    def to_internal_value(self, data: Any) -> dict[str, Any]:
        serializer_class = _discriminated_serializer(
            data,
            discriminator="mode",
            serializers_by_value={
                "device_local": ReminderDeviceLocalTimezoneSerializer,
                "fixed": ReminderFixedTimezoneSerializer,
            },
        )
        serializer = serializer_class(data=data, context=self.context)
        serializer.is_valid(raise_exception=True)
        return dict(serializer.validated_data)

    def to_representation(self, value: Any) -> Any:
        return value


class ReminderReviewTargetSerializer(StrictFieldsSerializer):
    start_ayah_id = serializers.UUIDField()
    end_ayah_id = serializers.UUIDField()


class ReminderFunctionalSerializer(StrictFieldsSerializer):
    reminder_type = serializers.ChoiceField(choices=ReminderType.choices)
    schedule = ReminderScheduleField()
    review_target = ReminderReviewTargetSerializer(required=False, allow_null=True)
    weekdays_mask = serializers.IntegerField(
        min_value=1,
        max_value=ALL_WEEKDAYS_MASK,
        required=False,
        default=ALL_WEEKDAYS_MASK,
    )
    timezone = ReminderTimezoneField(
        required=False,
        default={"mode": ReminderTimezoneMode.DEVICE_LOCAL},
    )
    signal = serializers.ChoiceField(
        choices=ReminderSignal.choices,
        required=False,
        default=ReminderSignal.SOUND,
    )
    is_enabled = serializers.BooleanField(required=False, default=True)

    def validate(self, attrs: dict[str, Any]) -> dict[str, Any]:
        attrs = super().validate(attrs)
        reminder_type = attrs["reminder_type"]
        schedule_kind = attrs["schedule"]["kind"]
        target_supplied = "review_target" in attrs and attrs["review_target"] is not None
        errors: dict[str, str] = {}
        if reminder_type == ReminderType.PRAYER and schedule_kind != "prayer":
            errors["schedule"] = "A prayer reminder requires a prayer schedule."
        if reminder_type != ReminderType.PRAYER and schedule_kind != "local_time":
            errors["schedule"] = "A Quran reminder requires a local-time schedule."
        if reminder_type == ReminderType.QURAN_REVIEW and not target_supplied:
            errors["review_target"] = "A Quran review reminder requires an ayah range."
        if reminder_type != ReminderType.QURAN_REVIEW and target_supplied:
            errors["review_target"] = "Only Quran review reminders can have an ayah range."
        if errors:
            raise serializers.ValidationError(errors)
        return attrs


class ReminderCreateSerializer(ReminderFunctionalSerializer):
    id = UUIDv7Field()
    base_revision = serializers.IntegerField(min_value=0, max_value=0)
    client_updated_at = serializers.DateTimeField()


class ReminderPatchFunctionalSerializer(StrictFieldsSerializer):
    reminder_type = serializers.ChoiceField(choices=ReminderType.choices, required=False)
    schedule = ReminderScheduleField(required=False)
    review_target = ReminderReviewTargetSerializer(required=False, allow_null=True)
    weekdays_mask = serializers.IntegerField(
        min_value=1,
        max_value=ALL_WEEKDAYS_MASK,
        required=False,
    )
    timezone = ReminderTimezoneField(required=False)
    signal = serializers.ChoiceField(choices=ReminderSignal.choices, required=False)
    is_enabled = serializers.BooleanField(required=False)


class ReminderPatchSerializer(ReminderPatchFunctionalSerializer):
    base_revision = serializers.IntegerField(min_value=1)
    client_updated_at = serializers.DateTimeField()


class ReminderDeleteSerializer(StrictFieldsSerializer):
    base_revision = serializers.IntegerField(min_value=1)
    client_updated_at = serializers.DateTimeField()


class ReminderAyahReferenceSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    surah_number = serializers.IntegerField(min_value=1, max_value=114)
    ayah_number = serializers.IntegerField(min_value=1)


class ReminderReviewTargetOutputSerializer(serializers.Serializer[Any]):
    start = ReminderAyahReferenceSerializer()
    end = ReminderAyahReferenceSerializer()


class ReminderOutputSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    reminder_type = serializers.ChoiceField(choices=ReminderType.choices)
    schedule = ReminderScheduleField(allow_null=True)
    review_target = ReminderReviewTargetOutputSerializer(allow_null=True)
    weekdays_mask = serializers.IntegerField(min_value=1, max_value=ALL_WEEKDAYS_MASK)
    timezone = ReminderTimezoneField()
    delivery_mode = serializers.ChoiceField(choices=ReminderDeliveryMode.choices)
    signal = serializers.ChoiceField(choices=ReminderSignal.choices)
    is_enabled = serializers.BooleanField()
    revision = serializers.IntegerField(min_value=1)
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(allow_null=True)
    deleted_at = serializers.DateTimeField(allow_null=True)
    created_at = serializers.DateTimeField()
    updated_at = serializers.DateTimeField()


class ReminderSyncOutputSerializer(ReminderOutputSerializer):
    entity_type = serializers.ChoiceField(choices=["reminder"], read_only=True)


class ReminderFullSnapshotSerializer(serializers.Serializer[Any]):
    mode = serializers.ChoiceField(choices=["full_snapshot"])
    authoritative = serializers.BooleanField()
    generated_at = serializers.DateTimeField()
    count = serializers.IntegerField(min_value=0, max_value=256)
    reminders = ReminderOutputSerializer(many=True)


def _discriminated_serializer(
    data: Any,
    *,
    discriminator: str,
    serializers_by_value: Mapping[str, type[serializers.Serializer[Any]]],
) -> type[serializers.Serializer[Any]]:
    if not isinstance(data, Mapping):
        raise serializers.ValidationError("Expected an object.")
    value = data.get(discriminator)
    serializer_class = serializers_by_value.get(value) if isinstance(value, str) else None
    if serializer_class is None:
        choices = ", ".join(sorted(serializers_by_value))
        raise serializers.ValidationError(
            {discriminator: f"Select one of the supported values: {choices}."}
        )
    return serializer_class
