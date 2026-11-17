"""Build prayer_cities_v1.tsv.gz from the GeoNames dumps.

The prayer-times city search serves places from one compact file kept in the repository,
so no request leaves our servers when a visitor looks a city up. This script makes that
file from two GeoNames downloads (https://download.geonames.org/export/dump/, CC BY 4.0):

    python scripts/build_prayer_cities.py cities1000.zip alternateNamesV2.zip

``cities1000.zip`` holds every populated place above 1000 inhabitants and the seats of
administrative divisions; ``alternateNamesV2.zip`` holds their names by language. Each
place keeps its GeoNames name and, where GeoNames has one, its preferred English name
and its Russian, Arabic and Turkish names. Rerun it to refresh the data, then run
``manage.py import_prayer_cities``.
"""

from __future__ import annotations

import gzip
import io
import sys
import zipfile
from pathlib import Path

LANGUAGES = ("en", "ru", "ar", "tr")
OUTPUT = (
    Path(__file__).resolve().parents[1]
    / "src/quran_backend/modules/prayer_times/data/prayer_cities_v1.tsv.gz"
)
COLUMNS = (
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


def read_cities(path: Path) -> dict[int, dict[str, str]]:
    cities: dict[int, dict[str, str]] = {}
    with zipfile.ZipFile(path) as archive, archive.open("cities1000.txt") as raw:
        for line in io.TextIOWrapper(raw, encoding="utf-8"):
            fields = line.rstrip("\n").split("\t")
            cities[int(fields[0])] = {
                "name": fields[1],
                "country_code": fields[8],
                "latitude": fields[4],
                "longitude": fields[5],
                "timezone": fields[17],
                "population": fields[14] or "0",
            }
    return cities


def read_names(path: Path, wanted: set[int]) -> dict[int, dict[str, str]]:
    """The best name of each wanted place per language: preferred, then short, then first.

    English counts only when GeoNames marks it preferred: its other English entries are
    often transliterations with apostrophes, worse than the place's main name.
    """
    best: dict[int, dict[str, tuple[int, str]]] = {}
    with zipfile.ZipFile(path) as archive, archive.open("alternateNamesV2.txt") as raw:
        for line in io.TextIOWrapper(raw, encoding="utf-8"):
            fields = line.rstrip("\n").split("\t")
            language = fields[2]
            if language not in LANGUAGES:
                continue
            geoname_id = int(fields[1])
            if geoname_id not in wanted:
                continue
            preferred, short, colloquial, historic = (fields[index] == "1" for index in range(4, 8))
            if colloquial or historic:
                continue
            rank = 0 if preferred else 1 if short else 2
            if language == "en" and rank:
                continue
            current = best.setdefault(geoname_id, {}).get(language)
            if current is None or rank < current[0]:
                best[geoname_id][language] = (rank, fields[3].strip())
    return {
        geoname_id: {language: name for language, (_, name) in names.items()}
        for geoname_id, names in best.items()
    }


def main(cities_zip: str, names_zip: str) -> None:
    cities = read_cities(Path(cities_zip))
    names = read_names(Path(names_zip), set(cities))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    # A fixed mtime and order keep the file identical between runs on the same dumps.
    with (
        OUTPUT.open("wb") as raw,
        gzip.GzipFile(fileobj=raw, mode="wb", mtime=0) as packed,
        io.TextIOWrapper(packed, encoding="utf-8", newline="") as text,
    ):
        # Plain tab-separated lines: GeoNames fields hold neither tabs nor line breaks.
        text.write("\t".join(COLUMNS) + "\n")
        for geoname_id in sorted(cities):
            city = cities[geoname_id]
            local = names.get(geoname_id, {})
            name = local.get("en") or city["name"]
            row = (
                geoname_id,
                name,
                # The GeoNames name stays searchable beside the English one («Makkah»).
                city["name"] if city["name"] != name else "",
                # A name equal to the main one is left out: the import falls back to it.
                *(
                    local.get(language, "") if local.get(language) != name else ""
                    for language in ("ru", "ar", "tr")
                ),
                city["country_code"],
                city["latitude"],
                city["longitude"],
                city["timezone"],
                city["population"],
            )
            text.write("\t".join(str(value) for value in row) + "\n")
    sys.stdout.write(f"{len(cities)} places -> {OUTPUT}\n")


if __name__ == "__main__":
    main(*sys.argv[1:3])
