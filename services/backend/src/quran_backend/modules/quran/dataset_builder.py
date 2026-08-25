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
EXPECTED_HIZB_COUNT = 60
EXPECTED_RUB_EL_HIZB_COUNT = 240
DATASET_VERSION = "1.0.2"

# quranpedia/quran-svg native coordinates were registered against the pinned PDF raster.
# The KFQC page art is centered on the PDF page with the same scale on both axes.
REGISTERED_PAGE_SCALE = 2.337
STANDARD_VIEWBOX = (345.0, 550.0)
OPENING_VIEWBOX = (235.0, 235.0)
NUMBER_PATTERN = re.compile(r"-?\d+(?:\.\d+)?")
EDITION_CODE_PATTERN = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
VERSION_PATTERN = re.compile(r"[A-Za-z0-9]+(?:[A-Za-z0-9._-]*[A-Za-z0-9])?\Z")

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


@dataclass(frozen=True, slots=True)
class QuranDatasetBuildSpec:
    source_version: str
    edition_code: str
    edition_version: str
    asset_version: str
    name_ar: str
    name_en: str
    name_ru: str
    riwayah: str
    source_name: str
    source_url: str
    license_name: str
    license_url: str
    corpus_sha256: str
    polygon_set_sha256: str
    expected_surah_count: int
    expected_ayah_count: int
    expected_page_count: int
    expected_juz_count: int
    expected_hizb_count: int
    expected_rub_el_hizb_count: int
    registered_page_scale: float
    standard_viewbox: tuple[float, float]
    opening_viewbox: tuple[float, float]
    opening_page_count: int
    page_assignment_authority: str
    surah_names_ru: tuple[str, ...]
    sources: dict[str, dict[str, Any]]


def madani_hafs_build_spec() -> QuranDatasetBuildSpec:
    """Return the pinned legacy Hafs profile without weakening its checksum gates."""

    return QuranDatasetBuildSpec(
        source_version=(
            "tanzil-mirror-c0dc86b060b854d03f62848692bf1d2936dba630+"
            "quran-svg-5fbcb1d4d92b5a2972ab51472fe991b6066bb6e2"
        ),
        edition_code="madani-hafs",
        edition_version=DATASET_VERSION,
        asset_version="1.0.0",
        name_ar="مصحف المدينة",
        name_en="Madani Mushaf",
        name_ru="Мединский мусхаф",
        riwayah="Hafs 'an Asim",
        source_name="Tanzil + quranpedia/quran-svg + pinned KFQC PDF",
        source_url="https://tanzil.net/download/",
        license_name="Tanzil CC BY 3.0; regions CC0 1.0; KFQC digital-use terms",
        license_url="https://tanzil.net/docs/Text_License",
        corpus_sha256=EXPECTED_CORPUS_SHA256,
        polygon_set_sha256=EXPECTED_POLYGON_SET_SHA256,
        expected_surah_count=EXPECTED_SURAH_COUNT,
        expected_ayah_count=EXPECTED_AYAH_COUNT,
        expected_page_count=EXPECTED_PAGE_COUNT,
        expected_juz_count=EXPECTED_JUZ_COUNT,
        expected_hizb_count=EXPECTED_HIZB_COUNT,
        expected_rub_el_hizb_count=EXPECTED_RUB_EL_HIZB_COUNT,
        registered_page_scale=REGISTERED_PAGE_SCALE,
        standard_viewbox=STANDARD_VIEWBOX,
        opening_viewbox=OPENING_VIEWBOX,
        opening_page_count=min(2, EXPECTED_PAGE_COUNT),
        page_assignment_authority="KFQC polygon geometry",
        surah_names_ru=RUSSIAN_SURAH_NAMES,
        sources={
            "corpus": {
                "repository": "https://github.com/mjmirza/quran-dataset",
                "commit": "c0dc86b060b854d03f62848692bf1d2936dba630",
                "upstream": "https://tanzil.net",
                "license": "CC BY 3.0",
            },
            "regions": {
                "repository": "https://github.com/quranpedia/quran-svg",
                "commit": "5fbcb1d4d92b5a2972ab51472fe991b6066bb6e2",
                "license": "CC0 1.0",
            },
            "assets": {},
        },
    )


def load_quran_dataset_build_spec(path: Path) -> QuranDatasetBuildSpec:
    """Load a checksummed edition profile used by the generic local builder."""

    payload = _load_mapping(path.resolve(strict=True))
    if payload.get("schema_version") != 1:
        raise QuranDatasetBuildError("Build spec schema_version must be 1.")
    edition = _require_mapping(payload.get("edition"), "build spec edition")
    expected = _require_mapping(payload.get("expected_counts"), "build spec expected_counts")
    geometry = _require_mapping(payload.get("geometry"), "build spec geometry")
    raw_sources = _require_mapping(payload.get("sources"), "build spec sources")
    raw_names = payload.get("surah_names_ru", RUSSIAN_SURAH_NAMES)
    if not isinstance(raw_names, list | tuple) or not all(
        isinstance(name, str) and name.strip() for name in raw_names
    ):
        raise QuranDatasetBuildError("build spec surah_names_ru must contain non-empty names.")
    sources: dict[str, dict[str, Any]] = {}
    for name in ("corpus", "regions", "assets"):
        sources[name] = dict(_require_mapping(raw_sources.get(name), f"build spec sources.{name}"))
    spec = QuranDatasetBuildSpec(
        source_version=_required_string(payload, "source_version", "build spec"),
        edition_code=_required_string(edition, "code", "build spec edition"),
        edition_version=_required_string(edition, "version", "build spec edition"),
        asset_version=_required_string(edition, "asset_version", "build spec edition"),
        name_ar=_required_string(edition, "name_ar", "build spec edition"),
        name_en=_required_string(edition, "name_en", "build spec edition"),
        name_ru=_required_string(edition, "name_ru", "build spec edition"),
        riwayah=_required_string(edition, "riwayah", "build spec edition"),
        source_name=_required_string(edition, "source_name", "build spec edition"),
        source_url=str(edition.get("source_url", "")).strip(),
        license_name=_required_string(edition, "license_name", "build spec edition"),
        license_url=str(edition.get("license_url", "")).strip(),
        corpus_sha256=_required_string(payload, "corpus_sha256", "build spec"),
        polygon_set_sha256=_required_string(payload, "polygon_set_sha256", "build spec"),
        expected_surah_count=_positive_int(expected, "surahs"),
        expected_ayah_count=_positive_int(expected, "ayahs"),
        expected_page_count=_positive_int(expected, "pages"),
        expected_juz_count=_positive_int(expected, "juz"),
        expected_hizb_count=_positive_int(expected, "hizb"),
        expected_rub_el_hizb_count=_positive_int(expected, "rub_el_hizb"),
        registered_page_scale=_positive_float(geometry, "registered_page_scale"),
        standard_viewbox=_viewbox(geometry, "standard_viewbox"),
        opening_viewbox=_viewbox(geometry, "opening_viewbox"),
        opening_page_count=_nonnegative_int(geometry, "opening_page_count"),
        page_assignment_authority=_required_string(
            geometry,
            "page_assignment_authority",
            "build spec geometry",
        ),
        surah_names_ru=tuple(name.strip() for name in raw_names),
        sources=sources,
    )
    _validate_build_spec(spec)
    return spec


def build_madani_hafs_dataset(
    *,
    corpus_path: Path,
    polygons_dir: Path,
    asset_manifest_path: Path,
    output: Path,
) -> BuildResult:
    return build_quran_dataset(
        spec=madani_hafs_build_spec(),
        corpus_path=corpus_path,
        polygons_dir=polygons_dir,
        asset_manifest_path=asset_manifest_path,
        output=output,
    )


def build_quran_dataset(  # noqa: PLR0915
    *,
    spec: QuranDatasetBuildSpec,
    corpus_path: Path,
    polygons_dir: Path,
    asset_manifest_path: Path,
    output: Path,
) -> BuildResult:
    _validate_build_spec(spec)
    corpus_path = corpus_path.resolve(strict=True)
    polygons_dir = polygons_dir.resolve(strict=True)
    asset_manifest_path = asset_manifest_path.resolve(strict=True)
    _require_sha256(corpus_path, spec.corpus_sha256, "Quran corpus")
    _require_polygon_set(
        polygons_dir,
        page_count=spec.expected_page_count,
        expected_sha256=spec.polygon_set_sha256,
    )

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
                "name_ru": spec.surah_names_ru[number - 1],
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
                    "hizb": int(source_ayah["hizb"]),
                    "rub_el_hizb": int(source_ayah["hizb_quarter"]),
                }
            )

    assets_by_page = _prepare_assets(
        assets_source,
        asset_manifest_path.parent,
        edition_code=spec.edition_code,
        asset_version=spec.asset_version,
        page_count=spec.expected_page_count,
    )
    pages: list[dict[str, Any]] = []
    polygon_keys: set[tuple[int, int]] = set()
    page_mapping_differences = 0
    for page_number in range(1, spec.expected_page_count + 1):
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
                    build_spec=spec,
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
    _require_counts(surahs, ayahs, pages, spec=spec)
    juz = _build_divisions(ayahs, field="juz", count=spec.expected_juz_count, label="Juz")
    hizb = _build_divisions(ayahs, field="hizb", count=spec.expected_hizb_count, label="Hizb")
    rub_el_hizb = _build_divisions(
        ayahs,
        field="rub_el_hizb",
        count=spec.expected_rub_el_hizb_count,
        label="Rub el Hizb",
    )

    output.mkdir(parents=True, exist_ok=True)
    payloads = {
        "surahs.json": _json_bytes(surahs),
        "ayahs.jsonl": _jsonl_bytes(ayahs),
        "pages.jsonl": _jsonl_bytes(pages),
        "juz.json": _json_bytes(juz),
        "hizb.json": _json_bytes(hizb),
        "rub-el-hizb.json": _json_bytes(rub_el_hizb),
    }
    file_hashes: dict[str, str] = {}
    for filename, payload in payloads.items():
        (output / filename).write_bytes(payload)
        file_hashes[filename] = hashlib.sha256(payload).hexdigest()
    canonical = "".join(f"{name}:{file_hashes[name]}\n" for name in sorted(file_hashes))
    content_sha256 = hashlib.sha256(canonical.encode()).hexdigest()
    manifest = {
        "schema_version": 2,
        "source_version": spec.source_version,
        "content_sha256": content_sha256,
        "edition": {
            "code": spec.edition_code,
            "version": spec.edition_version,
            "name_ar": spec.name_ar,
            "name_en": spec.name_en,
            "name_ru": spec.name_ru,
            "riwayah": spec.riwayah,
            "source_name": spec.source_name,
            "source_url": spec.source_url,
            "license_name": spec.license_name,
            "license_url": spec.license_url,
        },
        "counts": {
            "surahs": len(surahs),
            "ayahs": len(ayahs),
            "pages": len(pages),
            "juz": len(juz),
            "hizb": len(hizb),
            "rub_el_hizb": len(rub_el_hizb),
        },
        "files": file_hashes,
        "sources": _manifest_sources(spec, asset_manifest_path),
        "verification": {
            "ayah_polygon_coverage": len(polygon_keys),
            "region_segments": sum(len(page["regions"]) for page in pages),
            "hizb_coverage": len({ayah["hizb"] for ayah in ayahs}),
            "rub_el_hizb_coverage": len({ayah["rub_el_hizb"] for ayah in ayahs}),
            "corpus_page_mapping_differences": page_mapping_differences,
            "page_assignment_authority": spec.page_assignment_authority,
        },
    }
    (output / "manifest.json").write_bytes(_json_bytes(manifest))
    return BuildResult(output, content_sha256, page_mapping_differences)


def _prepare_assets(
    assets: list[dict[str, Any]],
    asset_root: Path,
    *,
    edition_code: str,
    asset_version: str,
    page_count: int,
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
            "path": f"quran/{edition_code}/{asset_version}/{relative_path.as_posix()}",
            "sha256": source["sha256"],
            "bytes": int(source["bytes"]),
        }
    if set(result) != set(range(1, page_count + 1)):
        raise QuranDatasetBuildError(f"Asset manifest must cover pages 1-{page_count} exactly.")
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
    build_spec: QuranDatasetBuildSpec | None = None,
) -> list[list[float]]:
    registered_page_scale = (
        build_spec.registered_page_scale if build_spec else REGISTERED_PAGE_SCALE
    )
    standard_viewbox = build_spec.standard_viewbox if build_spec else STANDARD_VIEWBOX
    opening_viewbox = build_spec.opening_viewbox if build_spec else OPENING_VIEWBOX
    opening_page_count = build_spec.opening_page_count if build_spec else 2
    viewbox_width, viewbox_height = (
        opening_viewbox if page_number <= opening_page_count else standard_viewbox
    )
    offset_x = (image_width - viewbox_width * registered_page_scale) / 2
    offset_y = (image_height - viewbox_height * registered_page_scale) / 2
    normalized: list[list[float]] = []
    for x, y in points:
        nx = (offset_x + x * registered_page_scale) / image_width
        ny = (offset_y + y * registered_page_scale) / image_height
        if not 0 <= nx <= 1 or not 0 <= ny <= 1:
            raise QuranDatasetBuildError(
                f"Page {page_number} polygon coordinate is outside the registered image."
            )
        normalized.append([round(nx, 7), round(ny, 7)])
    return normalized


def _build_divisions(
    ayahs: list[dict[str, Any]],
    *,
    field: str,
    count: int,
    label: str,
) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for number in range(1, count + 1):
        members = [ayah for ayah in ayahs if ayah[field] == number]
        if not members:
            raise QuranDatasetBuildError(f"{label} {number} is empty.")
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
    *,
    spec: QuranDatasetBuildSpec,
) -> None:
    actual = (len(surahs), len(ayahs), len(pages), len(spec.surah_names_ru))
    expected = (
        spec.expected_surah_count,
        spec.expected_ayah_count,
        spec.expected_page_count,
        spec.expected_surah_count,
    )
    if actual != expected:
        raise QuranDatasetBuildError(
            f"Canonical count mismatch: expected {expected}, got {actual}."
        )


def _require_polygon_set(
    polygons_dir: Path,
    *,
    page_count: int,
    expected_sha256: str,
) -> None:
    canonical = ""
    for page_number in range(1, page_count + 1):
        path = polygons_dir / f"{page_number:03}.json"
        canonical += f"{path.name}:{_sha256_file(path)}\n"
    actual = hashlib.sha256(canonical.encode()).hexdigest()
    if actual != expected_sha256:
        raise QuranDatasetBuildError(
            f"Polygon source checksum mismatch: expected {expected_sha256}, got {actual}."
        )


def _manifest_sources(
    spec: QuranDatasetBuildSpec,
    asset_manifest_path: Path,
) -> dict[str, dict[str, Any]]:
    sources = {name: dict(details) for name, details in spec.sources.items()}
    sources["corpus"]["sha256"] = spec.corpus_sha256
    sources["regions"]["aggregate_sha256"] = spec.polygon_set_sha256
    sources["assets"]["manifest_sha256"] = _sha256_file(asset_manifest_path)
    sources["assets"]["registered_scale"] = spec.registered_page_scale
    return sources


def _validate_build_spec(spec: QuranDatasetBuildSpec) -> None:
    if not EDITION_CODE_PATTERN.fullmatch(spec.edition_code):
        raise QuranDatasetBuildError("Build spec edition code must be a lowercase ASCII slug.")
    for label, value in (
        ("edition version", spec.edition_version),
        ("asset version", spec.asset_version),
    ):
        if not VERSION_PATTERN.fullmatch(value):
            raise QuranDatasetBuildError(f"Build spec {label} is invalid.")
    for label, value in (
        ("source version", spec.source_version),
        ("Arabic name", spec.name_ar),
        ("English name", spec.name_en),
        ("Russian name", spec.name_ru),
        ("riwayah", spec.riwayah),
        ("source name", spec.source_name),
        ("license name", spec.license_name),
        ("page assignment authority", spec.page_assignment_authority),
    ):
        if not value.strip():
            raise QuranDatasetBuildError(f"Build spec {label} is required.")
    for label, value in (
        ("corpus_sha256", spec.corpus_sha256),
        ("polygon_set_sha256", spec.polygon_set_sha256),
    ):
        if not re.fullmatch(r"[0-9a-f]{64}", value):
            raise QuranDatasetBuildError(f"Build spec {label} must be lowercase SHA-256.")
    counts = (
        spec.expected_surah_count,
        spec.expected_ayah_count,
        spec.expected_page_count,
        spec.expected_juz_count,
        spec.expected_hizb_count,
        spec.expected_rub_el_hizb_count,
    )
    if any(value <= 0 for value in counts):
        raise QuranDatasetBuildError("Build spec counts must be positive integers.")
    if len(spec.surah_names_ru) != spec.expected_surah_count:
        raise QuranDatasetBuildError(
            "Build spec Russian surah names must match the expected surah count."
        )
    if spec.opening_page_count > spec.expected_page_count:
        raise QuranDatasetBuildError("Build spec opening_page_count cannot exceed the page count.")
    if spec.registered_page_scale <= 0 or any(
        value <= 0 for value in (*spec.standard_viewbox, *spec.opening_viewbox)
    ):
        raise QuranDatasetBuildError("Build spec geometry values must be positive.")
    if set(spec.sources) != {"corpus", "regions", "assets"}:
        raise QuranDatasetBuildError("Build spec sources must contain corpus, regions, and assets.")


def _require_mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise QuranDatasetBuildError(f"{label} must be a JSON object.")
    return value


def _required_string(value: dict[str, Any], field: str, label: str) -> str:
    result = value.get(field)
    if not isinstance(result, str) or not result.strip():
        raise QuranDatasetBuildError(f"{label}.{field} must be a non-empty string.")
    return result.strip()


def _positive_int(value: dict[str, Any], field: str) -> int:
    result = value.get(field)
    if not isinstance(result, int) or isinstance(result, bool) or result <= 0:
        raise QuranDatasetBuildError(f"build spec value {field} must be a positive integer.")
    return result


def _nonnegative_int(value: dict[str, Any], field: str) -> int:
    result = value.get(field)
    if not isinstance(result, int) or isinstance(result, bool) or result < 0:
        raise QuranDatasetBuildError(f"build spec value {field} must be a non-negative integer.")
    return result


def _positive_float(value: dict[str, Any], field: str) -> float:
    result = value.get(field)
    if not isinstance(result, int | float) or isinstance(result, bool) or result <= 0:
        raise QuranDatasetBuildError(f"build spec value {field} must be a positive number.")
    return float(result)


def _viewbox(value: dict[str, Any], field: str) -> tuple[float, float]:
    result = value.get(field)
    if (
        not isinstance(result, list)
        or len(result) != 2
        or any(
            not isinstance(item, int | float) or isinstance(item, bool) or item <= 0
            for item in result
        )
    ):
        raise QuranDatasetBuildError(f"build spec value {field} must contain two positive numbers.")
    return float(result[0]), float(result[1])


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
