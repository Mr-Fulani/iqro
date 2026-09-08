from __future__ import annotations

import json
from datetime import date
from pathlib import Path

import pytest
from django.contrib import admin
from django.core.exceptions import ValidationError
from django.test import RequestFactory
from rest_framework.test import APIClient

from quran_backend.modules.calendar import models as calendar_models
from quran_backend.modules.calendar.calculation import (
    MAX_YEAR,
    MIN_YEAR,
    civil_date,
    hijri_date,
    month_length,
)
from quran_backend.modules.calendar.models import CalendarEvent
from quran_backend.modules.calendar.services import catalog, matches


def test_mobile_table_known_dates_and_every_month_roundtrip() -> None:
    assert hijri_date(date(2018, 11, 12)) == (1440, 3, 4)
    assert civil_date(MIN_YEAR, 1, 1) == date(1937, 3, 14)
    assert civil_date(MAX_YEAR, 12, 30) == date(2077, 11, 16)
    for year in range(MIN_YEAR, MAX_YEAR + 1):
        for month in range(1, 13):
            for day in (1, month_length(year, month)):
                for adjustment in (-2, 0, 2):
                    assert hijri_date(civil_date(year, month, day, adjustment), adjustment) == (
                        year,
                        month,
                        day,
                    )


@pytest.mark.parametrize(
    ("year", "month", "day", "offset"),
    [
        (1355, 1, 1, 0),
        (1501, 1, 1, 0),
        (1448, 0, 1, 0),
        (1448, 13, 1, 0),
        (1448, 1, 31, 0),
        (1448, 1, 1, 3),
    ],
)
def test_invalid_dates_rejected(year: int, month: int, day: int, offset: int) -> None:
    with pytest.raises(ValueError, match=r"Invalid|outside"):
        civil_date(year, month, day, offset)
    with pytest.raises(ValueError, match="outside"):
        hijri_date(date(1900, 1, 1))


@pytest.mark.django_db
def test_seed_is_identical_to_bundled_mobile_catalog_and_has_sources() -> None:
    seed = Path(calendar_models.__file__).parent / "data/events-v1.json"
    bundled = json.loads(seed.read_text())
    assert catalog() == bundled
    # Monorepo parity when available; standalone backend Docker tests still
    # verify the exact same seed/API contract without requiring a Flutter tree.
    root = next((p for p in seed.parents if (p / "clients/iqro_mobile").is_dir()), None)
    if root is not None:
        assert (
            json.loads((root / "clients/iqro_mobile/assets/calendar/events-v1.json").read_text())
            == bundled
        )
    assert len(catalog()["events"]) == 8
    for event in CalendarEvent.objects.all():
        event.full_clean()


@pytest.mark.django_db
def test_public_catalog_drafts_updates_and_etag(api_client: APIClient) -> None:
    first = api_client.get("/api/v1/calendar/catalog")
    assert first.status_code == 200
    assert "public" in first["Cache-Control"]
    assert (
        api_client.get("/api/v1/calendar/catalog", HTTP_IF_NONE_MATCH=first["ETag"]).status_code
        == 304
    )
    item = CalendarEvent.objects.get(code="arafah")
    item.title_ru = "Updated from admin"
    item.save()
    second = api_client.get("/api/v1/calendar/catalog", HTTP_IF_NONE_MATCH=first["ETag"])
    assert second.status_code == 200
    assert second.data["version"] != first.data["version"]
    item.is_published = False
    item.save()
    assert "arafah" not in [
        e["code"] for e in api_client.get("/api/v1/calendar/catalog").data["events"]
    ]
    assert api_client.post("/api/v1/calendar/catalog", {}, format="json").status_code == 405


@pytest.mark.django_db
def test_month_contract_and_religious_safety(api_client: APIClient) -> None:
    response = api_client.get("/api/v1/calendar/month?year=1448&month=12&adjustment=1")
    assert response.status_code == 200
    assert response.data["days"][12]["events"] == ["tashriq"]
    assert response.data["days"][13]["events"] == ["white_days"]
    assert response.data["days"][0]["civil_date"] == civil_date(1448, 12, 1, 1).isoformat()
    converted = api_client.get("/api/v1/calendar/month?date=2018-11-12").data
    assert (converted["year"], converted["month"], converted["selected_day"]) == (1440, 3, 4)
    white = next(e for e in catalog()["events"] if e["code"] == "white_days")
    for day in (13, 14, 15):
        assert not matches(white, 9, day)
    blanket = {**white, "day_start": 1, "day_end": 30}
    assert not matches(blanket, 10, 1)
    for day in range(10, 14):
        assert not matches(blanket, 12, day)


@pytest.mark.django_db
@pytest.mark.parametrize(
    "query",
    [
        "",
        "year=1448",
        "date=1900-01-01",
        "date=bad",
        "date=2026-09-08&year=1448",
        "year=1448&month=13",
        "year=1448&month=1&adjustment=3",
    ],
)
def test_bad_month_queries(api_client: APIClient, query: str) -> None:
    assert api_client.get(f"/api/v1/calendar/month?{query}").status_code == 400


@pytest.mark.django_db
def test_admin_validation_prevents_incomplete_or_unsafe_publication() -> None:
    item = CalendarEvent(code="draft", day_start=10, day_end=9)
    with pytest.raises(ValidationError, match="day_end"):
        item.full_clean()
    item.day_end = 10
    item.is_published = True
    with pytest.raises(ValidationError, match="title_ru"):
        item.full_clean()
    item.is_published = False
    item.source_url = "https://user:password@example.org/reference"
    with pytest.raises(ValidationError, match="source_url"):
        item.full_clean()


@pytest.mark.django_db
def test_admin_creates_identity_and_publishes_without_technical_input() -> None:
    model_admin = admin.site._registry[CalendarEvent]
    form_type = model_admin.get_form(RequestFactory().get("/admin/calendar/calendarevent/add/"))
    assert "code" not in form_type.base_fields
    data = {
        "kind": "occasion",
        "month": 9,
        "day_start": 1,
        "day_end": 1,
        "sort_order": 100,
        "source_label": "Quran 2:185",
        "source_url": "https://quran.com/2/185",
        "is_published": True,
        **{f"title_{locale}": "Ramadan" for locale in ("ru", "en", "ar", "tr")},
        **{f"description_{locale}": "Reference checked" for locale in ("ru", "en", "ar", "tr")},
    }
    form = form_type(data=data)
    assert form.is_valid(), form.errors
    item = form.save()
    assert item.code.startswith("event_")
    assert item.code in {event["code"] for event in catalog()["events"]}
