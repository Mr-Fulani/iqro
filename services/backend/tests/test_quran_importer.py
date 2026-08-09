from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

import pytest

from quran_backend.modules.quran.importer import (
    QuranDatasetError,
    import_quran_dataset,
    validate_quran_dataset,
)
from quran_backend.modules.quran.models import PublicationStatus, QuranEditionVersion


def _write_dataset(root: Path, *, mapped: bool = True) -> Path:
    root.mkdir()
    content: dict[str, str] = {
        "surahs.json": json.dumps(
            [
                {
                    "number": 1,
                    "name_ar": "الفاتحة",
                    "name_en": "Al-Fatihah",
                    "name_ru": "Аль-Фатиха",
                    "revelation_type": "meccan",
                    "ayah_count": 1,
                }
            ],
            ensure_ascii=False,
        ),
        "ayahs.jsonl": json.dumps(
            {
                "surah": 1,
                "number": 1,
                "text_uthmani": "بِسْمِ اللَّهِ",
                "text_search": "بسم الله",
                "juz": 1,
            },
            ensure_ascii=False,
        )
        + "\n",
        "pages.jsonl": json.dumps(
            {
                "number": 1,
                "image_width": 100,
                "image_height": 150,
                "checksum_sha256": "b" * 64,
                "assets": [
                    {
                        "format": "webp",
                        "width": 100,
                        "height": 150,
                        "path": "quran/test/1/pages/001.webp",
                        "sha256": "b" * 64,
                        "bytes": 1_000,
                    }
                ],
                "regions": (
                    [
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
                    ]
                    if mapped
                    else []
                ),
            }
        )
        + "\n",
        "juz.json": json.dumps(
            [
                {
                    "number": 1,
                    "start": {"surah": 1, "ayah": 1},
                    "end": {"surah": 1, "ayah": 1},
                }
            ]
        ),
    }
    for filename, value in content.items():
        (root / filename).write_text(value, encoding="utf-8")

    file_hashes = {
        filename: hashlib.sha256(value.encode()).hexdigest() for filename, value in content.items()
    }
    canonical = "".join(f"{name}:{file_hashes[name]}\n" for name in sorted(file_hashes))
    manifest: dict[str, Any] = {
        "schema_version": 1,
        "source_version": "test-source-1",
        "content_sha256": hashlib.sha256(canonical.encode()).hexdigest(),
        "edition": {
            "code": "test-hafs",
            "version": "1.0.0",
            "name_ar": "اختبار",
            "name_en": "Test Mushaf",
            "name_ru": "Тестовый мусхаф",
            "riwayah": "Hafs 'an Asim",
            "source_name": "Test source",
            "license_name": "Test license",
        },
        "counts": {"surahs": 1, "ayahs": 1, "pages": 1, "juz": 1},
        "files": file_hashes,
    }
    (root / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False),
        encoding="utf-8",
    )
    return root


def test_validate_quran_dataset_checks_all_references(tmp_path: Path) -> None:
    dataset = validate_quran_dataset(_write_dataset(tmp_path / "dataset"))

    assert dataset.manifest["edition"]["code"] == "test-hafs"
    assert len(dataset.ayahs) == 1
    assert len(dataset.pages) == 1


def test_validate_quran_dataset_rejects_unmapped_ayah(tmp_path: Path) -> None:
    dataset_path = _write_dataset(tmp_path / "dataset", mapped=False)

    with pytest.raises(QuranDatasetError, match="is not mapped to a page"):
        validate_quran_dataset(dataset_path)


def test_validate_quran_dataset_rejects_checksum_mismatch(tmp_path: Path) -> None:
    dataset_path = _write_dataset(tmp_path / "dataset")
    with (dataset_path / "ayahs.jsonl").open("a", encoding="utf-8") as handle:
        handle.write(" ")

    with pytest.raises(QuranDatasetError, match="Checksum mismatch"):
        validate_quran_dataset(dataset_path)


@pytest.mark.django_db
def test_import_creates_immutable_draft_and_is_idempotent(tmp_path: Path) -> None:
    dataset = validate_quran_dataset(_write_dataset(tmp_path / "dataset"))

    first_result = import_quran_dataset(dataset)
    second_result = import_quran_dataset(dataset)

    assert first_result.created
    assert not second_result.created
    assert first_result.version.id == second_result.version.id
    assert first_result.version.status == PublicationStatus.DRAFT
    assert first_result.edition.active_version is None
    assert QuranEditionVersion.objects.count() == 1
    assert first_result.version.surahs.count() == 1
    assert first_result.version.pages.count() == 1
