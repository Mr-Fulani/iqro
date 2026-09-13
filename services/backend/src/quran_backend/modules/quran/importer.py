from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path
from typing import Any

from django.core.exceptions import ValidationError
from django.db import transaction

from quran_backend.modules.quran.models import (
    Ayah,
    AyahPageMapping,
    AyahPageRegion,
    Hizb,
    Juz,
    MushafPage,
    QuranEdition,
    QuranEditionVersion,
    RubElHizb,
    SourceManifest,
    Surah,
)
from quran_backend.modules.quran.region_audit import (
    QuranRegionAuditError,
    QuranRegionAuditReport,
    audit_quran_regions,
)

DATASET_SCHEMA_FILES = {
    1: ("surahs.json", "ayahs.jsonl", "pages.jsonl", "juz.json"),
    2: (
        "surahs.json",
        "ayahs.jsonl",
        "pages.jsonl",
        "juz.json",
        "hizb.json",
        "rub-el-hizb.json",
    ),
}
MAX_JSON_FILE_BYTES = 10 * 1024 * 1024
MAX_JSONL_FILE_BYTES = 250 * 1024 * 1024


class QuranDatasetError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class ValidatedQuranDataset:
    root: Path
    manifest: dict[str, Any]
    surahs: list[dict[str, Any]]
    ayahs: list[dict[str, Any]]
    pages: list[dict[str, Any]]
    juz: list[dict[str, Any]]
    hizb: list[dict[str, Any]]
    rub_el_hizb: list[dict[str, Any]]
    region_audit: QuranRegionAuditReport
    aggregate_checksum: str


@dataclass(frozen=True, slots=True)
class ImportResult:
    edition: QuranEdition
    version: QuranEditionVersion
    created: bool


def validate_quran_dataset(root: Path) -> ValidatedQuranDataset:
    root = root.resolve(strict=True)
    if not root.is_dir():
        raise QuranDatasetError("Dataset path must be a directory.")

    manifest = _require_mapping(
        _load_json(root, "manifest.json", MAX_JSON_FILE_BYTES),
        "manifest",
    )
    schema_version = manifest.get("schema_version")
    if schema_version not in DATASET_SCHEMA_FILES:
        supported = ", ".join(str(value) for value in sorted(DATASET_SCHEMA_FILES))
        raise QuranDatasetError(f"Unsupported schema_version; expected one of: {supported}.")

    file_hashes = _require_mapping(manifest.get("files"), "manifest.files")
    for filename in DATASET_SCHEMA_FILES[schema_version]:
        expected_checksum = str(file_hashes.get(filename, ""))
        _require_sha256(expected_checksum, f"manifest.files.{filename}")
        actual_checksum = _sha256_file(_safe_dataset_file(root, filename))
        if actual_checksum != expected_checksum:
            raise QuranDatasetError(f"Checksum mismatch for {filename}.")

    aggregate_checksum = _aggregate_checksum(file_hashes, DATASET_SCHEMA_FILES[schema_version])
    expected_aggregate = str(manifest.get("content_sha256", ""))
    _require_sha256(expected_aggregate, "manifest.content_sha256")
    if aggregate_checksum != expected_aggregate:
        raise QuranDatasetError("Aggregate content checksum mismatch.")

    surahs = _load_json(root, "surahs.json", MAX_JSON_FILE_BYTES)
    juz = _load_json(root, "juz.json", MAX_JSON_FILE_BYTES)
    hizb = _load_json(root, "hizb.json", MAX_JSON_FILE_BYTES) if schema_version >= 2 else []
    rub_el_hizb = (
        _load_json(root, "rub-el-hizb.json", MAX_JSON_FILE_BYTES) if schema_version >= 2 else []
    )
    ayahs = _load_json_lines(root, "ayahs.jsonl", MAX_JSONL_FILE_BYTES)
    pages = _load_json_lines(root, "pages.jsonl", MAX_JSONL_FILE_BYTES)
    for value, label in (
        (surahs, "surahs"),
        (juz, "juz"),
        (hizb, "hizb"),
        (rub_el_hizb, "rub_el_hizb"),
    ):
        if not isinstance(value, list):
            raise QuranDatasetError(f"{label} must be a JSON array.")

    _validate_manifest_metadata(manifest)
    _validate_content(
        manifest,
        {
            "surahs": surahs,
            "ayahs": ayahs,
            "pages": pages,
            "juz": juz,
            "hizb": hizb,
            "rub_el_hizb": rub_el_hizb,
        },
    )
    try:
        region_audit = audit_quran_regions(pages=pages, ayahs=ayahs)
    except QuranRegionAuditError as exc:
        raise QuranDatasetError(str(exc)) from exc
    return ValidatedQuranDataset(
        root=root,
        manifest=manifest,
        surahs=surahs,
        ayahs=ayahs,
        pages=pages,
        juz=juz,
        hizb=hizb,
        rub_el_hizb=rub_el_hizb,
        region_audit=region_audit,
        aggregate_checksum=aggregate_checksum,
    )


@transaction.atomic
def import_quran_dataset(dataset: ValidatedQuranDataset) -> ImportResult:
    edition_data = dataset.manifest["edition"]
    counts = dataset.manifest["counts"]
    edition, edition_created = QuranEdition.objects.get_or_create(
        code=edition_data["code"],
        defaults={
            "name_ar": edition_data["name_ar"],
            "name_en": edition_data["name_en"],
            "name_ru": edition_data["name_ru"],
            "riwayah": edition_data["riwayah"],
            "source_name": edition_data["source_name"],
            "source_url": edition_data.get("source_url", ""),
            "license_name": edition_data["license_name"],
            "license_url": edition_data.get("license_url", ""),
        },
    )
    if not edition_created:
        _verify_existing_edition(edition, edition_data)

    version_value = str(edition_data["version"])
    existing_version = QuranEditionVersion.objects.filter(
        edition=edition,
        version=version_value,
    ).first()
    if existing_version:
        if existing_version.checksum_sha256 != dataset.aggregate_checksum:
            raise QuranDatasetError("The edition version exists with a different checksum.")
        return ImportResult(edition=edition, version=existing_version, created=False)

    version = QuranEditionVersion.objects.create(
        edition=edition,
        version=version_value,
        checksum_sha256=dataset.aggregate_checksum,
        page_count=counts["pages"],
        surah_count=counts["surahs"],
        juz_count=counts["juz"],
        hizb_count=counts.get("hizb", 0),
        rub_el_hizb_count=counts.get("rub_el_hizb", 0),
    )
    surah_by_number = _create_surahs(version, dataset.surahs)
    ayah_by_key = _create_ayahs(surah_by_number, dataset.ayahs)
    _create_pages(version, ayah_by_key, dataset.pages)
    _create_juz(version, ayah_by_key, dataset.juz)
    hizb_by_number = _create_hizb(version, ayah_by_key, dataset.hizb)
    _create_rub_el_hizb(version, ayah_by_key, hizb_by_number, dataset.rub_el_hizb)
    SourceManifest.objects.create(
        edition_version=version,
        source_version=str(dataset.manifest["source_version"]),
        checksum_sha256=dataset.aggregate_checksum,
        expected_surahs=counts["surahs"],
        expected_ayahs=counts["ayahs"],
        expected_pages=counts["pages"],
        payload=dataset.manifest,
    )
    return ImportResult(edition=edition, version=version, created=True)


def _create_surahs(
    version: QuranEditionVersion,
    rows: list[dict[str, Any]],
) -> dict[int, Surah]:
    objects = [
        Surah(
            edition_version=version,
            number=row["number"],
            name_ar=row["name_ar"],
            name_en=row["name_en"],
            name_ru=row["name_ru"],
            revelation_type=row["revelation_type"],
            ayah_count=row["ayah_count"],
        )
        for row in rows
    ]
    Surah.objects.bulk_create(objects)
    return {surah.number: surah for surah in objects}


def _create_ayahs(
    surah_by_number: dict[int, Surah],
    rows: list[dict[str, Any]],
) -> dict[tuple[int, int], Ayah]:
    objects = [
        Ayah(
            surah=surah_by_number[row["surah"]],
            number=row["number"],
            text_uthmani=row["text_uthmani"],
            text_search=row.get("text_search", ""),
            juz_number=row["juz"],
            hizb_number=row.get("hizb"),
            rub_el_hizb_number=row.get("rub_el_hizb"),
        )
        for row in rows
    ]
    Ayah.objects.bulk_create(objects, batch_size=1_000)
    return {(ayah.surah.number, ayah.number): ayah for ayah in objects}


def _create_pages(
    version: QuranEditionVersion,
    ayah_by_key: dict[tuple[int, int], Ayah],
    rows: list[dict[str, Any]],
) -> None:
    pages: list[MushafPage] = []
    for row in rows:
        page = MushafPage(
            edition_version=version,
            number=row["number"],
            image_width=row["image_width"],
            image_height=row["image_height"],
            checksum_sha256=row["checksum_sha256"],
            asset_variants=row["assets"],
        )
        page.full_clean(exclude={"edition_version"})
        pages.append(page)
    MushafPage.objects.bulk_create(pages, batch_size=200)
    page_by_number = {page.number: page for page in pages}

    regions: list[AyahPageRegion] = []
    for row in rows:
        page = page_by_number[row["number"]]
        for region_data in row["regions"]:
            ayah = ayah_by_key[(region_data["surah"], region_data["ayah"])]
            region = AyahPageRegion(
                page=page,
                ayah=ayah,
                reading_order=region_data["reading_order"],
                polygon=region_data["polygon"],
                x=Decimal(str(region_data["x"])),
                y=Decimal(str(region_data["y"])),
                width=Decimal(str(region_data["width"])),
                height=Decimal(str(region_data["height"])),
            )
            try:
                region.full_clean(exclude={"page", "ayah"})
            except ValidationError as exc:
                details = getattr(exc, "message_dict", None) or exc.messages
                raise QuranDatasetError(f"Invalid region on page {page.number}: {details}") from exc
            regions.append(region)
    AyahPageRegion.objects.bulk_create(regions, batch_size=1_000)
    AyahPageMapping.objects.bulk_create(
        [
            AyahPageMapping(page_id=page_id, ayah_id=ayah_id)
            for page_id, ayah_id in {(region.page_id, region.ayah_id) for region in regions}
        ],
        batch_size=1_000,
    )


def _create_juz(
    version: QuranEditionVersion,
    ayah_by_key: dict[tuple[int, int], Ayah],
    rows: list[dict[str, Any]],
) -> None:
    objects = [
        Juz(
            edition_version=version,
            number=row["number"],
            start_ayah=ayah_by_key[(row["start"]["surah"], row["start"]["ayah"])],
            end_ayah=ayah_by_key[(row["end"]["surah"], row["end"]["ayah"])],
        )
        for row in rows
    ]
    Juz.objects.bulk_create(objects)


def _create_hizb(
    version: QuranEditionVersion,
    ayah_by_key: dict[tuple[int, int], Ayah],
    rows: list[dict[str, Any]],
) -> dict[int, Hizb]:
    objects = [
        Hizb(
            edition_version=version,
            number=row["number"],
            start_ayah=ayah_by_key[(row["start"]["surah"], row["start"]["ayah"])],
            end_ayah=ayah_by_key[(row["end"]["surah"], row["end"]["ayah"])],
        )
        for row in rows
    ]
    Hizb.objects.bulk_create(objects)
    return {hizb.number: hizb for hizb in objects}


def _create_rub_el_hizb(
    version: QuranEditionVersion,
    ayah_by_key: dict[tuple[int, int], Ayah],
    hizb_by_number: dict[int, Hizb],
    rows: list[dict[str, Any]],
) -> None:
    objects = [
        RubElHizb(
            edition_version=version,
            hizb=hizb_by_number[(row["number"] - 1) // 4 + 1],
            number=row["number"],
            start_ayah=ayah_by_key[(row["start"]["surah"], row["start"]["ayah"])],
            end_ayah=ayah_by_key[(row["end"]["surah"], row["end"]["ayah"])],
        )
        for row in rows
    ]
    RubElHizb.objects.bulk_create(objects)


def _validate_manifest_metadata(manifest: dict[str, Any]) -> None:
    edition = _require_mapping(manifest.get("edition"), "manifest.edition")
    counts = _require_mapping(manifest.get("counts"), "manifest.counts")
    required_edition_fields = {
        "code",
        "version",
        "name_ar",
        "name_en",
        "name_ru",
        "riwayah",
        "source_name",
        "license_name",
    }
    missing = sorted(required_edition_fields - set(edition))
    if missing:
        raise QuranDatasetError(f"Missing edition fields: {', '.join(missing)}.")
    required_counts = ["surahs", "ayahs", "pages", "juz"]
    if manifest["schema_version"] >= 2:
        required_counts.extend(("hizb", "rub_el_hizb"))
    for field in required_counts:
        if not isinstance(counts.get(field), int) or counts[field] <= 0:
            raise QuranDatasetError(f"manifest.counts.{field} must be a positive integer.")
    if not str(manifest.get("source_version", "")).strip():
        raise QuranDatasetError("manifest.source_version is required.")


def _validate_content(
    manifest: dict[str, Any],
    sections: dict[str, list[dict[str, Any]]],
) -> None:
    counts = _require_mapping(manifest["counts"], "manifest.counts")
    surahs = sections["surahs"]
    ayahs = sections["ayahs"]
    pages = sections["pages"]
    juz = sections["juz"]
    hizb = sections["hizb"]
    rub_el_hizb = sections["rub_el_hizb"]
    _validate_declared_counts(counts, sections)
    _require_number_sequence(surahs, int(counts["surahs"]), "surahs")
    _require_number_sequence(pages, int(counts["pages"]), "pages")
    _require_number_sequence(juz, int(counts["juz"]), "juz")
    if manifest["schema_version"] >= 2:
        _require_number_sequence(hizb, int(counts["hizb"]), "hizb")
        _require_number_sequence(
            rub_el_hizb,
            int(counts["rub_el_hizb"]),
            "rub_el_hizb",
        )
    ayah_keys, surah_counts = _collect_ayah_keys(
        ayahs,
        int(counts["juz"]),
        hizb_count=int(counts["hizb"]) if manifest["schema_version"] >= 2 else None,
        rub_el_hizb_count=(int(counts["rub_el_hizb"]) if manifest["schema_version"] >= 2 else None),
    )
    _validate_surah_ayah_counts(surahs, ayah_keys, surah_counts)
    _validate_page_mappings(pages, ayah_keys)
    _validate_division_boundaries(juz, ayahs, ayah_keys, field="juz", label="Juz")
    if manifest["schema_version"] >= 2:
        _validate_division_boundaries(hizb, ayahs, ayah_keys, field="hizb", label="Hizb")
        _validate_division_boundaries(
            rub_el_hizb,
            ayahs,
            ayah_keys,
            field="rub_el_hizb",
            label="Rub el Hizb",
        )


def _validate_declared_counts(
    counts: dict[str, Any],
    sections: dict[str, list[dict[str, Any]]],
) -> None:
    actual_counts = {label: len(rows) for label, rows in sections.items()}
    for label, expected in counts.items():
        if label in actual_counts and actual_counts[label] != expected:
            raise QuranDatasetError(
                f"Count mismatch for {label}: expected {expected}, got {actual_counts[label]}."
            )


def _collect_ayah_keys(
    ayahs: list[dict[str, Any]],
    juz_count: int,
    *,
    hizb_count: int | None,
    rub_el_hizb_count: int | None,
) -> tuple[set[tuple[int, int]], dict[int, int]]:
    surah_counts: dict[int, int] = {}
    ayah_keys: set[tuple[int, int]] = set()
    for row in ayahs:
        key = (int(row.get("surah", 0)), int(row.get("number", 0)))
        if key in ayah_keys:
            raise QuranDatasetError(f"Duplicate ayah reference {key[0]}:{key[1]}.")
        if not str(row.get("text_uthmani", "")).strip():
            raise QuranDatasetError(f"Ayah {key[0]}:{key[1]} has empty Uthmani text.")
        if not 1 <= int(row.get("juz", 0)) <= juz_count:
            raise QuranDatasetError(f"Ayah {key[0]}:{key[1]} has an invalid juz number.")
        if hizb_count is not None and not 1 <= int(row.get("hizb", 0)) <= hizb_count:
            raise QuranDatasetError(f"Ayah {key[0]}:{key[1]} has an invalid hizb number.")
        if rub_el_hizb_count is not None:
            rub_number = int(row.get("rub_el_hizb", 0))
            if not 1 <= rub_number <= rub_el_hizb_count:
                raise QuranDatasetError(
                    f"Ayah {key[0]}:{key[1]} has an invalid rub el hizb number."
                )
            if int(row["hizb"]) != (rub_number - 1) // 4 + 1:
                raise QuranDatasetError(
                    f"Ayah {key[0]}:{key[1]} has inconsistent hizb and rub el hizb numbers."
                )
        ayah_keys.add(key)
        surah_counts[key[0]] = surah_counts.get(key[0], 0) + 1
    return ayah_keys, surah_counts


def _validate_surah_ayah_counts(
    surahs: list[dict[str, Any]],
    ayah_keys: set[tuple[int, int]],
    surah_counts: dict[int, int],
) -> None:
    for surah in surahs:
        number = int(surah["number"])
        expected = int(surah.get("ayah_count", 0))
        if surah_counts.get(number, 0) != expected:
            raise QuranDatasetError(f"Ayah count mismatch for surah {number}.")
        expected_numbers = {(number, ayah_number) for ayah_number in range(1, expected + 1)}
        if not expected_numbers.issubset(ayah_keys):
            raise QuranDatasetError(f"Ayah numbering is not continuous for surah {number}.")


def _validate_page_mappings(
    pages: list[dict[str, Any]],
    ayah_keys: set[tuple[int, int]],
) -> None:
    covered_ayahs: set[tuple[int, int]] = set()
    for page in pages:
        if not isinstance(page.get("assets"), list) or not page["assets"]:
            raise QuranDatasetError(f"Page {page.get('number')} has no assets.")
        if not isinstance(page.get("regions"), list):
            raise QuranDatasetError(f"Page {page.get('number')} has invalid regions.")
        region_geometries: set[tuple[tuple[int, int], str]] = set()
        for region in page["regions"]:
            key = (int(region.get("surah", 0)), int(region.get("ayah", 0)))
            if key not in ayah_keys:
                raise QuranDatasetError(
                    f"Page {page['number']} references unknown ayah {key[0]}:{key[1]}."
                )
            geometry = json.dumps(
                region.get("polygon"),
                ensure_ascii=True,
                separators=(",", ":"),
            )
            geometry_key = (key, geometry)
            if geometry_key in region_geometries:
                raise QuranDatasetError(
                    f"Page {page['number']} repeats polygon geometry for ayah {key[0]}:{key[1]}."
                )
            region_geometries.add(geometry_key)
            covered_ayahs.add(key)
    if covered_ayahs != ayah_keys:
        missing = sorted(ayah_keys - covered_ayahs)[0]
        raise QuranDatasetError(f"Ayah {missing[0]}:{missing[1]} is not mapped to a page.")


def _validate_division_boundaries(
    divisions: list[dict[str, Any]],
    ayahs: list[dict[str, Any]],
    ayah_keys: set[tuple[int, int]],
    *,
    field: str,
    label: str,
) -> None:
    for row in divisions:
        for boundary in ("start", "end"):
            value = row.get(boundary, {})
            key = (int(value.get("surah", 0)), int(value.get("ayah", 0)))
            if key not in ayah_keys:
                raise QuranDatasetError(f"{label} {row['number']} has an invalid {boundary} ayah.")
        members = [ayah for ayah in ayahs if int(ayah[field]) == int(row["number"])]
        if not members:
            raise QuranDatasetError(f"{label} {row['number']} is empty.")
        expected_start = (int(members[0]["surah"]), int(members[0]["number"]))
        expected_end = (int(members[-1]["surah"]), int(members[-1]["number"]))
        actual_start = (int(row["start"]["surah"]), int(row["start"]["ayah"]))
        actual_end = (int(row["end"]["surah"]), int(row["end"]["ayah"]))
        if actual_start != expected_start or actual_end != expected_end:
            raise QuranDatasetError(f"{label} {row['number']} boundaries do not match ayahs.")


def _verify_existing_edition(edition: QuranEdition, data: dict[str, Any]) -> None:
    immutable_fields = ("riwayah", "source_name", "license_name")
    mismatches = [field for field in immutable_fields if getattr(edition, field) != data[field]]
    if mismatches:
        raise QuranDatasetError(
            f"Edition metadata conflicts with existing data: {', '.join(mismatches)}."
        )


def _load_json(root: Path, filename: str, max_bytes: int) -> Any:
    path = _safe_dataset_file(root, filename)
    _require_file_size(path, max_bytes)
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise QuranDatasetError(f"Cannot read valid JSON from {filename}: {exc}.") from exc


def _load_json_lines(root: Path, filename: str, max_bytes: int) -> list[dict[str, Any]]:
    path = _safe_dataset_file(root, filename)
    _require_file_size(path, max_bytes)
    rows: list[dict[str, Any]] = []
    try:
        with path.open(encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, start=1):
                if not line.strip():
                    continue
                value = json.loads(line)
                if not isinstance(value, dict):
                    raise QuranDatasetError(f"{filename}:{line_number} must contain an object.")
                rows.append(value)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise QuranDatasetError(f"Cannot read valid JSONL from {filename}: {exc}.") from exc
    return rows


def _safe_dataset_file(root: Path, filename: str) -> Path:
    path = (root / filename).resolve(strict=True)
    if not path.is_relative_to(root) or not path.is_file():
        raise QuranDatasetError(f"Invalid dataset file: {filename}.")
    return path


def _require_file_size(path: Path, max_bytes: int) -> None:
    size = path.stat().st_size
    if size <= 0 or size > max_bytes:
        raise QuranDatasetError(f"Invalid file size for {path.name}: {size} bytes.")


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _aggregate_checksum(file_hashes: dict[str, Any], required_files: tuple[str, ...]) -> str:
    canonical = "".join(f"{name}:{file_hashes[name]}\n" for name in sorted(required_files))
    return hashlib.sha256(canonical.encode()).hexdigest()


def _require_mapping(value: object, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise QuranDatasetError(f"{label} must be a JSON object.")
    return value


def _require_sha256(value: str, label: str) -> None:
    if len(value) != 64 or any(character not in "0123456789abcdef" for character in value):
        raise QuranDatasetError(f"{label} must be a lowercase SHA-256 checksum.")


def _require_number_sequence(rows: list[dict[str, Any]], count: int, label: str) -> None:
    numbers = [row.get("number") for row in rows]
    expected = list(range(1, count + 1))
    if numbers != expected:
        raise QuranDatasetError(f"{label} numbers must be continuous and ordered from 1.")
