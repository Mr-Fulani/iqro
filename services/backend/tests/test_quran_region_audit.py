from __future__ import annotations

from pathlib import Path

import pytest

from quran_backend.modules.quran.importer import validate_quran_dataset
from quran_backend.modules.quran.region_audit import QuranRegionAuditError, audit_quran_regions

DATASET_ROOT = (
    Path(__file__).resolve().parents[1] / "media" / "quran" / "datasets" / "madani-hafs-1.0.2"
)


@pytest.mark.skipif(
    not DATASET_ROOT.exists(),
    reason="Quran media is mounted outside Git; run audit_quran_regions when it is provisioned.",
)
def test_full_madani_dataset_passes_region_regression() -> None:
    report = validate_quran_dataset(DATASET_ROOT).region_audit

    assert report.pages == 604
    assert report.ayahs == 6_236
    assert report.region_segments == 12_346
    assert report.multi_segment_ayahs == 4_441


def test_region_audit_rejects_bbox_drift() -> None:
    ayahs = [{"surah": 1, "number": 1}]
    pages = [
        {
            "number": 1,
            "image_width": 100,
            "image_height": 150,
            "assets": [{"width": 100, "height": 150}],
            "regions": [
                {
                    "surah": 1,
                    "ayah": 1,
                    "reading_order": 1,
                    "polygon": [[0.1, 0.1], [0.9, 0.1], [0.9, 0.2]],
                    "x": 0.1,
                    "y": 0.1,
                    "width": 0.7,
                    "height": 0.1,
                }
            ],
        }
    ]

    with pytest.raises(QuranRegionAuditError, match="bbox does not match"):
        audit_quran_regions(pages=pages, ayahs=ayahs)


def test_region_audit_allows_renderer_rounding_across_asset_widths() -> None:
    ayahs = [{"surah": 1, "number": 1}]
    pages = [
        {
            "number": 1,
            "image_width": 900,
            "image_height": 1380,
            "assets": [
                {"width": 900, "height": 1380},
                {"width": 2700, "height": 4138},
            ],
            "regions": [
                {
                    "surah": 1,
                    "ayah": 1,
                    "reading_order": 1,
                    "polygon": [[0.1, 0.1], [0.9, 0.1], [0.9, 0.2]],
                    "x": 0.1,
                    "y": 0.1,
                    "width": 0.8,
                    "height": 0.1,
                }
            ],
        }
    ]

    report = audit_quran_regions(pages=pages, ayahs=ayahs)

    assert report.pages == 1
    assert report.ayahs == 1
