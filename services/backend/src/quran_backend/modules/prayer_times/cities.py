from __future__ import annotations

import gzip
import unicodedata
from collections.abc import Iterator
from decimal import Decimal
from itertools import batched
from pathlib import Path

from django.db import transaction
from django.db.models import Q

from quran_backend.modules.prayer_times.models import PrayerCity

DEFAULT_CITIES_FILE = Path(__file__).resolve().parent / "data" / "prayer_cities_v1.tsv.gz"
CITY_LOCALES = ("en", "ru", "ar", "tr")
CITY_SEARCH_MIN_LENGTH = 2
CITY_SEARCH_MAX_LENGTH = 80
CITY_SEARCH_LIMIT = 20
_IMPORT_BATCH = 2000
# Hyphens, dashes and apostrophes of every kind separate words like a space.
_NAME_SEPARATORS = "-\u2010\u2011\u2013\u2014'\u2019\u02bb\u02bc`"
_COLUMNS = (
    "geoname_id",
    "name",
    "name_local",
    "name_ru",
    "name_ar",
    "name_tr",
    "country_code",
    "latitude",
    "longitude",
    "timezone",
    "population",
)
_UPDATED_FIELDS = (
    "name",
    "name_ru",
    "name_ar",
    "name_tr",
    "search_name",
    "search_local",
    "search_ru",
    "search_ar",
    "search_tr",
    "country_code",
    "latitude",
    "longitude",
    "timezone",
    "population",
)


class PrayerCitiesFileError(ValueError):
    pass


def normalize_city_name(value: str) -> str:
    """One spelling for a stored name and a typed query.

    Case, accents and Arabic vowel marks go, and «ё», «й» or «أ» fall back to their
    base letters; hyphens and apostrophes become spaces, so «нью йорк» finds «Нью-Йорк».
    """
    decomposed = unicodedata.normalize("NFKD", value.casefold())
    letters = "".join(
        " " if character in _NAME_SEPARATORS else character
        for character in decomposed
        if not unicodedata.combining(character)
    )
    return " ".join(letters.split())


def search_prayer_cities(query: str, locale: str) -> list[PrayerCity]:
    """Places whose name in any of the four languages starts with the query, largest first."""
    prefix = normalize_city_name(query)
    if len(prefix) < CITY_SEARCH_MIN_LENGTH:
        return []
    matches = (
        Q(search_name__startswith=prefix)
        | Q(search_local__startswith=prefix)
        | Q(search_ru__startswith=prefix)
        | Q(search_ar__startswith=prefix)
        | Q(search_tr__startswith=prefix)
    )
    cities = list(
        PrayerCity.objects.filter(matches).order_by("-population", "geoname_id")[:CITY_SEARCH_LIMIT]
    )
    for city in cities:
        city.name = city_name(city, locale)
    return cities


def city_name(city: PrayerCity, locale: str) -> str:
    """The place's name in the locale, else the main one."""
    localized = {"ru": city.name_ru, "ar": city.name_ar, "tr": city.name_tr}.get(locale, "")
    return localized or city.name


def _read_cities(path: Path, model: type[PrayerCity]) -> Iterator[PrayerCity]:
    """The file's places one by one, so a small server never holds them all at once."""
    try:
        with gzip.open(path, "rt", encoding="utf-8") as lines:
            header = next(lines, "").rstrip("\n").split("\t")
            if tuple(header) != _COLUMNS:
                raise PrayerCitiesFileError(f"Unexpected columns in {path.name}.")
            for number, line in enumerate(lines, start=2):
                fields = line.rstrip("\n").split("\t")
                if len(fields) != len(_COLUMNS):
                    raise PrayerCitiesFileError(f"Line {number} of {path.name} is malformed.")
                row = dict(zip(_COLUMNS, fields, strict=True))
                yield model(
                    geoname_id=int(row["geoname_id"]),
                    name=row["name"],
                    name_ru=row["name_ru"],
                    name_ar=row["name_ar"],
                    name_tr=row["name_tr"],
                    search_name=normalize_city_name(row["name"]),
                    search_local=normalize_city_name(row["name_local"]),
                    search_ru=normalize_city_name(row["name_ru"]),
                    search_ar=normalize_city_name(row["name_ar"]),
                    search_tr=normalize_city_name(row["name_tr"]),
                    country_code=row["country_code"],
                    latitude=Decimal(row["latitude"]),
                    longitude=Decimal(row["longitude"]),
                    timezone=row["timezone"],
                    population=int(row["population"]),
                )
    except (OSError, ArithmeticError, ValueError) as error:
        if isinstance(error, PrayerCitiesFileError):
            raise
        raise PrayerCitiesFileError(f"Cannot read {path.name}: {error}") from error


@transaction.atomic
def import_prayer_cities(
    path: Path = DEFAULT_CITIES_FILE,
    model: type[PrayerCity] = PrayerCity,
) -> int:
    """Replace the places with the file's: new and changed rows are written, the rest go.

    A broken file changes nothing. ``model`` is the historical model inside a migration.
    """
    kept: set[int] = set()
    for batch in batched(_read_cities(path, model), _IMPORT_BATCH, strict=False):
        model.objects.bulk_create(
            batch,
            update_conflicts=True,
            unique_fields=("geoname_id",),
            update_fields=_UPDATED_FIELDS,
        )
        kept.update(city.geoname_id for city in batch)
    if not kept:
        raise PrayerCitiesFileError(f"{path.name} holds no places.")
    stale = [
        geoname_id
        for geoname_id in model.objects.values_list("geoname_id", flat=True)
        if geoname_id not in kept
    ]
    for ids in batched(stale, _IMPORT_BATCH, strict=False):
        model.objects.filter(geoname_id__in=ids).delete()
    return len(kept)
