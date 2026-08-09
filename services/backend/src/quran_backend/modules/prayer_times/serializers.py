from __future__ import annotations

import datetime as dt
from decimal import Decimal
from typing import Any

from rest_framework import serializers

from quran_backend.modules.core.serializers import StrictFieldsSerializer
from quran_backend.modules.prayer_times.domain import AsrMethod
from quran_backend.modules.prayer_times.models import (
    HighLatitudeRule,
    PolarCircleResolution,
    PrayerAsrMethod,
)
from quran_backend.modules.prayer_times.timezones import (
    InvalidPrayerTimezoneError,
    get_prayer_timezone,
)


class PrayerLocationInputSerializer(StrictFieldsSerializer):
    latitude = serializers.DecimalField(
        max_digits=9,
        decimal_places=6,
        min_value=Decimal("-90"),
        max_value=Decimal("90"),
    )
    longitude = serializers.DecimalField(
        max_digits=10,
        decimal_places=6,
        min_value=Decimal("-180"),
        max_value=Decimal("180"),
    )


class PrayerAdjustmentsSerializer(StrictFieldsSerializer):
    fajr = serializers.IntegerField(min_value=-120, max_value=120, required=False, default=0)
    sunrise = serializers.IntegerField(min_value=-120, max_value=120, required=False, default=0)
    dhuhr = serializers.IntegerField(min_value=-120, max_value=120, required=False, default=0)
    asr = serializers.IntegerField(min_value=-120, max_value=120, required=False, default=0)
    maghrib = serializers.IntegerField(min_value=-120, max_value=120, required=False, default=0)
    isha = serializers.IntegerField(min_value=-120, max_value=120, required=False, default=0)


class PrayerCalculationRequestSerializer(StrictFieldsSerializer):
    date = serializers.DateField()
    timezone = serializers.CharField(min_length=1, max_length=255)
    location = PrayerLocationInputSerializer()
    method_config_id = serializers.UUIDField()
    method_checksum_sha256 = serializers.RegexField(
        r"^[0-9a-f]{64}$",
        required=False,
    )
    asr_method = serializers.ChoiceField(
        choices=PrayerAsrMethod.choices,
        default=AsrMethod.STANDARD,
    )
    high_latitude_rule = serializers.ChoiceField(
        choices=HighLatitudeRule.choices,
        required=False,
    )
    polar_resolution = serializers.ChoiceField(
        choices=PolarCircleResolution.choices,
        required=False,
    )
    adjustments = PrayerAdjustmentsSerializer(required=False)

    def validate_date(self, value: dt.date) -> dt.date:
        if not dt.date(1900, 1, 1) <= value <= dt.date(2100, 12, 31):
            raise serializers.ValidationError("Date must be between 1900-01-01 and 2100-12-31.")
        return value

    def validate_timezone(self, value: str) -> str:
        if (
            value != value.strip()
            or ".." in value
            or "\\" in value
            or value.startswith("/")
            or "\x00" in value
        ):
            raise serializers.ValidationError("Use a canonical IANA timezone identifier.")
        try:
            get_prayer_timezone(value)
        except InvalidPrayerTimezoneError as exc:
            raise serializers.ValidationError(
                "Use a timezone identifier available in the pinned IANA database."
            ) from exc
        return value


class LocalizedPrayerTextSerializer(serializers.Serializer[Any]):
    ar = serializers.CharField()
    en = serializers.CharField()
    ru = serializers.CharField()


class PrayerAuthoritySerializer(serializers.Serializer[Any]):
    name = serializers.CharField()
    url = serializers.URLField()


class PrayerSourceSerializer(serializers.Serializer[Any]):
    name = serializers.CharField()
    url = serializers.URLField()
    version = serializers.CharField()
    checksum_sha256 = serializers.CharField()


class PrayerIshaRuleSerializer(serializers.Serializer[Any]):
    type = serializers.ChoiceField(choices=["angle", "fixed_interval"])
    angle = serializers.DecimalField(
        max_digits=4,
        decimal_places=2,
        allow_null=True,
    )
    interval_minutes = serializers.IntegerField(allow_null=True)
    ramadan_interval_minutes = serializers.IntegerField(allow_null=True)


class PrayerMethodParametersSerializer(serializers.Serializer[Any]):
    fajr_angle = serializers.DecimalField(max_digits=4, decimal_places=2)
    isha = PrayerIshaRuleSerializer()
    method_adjustments = PrayerAdjustmentsSerializer()


class PrayerMethodRulesSerializer(serializers.Serializer[Any]):
    supported = serializers.ListField(child=serializers.CharField())
    default = serializers.CharField()


class PrayerMethodCatalogItemSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    code = serializers.CharField()
    available = serializers.BooleanField()
    name = LocalizedPrayerTextSerializer()
    description = LocalizedPrayerTextSerializer()
    authority = PrayerAuthoritySerializer()
    parameters = PrayerMethodParametersSerializer()
    high_latitude_rules = PrayerMethodRulesSerializer()
    polar_resolutions = PrayerMethodRulesSerializer()
    source: Any = PrayerSourceSerializer()
    checksum_sha256 = serializers.CharField()


class PrayerAlgorithmSerializer(serializers.Serializer[Any]):
    id = serializers.CharField()
    version = serializers.CharField()
    upstream = serializers.CharField()


class PrayerMethodsResponseSerializer(serializers.Serializer[Any]):
    catalog_version = serializers.CharField()
    configuration_schema_version = serializers.IntegerField(min_value=1)
    algorithm = PrayerAlgorithmSerializer()
    timezone_database_version = serializers.CharField()
    checksum_sha256 = serializers.CharField()
    methods = PrayerMethodCatalogItemSerializer(many=True)


class PrayerTimeEventSerializer(serializers.Serializer[Any]):
    local = serializers.DateTimeField()
    utc = serializers.DateTimeField()
    utc_offset_seconds = serializers.IntegerField()


class PrayerTimesResultSerializer(serializers.Serializer[Any]):
    fajr = PrayerTimeEventSerializer()
    sunrise = PrayerTimeEventSerializer()
    dhuhr = PrayerTimeEventSerializer()
    asr = PrayerTimeEventSerializer()
    maghrib = PrayerTimeEventSerializer()
    isha = PrayerTimeEventSerializer()


class PrayerFallbackSerializer(serializers.Serializer[Any]):
    applied = serializers.BooleanField()
    strategy = serializers.CharField(allow_null=True)
    reason = serializers.CharField(allow_null=True)
    reference_date = serializers.DateField(allow_null=True)


class PrayerMethodResultSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    code = serializers.CharField()
    catalog_version = serializers.CharField()
    checksum_sha256 = serializers.CharField()


class PrayerCalculationResponseSerializer(serializers.Serializer[Any]):
    date = serializers.DateField()
    timezone = serializers.CharField()
    timezone_database_version = serializers.CharField()
    method = PrayerMethodResultSerializer()
    algorithm = PrayerAlgorithmSerializer()
    asr_method = serializers.ChoiceField(choices=PrayerAsrMethod.choices)
    high_latitude_rule = serializers.ChoiceField(choices=HighLatitudeRule.choices)
    polar_resolution = serializers.ChoiceField(choices=PolarCircleResolution.choices)
    adjustments = PrayerAdjustmentsSerializer()
    times = PrayerTimesResultSerializer()
    fallback = PrayerFallbackSerializer()
    warnings = serializers.ListField(child=serializers.CharField())
    next_recalculation_at = PrayerTimeEventSerializer()
