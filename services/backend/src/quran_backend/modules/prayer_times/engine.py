from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Final, Protocol

from adhanpy.astronomy.Astronomical import (  # type: ignore[import-untyped]
    corrected_hour_angle,
    corrected_transit,
)
from adhanpy.astronomy.CalendricalHelper import julian_day  # type: ignore[import-untyped]
from adhanpy.astronomy.SolarCoordinates import SolarCoordinates  # type: ignore[import-untyped]
from adhanpy.data.Coordinates import Coordinates  # type: ignore[import-untyped]
from django.views.decorators.debug import sensitive_variables

from quran_backend.modules.prayer_times.domain import (
    AsrMethod,
    CalculationInput,
    CalculationResult,
    FallbackMetadata,
    HighLatitudeRule,
    PolarResolution,
    PrayerName,
    RoundingRule,
    Shafaq,
)

ENGINE_ID: Final = "adhan-js-python-adapter"
ENGINE_VERSION: Final = "4.4.4-quran.1-adhanpy.1.0.5"
UPSTREAM_COMMIT: Final = "a6f1a5c4a00105103f310ef18200b95f7184d2e7"

_LATITUDE_VARIATION_STEP: Final = 0.5
_UNSAFE_LATITUDE: Final = 65.0
_MAX_POLAR_DAY_SEARCH: Final = 183


class PrayerCalculationUnavailableError(Exception):
    """A complete schedule cannot be calculated without an allowed fallback."""

    def __init__(self, reason: str) -> None:
        super().__init__("Prayer times are unavailable for the requested calculation settings.")
        self.reason = reason


class PrayerTimesEngine(Protocol):
    def calculate(self, calculation_input: CalculationInput) -> CalculationResult: ...


@dataclass(frozen=True, slots=True)
class _ResolvedSolarTime:
    solar_time: _SolarTime
    tomorrow_solar_time: _SolarTime
    calculation_latitude: float
    fallback: FallbackMetadata


class _SolarTime:
    """Adhan-compatible solar values with the 4.4.4 date-line correction."""

    def __init__(self, local_date: date, latitude: float, longitude: float) -> None:
        coordinates = Coordinates(latitude, longitude)
        julian_date = julian_day(local_date.year, local_date.month, local_date.day)
        previous = SolarCoordinates(julian_date - 1)
        current = SolarCoordinates(julian_date)
        following = SolarCoordinates(julian_date + 1)

        approximate_transit = _approximate_transit(
            longitude,
            current.apparent_sidereal_time,
            current.right_ascension,
        )
        self._approximate_transit = approximate_transit
        self._coordinates = coordinates
        self._previous = previous
        self._current = current
        self._following = following
        self.transit = corrected_transit(
            approximate_transit,
            longitude,
            current.apparent_sidereal_time,
            current.right_ascension,
            previous.right_ascension,
            following.right_ascension,
        )
        self.sunrise = self.hour_angle(-50.0 / 60.0, after_transit=False)
        self.sunset = self.hour_angle(-50.0 / 60.0, after_transit=True)

    def hour_angle(self, angle: float, *, after_transit: bool) -> float:
        return float(
            corrected_hour_angle(
                self._approximate_transit,
                angle,
                self._coordinates,
                after_transit,
                self._current.apparent_sidereal_time,
                self._current.right_ascension,
                self._previous.right_ascension,
                self._following.right_ascension,
                self._current.declination,
                self._previous.declination,
                self._following.declination,
            )
        )

    def afternoon(self, shadow_length: int) -> float:
        tangent = abs(self._coordinates.latitude - self._current.declination)
        inverse = shadow_length + math.tan(math.radians(tangent))
        angle = math.degrees(math.atan(1.0 / inverse))
        return self.hour_angle(angle, after_transit=True)


class AdhanCompatibilityEngine:
    """Python adapter of Adhan JS 4.4.4 prayer orchestration.

    The astronomical primitives come from the MIT-licensed ``adhanpy`` port.
    Orchestration, polar resolution, shafaq handling, rounding and the 4.4.4
    international-date-line correction are kept locally so their behavior can
    be versioned and tested independently of Django and the database.
    """

    @sensitive_variables()
    def calculate(self, calculation_input: CalculationInput) -> CalculationResult:
        resolved = self._resolve_solar_time(calculation_input)
        times = self._calculate_times(calculation_input, resolved)
        if set(times) != set(PrayerName):  # pragma: no cover - defensive invariant.
            raise PrayerCalculationUnavailableError("incomplete_result")
        return CalculationResult(times_utc=times, fallback=resolved.fallback)

    def _resolve_solar_time(self, value: CalculationInput) -> _ResolvedSolarTime:
        today = _SolarTime(value.local_date, value.latitude, value.longitude)
        tomorrow_date = value.local_date + timedelta(days=1)
        tomorrow = _SolarTime(tomorrow_date, value.latitude, value.longitude)
        if _valid_solar_day(today) and _valid_solar_day(tomorrow):
            return _ResolvedSolarTime(
                today,
                tomorrow,
                value.latitude,
                FallbackMetadata(applied=False),
            )

        if value.polar_resolution == PolarResolution.AQRAB_YAUM:
            resolved = self._resolve_aqrab_yaum(value)
        elif value.polar_resolution == PolarResolution.AQRAB_BALAD:
            resolved = self._resolve_aqrab_balad(value)
        else:
            resolved = None
        if resolved is None:
            raise PrayerCalculationUnavailableError("polar_sunrise_or_sunset_unresolved")
        return resolved

    def _resolve_aqrab_yaum(self, value: CalculationInput) -> _ResolvedSolarTime | None:
        for distance in range(1, _MAX_POLAR_DAY_SEARCH + 1):
            for direction in (1, -1):
                reference_date = value.local_date + timedelta(days=distance * direction)
                solar_time = _SolarTime(reference_date, value.latitude, value.longitude)
                tomorrow = _SolarTime(
                    reference_date + timedelta(days=1),
                    value.latitude,
                    value.longitude,
                )
                if _valid_solar_day(solar_time) and _valid_solar_day(tomorrow):
                    return _ResolvedSolarTime(
                        solar_time,
                        tomorrow,
                        value.latitude,
                        FallbackMetadata(
                            applied=True,
                            strategy=PolarResolution.AQRAB_YAUM,
                            reason="polar_sunrise_or_sunset_unavailable",
                            reference_date=reference_date,
                        ),
                    )
        return None

    def _resolve_aqrab_balad(self, value: CalculationInput) -> _ResolvedSolarTime | None:
        direction = 1.0 if value.latitude > 0 else -1.0
        latitude = value.latitude - direction * _LATITUDE_VARIATION_STEP
        while abs(latitude) >= _UNSAFE_LATITUDE:
            solar_time = _SolarTime(value.local_date, latitude, value.longitude)
            tomorrow = _SolarTime(
                value.local_date + timedelta(days=1),
                latitude,
                value.longitude,
            )
            if _valid_solar_day(solar_time) and _valid_solar_day(tomorrow):
                return _ResolvedSolarTime(
                    solar_time,
                    tomorrow,
                    latitude,
                    FallbackMetadata(
                        applied=True,
                        strategy=PolarResolution.AQRAB_BALAD,
                        reason="polar_sunrise_or_sunset_unavailable",
                        reference_latitude=latitude,
                    ),
                )
            latitude -= direction * _LATITUDE_VARIATION_STEP
        return None

    def _calculate_times(
        self,
        value: CalculationInput,
        resolved: _ResolvedSolarTime,
    ) -> dict[PrayerName, datetime]:
        target_date = value.local_date
        tomorrow_date = target_date + timedelta(days=1)
        solar_time = resolved.solar_time

        dhuhr = _as_utc_datetime(solar_time.transit, target_date)
        sunrise = _as_utc_datetime(solar_time.sunrise, target_date)
        sunset = _as_utc_datetime(solar_time.sunset, target_date)
        tomorrow_sunrise = _as_utc_datetime(resolved.tomorrow_solar_time.sunrise, tomorrow_date)
        asr = _as_utc_datetime(
            solar_time.afternoon(2 if value.asr_method == AsrMethod.HANAFI else 1),
            target_date,
        )
        if None in (dhuhr, sunrise, sunset, tomorrow_sunrise, asr):
            raise PrayerCalculationUnavailableError("required_solar_event_unavailable")
        assert dhuhr is not None
        assert sunrise is not None
        assert sunset is not None
        assert tomorrow_sunrise is not None
        assert asr is not None

        night_seconds = (tomorrow_sunrise - sunset).total_seconds()
        if not math.isfinite(night_seconds) or night_seconds <= 0:
            raise PrayerCalculationUnavailableError("invalid_night_duration")

        fajr = _as_utc_datetime(
            solar_time.hour_angle(-value.method.fajr_angle, after_transit=False),
            target_date,
        )
        if _is_moonsighting(value.method.method_code) and value.latitude >= 55:
            fajr = sunrise - timedelta(seconds=night_seconds / 7)
        safe_fajr = self._safe_fajr(value, sunrise, night_seconds)
        if fajr is None or safe_fajr > fajr:
            fajr = safe_fajr

        if value.method.isha_interval_minutes is not None:
            isha = sunset + timedelta(minutes=value.method.isha_interval_minutes)
        else:
            assert value.method.isha_angle is not None
            isha_candidate = _as_utc_datetime(
                solar_time.hour_angle(-value.method.isha_angle, after_transit=True),
                target_date,
            )
            if _is_moonsighting(value.method.method_code) and value.latitude >= 55:
                isha_candidate = sunset + timedelta(seconds=night_seconds / 7)
            safe_isha = self._safe_isha(value, sunset, night_seconds)
            isha = (
                safe_isha
                if isha_candidate is None or safe_isha < isha_candidate
                else isha_candidate
            )

        maghrib = sunset
        if value.method.maghrib_angle is not None:
            angle_maghrib = _as_utc_datetime(
                solar_time.hour_angle(-value.method.maghrib_angle, after_transit=True),
                target_date,
            )
            if angle_maghrib is not None and sunset < angle_maghrib < isha:
                maghrib = angle_maghrib

        raw_times = {
            PrayerName.FAJR: fajr,
            PrayerName.SUNRISE: sunrise,
            PrayerName.DHUHR: dhuhr,
            PrayerName.ASR: asr,
            PrayerName.MAGHRIB: maghrib,
            PrayerName.ISHA: isha,
        }
        method_adjustments = value.method.method_adjustments.as_dict()
        user_adjustments = value.adjustments.as_dict()
        return {
            prayer: _round_datetime(
                prayer_time
                + timedelta(minutes=method_adjustments[prayer] + user_adjustments[prayer]),
                value.method.rounding,
            )
            for prayer, prayer_time in raw_times.items()
        }

    def _safe_fajr(
        self,
        value: CalculationInput,
        sunrise: datetime,
        night_seconds: float,
    ) -> datetime:
        if _is_moonsighting(value.method.method_code):
            return _season_adjusted_morning_twilight(
                value.latitude,
                value.local_date,
                sunrise,
            )
        portion = _night_portion(
            value.high_latitude_rule,
            value.method.fajr_angle,
        )
        return sunrise - timedelta(seconds=night_seconds * portion)

    def _safe_isha(
        self,
        value: CalculationInput,
        sunset: datetime,
        night_seconds: float,
    ) -> datetime:
        assert value.method.isha_angle is not None
        if _is_moonsighting(value.method.method_code):
            return _season_adjusted_evening_twilight(
                value.latitude,
                value.local_date,
                sunset,
                value.method.shafaq,
            )
        portion = _night_portion(
            value.high_latitude_rule,
            value.method.isha_angle,
        )
        return sunset + timedelta(seconds=night_seconds * portion)


def _approximate_transit(longitude: float, sidereal_time: float, right_ascension: float) -> float:
    longitude_west = longitude * -1
    transit = ((right_ascension + longitude_west - sidereal_time) / 360) % 1
    expected = ((12.0 - longitude / 15.0) / 24.0) % 1
    if transit - expected > 0.5:
        return transit - 1.0
    if expected - transit > 0.5:
        return transit + 1.0
    return transit


def _valid_solar_day(value: _SolarTime) -> bool:
    return math.isfinite(value.sunrise) and math.isfinite(value.sunset)


def _as_utc_datetime(value: float, local_date: date) -> datetime | None:
    if not math.isfinite(value):
        return None
    hours = math.floor(value)
    minutes = math.floor((value - hours) * 60)
    seconds = math.floor((value - (hours + minutes / 60)) * 3600)
    return datetime(local_date.year, local_date.month, local_date.day, tzinfo=UTC) + timedelta(
        hours=hours,
        minutes=minutes,
        seconds=seconds,
    )


def _round_datetime(value: datetime, rule: RoundingRule) -> datetime:
    if rule == RoundingRule.NONE:
        return value
    seconds = value.second
    if rule == RoundingRule.UP:
        offset = 60 - seconds
    else:
        offset = 60 - seconds if seconds >= 30 else -seconds
    return value + timedelta(seconds=offset, microseconds=-value.microsecond)


def _night_portion(rule: HighLatitudeRule, angle: float) -> float:
    if rule == HighLatitudeRule.MIDDLE_OF_THE_NIGHT:
        return 0.5
    if rule == HighLatitudeRule.SEVENTH_OF_THE_NIGHT:
        return 1 / 7
    if rule == HighLatitudeRule.TWILIGHT_ANGLE:
        return angle / 60
    raise PrayerCalculationUnavailableError("invalid_high_latitude_rule")  # pragma: no cover


def _is_moonsighting(method_code: str) -> bool:
    return method_code == "moonsighting_committee"


def _days_since_solstice(local_date: date, latitude: float) -> int:
    day_of_year = local_date.timetuple().tm_yday
    days_in_year = 366 if _is_leap_year(local_date.year) else 365
    if latitude >= 0:
        result = day_of_year + 10
        return result - days_in_year if result >= days_in_year else result
    southern_offset = 173 if _is_leap_year(local_date.year) else 172
    result = day_of_year - southern_offset
    return result + days_in_year if result < 0 else result


def _is_leap_year(year: int) -> bool:
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


def _seasonal_adjustment(
    local_date: date,
    latitude: float,
    coefficients: tuple[float, float, float, float],
) -> float:
    a, b, c, d = coefficients
    day = _days_since_solstice(local_date, latitude)
    if day < 91:
        return a + (b - a) / 91 * day
    if day < 137:
        return b + (c - b) / 46 * (day - 91)
    if day < 183:
        return c + (d - c) / 46 * (day - 137)
    if day < 229:
        return d + (c - d) / 46 * (day - 183)
    if day < 275:
        return c + (b - c) / 46 * (day - 229)
    return b + (a - b) / 91 * (day - 275)


def _season_adjusted_morning_twilight(
    latitude: float,
    local_date: date,
    sunrise: datetime,
) -> datetime:
    absolute_latitude = abs(latitude)
    adjustment = _seasonal_adjustment(
        local_date,
        latitude,
        (
            75 + 28.65 / 55 * absolute_latitude,
            75 + 19.44 / 55 * absolute_latitude,
            75 + 32.74 / 55 * absolute_latitude,
            75 + 48.10 / 55 * absolute_latitude,
        ),
    )
    return sunrise - timedelta(seconds=_javascript_round(adjustment * 60))


def _season_adjusted_evening_twilight(
    latitude: float,
    local_date: date,
    sunset: datetime,
    shafaq: Shafaq,
) -> datetime:
    absolute_latitude = abs(latitude)
    if shafaq == Shafaq.AHMER:
        coefficients = (
            62 + 17.4 / 55 * absolute_latitude,
            62 - 7.16 / 55 * absolute_latitude,
            62 + 5.12 / 55 * absolute_latitude,
            62 + 19.44 / 55 * absolute_latitude,
        )
    elif shafaq == Shafaq.ABYAD:
        coefficients = (
            75 + 25.6 / 55 * absolute_latitude,
            75 + 7.16 / 55 * absolute_latitude,
            75 + 36.84 / 55 * absolute_latitude,
            75 + 81.84 / 55 * absolute_latitude,
        )
    else:
        coefficients = (
            75 + 25.6 / 55 * absolute_latitude,
            75 + 2.05 / 55 * absolute_latitude,
            75 - 9.21 / 55 * absolute_latitude,
            75 + 6.14 / 55 * absolute_latitude,
        )
    adjustment = _seasonal_adjustment(local_date, latitude, coefficients)
    return sunset + timedelta(seconds=_javascript_round(adjustment * 60))


def _javascript_round(value: float) -> int:
    return math.floor(value + 0.5)
