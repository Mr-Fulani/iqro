from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime
from enum import StrEnum


class PrayerName(StrEnum):
    FAJR = "fajr"
    SUNRISE = "sunrise"
    DHUHR = "dhuhr"
    ASR = "asr"
    MAGHRIB = "maghrib"
    ISHA = "isha"


class AsrMethod(StrEnum):
    STANDARD = "standard"
    HANAFI = "hanafi"


class HighLatitudeRule(StrEnum):
    MIDDLE_OF_THE_NIGHT = "middle_of_night"
    SEVENTH_OF_THE_NIGHT = "seventh_of_night"
    TWILIGHT_ANGLE = "twilight_angle"


class PolarResolution(StrEnum):
    UNRESOLVED = "unresolved"
    AQRAB_YAUM = "aqrab_yaum"
    AQRAB_BALAD = "aqrab_balad"


class RoundingRule(StrEnum):
    NEAREST = "nearest"
    UP = "up"
    NONE = "none"


class Shafaq(StrEnum):
    GENERAL = "general"
    AHMER = "ahmer"
    ABYAD = "abyad"


@dataclass(frozen=True, slots=True)
class PrayerAdjustments:
    fajr: int = 0
    sunrise: int = 0
    dhuhr: int = 0
    asr: int = 0
    maghrib: int = 0
    isha: int = 0

    def as_dict(self) -> dict[str, int]:
        return {
            PrayerName.FAJR: self.fajr,
            PrayerName.SUNRISE: self.sunrise,
            PrayerName.DHUHR: self.dhuhr,
            PrayerName.ASR: self.asr,
            PrayerName.MAGHRIB: self.maghrib,
            PrayerName.ISHA: self.isha,
        }


@dataclass(frozen=True, slots=True)
class EngineMethodConfig:
    """Exact immutable inputs needed by the calculation engine."""

    method_code: str
    fajr_angle: float
    isha_angle: float | None
    isha_interval_minutes: int | None
    method_adjustments: PrayerAdjustments = field(default_factory=PrayerAdjustments)
    maghrib_angle: float | None = None
    rounding: RoundingRule = RoundingRule.NEAREST
    shafaq: Shafaq = Shafaq.GENERAL


@dataclass(frozen=True, slots=True)
class CalculationInput:
    latitude: float
    longitude: float
    local_date: date
    method: EngineMethodConfig
    asr_method: AsrMethod
    high_latitude_rule: HighLatitudeRule
    polar_resolution: PolarResolution
    adjustments: PrayerAdjustments = field(default_factory=PrayerAdjustments)


@dataclass(frozen=True, slots=True)
class FallbackMetadata:
    applied: bool
    strategy: PolarResolution | None = None
    reason: str | None = None
    reference_date: date | None = None
    reference_latitude: float | None = None


@dataclass(frozen=True, slots=True)
class CalculationResult:
    times_utc: dict[PrayerName, datetime]
    fallback: FallbackMetadata
