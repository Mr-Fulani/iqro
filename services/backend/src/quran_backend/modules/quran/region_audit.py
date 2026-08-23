from __future__ import annotations

import json
import math
from dataclasses import dataclass
from typing import Any

COORDINATE_TOLERANCE = 1e-6
MIN_POLYGON_AREA = 1e-10


class QuranRegionAuditError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class QuranRegionAuditReport:
    pages: int
    ayahs: int
    region_segments: int
    multi_segment_ayahs: int


def audit_quran_regions(
    *,
    pages: list[dict[str, Any]],
    ayahs: list[dict[str, Any]],
) -> QuranRegionAuditReport:
    ayah_order = {
        (int(ayah["surah"]), int(ayah["number"])): index for index, ayah in enumerate(ayahs)
    }
    page_by_ayah: dict[tuple[int, int], int] = {}
    segments_by_ayah: dict[tuple[int, int], int] = {}
    region_segments = 0

    for page in pages:
        page_number = int(page["number"])
        regions = page.get("regions")
        if not isinstance(regions, list) or not regions:
            raise QuranRegionAuditError(f"Page {page_number} must contain at least one region.")
        _audit_asset_registration(page)

        reading_orders = [int(region.get("reading_order", 0)) for region in regions]
        if reading_orders != list(range(1, len(regions) + 1)):
            raise QuranRegionAuditError(
                f"Page {page_number} region reading_order must be continuous from 1."
            )

        page_geometries: dict[str, tuple[int, int]] = {}
        page_ayah_sequence: list[tuple[int, int]] = []
        for region in regions:
            key = (int(region.get("surah", 0)), int(region.get("ayah", 0)))
            if key not in ayah_order:
                raise QuranRegionAuditError(
                    f"Page {page_number} references unknown ayah {key[0]}:{key[1]}."
                )
            previous_page = page_by_ayah.setdefault(key, page_number)
            if previous_page != page_number:
                raise QuranRegionAuditError(
                    f"Ayah {key[0]}:{key[1]} is split across pages {previous_page} and "
                    f"{page_number}."
                )

            polygon = _audit_polygon(page_number=page_number, key=key, region=region)
            geometry = json.dumps(polygon, separators=(",", ":"))
            duplicate_key = page_geometries.get(geometry)
            if duplicate_key is not None:
                raise QuranRegionAuditError(
                    f"Page {page_number} reuses one polygon for ayahs "
                    f"{duplicate_key[0]}:{duplicate_key[1]} and {key[0]}:{key[1]}."
                )
            page_geometries[geometry] = key
            page_ayah_sequence.append(key)
            segments_by_ayah[key] = segments_by_ayah.get(key, 0) + 1
            region_segments += 1

        canonical_positions = [ayah_order[key] for key in page_ayah_sequence]
        if canonical_positions != sorted(canonical_positions):
            raise QuranRegionAuditError(
                f"Page {page_number} regions are not in canonical ayah order."
            )

    covered = set(page_by_ayah)
    expected = set(ayah_order)
    if covered != expected:
        missing = sorted(expected - covered)
        extra = sorted(covered - expected)
        raise QuranRegionAuditError(
            f"Ayah region coverage mismatch: missing={missing[:1]}, extra={extra[:1]}."
        )

    return QuranRegionAuditReport(
        pages=len(pages),
        ayahs=len(ayahs),
        region_segments=region_segments,
        multi_segment_ayahs=sum(count > 1 for count in segments_by_ayah.values()),
    )


def _audit_asset_registration(page: dict[str, Any]) -> None:
    page_number = int(page["number"])
    width = int(page.get("image_width", 0))
    height = int(page.get("image_height", 0))
    if width <= 0 or height <= 0:
        raise QuranRegionAuditError(f"Page {page_number} has invalid registered dimensions.")
    assets = page.get("assets")
    if not isinstance(assets, list) or not assets:
        raise QuranRegionAuditError(f"Page {page_number} has no registered assets.")
    expected_ratio = width / height
    for asset in assets:
        asset_width = int(asset.get("width", 0))
        asset_height = int(asset.get("height", 0))
        if asset_width <= 0 or asset_height <= 0:
            raise QuranRegionAuditError(f"Page {page_number} has invalid asset dimensions.")
        ratio_delta = abs(asset_width / asset_height - expected_ratio)
        if ratio_delta > COORDINATE_TOLERANCE:
            raise QuranRegionAuditError(
                f"Page {page_number} asset aspect ratio does not match region coordinates."
            )


def _audit_polygon(
    *,
    page_number: int,
    key: tuple[int, int],
    region: dict[str, Any],
) -> list[tuple[float, float]]:
    raw_polygon = region.get("polygon")
    if not isinstance(raw_polygon, list) or len(raw_polygon) < 3:
        raise QuranRegionAuditError(
            f"Page {page_number} ayah {key[0]}:{key[1]} has an invalid polygon."
        )
    polygon: list[tuple[float, float]] = []
    for point in raw_polygon:
        if not isinstance(point, list | tuple) or len(point) != 2:
            raise QuranRegionAuditError(
                f"Page {page_number} ayah {key[0]}:{key[1]} has a malformed point."
            )
        x, y = float(point[0]), float(point[1])
        if not math.isfinite(x) or not math.isfinite(y) or not 0 <= x <= 1 or not 0 <= y <= 1:
            raise QuranRegionAuditError(
                f"Page {page_number} ayah {key[0]}:{key[1]} has an out-of-range point."
            )
        polygon.append((x, y))

    if len(set(polygon)) < 3 or abs(_signed_area(polygon)) <= MIN_POLYGON_AREA:
        raise QuranRegionAuditError(
            f"Page {page_number} ayah {key[0]}:{key[1]} has a zero-area polygon."
        )
    xs = [point[0] for point in polygon]
    ys = [point[1] for point in polygon]
    actual_bbox = (
        float(region.get("x", -1)),
        float(region.get("y", -1)),
        float(region.get("width", -1)),
        float(region.get("height", -1)),
    )
    expected_bbox = (min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys))
    if any(
        abs(actual - expected) > COORDINATE_TOLERANCE
        for actual, expected in zip(actual_bbox, expected_bbox, strict=True)
    ):
        raise QuranRegionAuditError(
            f"Page {page_number} ayah {key[0]}:{key[1]} bbox does not match its polygon."
        )
    return polygon


def _signed_area(polygon: list[tuple[float, float]]) -> float:
    return (
        sum(
            x1 * y2 - x2 * y1
            for (x1, y1), (x2, y2) in zip(polygon, polygon[1:] + polygon[:1], strict=True)
        )
        / 2
    )
