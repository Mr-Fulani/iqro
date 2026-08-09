from __future__ import annotations

from typing import Any

from rest_framework import serializers

from quran_backend.modules.core.serializers import StrictFieldsSerializer
from quran_backend.modules.prayer_times.models import (
    HighLatitudeRule,
    PolarCircleResolution,
    PrayerAsrMethod,
    PrayerTimezoneMode,
)
from quran_backend.modules.prayer_times.serializers import PrayerAdjustmentsSerializer
from quran_backend.modules.prayer_times.timezones import (
    InvalidPrayerTimezoneError,
    get_prayer_timezone,
)


class PrayerProfileWriteSerializer(StrictFieldsSerializer):
    base_revision = serializers.IntegerField(min_value=0)
    method_config_id = serializers.UUIDField()
    method_checksum_sha256 = serializers.RegexField(r"^[0-9a-f]{64}$")
    asr_method = serializers.ChoiceField(choices=PrayerAsrMethod.choices)
    high_latitude_rule = serializers.ChoiceField(choices=HighLatitudeRule.choices)
    polar_resolution = serializers.ChoiceField(choices=PolarCircleResolution.choices)
    adjustments = PrayerAdjustmentsSerializer()
    timezone_mode = serializers.ChoiceField(choices=PrayerTimezoneMode.choices)
    fixed_timezone = serializers.CharField(min_length=1, max_length=255, required=False)
    client_updated_at = serializers.DateTimeField()

    def validate_fixed_timezone(self, value: str) -> str:
        try:
            get_prayer_timezone(value)
        except InvalidPrayerTimezoneError as exc:
            raise serializers.ValidationError(
                "Use a timezone identifier available in the pinned IANA database."
            ) from exc
        return value

    def validate(self, attrs: dict[str, Any]) -> dict[str, Any]:
        attrs = super().validate(attrs)
        fixed_timezone_supplied = "fixed_timezone" in attrs
        if attrs["timezone_mode"] == PrayerTimezoneMode.FIXED:
            if not fixed_timezone_supplied:
                raise serializers.ValidationError(
                    {"fixed_timezone": "This field is required in fixed timezone mode."}
                )
        elif fixed_timezone_supplied:
            raise serializers.ValidationError(
                {"fixed_timezone": "This field is only allowed in fixed timezone mode."}
            )
        else:
            attrs["fixed_timezone"] = ""
        return attrs


class PrayerProfileMethodSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    code = serializers.CharField()
    catalog_version = serializers.CharField()
    checksum_sha256 = serializers.CharField()


class PrayerProfileResponseSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    method_config = PrayerProfileMethodSerializer()
    method_available = serializers.BooleanField()
    asr_method = serializers.ChoiceField(choices=PrayerAsrMethod.choices)
    high_latitude_rule = serializers.ChoiceField(choices=HighLatitudeRule.choices)
    polar_resolution = serializers.ChoiceField(choices=PolarCircleResolution.choices)
    adjustments = PrayerAdjustmentsSerializer()
    timezone_mode = serializers.ChoiceField(choices=PrayerTimezoneMode.values)
    fixed_timezone = serializers.CharField(allow_null=True)
    revision = serializers.IntegerField(min_value=1)
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(allow_null=True)
    created_at = serializers.DateTimeField()
    updated_at = serializers.DateTimeField()
