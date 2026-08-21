from __future__ import annotations

# ruff: noqa: RUF001 -- Russian surah names intentionally use Cyrillic characters.
import hashlib
import json
import re
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Any

EXPECTED_CORPUS_SHA256 = "8b06e904890d9b918a470381c61c0a02bea70dcd595c56b6407c839483750de3"
EXPECTED_POLYGON_SET_SHA256 = "1278aa23076974174a59b577284ae757b12efac90124fb8241229f77486294cd"
EXPECTED_SURAH_COUNT = 114
EXPECTED_AYAH_COUNT = 6_236
EXPECTED_PAGE_COUNT = 604
EXPECTED_JUZ_COUNT = 30
DATASET_VERSION = "1.0.1"

# quranpedia/quran-svg native coordinates were registered against the pinned PDF raster.
# The KFQC page art is centered on the PDF page with the same scale on both axes.
REGISTERED_PAGE_SCALE = 2.337
STANDARD_VIEWBOX = (345.0, 550.0)
OPENING_VIEWBOX = (235.0, 235.0)
NUMBER_PATTERN = re.compile(r"-?\d+(?:\.\d+)?")

RUSSIAN_SURAH_NAMES = (
    "Аль-Фатиха",
    "Аль-Бакара",
    "Аль Имран",
    "Ан-Ниса",
    "Аль-Маида",
    "Аль-Анам",
    "Аль-Араф",
    "Аль-Анфаль",
    "Ат-Тауба",
    "Юнус",
    "Худ",
    "Юсуф",
    "Ар-Рад",
    "Ибрахим",
    "Аль-Хиджр",
    "Ан-Нахль",
    "Аль-Исра",
    "Аль-Кахф",
    "Марьям",
    "Та Ха",
    "Аль-Анбия",
    "Аль-Хадж",
    "Аль-Муминун",
    "Ан-Нур",
    "Аль-Фуркан",
    "Аш-Шуара",
    "Ан-Намль",
    "Аль-Касас",
    "Аль-Анкабут",
    "Ар-Рум",
    "Лукман",
    "Ас-Саджда",
    "Аль-Ахзаб",
    "Саба",
    "Фатыр",
    "Йа Син",
    "Ас-Саффат",
    "Сад",
    "Аз-Зумар",
    "Гафир",
    "Фуссылат",
    "Аш-Шура",
    "Аз-Зухруф",
    "Ад-Духан",
    "Аль-Джасия",
    "Аль-Ахкаф",
    "Мухаммад",
    "Аль-Фатх",
    "Аль-Худжурат",
    "Каф",
    "Аз-Зарият",
    "Ат-Тур",
    "Ан-Наджм",
    "Аль-Камар",
    "Ар-Рахман",
    "Аль-Вакиа",
    "Аль-Хадид",
    "Аль-Муджадиля",
    "Аль-Хашр",
    "Аль-Мумтахана",
    "Ас-Сафф",
    "Аль-Джумуа",
    "Аль-Мунафикун",
    "Ат-Тагабун",
    "Ат-Талак",
    "Ат-Тахрим",
    "Аль-Мульк",
    "Аль-Калам",
    "Аль-Хакка",
    "Аль-Мааридж",
    "Нух",
    "Аль-Джинн",
    "Аль-Муззаммиль",
    "Аль-Муддассир",
    "Аль-Кияма",
    "Аль-Инсан",
    "Аль-Мурсалят",
    "Ан-Наба",
    "Ан-Назиат",
    "Абаса",
    "Ат-Таквир",
    "Аль-Инфитар",
    "Аль-Мутаффифин",
    "Аль-Иншикак",
    "Аль-Бурудж",
    "Ат-Тарик",
    "Аль-Аля",
    "Аль-Гашия",
    "Аль-Фаджр",
    "Аль-Балад",
    "Аш-Шамс",
    "Аль-Лайл",
    "Ад-Духа",
    "Аш-Шарх",
    "Ат-Тин",
    "Аль-Алак",
    "Аль-Кадр",
    "Аль-Баййина",
    "Аз-Зальзаля",
    "Аль-Адият",
    "Аль-Кариа",
    "Ат-Такасур",
    "Аль-Аср",
    "Аль-Хумаза",
    "Аль-Филь",
    "Курайш",
    "Аль-Маун",
    "Аль-Каусар",
    "Аль-Кафирун",
    "Ан-Наср",
    "Аль-Масад",
    "Аль-Ихлас",
    "Аль-Фаляк",
    "Ан-Нас",
)


class QuranDatasetBuildError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class BuildResult:
    output: Path
    content_sha256: str
    page_mapping_differences: int


def build_madani_hafs_dataset(  # noqa: PLR0915
    *,
    corpus_path: Path,
    polygons_dir: Path,
    asset_manifest_path: Path,
    output: Path,
) -> BuildResult:
    corpus_path = corpus_path.resolve(strict=True)
    polygons_dir = polygons_dir.resolve(strict=True)
    asset_manifest_path = asset_manifest_path.resolve(strict=True)
    _require_sha256(corpus_path, EXPECTED_CORPUS_SHA256, "Quran corpus")
    _require_polygon_set(polygons_dir)

    corpus = _load_mapping(corpus_path)
    asset_manifest = _load_mapping(asset_manifest_path)
    surahs_source = corpus.get("surahs")
    assets_source = asset_manifest.get("assets")
    if not isinstance(surahs_source, list) or not isinstance(assets_source, list):
        raise QuranDatasetBuildError("Source corpus or asset manifest has an invalid shape.")

    source_ayahs: dict[tuple[int, int], dict[str, Any]] = {}
    surahs: list[dict[str, Any]] = []
    ayahs: list[dict[str, Any]] = []
    for source_surah in surahs_source:
        number = int(source_surah["number"])
        source_surah_ayahs = source_surah["ayahs"]
        surahs.append(
            {
                "number": number,
                "name_ar": source_surah["name_arabic"],
                "name_en": source_surah["name_transliteration"],
                "name_ru": RUSSIAN_SURAH_NAMES[number - 1],
                "revelation_type": str(source_surah["revelation"]["type"]).lower(),
                "ayah_count": len(source_surah_ayahs),
            }
        )
        for source_ayah in source_surah_ayahs:
            ayah_number = int(source_ayah["number"])
            key = (number, ayah_number)
            source_ayahs[key] = source_ayah
            text = str(source_ayah["text"])
            ayahs.append(
                {
                    "surah": number,
                    "number": ayah_number,
                    "text_uthmani": text,
                    "text_search": _search_text(text),
                    "juz": int(source_ayah["juz"]),
                }
            )

    assets_by_page = _prepare_assets(assets_source, asset_manifest_path.parent)
    pages: list[dict[str, Any]] = []
    polygon_keys: set[tuple[int, int]] = set()
    page_mapping_differences = 0
    for page_number in range(1, EXPECTED_PAGE_COUNT + 1):
        page_asset = assets_by_page[page_number]
        image_width = int(page_asset["width"])
        image_height = int(page_asset["height"])
        source_regions = json.loads(
            (polygons_dir / f"{page_number:03}.json").read_text(encoding="utf-8")
        )
        regions: list[dict[str, Any]] = []
        reading_order = 0
        for source_region in source_regions:
            key = (int(source_region["surahNumber"]), int(source_region["ayahNumber"]))
            if key in polygon_keys:
                raise QuranDatasetBuildError(f"Duplicate polygon for ayah {key[0]}:{key[1]}.")
            if key not in source_ayahs:
                raise QuranDatasetBuildError(f"Polygon references unknown ayah {key[0]}:{key[1]}.")
            polygon_keys.add(key)
            if int(source_ayahs[key]["page"]) != page_number:
                page_mapping_differences += 1
            for points in _parse_polygons(str(source_region["polygon"])):
                reading_order += 1
                normalized = _normalize_polygon(
                    points,
                    page_number=page_number,
                    image_width=image_width,
                    image_height=image_height,
                )
                xs = [point[0] for point in normalized]
                ys = [point[1] for point in normalized]
                x_min, x_max = min(xs), max(xs)
                y_min, y_max = min(ys), max(ys)
                regions.append(
                    {
                        "surah": key[0],
                        "ayah": key[1],
                        "reading_order": reading_order,
                        "polygon": normalized,
                        "x": round(x_min, 7),
                        "y": round(y_min, 7),
                        "width": round(x_max - x_min, 7),
                        "height": round(y_max - y_min, 7),
                    }
                )
        pages.append(
            {
                "number": page_number,
                "image_width": image_width,
                "image_height": image_height,
                "checksum_sha256": page_asset["sha256"],
                "assets": [page_asset],
                "regions": regions,
            }
        )

    ayah_keys = set(source_ayahs)
    if polygon_keys != ayah_keys:
        missing = sorted(ayah_keys - polygon_keys)
        extra = sorted(polygon_keys - ayah_keys)
        raise QuranDatasetBuildError(
            f"Polygon coverage mismatch: missing={missing[:1]}, extra={extra[:1]}."
        )
    _require_counts(surahs, ayahs, pages)
    juz = _build_juz(ayahs)

    output.mkdir(parents=True, exist_ok=True)
    payloads = {
        "surahs.json": _json_bytes(surahs),
        "ayahs.jsonl": _jsonl_bytes(ayahs),
        "pages.jsonl": _jsonl_bytes(pages),
        "juz.json": _json_bytes(juz),
    }
    file_hashes: dict[str, str] = {}
    for filename, payload in payloads.items():
        (output / filename).write_bytes(payload)
        file_hashes[filename] = hashlib.sha256(payload).hexdigest()
    canonical = "".join(f"{name}:{file_hashes[name]}\n" for name in sorted(file_hashes))
    content_sha256 = hashlib.sha256(canonical.encode()).hexdigest()
    manifest = {
        "schema_version": 1,
        "source_version": (
            "tanzil-mirror-c0dc86b060b854d03f62848692bf1d2936dba630+"
            "quran-svg-5fbcb1d4d92b5a2972ab51472fe991b6066bb6e2"
        ),
        "content_sha256": content_sha256,
        "edition": {
            "code": "madani-hafs",
            "version": DATASET_VERSION,
            "name_ar": "مصحف المدينة",
            "name_en": "Madani Mushaf",
            "name_ru": "Мединский мусхаф",
            "riwayah": "Hafs 'an Asim",
            "source_name": "Tanzil + quranpedia/quran-svg + pinned KFQC PDF",
            "source_url": "https://tanzil.net/download/",
            "license_name": "Tanzil CC BY 3.0; regions CC0 1.0; KFQC digital-use terms",
            "license_url": "https://tanzil.net/docs/Text_License",
        },
        "counts": {
            "surahs": len(surahs),
            "ayahs": len(ayahs),
            "pages": len(pages),
            "juz": len(juz),
        },
        "files": file_hashes,
        "sources": {
            "corpus": {
                "repository": "https://github.com/mjmirza/quran-dataset",
                "commit": "c0dc86b060b854d03f62848692bf1d2936dba630",
                "sha256": EXPECTED_CORPUS_SHA256,
                "upstream": "https://tanzil.net",
                "license": "CC BY 3.0",
            },
            "regions": {
                "repository": "https://github.com/quranpedia/quran-svg",
                "commit": "5fbcb1d4d92b5a2972ab51472fe991b6066bb6e2",
                "aggregate_sha256": EXPECTED_POLYGON_SET_SHA256,
                "license": "CC0 1.0",
            },
            "assets": {
                "manifest_sha256": _sha256_file(asset_manifest_path),
                "registered_scale": REGISTERED_PAGE_SCALE,
            },
        },
        "verification": {
            "ayah_polygon_coverage": len(polygon_keys),
            "region_segments": sum(len(page["regions"]) for page in pages),
            "corpus_page_mapping_differences": page_mapping_differences,
            "page_assignment_authority": "KFQC polygon geometry",
        },
    }
    (output / "manifest.json").write_bytes(_json_bytes(manifest))
    return BuildResult(output, content_sha256, page_mapping_differences)


def _prepare_assets(
    assets: list[dict[str, Any]],
    asset_root: Path,
) -> dict[int, dict[str, Any]]:
    result: dict[int, dict[str, Any]] = {}
    for source in assets:
        page_number = int(source["logical_page"])
        dimensions = source["dimensions"]
        relative_path = Path(str(source["path"]))
        asset_path = (asset_root / relative_path).resolve(strict=True)
        if not asset_path.is_relative_to(asset_root.resolve()):
            raise QuranDatasetBuildError("Asset path escapes its manifest directory.")
        _require_sha256(asset_path, str(source["sha256"]), f"Page {page_number} asset")
        result[page_number] = {
            "format": source["format"],
            "width": int(dimensions["width"]),
            "height": int(dimensions["height"]),
            "path": f"quran/madani-hafs/1.0.0/{relative_path.as_posix()}",
            "sha256": source["sha256"],
            "bytes": int(source["bytes"]),
        }
    if set(result) != set(range(1, EXPECTED_PAGE_COUNT + 1)):
        raise QuranDatasetBuildError("Asset manifest must cover pages 1-604 exactly.")
    return result


def _parse_polygons(value: str) -> list[list[tuple[float, float]]]:
    # KFQC path data uses one closed M…Z subpath per visual line. Keeping those
    # subpaths separate prevents SVG from drawing diagonal bridges between lines.
    parts = re.findall(r"M\s*(.*?)(?=\s*M\s*|$)", value, flags=re.IGNORECASE)
    coordinate_sets = parts or [value]
    polygons: list[list[tuple[float, float]]] = []
    for coordinates in coordinate_sets:
        numbers = [float(number) for number in NUMBER_PATTERN.findall(coordinates)]
        if len(numbers) < 6 or len(numbers) % 2:
            raise QuranDatasetBuildError("Polygon contains invalid coordinates.")
        polygons.append(list(zip(numbers[::2], numbers[1::2], strict=True)))
    return polygons


def _normalize_polygon(
    points: list[tuple[float, float]],
    *,
    page_number: int,
    image_width: int,
    image_height: int,
) -> list[list[float]]:
    viewbox_width, viewbox_height = OPENING_VIEWBOX if page_number <= 2 else STANDARD_VIEWBOX
    offset_x = (image_width - viewbox_width * REGISTERED_PAGE_SCALE) / 2
    offset_y = (image_height - viewbox_height * REGISTERED_PAGE_SCALE) / 2
    normalized: list[list[float]] = []
    for x, y in points:
        nx = (offset_x + x * REGISTERED_PAGE_SCALE) / image_width
        ny = (offset_y + y * REGISTERED_PAGE_SCALE) / image_height
        if not 0 <= nx <= 1 or not 0 <= ny <= 1:
            raise QuranDatasetBuildError(
                f"Page {page_number} polygon coordinate is outside the registered image."
            )
        normalized.append([round(nx, 7), round(ny, 7)])
    return normalized


def _build_juz(ayahs: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for number in range(1, EXPECTED_JUZ_COUNT + 1):
        members = [ayah for ayah in ayahs if ayah["juz"] == number]
        if not members:
            raise QuranDatasetBuildError(f"Juz {number} is empty.")
        first, last = members[0], members[-1]
        result.append(
            {
                "number": number,
                "start": {"surah": first["surah"], "ayah": first["number"]},
                "end": {"surah": last["surah"], "ayah": last["number"]},
            }
        )
    return result


def _search_text(text: str) -> str:
    decomposed = unicodedata.normalize("NFKD", text.replace("ـ", ""))
    return "".join(character for character in decomposed if unicodedata.category(character) != "Mn")


def _require_counts(
    surahs: list[dict[str, Any]],
    ayahs: list[dict[str, Any]],
    pages: list[dict[str, Any]],
) -> None:
    actual = (len(surahs), len(ayahs), len(pages), len(RUSSIAN_SURAH_NAMES))
    expected = (
        EXPECTED_SURAH_COUNT,
        EXPECTED_AYAH_COUNT,
        EXPECTED_PAGE_COUNT,
        EXPECTED_SURAH_COUNT,
    )
    if actual != expected:
        raise QuranDatasetBuildError(
            f"Canonical count mismatch: expected {expected}, got {actual}."
        )


def _require_polygon_set(polygons_dir: Path) -> None:
    canonical = ""
    for page_number in range(1, EXPECTED_PAGE_COUNT + 1):
        path = polygons_dir / f"{page_number:03}.json"
        canonical += f"{path.name}:{_sha256_file(path)}\n"
    actual = hashlib.sha256(canonical.encode()).hexdigest()
    if actual != EXPECTED_POLYGON_SET_SHA256:
        raise QuranDatasetBuildError(
            "Polygon source checksum mismatch: "
            f"expected {EXPECTED_POLYGON_SET_SHA256}, got {actual}."
        )


def _require_sha256(path: Path, expected: str, label: str) -> None:
    actual = _sha256_file(path)
    if actual != expected:
        raise QuranDatasetBuildError(
            f"{label} checksum mismatch: expected {expected}, got {actual}."
        )


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _load_mapping(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise QuranDatasetBuildError(f"{path.name} must contain a JSON object.")
    return value


def _json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n").encode()


def _jsonl_bytes(rows: list[dict[str, Any]]) -> bytes:
    return b"".join(_json_bytes(row) for row in rows)
