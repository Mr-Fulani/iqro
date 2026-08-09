from __future__ import annotations

from dataclasses import replace
from datetime import UTC, date, datetime, time, timedelta
from decimal import Decimal
from typing import Any, cast

from django.views.decorators.debug import sensitive_variables

from quran_backend.modules.prayer_times.domain import (
    AsrMethod,
    CalculationInput,
    CalculationResult,
    EngineMethodConfig,
    PrayerAdjustments,
    PrayerName,
)
from quran_backend.modules.prayer_times.domain import (
    HighLatitudeRule as DomainHighLatitudeRule,
)
from quran_backend.modules.prayer_times.domain import (
    PolarResolution as DomainPolarResolution,
)
from quran_backend.modules.prayer_times.engine import (
    ENGINE_ID,
    ENGINE_VERSION,
    UPSTREAM_COMMIT,
    AdhanCompatibilityEngine,
    PrayerCalculationUnavailableError,
)
from quran_backend.modules.prayer_times.exceptions import (
    PrayerCalculationUnavailableAPIError,
    PrayerEngineUnsupportedError,
    PrayerMethodChecksumMismatchError,
    PrayerRuleUnsupportedError,
)
from quran_backend.modules.prayer_times.models import (
    PrayerConfigRelease,
    PrayerMethodConfig,
    high_latitude_support_items,
    polar_support_items,
)
from quran_backend.modules.prayer_times.selectors import (
    calculation_method_configuration,
    default_public_release,
)
from quran_backend.modules.prayer_times.timezones import (
    TZDB_VERSION,
    get_prayer_timezone,
)


def prayer_methods_manifest() -> dict[str, Any]:
    release = default_public_release()
    configurations = cast(
        list[PrayerMethodConfig],
        getattr(release, "public_method_configurations", []),
    )
    return {
        "catalog_version": release.version,
        "configuration_schema_version": release.configuration_schema_version,
        "algorithm": _algorithm_snapshot(release),
        "timezone_database_version": release.timezone_database_version,
        "checksum_sha256": release.manifest_checksum_sha256,
        "methods": [_method_snapshot(configuration) for configuration in configurations],
    }


@sensitive_variables()
def calculate_prayer_times(payload: dict[str, Any]) -> dict[str, Any]:
    configuration = calculation_method_configuration(payload["method_config_id"])
    expected_checksum = payload.get("method_checksum_sha256")
    if expected_checksum is not None and expected_checksum != configuration.checksum_sha256:
        raise PrayerMethodChecksumMismatchError
    _assert_engine_compatibility(configuration.release)

    high_latitude_rule = str(
        payload.get("high_latitude_rule", configuration.default_high_latitude_rule)
    )
    polar_resolution = str(payload.get("polar_resolution", configuration.default_polar_resolution))
    _validate_supported_rules(configuration, high_latitude_rule, polar_resolution)

    adjustments = PrayerAdjustments(**dict(payload.get("adjustments", {})))
    location = dict(payload["location"])
    requested_date = payload["date"]
    timezone_name = str(payload["timezone"])
    prayer_timezone = get_prayer_timezone(timezone_name)
    calculation_input = CalculationInput(
        latitude=float(location["latitude"]),
        longitude=float(location["longitude"]),
        local_date=requested_date,
        method=_engine_method_configuration(configuration),
        asr_method=AsrMethod(str(payload["asr_method"])),
        high_latitude_rule=DomainHighLatitudeRule(high_latitude_rule),
        polar_resolution=DomainPolarResolution(polar_resolution),
        adjustments=adjustments,
    )
    try:
        result, astronomical_date = _calculate_for_civil_date(
            calculation_input,
            prayer_timezone,
        )
    except PrayerCalculationUnavailableError as exc:
        raise PrayerCalculationUnavailableAPIError from exc

    times = {
        prayer.value: _event_snapshot(result.times_utc[prayer], prayer_timezone)
        for prayer in PrayerName
    }
    next_midnight_local = datetime.combine(
        requested_date + timedelta(days=1),
        time.min,
        tzinfo=prayer_timezone,
    )
    warnings: list[str] = []
    if any(adjustments.as_dict().values()):
        warnings.append("manual_adjustments_applied")
    if result.fallback.applied:
        warnings.append("polar_resolution_applied")
    return {
        "date": requested_date.isoformat(),
        "timezone": timezone_name,
        "timezone_database_version": TZDB_VERSION,
        "method": {
            "id": str(configuration.id),
            "code": configuration.method.code,
            "catalog_version": configuration.release.version,
            "checksum_sha256": configuration.checksum_sha256,
        },
        "algorithm": _algorithm_snapshot(configuration.release),
        "asr_method": calculation_input.asr_method.value,
        "high_latitude_rule": calculation_input.high_latitude_rule.value,
        "polar_resolution": calculation_input.polar_resolution.value,
        "adjustments": adjustments.as_dict(),
        "times": times,
        "fallback": {
            "applied": result.fallback.applied,
            "strategy": (
                result.fallback.strategy.value if result.fallback.strategy is not None else None
            ),
            "reason": result.fallback.reason,
            "reference_date": (
                (result.fallback.reference_date + (requested_date - astronomical_date)).isoformat()
                if result.fallback.reference_date is not None
                else None
            ),
        },
        "warnings": warnings,
        "next_recalculation_at": _event_snapshot(
            next_midnight_local.astimezone(UTC),
            prayer_timezone,
        ),
    }


@sensitive_variables()
def _calculate_for_civil_date(
    calculation_input: CalculationInput,
    prayer_timezone: Any,
) -> tuple[CalculationResult, date]:
    """Anchor the engine's astronomical date to the requested IANA civil date.

    Adhan's astronomy API accepts a calendar date without a timezone. Around the
    international date line the longitude-based UTC instants can therefore land
    on the adjacent civil day (for example, Kiritimati at UTC+14). Solar noon is
    the stable anchor: calculate once, shift the astronomical date by the observed
    civil-day delta, then verify the corrected result.
    """

    engine = AdhanCompatibilityEngine()
    result = engine.calculate(calculation_input)
    requested_date = calculation_input.local_date
    observed_date = result.times_utc[PrayerName.DHUHR].astimezone(prayer_timezone).date()
    date_shift = requested_date - observed_date
    if date_shift.days == 0:
        return result, requested_date

    astronomical_date = requested_date + date_shift
    result = engine.calculate(replace(calculation_input, local_date=astronomical_date))
    corrected_date = result.times_utc[PrayerName.DHUHR].astimezone(prayer_timezone).date()
    if corrected_date != requested_date:
        raise PrayerCalculationUnavailableError("civil_date_alignment_failed")
    return result, astronomical_date


def _method_snapshot(configuration: PrayerMethodConfig) -> dict[str, Any]:
    method = configuration.method
    isha_type = "angle" if configuration.isha_angle is not None else "fixed_interval"
    return {
        "id": str(configuration.id),
        "code": method.code,
        "available": method.is_active,
        "name": {"ar": method.name_ar, "en": method.name_en, "ru": method.name_ru},
        "description": {
            "ar": method.description_ar,
            "en": method.description_en,
            "ru": method.description_ru,
        },
        "authority": {"name": method.authority_name, "url": method.authority_url},
        "parameters": {
            "fajr_angle": _decimal_text(configuration.fajr_angle),
            "isha": {
                "type": isha_type,
                "angle": _decimal_text(configuration.isha_angle),
                "interval_minutes": configuration.isha_interval_minutes,
                "ramadan_interval_minutes": configuration.ramadan_isha_interval_minutes,
            },
            "method_adjustments": _configuration_adjustments(configuration).as_dict(),
        },
        "high_latitude_rules": {
            "supported": [
                str(rule)
                for rule, supported in high_latitude_support_items(configuration)
                if supported
            ],
            "default": configuration.default_high_latitude_rule,
        },
        "polar_resolutions": {
            "supported": [
                str(strategy)
                for strategy, supported in polar_support_items(configuration)
                if supported
            ],
            "default": configuration.default_polar_resolution,
        },
        "source": {
            "name": configuration.source_name,
            "url": configuration.source_url,
            "version": configuration.source_version,
            "checksum_sha256": configuration.source_checksum_sha256,
        },
        "checksum_sha256": configuration.checksum_sha256,
    }


def _engine_method_configuration(configuration: PrayerMethodConfig) -> EngineMethodConfig:
    return EngineMethodConfig(
        method_code=configuration.method.code.replace("-", "_"),
        fajr_angle=float(configuration.fajr_angle),
        isha_angle=(
            float(configuration.isha_angle) if configuration.isha_angle is not None else None
        ),
        isha_interval_minutes=configuration.isha_interval_minutes,
        method_adjustments=_configuration_adjustments(configuration),
    )


def _configuration_adjustments(configuration: PrayerMethodConfig) -> PrayerAdjustments:
    return PrayerAdjustments(
        fajr=configuration.fajr_adjustment_minutes,
        sunrise=configuration.sunrise_adjustment_minutes,
        dhuhr=configuration.dhuhr_adjustment_minutes,
        asr=configuration.asr_adjustment_minutes,
        maghrib=configuration.maghrib_adjustment_minutes,
        isha=configuration.isha_adjustment_minutes,
    )


def _validate_supported_rules(
    configuration: PrayerMethodConfig,
    high_latitude_rule: str,
    polar_resolution: str,
) -> None:
    supported_high_latitude = {
        str(rule) for rule, supported in high_latitude_support_items(configuration) if supported
    }
    supported_polar = {
        str(strategy) for strategy, supported in polar_support_items(configuration) if supported
    }
    errors: dict[str, str] = {}
    if high_latitude_rule not in supported_high_latitude:
        errors["high_latitude_rule"] = "The selected method does not support this rule."
    if polar_resolution not in supported_polar:
        errors["polar_resolution"] = "The selected method does not support this strategy."
    if errors:
        raise PrayerRuleUnsupportedError(detail=errors)


def _assert_engine_compatibility(release: PrayerConfigRelease) -> None:
    if (
        release.algorithm != ENGINE_ID
        or release.algorithm_version != ENGINE_VERSION
        or release.timezone_database_version != TZDB_VERSION
    ):
        raise PrayerEngineUnsupportedError


def _algorithm_snapshot(release: PrayerConfigRelease) -> dict[str, str]:
    return {
        "id": release.algorithm,
        "version": release.algorithm_version,
        "upstream": UPSTREAM_COMMIT,
    }


def _event_snapshot(instant: datetime, prayer_timezone: Any) -> dict[str, Any]:
    utc_instant = instant.astimezone(UTC)
    local = utc_instant.astimezone(prayer_timezone)
    offset = local.utcoffset()
    return {
        "local": local.isoformat(timespec="seconds"),
        "utc": utc_instant.isoformat(timespec="seconds").replace("+00:00", "Z"),
        "utc_offset_seconds": int(offset.total_seconds()) if offset is not None else 0,
    }


def _decimal_text(value: Decimal | None) -> str | None:
    return format(value, ".2f") if value is not None else None
