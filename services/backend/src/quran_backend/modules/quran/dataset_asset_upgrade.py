from __future__ import annotations

import hashlib
import json
import re
import tempfile
from pathlib import Path
from typing import Any

from quran_backend.modules.quran.importer import (
    DATASET_SCHEMA_FILES,
    ValidatedQuranDataset,
    validate_quran_dataset,
)
from quran_backend.modules.quran.mushaf_publication import PreparedMushafCatalog

VERSION_PATTERN = re.compile(r"[A-Za-z0-9]+(?:[A-Za-z0-9._-]*[A-Za-z0-9])?\Z")


class QuranDatasetAssetUpgradeError(ValueError):
    pass


def upgrade_quran_dataset_assets(
    source: ValidatedQuranDataset,
    catalog: PreparedMushafCatalog,
    *,
    output: Path,
    version_value: str,
) -> ValidatedQuranDataset:
    """Create a new complete dataset with upgraded immutable page renditions."""

    output = _validate_request(source, catalog, output, version_value)
    upgraded_pages = _upgrade_pages(source, catalog)
    _write_upgraded_dataset(
        source,
        catalog,
        output=output,
        version_value=version_value,
        upgraded_pages=upgraded_pages,
    )
    return validate_quran_dataset(output)


def _validate_request(
    source: ValidatedQuranDataset,
    catalog: PreparedMushafCatalog,
    output: Path,
    version_value: str,
) -> Path:
    if not VERSION_PATTERN.fullmatch(version_value) or len(version_value) > 64:
        raise QuranDatasetAssetUpgradeError("The target Quran content version is invalid.")
    resolved_output = output.resolve()
    if resolved_output.exists():
        raise QuranDatasetAssetUpgradeError("The target dataset directory already exists.")

    edition = source.manifest["edition"]
    edition_code = str(edition["code"])
    catalog_code = str(catalog.edition_metadata.get("code", "")).strip()
    if catalog_code and catalog_code != edition_code:
        raise QuranDatasetAssetUpgradeError("The page assets belong to a different Quran edition.")
    if catalog.logical_page_count != len(source.pages):
        raise QuranDatasetAssetUpgradeError(
            "The page assets do not cover the complete source dataset."
        )
    return resolved_output


def _upgrade_pages(
    source: ValidatedQuranDataset,
    catalog: PreparedMushafCatalog,
) -> list[dict[str, Any]]:
    catalog_pages = {page.number: page for page in catalog.pages}
    if len(catalog_pages) != len(source.pages):
        raise QuranDatasetAssetUpgradeError("The page asset catalog contains duplicate pages.")

    upgraded_pages: list[dict[str, Any]] = []
    expected_widths: tuple[int, ...] | None = None
    for source_page in source.pages:
        number = int(source_page["number"])
        prepared = catalog_pages.get(number)
        if prepared is None:
            raise QuranDatasetAssetUpgradeError(f"Page {number} has no prepared renditions.")
        variants = [dict(variant) for variant in prepared.asset_variants]
        variants.sort(key=lambda variant: int(str(variant["width"])))
        widths = tuple(int(str(variant["width"])) for variant in variants)
        if not widths or len(widths) != len(set(widths)):
            raise QuranDatasetAssetUpgradeError(
                f"Page {number} contains duplicate or missing rendition widths."
            )
        if expected_widths is None:
            expected_widths = widths
        elif widths != expected_widths:
            raise QuranDatasetAssetUpgradeError(
                "Every page must publish the same rendition widths."
            )

        image_width = int(source_page["image_width"])
        image_height = int(source_page["image_height"])
        canonical = next(
            (
                variant
                for variant in variants
                if int(str(variant["width"])) == image_width
                and int(str(variant["height"])) == image_height
            ),
            None,
        )
        if canonical is None:
            raise QuranDatasetAssetUpgradeError(
                f"Page {number} is missing its registered geometry rendition "
                f"{image_width}x{image_height}."
            )
        source_ratio = image_height / image_width
        if any(
            abs(int(str(variant["height"])) / int(str(variant["width"])) - source_ratio) > 0.001
            for variant in variants
        ):
            raise QuranDatasetAssetUpgradeError(f"Page {number} contains a distorted rendition.")

        upgraded = dict(source_page)
        upgraded["checksum_sha256"] = canonical["sha256"]
        upgraded["assets"] = variants
        upgraded_pages.append(upgraded)
    return upgraded_pages


def _write_upgraded_dataset(
    source: ValidatedQuranDataset,
    catalog: PreparedMushafCatalog,
    *,
    output: Path,
    version_value: str,
    upgraded_pages: list[dict[str, Any]],
) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        dir=output.parent,
        prefix=f".{output.name}.staging-",
    ) as temporary_value:
        staging = Path(temporary_value) / "dataset"
        staging.mkdir()
        schema_version = int(source.manifest["schema_version"])
        filenames = DATASET_SCHEMA_FILES[schema_version]
        file_hashes: dict[str, str] = {}
        for filename in filenames:
            payload = (
                _jsonl_bytes(upgraded_pages)
                if filename == "pages.jsonl"
                else (source.root / filename).read_bytes()
            )
            (staging / filename).write_bytes(payload)
            file_hashes[filename] = hashlib.sha256(payload).hexdigest()

        manifest = json.loads(json.dumps(source.manifest))
        manifest["edition"]["version"] = version_value
        suffix = f"+assets-{catalog.checksum_sha256[:16]}"
        manifest["source_version"] = (
            f"{str(manifest['source_version'])[: 128 - len(suffix)]}{suffix}"
        )
        manifest["files"] = file_hashes
        manifest["content_sha256"] = _aggregate_checksum(file_hashes, filenames)
        asset_source = manifest.setdefault("sources", {}).setdefault("assets", {})
        asset_source["manifest_sha256"] = catalog.checksum_sha256
        asset_source["variant_widths"] = [
            int(asset["width"]) for asset in upgraded_pages[0]["assets"]
        ]
        asset_source["registered_dimensions"] = [
            int(source.pages[0]["image_width"]),
            int(source.pages[0]["image_height"]),
        ]
        verification = manifest.setdefault("verification", {})
        verification["semantic_source_content_sha256"] = source.aggregate_checksum
        verification["page_asset_variants"] = sum(len(page["assets"]) for page in upgraded_pages)
        (staging / "manifest.json").write_bytes(_json_bytes(manifest))

        validate_quran_dataset(staging)
        staging.replace(output)


def _aggregate_checksum(file_hashes: dict[str, str], filenames: tuple[str, ...]) -> str:
    canonical = "".join(f"{name}:{file_hashes[name]}\n" for name in sorted(filenames))
    return hashlib.sha256(canonical.encode()).hexdigest()


def _json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n").encode()


def _jsonl_bytes(rows: list[dict[str, Any]]) -> bytes:
    return b"".join(_json_bytes(row) for row in rows)
