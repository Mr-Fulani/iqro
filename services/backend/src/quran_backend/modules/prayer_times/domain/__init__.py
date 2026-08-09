"""Framework-independent prayer-time calculation contracts."""

from quran_backend.modules.prayer_times.domain.types import (
    AsrMethod,
    CalculationInput,
    CalculationResult,
    EngineMethodConfig,
    FallbackMetadata,
    HighLatitudeRule,
    PolarResolution,
    PrayerAdjustments,
    PrayerName,
    RoundingRule,
    Shafaq,
)

__all__ = [
    "AsrMethod",
    "CalculationInput",
    "CalculationResult",
    "EngineMethodConfig",
    "FallbackMetadata",
    "HighLatitudeRule",
    "PolarResolution",
    "PrayerAdjustments",
    "PrayerName",
    "RoundingRule",
    "Shafaq",
]
