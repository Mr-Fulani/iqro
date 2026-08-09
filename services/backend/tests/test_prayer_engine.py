from __future__ import annotations

import json
from dataclasses import replace
from datetime import UTC, date, datetime
from pathlib import Path
from typing import Any

import pytest

from quran_backend.modules.prayer_times.domain import (
    AsrMethod,
    CalculationInput,
    EngineMethodConfig,
    HighLatitudeRule,
    PolarResolution,
    PrayerAdjustments,
    PrayerName,
    RoundingRule,
)
from quran_backend.modules.prayer_times.engine import (
    ENGINE_VERSION,
    AdhanCompatibilityEngine,
    PrayerCalculationUnavailableError,
)

FIXTURE_PATH = Path(__file__).parent / "fixtures/prayer_times/adhan_js_4_4_4.json"


def _fixture() -> dict[str, Any]:
    return json.loads(FIXTURE_PATH.read_text())


def _mwl_config() -> EngineMethodConfig:
    return EngineMethodConfig(
        method_code="muslim_world_league",
        fajr_angle=18,
        isha_angle=17,
        isha_interval_minutes=None,
        method_adjustments=PrayerAdjustments(dhuhr=1),
    )


@pytest.mark.parametrize("case", _fixture()["cases"], ids=lambda case: str(case["id"]))
def test_engine_matches_independent_adhan_js_golden_cases(case: dict[str, Any]) -> None:
    result = AdhanCompatibilityEngine().calculate(
        CalculationInput(
            latitude=float(case["latitude"]),
            longitude=float(case["longitude"]),
            local_date=date.fromisoformat(case["date"]),
            method=_mwl_config(),
            asr_method=AsrMethod.STANDARD,
            high_latitude_rule=HighLatitudeRule(case["high_latitude_rule"]),
            polar_resolution=PolarResolution(case["polar_resolution"]),
        )
    )

    tolerance = float(_fixture()["provenance"]["tolerance_seconds"])
    for prayer in PrayerName:
        expected = datetime.fromisoformat(case["expected_utc"][prayer].replace("Z", "+00:00"))
        assert expected.tzinfo == UTC
        assert abs((result.times_utc[prayer] - expected).total_seconds()) <= tolerance

    expected_fallback = case.get("expected_fallback")
    assert result.fallback.applied is (expected_fallback is not None)
    if expected_fallback:
        assert result.fallback.strategy == PolarResolution(expected_fallback["strategy"])
        assert result.fallback.reference_date == date.fromisoformat(
            expected_fallback["reference_date"]
        )


def test_hanafi_asr_is_later_than_standard_asr() -> None:
    base = {
        "latitude": 41.0082,
        "longitude": 28.9784,
        "local_date": date(2026, 8, 9),
        "method": _mwl_config(),
        "high_latitude_rule": HighLatitudeRule.MIDDLE_OF_THE_NIGHT,
        "polar_resolution": PolarResolution.UNRESOLVED,
    }
    standard = AdhanCompatibilityEngine().calculate(
        CalculationInput(asr_method=AsrMethod.STANDARD, **base)
    )
    hanafi = AdhanCompatibilityEngine().calculate(
        CalculationInput(asr_method=AsrMethod.HANAFI, **base)
    )

    assert hanafi.times_utc[PrayerName.ASR] > standard.times_utc[PrayerName.ASR]


def test_user_adjustments_apply_exactly_after_calculation() -> None:
    base = CalculationInput(
        latitude=41.0082,
        longitude=28.9784,
        local_date=date(2026, 8, 9),
        method=replace(_mwl_config(), rounding=RoundingRule.NONE),
        asr_method=AsrMethod.STANDARD,
        high_latitude_rule=HighLatitudeRule.MIDDLE_OF_THE_NIGHT,
        polar_resolution=PolarResolution.UNRESOLVED,
    )
    adjusted = CalculationInput(
        latitude=base.latitude,
        longitude=base.longitude,
        local_date=base.local_date,
        method=base.method,
        asr_method=base.asr_method,
        high_latitude_rule=base.high_latitude_rule,
        polar_resolution=base.polar_resolution,
        adjustments=PrayerAdjustments(fajr=-7, sunrise=2, dhuhr=3, asr=4, maghrib=5, isha=6),
    )

    original_result = AdhanCompatibilityEngine().calculate(base)
    adjusted_result = AdhanCompatibilityEngine().calculate(adjusted)

    for prayer, minutes in adjusted.adjustments.as_dict().items():
        assert (
            adjusted_result.times_utc[PrayerName(prayer)]
            - original_result.times_utc[PrayerName(prayer)]
        ).total_seconds() == minutes * 60


def test_unresolved_polar_day_returns_safe_typed_error() -> None:
    with pytest.raises(PrayerCalculationUnavailableError) as exc_info:
        AdhanCompatibilityEngine().calculate(
            CalculationInput(
                latitude=69.6492,
                longitude=18.9553,
                local_date=date(2026, 6, 21),
                method=_mwl_config(),
                asr_method=AsrMethod.STANDARD,
                high_latitude_rule=HighLatitudeRule.SEVENTH_OF_THE_NIGHT,
                polar_resolution=PolarResolution.UNRESOLVED,
            )
        )

    assert exc_info.value.reason == "polar_sunrise_or_sunset_unresolved"
    assert "69.6492" not in str(exc_info.value)


def test_engine_version_pins_upstream_and_adapter_versions() -> None:
    assert ENGINE_VERSION == "4.4.4-quran.1-adhanpy.1.0.5"
