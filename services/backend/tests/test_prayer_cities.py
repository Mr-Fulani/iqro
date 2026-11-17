# The fixtures quote place names in Cyrillic and Arabic.
# ruff: noqa: E501, RUF001
from __future__ import annotations

import gzip
import re
from importlib import import_module
from pathlib import Path

import pytest
from django.apps import apps
from django.core.cache import cache
from django.core.management import CommandError, call_command
from django.urls import reverse
from rest_framework.test import APIClient

from quran_backend.modules.prayer_times.cities import (
    CITY_SEARCH_LIMIT,
    DEFAULT_CITIES_FILE,
    PrayerCitiesFileError,
    import_prayer_cities,
    normalize_city_name,
    search_prayer_cities,
)
from quran_backend.modules.prayer_times.models import PrayerCity
from quran_backend.modules.prayer_times.throttling import PrayerCitySearchThrottle

HEADER = (
    "geoname_id\tname\tname_local\tname_ru\tname_ar\tname_tr\tcountry_code"
    "\tlatitude\tlongitude\ttimezone\tpopulation"
)
ROWS = (
    "104515\tMecca\tMakkah\tМекка\tمكة المكرمة\tMekke\tSA\t21.42664\t39.82563\tAsia/Riyadh\t1578722",
    "551487\tKazan’\tKazan\tКазань\tقازان\tKazan\tRU\t55.78874\t49.12214\tEurope/Moscow\t1243500",
    "5128581\tNew York City\t\tНью-Йорк\tنيويورك\tNew York\tUS\t40.71427\t-74.00597\tAmerica/New_York\t8804190",
    "750269\tBursa\t\tБурса\tبورصة\t\tTR\t40.19559\t29.06013\tEurope/Istanbul\t3101833",
    "1526273\tAstana\t\tАстана\t\t\tKZ\t51.1801\t71.44598\tAsia/Almaty\t1078362",
    "5371965\tMecca\t\t\t\t\tUS\t33.57219\t-116.0782\tAmerica/Los_Angeles\t8577",
)


def _write(path: Path, *rows: str, header: str = HEADER) -> Path:
    with gzip.open(path, "wt", encoding="utf-8") as lines:
        lines.write("\n".join((header, *rows)) + "\n")
    return path


@pytest.fixture
def cities(db: None, tmp_path: Path) -> None:
    import_prayer_cities(_write(tmp_path / "cities.tsv.gz", *ROWS))


@pytest.mark.parametrize(
    ("typed", "stored"),
    [
        ("  Нью-Йорк ", "нью иорк"),
        ("Ёлка", "елка"),
        ("Kazan’", "kazan"),
        ("São  Paulo", "sao paulo"),
        ("مَكَّة", "مكة"),
        ("أبو ظبي", "ابو ظبي"),
        ("İSTANBUL", "istanbul"),
    ],
)
def test_names_and_queries_share_one_spelling(typed: str, stored: str) -> None:
    assert normalize_city_name(typed) == stored


def test_import_replaces_the_places_with_the_files(db: None, tmp_path: Path) -> None:
    assert import_prayer_cities(_write(tmp_path / "first.tsv.gz", *ROWS)) == len(ROWS)
    kazan = PrayerCity.objects.get(geoname_id=551487)
    assert (kazan.name, kazan.name_ru, kazan.search_local) == ("Kazan’", "Казань", "kazan")
    assert (str(kazan.latitude), str(kazan.longitude), kazan.timezone) == (
        "55.78874",
        "49.12214",
        "Europe/Moscow",
    )

    changed = ROWS[1].replace("1243500", "1300000")
    assert import_prayer_cities(_write(tmp_path / "second.tsv.gz", ROWS[0], changed)) == 2
    assert set(PrayerCity.objects.values_list("geoname_id", flat=True)) == {104515, 551487}
    assert PrayerCity.objects.get(geoname_id=551487).population == 1_300_000


@pytest.mark.parametrize(
    ("rows", "header"),
    [
        ((), HEADER),
        (ROWS[:1], HEADER.replace("name_local\t", "")),
        (("1\tOnly a name",), HEADER),
        ((ROWS[0].replace("21.42664", "north"),), HEADER),
    ],
)
def test_import_refuses_a_broken_file_and_keeps_the_places(
    cities: None,
    tmp_path: Path,
    rows: tuple[str, ...],
    header: str,
) -> None:
    with pytest.raises(PrayerCitiesFileError):
        import_prayer_cities(_write(tmp_path / "broken.tsv.gz", *rows, header=header))
    with pytest.raises(PrayerCitiesFileError):
        import_prayer_cities(tmp_path / "missing.tsv.gz")
    assert PrayerCity.objects.count() == len(ROWS)


def test_the_command_loads_a_file_and_reports_a_broken_one(db: None, tmp_path: Path) -> None:
    call_command("import_prayer_cities", str(_write(tmp_path / "cities.tsv.gz", *ROWS)))
    assert PrayerCity.objects.count() == len(ROWS)
    with pytest.raises(CommandError):
        call_command("import_prayer_cities", str(tmp_path / "missing.tsv.gz"))


@pytest.mark.parametrize(
    ("query", "locale", "names"),
    [
        ("каз", "ru", ["Казань"]),
        ("Kaz", "en", ["Kazan’"]),
        ("makk", "en", ["Mecca"]),
        ("مكة", "ar", ["مكة المكرمة"]),
        ("нью йо", "ru", ["Нью-Йорк"]),
        ("burs", "tr", ["Bursa"]),
        ("аст", "ar", ["Astana"]),
        ("mec", "en", ["Mecca", "Mecca"]),
        ("zz", "en", []),
        ("к", "ru", []),
    ],
)
def test_search_matches_the_start_of_a_name_in_any_language(
    cities: None,
    query: str,
    locale: str,
    names: list[str],
) -> None:
    assert [city.name for city in search_prayer_cities(query, locale)] == names


def test_search_puts_larger_places_first_and_stops_at_the_limit(db: None, tmp_path: Path) -> None:
    rows = [
        f"{number}\tSpringfield {number}\t\t\t\t\tUS\t40.0\t-90.0\tAmerica/Chicago\t{number * 10}"
        for number in range(1, CITY_SEARCH_LIMIT + 6)
    ]
    import_prayer_cities(_write(tmp_path / "cities.tsv.gz", *rows))
    found = search_prayer_cities("spring", "en")
    assert len(found) == CITY_SEARCH_LIMIT
    assert [city.population for city in found] == sorted(
        (city.population for city in found), reverse=True
    )
    assert found[0].geoname_id == CITY_SEARCH_LIMIT + 5


def test_city_search_api_returns_public_places(cities: None) -> None:
    response = APIClient().get(reverse("prayer_times:cities"), {"q": "Каз", "locale": "ru"})
    assert response.status_code == 200
    assert response.json() == {
        "results": [
            {
                "id": 551487,
                "name": "Казань",
                "country_code": "RU",
                "latitude": "55.78874",
                "longitude": "49.12214",
                "timezone": "Europe/Moscow",
            }
        ]
    }
    assert response["Cache-Control"].startswith("public")
    assert "Set-Cookie" not in response


@pytest.mark.parametrize(
    "params",
    [{}, {"q": "к"}, {"q": "x" * 81}, {"q": "kaz", "locale": "de"}, {"q": "kaz", "page": "2"}],
)
def test_city_search_api_rejects_a_bad_query(cities: None, params: dict[str, str]) -> None:
    assert APIClient().get(reverse("prayer_times:cities"), params).status_code == 400


def test_city_search_throttle_hashes_the_address(cities: None, settings: object) -> None:
    cache.clear()
    keys: list[str] = []
    original = PrayerCitySearchThrottle.get_cache_key

    def remember(self: PrayerCitySearchThrottle, request: object, view: object) -> str:
        key = original(self, request, view)  # type: ignore[arg-type]
        keys.append(key)
        return key

    PrayerCitySearchThrottle.get_cache_key = remember  # type: ignore[method-assign]
    PrayerCitySearchThrottle.THROTTLE_RATES = {"prayer_city_search": "1/minute"}
    try:
        client = APIClient()
        url = reverse("prayer_times:cities")
        assert client.get(url, {"q": "kaz"}, REMOTE_ADDR="203.0.113.7").status_code == 200
        limited = client.get(url, {"q": "kaz"}, REMOTE_ADDR="203.0.113.7")
    finally:
        PrayerCitySearchThrottle.get_cache_key = original  # type: ignore[method-assign]
        del PrayerCitySearchThrottle.THROTTLE_RATES
        cache.clear()
    assert limited.status_code == 429
    assert limited.json()["code"] == "prayer_city_search_rate_limited"
    assert re.fullmatch(r"throttle_prayer_city_search_[0-9a-f]{64}", keys[0])
    assert "203.0.113.7" not in keys[0]


def test_the_bundled_file_holds_the_world_with_local_names() -> None:
    with gzip.open(DEFAULT_CITIES_FILE, "rt", encoding="utf-8") as lines:
        assert next(lines).rstrip("\n") == HEADER
        places = {fields[0]: fields for fields in (line.rstrip("\n").split("\t") for line in lines)}
    assert len(places) > 150_000
    assert places["104515"][1:6] == ["Mecca", "Makkah", "Мекка", "مكة المكرمة", "Mekke"]
    assert places["551487"][3] == "Казань"
    assert all(len(fields) == 11 and fields[9] for fields in places.values())


def test_the_migration_loads_the_bundled_places_outside_tests(db: None, settings: object) -> None:
    migration = import_module(
        "quran_backend.modules.prayer_times.migrations.0005_load_prayer_cities"
    )
    migration.load_prayer_cities(apps, None)
    assert PrayerCity.objects.count() == 0

    settings.QURAN_PRAYER_CITIES_IMPORT_ON_MIGRATE = True  # type: ignore[attr-defined]
    migration.load_prayer_cities(apps, None)
    assert PrayerCity.objects.count() > 150_000
    assert [city.name for city in search_prayer_cities("Наманг", "ru")][:1] == ["Наманган"]
    assert PrayerCity.objects.get(geoname_id=104515).timezone == "Asia/Riyadh"
