from __future__ import annotations

import copy
import json
import re
from datetime import datetime
from typing import Any, cast

import pytest
from django.core.cache import cache
from django.http import HttpRequest
from django.urls import reverse
from django.views.debug import SafeExceptionReporterFilter
from drf_spectacular.generators import SchemaGenerator
from rest_framework.test import APIClient, APIRequestFactory

from quran_backend.modules.core.privacy import PRIVATE_NO_STORE_CACHE_CONTROL
from quran_backend.modules.prayer_times.engine import (
    ENGINE_ID,
    ENGINE_VERSION,
    AdhanCompatibilityEngine,
)
from quran_backend.modules.prayer_times.models import (
    PrayerConfigRelease,
    PrayerMethod,
    PrayerMethodConfig,
)
from quran_backend.modules.prayer_times.throttling import PrayerCalculationThrottle
from quran_backend.modules.prayer_times.timezones import TZDB_VERSION


@pytest.fixture
def prayer_method_config(db: None) -> PrayerMethodConfig:
    return PrayerMethodConfig.objects.select_related("release", "method").get(
        method__code="muslim-world-league",
        release__version="2026.1",
    )


def _calculation_payload(
    configuration: PrayerMethodConfig,
    **overrides: Any,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "date": "2026-08-09",
        "timezone": "Europe/Istanbul",
        "location": {
            "latitude": "41.012345",
            "longitude": "28.976543",
        },
        "method_config_id": str(configuration.id),
        "method_checksum_sha256": configuration.checksum_sha256,
        "asr_method": "standard",
        "high_latitude_rule": "middle_of_night",
        "polar_resolution": "unresolved",
    }
    payload.update(overrides)
    return payload


def _assert_private_no_store(response: Any) -> None:
    assert response.headers["Cache-Control"] == PRIVATE_NO_STORE_CACHE_CONTROL
    assert response.headers["Pragma"] == "no-cache"
    assert response.headers["Expires"] == "0"
    assert "Authorization" in {item.strip() for item in response.headers["Vary"].split(",")}


@pytest.mark.django_db
def test_prayer_methods_is_public_versioned_and_conditionally_cacheable(
    prayer_method_config: PrayerMethodConfig,
) -> None:
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION="Bearer deliberately-invalid-token")
    url = reverse("prayer_times:methods")

    response = client.get(url)

    assert response.status_code == 200
    assert response.headers["Cache-Control"] == (
        "public, max-age=300, stale-while-revalidate=86400"
    )
    assert re.fullmatch(r'W/"[0-9a-f]{64}"', response.headers["ETag"])
    payload = response.json()
    assert payload["catalog_version"] == "2026.1"
    assert payload["configuration_schema_version"] == 1
    assert payload["algorithm"] == {
        "id": ENGINE_ID,
        "version": ENGINE_VERSION,
        "upstream": "a6f1a5c4a00105103f310ef18200b95f7184d2e7",
    }
    assert payload["timezone_database_version"] == TZDB_VERSION
    assert len(payload["checksum_sha256"]) == 64
    assert len(payload["methods"]) == 9
    selected = next(item for item in payload["methods"] if item["code"] == "muslim-world-league")
    assert selected["id"] == str(prayer_method_config.id)
    assert selected["available"] is True
    assert selected["checksum_sha256"] == prayer_method_config.checksum_sha256
    assert selected["high_latitude_rules"]["default"] == "middle_of_night"
    assert selected["polar_resolutions"]["default"] == "unresolved"

    not_modified = client.get(url, headers={"If-None-Match": response.headers["ETag"]})

    assert not_modified.status_code == 304
    assert not_modified.content == b""
    assert not_modified.headers["ETag"] == response.headers["ETag"]
    assert not_modified.headers["Cache-Control"] == response.headers["Cache-Control"]


@pytest.mark.django_db
def test_calculate_is_stateless_private_and_never_echoes_coordinates(
    prayer_method_config: PrayerMethodConfig,
) -> None:
    client = APIClient()
    before_counts = {
        "releases": PrayerConfigRelease.objects.count(),
        "methods": PrayerMethod.objects.count(),
        "configurations": PrayerMethodConfig.objects.count(),
    }

    response = client.post(
        reverse("prayer_times:calculate"),
        _calculation_payload(prayer_method_config),
        format="json",
    )

    assert response.status_code == 200
    _assert_private_no_store(response)
    payload = response.json()
    serialized = json.dumps(payload, sort_keys=True)
    assert "location" not in payload
    assert '"latitude":' not in serialized
    assert '"longitude":' not in serialized
    assert "41.012345" not in serialized
    assert "28.976543" not in serialized
    assert payload["date"] == "2026-08-09"
    assert payload["timezone"] == "Europe/Istanbul"
    assert payload["timezone_database_version"] == TZDB_VERSION
    assert payload["method"] == {
        "id": str(prayer_method_config.id),
        "code": "muslim-world-league",
        "catalog_version": "2026.1",
        "checksum_sha256": prayer_method_config.checksum_sha256,
    }
    assert set(payload["times"]) == {"fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"}
    for event in payload["times"].values():
        assert datetime.fromisoformat(event["local"]).utcoffset() is not None
        assert datetime.fromisoformat(event["utc"].replace("Z", "+00:00")).utcoffset() is not None
        assert event["utc_offset_seconds"] == 10_800
    assert PrayerConfigRelease.objects.count() == before_counts["releases"]
    assert PrayerMethod.objects.count() == before_counts["methods"]
    assert PrayerMethodConfig.objects.count() == before_counts["configurations"]


@pytest.mark.django_db
def test_unexpected_exception_reporter_redacts_coordinate_bearing_frames(
    prayer_method_config: PrayerMethodConfig,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def _explode(_self: Any, calculation_input: Any) -> Any:
        latitude = calculation_input.latitude
        longitude = calculation_input.longitude
        assert latitude == 41.123456
        assert longitude == 28.654321
        raise RuntimeError("Synthetic unexpected prayer engine failure.")

    monkeypatch.setattr(AdhanCompatibilityEngine, "_resolve_solar_time", _explode)
    payload = _calculation_payload(
        prayer_method_config,
        location={"latitude": "41.123456", "longitude": "28.654321"},
    )

    with pytest.raises(RuntimeError) as exc_info:
        APIClient().post(reverse("prayer_times:calculate"), payload, format="json")

    traceback = exc_info.value.__traceback__
    reporter_filter = SafeExceptionReporterFilter()
    reporter_request = HttpRequest()
    protected_frames = 0
    while traceback is not None:
        frame = traceback.tb_frame
        is_prayer_frame = "/modules/prayer_times/" in frame.f_code.co_filename
        if is_prayer_frame or frame.f_code.co_name == "_explode":
            protected_frames += 1
            cleansed = dict(reporter_filter.get_traceback_frame_variables(reporter_request, frame))
            rendered = repr(cleansed.values())
            assert "41.123456" not in rendered
            assert "28.654321" not in rendered
        traceback = traceback.tb_next
    assert protected_frames >= 4


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("timezone_name", "location", "expected_dhuhr"),
    [
        (
            "Pacific/Kiritimati",
            {"latitude": "1.872100", "longitude": "-157.427800"},
            "2026-08-09T12:36:00+14:00",
        ),
        (
            "Pacific/Pago_Pago",
            {"latitude": "-14.275600", "longitude": "-170.702000"},
            "2026-08-09T12:29:00-11:00",
        ),
    ],
)
def test_calculate_anchors_international_date_line_results_to_requested_civil_date(
    prayer_method_config: PrayerMethodConfig,
    timezone_name: str,
    location: dict[str, str],
    expected_dhuhr: str,
) -> None:
    response = APIClient().post(
        reverse("prayer_times:calculate"),
        _calculation_payload(
            prayer_method_config,
            timezone=timezone_name,
            location=location,
        ),
        format="json",
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["date"] == "2026-08-09"
    assert payload["times"]["dhuhr"]["local"] == expected_dhuhr
    assert {
        datetime.fromisoformat(event["local"]).date().isoformat()
        for event in payload["times"].values()
    } == {"2026-08-09"}


@pytest.mark.django_db
def test_calculate_fails_closed_for_a_civil_date_skipped_by_timezone_history(
    prayer_method_config: PrayerMethodConfig,
) -> None:
    response = APIClient().post(
        reverse("prayer_times:calculate"),
        _calculation_payload(
            prayer_method_config,
            date="2011-12-30",
            timezone="Pacific/Apia",
            location={"latitude": "-13.850000", "longitude": "-171.750000"},
        ),
        format="json",
    )

    assert response.status_code == 422
    _assert_private_no_store(response)
    assert response.json()["code"] == "prayer_calculation_unavailable"


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("mutation", "field_fragment"),
    [
        (lambda payload: payload.update({"unexpected": True}), "unexpected"),
        (lambda payload: payload["location"].update({"accuracy": 5}), "accuracy"),
        (lambda payload: payload.update({"adjustments": {"fajr": 0, "hidden": 1}}), "hidden"),
        (lambda payload: payload["location"].update({"latitude": "NaN"}), "latitude"),
        (lambda payload: payload["location"].update({"latitude": "90.000001"}), "latitude"),
        (lambda payload: payload["location"].update({"longitude": "-180.000001"}), "longitude"),
        (lambda payload: payload.update({"timezone": "../Europe/Istanbul"}), "timezone"),
        (lambda payload: payload.update({"date": "1899-12-31"}), "date"),
        (lambda payload: payload.update({"adjustments": {"isha": 121}}), "isha"),
    ],
    ids=[
        "unknown-top-level",
        "unknown-location",
        "unknown-adjustment",
        "nan-coordinate",
        "latitude-bound",
        "longitude-bound",
        "timezone",
        "date-bound",
        "adjustment-bound",
    ],
)
def test_calculate_strictly_rejects_unknown_or_unsafe_input(
    prayer_method_config: PrayerMethodConfig,
    mutation: Any,
    field_fragment: str,
) -> None:
    payload = _calculation_payload(prayer_method_config)
    mutation(payload)

    response = APIClient().post(reverse("prayer_times:calculate"), payload, format="json")

    assert response.status_code == 400
    _assert_private_no_store(response)
    problem = response.json()
    assert problem["code"] == "invalid"
    assert field_fragment in json.dumps(problem["field_errors"], sort_keys=True)


@pytest.mark.django_db
def test_calculate_rejects_stale_method_checksum(
    prayer_method_config: PrayerMethodConfig,
) -> None:
    payload = _calculation_payload(
        prayer_method_config,
        method_checksum_sha256="0" * 64,
    )

    response = APIClient().post(reverse("prayer_times:calculate"), payload, format="json")

    assert response.status_code == 409
    _assert_private_no_store(response)
    assert response.json()["code"] == "prayer_method_checksum_mismatch"


def _clone_configuration_into_release(
    source: PrayerMethodConfig,
    release: PrayerConfigRelease,
) -> PrayerMethodConfig:
    return PrayerMethodConfig.objects.create(
        release=release,
        method=source.method,
        fajr_angle=source.fajr_angle,
        isha_angle=source.isha_angle,
        isha_interval_minutes=source.isha_interval_minutes,
        ramadan_isha_interval_minutes=source.ramadan_isha_interval_minutes,
        fajr_adjustment_minutes=source.fajr_adjustment_minutes,
        sunrise_adjustment_minutes=source.sunrise_adjustment_minutes,
        dhuhr_adjustment_minutes=source.dhuhr_adjustment_minutes,
        asr_adjustment_minutes=source.asr_adjustment_minutes,
        maghrib_adjustment_minutes=source.maghrib_adjustment_minutes,
        isha_adjustment_minutes=source.isha_adjustment_minutes,
        supports_middle_of_night=source.supports_middle_of_night,
        supports_seventh_of_night=source.supports_seventh_of_night,
        supports_twilight_angle=source.supports_twilight_angle,
        default_high_latitude_rule=source.default_high_latitude_rule,
        supports_polar_unresolved=source.supports_polar_unresolved,
        supports_polar_aqrab_balad=source.supports_polar_aqrab_balad,
        supports_polar_aqrab_yaum=source.supports_polar_aqrab_yaum,
        default_polar_resolution=source.default_polar_resolution,
        source_name=source.source_name,
        source_url=source.source_url,
        source_version=source.source_version,
        source_checksum_sha256=source.source_checksum_sha256,
    )


def _new_release(version: str) -> PrayerConfigRelease:
    return PrayerConfigRelease.objects.create(
        version=version,
        configuration_schema_version=1,
        algorithm=ENGINE_ID,
        algorithm_version=ENGINE_VERSION,
        timezone_database_version=TZDB_VERSION,
        release_notes="Synthetic API lifecycle test release.",
    )


@pytest.mark.django_db
def test_calculate_hides_draft_method_configuration(
    prayer_method_config: PrayerMethodConfig,
) -> None:
    release = _new_release("2099.1-draft-api")
    draft = _clone_configuration_into_release(prayer_method_config, release)

    response = APIClient().post(
        reverse("prayer_times:calculate"),
        _calculation_payload(
            draft,
            method_checksum_sha256=draft.checksum_sha256,
        ),
        format="json",
    )

    assert response.status_code == 404
    _assert_private_no_store(response)
    assert response.json()["code"] == "prayer_method_not_found"


@pytest.mark.django_db
def test_calculate_returns_gone_for_withdrawn_method_configuration(
    prayer_method_config: PrayerMethodConfig,
) -> None:
    release = _new_release("2099.2-withdrawn-api")
    configuration = _clone_configuration_into_release(prayer_method_config, release)
    release.publish(make_default=False)
    release.save()
    release.withdraw()
    release.save()

    response = APIClient().post(
        reverse("prayer_times:calculate"),
        _calculation_payload(configuration),
        format="json",
    )

    assert response.status_code == 410
    _assert_private_no_store(response)
    assert response.json()["code"] == "prayer_method_withdrawn"


@pytest.mark.django_db
def test_calculate_returns_semantic_422_for_method_specific_unsupported_rule(
    prayer_method_config: PrayerMethodConfig,
) -> None:
    release = _new_release("2099.3-limited-rules-api")
    configuration = _clone_configuration_into_release(prayer_method_config, release)
    configuration.supports_twilight_angle = False
    configuration.save(update_fields={"supports_twilight_angle"})
    release.publish(make_default=False)
    release.save()

    response = APIClient().post(
        reverse("prayer_times:calculate"),
        _calculation_payload(
            configuration,
            method_checksum_sha256=configuration.checksum_sha256,
            high_latitude_rule="twilight_angle",
        ),
        format="json",
    )

    assert response.status_code == 422
    _assert_private_no_store(response)
    problem = response.json()
    assert problem["code"] == "prayer_rule_unsupported"
    assert "high_latitude_rule" in problem["field_errors"]


@pytest.mark.django_db
def test_unresolved_polar_day_is_safe_typed_422_and_aqrab_yaum_is_explicit(
    prayer_method_config: PrayerMethodConfig,
) -> None:
    base = _calculation_payload(
        prayer_method_config,
        date="2026-06-21",
        timezone="Europe/Oslo",
        location={"latitude": "69.649200", "longitude": "18.955300"},
        high_latitude_rule="seventh_of_night",
    )
    client = APIClient()

    unresolved = client.post(reverse("prayer_times:calculate"), base, format="json")
    resolved_payload = copy.deepcopy(base)
    resolved_payload["polar_resolution"] = "aqrab_yaum"
    resolved = client.post(reverse("prayer_times:calculate"), resolved_payload, format="json")

    assert unresolved.status_code == 422
    _assert_private_no_store(unresolved)
    assert unresolved.json()["code"] == "prayer_calculation_unavailable"
    assert "69.6492" not in unresolved.content.decode()
    assert "18.9553" not in unresolved.content.decode()
    assert resolved.status_code == 200
    assert resolved.json()["fallback"] == {
        "applied": True,
        "strategy": "aqrab_yaum",
        "reason": "polar_sunrise_or_sunset_unavailable",
        "reference_date": "2026-07-26",
    }
    assert "polar_resolution_applied" in resolved.json()["warnings"]


@pytest.mark.django_db
def test_polar_reference_date_stays_civil_aligned_across_the_date_line(
    prayer_method_config: PrayerMethodConfig,
) -> None:
    common = {
        "date": "2026-06-21",
        "location": {"latitude": "66.313000", "longitude": "17.886000"},
        "high_latitude_rule": "seventh_of_night",
        "polar_resolution": "aqrab_yaum",
    }
    client = APIClient()
    utc = client.post(
        reverse("prayer_times:calculate"),
        _calculation_payload(prayer_method_config, timezone="Etc/UTC", **common),
        format="json",
    )
    date_line = client.post(
        reverse("prayer_times:calculate"),
        _calculation_payload(
            prayer_method_config,
            timezone="Pacific/Kiritimati",
            **common,
        ),
        format="json",
    )

    assert utc.status_code == 200
    assert date_line.status_code == 200
    assert date_line.json()["times"]["dhuhr"]["local"].startswith("2026-06-21T")
    assert utc.json()["fallback"]["reference_date"] == "2026-07-05"
    assert date_line.json()["fallback"]["reference_date"] == "2026-06-08"


@pytest.mark.django_db
def test_hanafi_asr_and_manual_adjustments_are_applied_exactly(
    prayer_method_config: PrayerMethodConfig,
) -> None:
    client = APIClient()
    standard = client.post(
        reverse("prayer_times:calculate"),
        _calculation_payload(prayer_method_config),
        format="json",
    ).json()
    hanafi = client.post(
        reverse("prayer_times:calculate"),
        _calculation_payload(prayer_method_config, asr_method="hanafi"),
        format="json",
    ).json()
    adjusted = client.post(
        reverse("prayer_times:calculate"),
        _calculation_payload(prayer_method_config, adjustments={"fajr": -7, "isha": 11}),
        format="json",
    ).json()

    standard_asr = datetime.fromisoformat(standard["times"]["asr"]["utc"].replace("Z", "+00:00"))
    hanafi_asr = datetime.fromisoformat(hanafi["times"]["asr"]["utc"].replace("Z", "+00:00"))
    standard_fajr = datetime.fromisoformat(standard["times"]["fajr"]["utc"].replace("Z", "+00:00"))
    adjusted_fajr = datetime.fromisoformat(adjusted["times"]["fajr"]["utc"].replace("Z", "+00:00"))
    standard_isha = datetime.fromisoformat(standard["times"]["isha"]["utc"].replace("Z", "+00:00"))
    adjusted_isha = datetime.fromisoformat(adjusted["times"]["isha"]["utc"].replace("Z", "+00:00"))

    assert hanafi_asr > standard_asr
    assert (adjusted_fajr - standard_fajr).total_seconds() == -7 * 60
    assert (adjusted_isha - standard_isha).total_seconds() == 11 * 60
    assert adjusted["adjustments"] == {
        "fajr": -7,
        "sunrise": 0,
        "dhuhr": 0,
        "asr": 0,
        "maghrib": 0,
        "isha": 11,
    }
    assert adjusted["warnings"] == ["manual_adjustments_applied"]


@pytest.mark.django_db
def test_calculation_throttle_uses_hmac_identity_and_returns_private_429(
    prayer_method_config: PrayerMethodConfig,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    cache.clear()
    monkeypatch.setattr(PrayerCalculationThrottle, "get_rate", lambda _self: "1/minute")
    request = APIRequestFactory().post(
        reverse("prayer_times:calculate"),
        _calculation_payload(prayer_method_config),
        format="json",
        REMOTE_ADDR="203.0.113.27",
    )
    key = PrayerCalculationThrottle().get_cache_key(request, object())
    assert "203.0.113.27" not in key
    assert re.fullmatch(r"throttle_prayer_calculate_[0-9a-f]{64}", key)

    client = APIClient(REMOTE_ADDR="203.0.113.27")
    first = client.post(
        reverse("prayer_times:calculate"),
        _calculation_payload(prayer_method_config),
        format="json",
    )
    limited = client.post(
        reverse("prayer_times:calculate"),
        _calculation_payload(prayer_method_config),
        format="json",
    )

    assert first.status_code == 200
    assert limited.status_code == 429
    _assert_private_no_store(limited)
    assert limited.json()["code"] == "prayer_calculation_rate_limited"
    assert int(limited.headers["Retry-After"]) >= 1
    cache.clear()


def test_openapi_declares_public_prayer_contract_cache_headers_and_anonymous_security() -> None:
    schema = cast(
        dict[str, Any],
        SchemaGenerator().get_schema(public=True),  # type: ignore[no-untyped-call]
    )

    methods = schema["paths"]["/api/v1/prayer/methods"]["get"]
    calculate = schema["paths"]["/api/v1/prayer/calculate"]["post"]
    assert methods["security"] == [{}]
    assert calculate["security"] == [{}]
    assert set(methods["responses"]["200"]["headers"]) == {"ETag", "Cache-Control"}
    assert set(methods["responses"]["304"]["headers"]) == {"ETag", "Cache-Control"}
    assert "content" not in methods["responses"]["304"]
    assert set(calculate["responses"]) == {"200", "400", "404", "409", "410", "422", "429"}
    request_schema = schema["components"]["schemas"]["PrayerCalculationRequestRequest"]
    assert set(request_schema["required"]) >= {
        "date",
        "timezone",
        "location",
        "method_config_id",
    }
    location_schema = schema["components"]["schemas"]["PrayerLocationInputRequest"]
    assert set(location_schema["required"]) == {"latitude", "longitude"}
    assert location_schema["properties"]["latitude"]["format"] == "decimal"
    assert location_schema["properties"]["longitude"]["format"] == "decimal"
