from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

from quran_backend.modules.quran import dataset_builder


def _write_sources(root: Path) -> tuple[Path, Path, Path]:
    corpus = root / "quran.json"
    corpus.write_text(
        json.dumps(
            {
                "surahs": [
                    {
                        "number": 1,
                        "name_arabic": "الفاتحة",
                        "name_transliteration": "Al-Fatihah",
                        "revelation": {"type": "Meccan"},
                        "ayahs": [
                            {
                                "number": 1,
                                "text": "بِسْمِ ٱللَّهِ",
                                "juz": 1,
                                "page": 2,
                            }
                        ],
                    }
                ]
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    polygons = root / "polygons"
    polygons.mkdir()
    polygon_payload = json.dumps(
        [
            {
                "surahNumber": 1,
                "ayahNumber": 1,
                "polygon": "10,10 100,10 100,40 10,40",
            }
        ]
    )
    (polygons / "001.json").write_text(polygon_payload, encoding="utf-8")
    assets = root / "assets"
    assets.mkdir()
    page = assets / "page.webp"
    page.write_bytes(b"test-page")
    asset_manifest = assets / "manifest.json"
    asset_manifest.write_text(
        json.dumps(
            {
                "assets": [
                    {
                        "logical_page": 1,
                        "dimensions": {"width": 900, "height": 1380},
                        "format": "webp",
                        "path": "page.webp",
                        "sha256": hashlib.sha256(page.read_bytes()).hexdigest(),
                        "bytes": page.stat().st_size,
                    }
                ]
            }
        ),
        encoding="utf-8",
    )
    return corpus, polygons, asset_manifest


def test_builds_checksummed_dataset_from_verified_sources(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    corpus, polygons, asset_manifest = _write_sources(tmp_path)
    polygon_hash = hashlib.sha256(
        (f"001.json:{hashlib.sha256((polygons / '001.json').read_bytes()).hexdigest()}\n").encode()
    ).hexdigest()
    monkeypatch.setattr(
        dataset_builder,
        "EXPECTED_CORPUS_SHA256",
        hashlib.sha256(corpus.read_bytes()).hexdigest(),
    )
    monkeypatch.setattr(dataset_builder, "EXPECTED_POLYGON_SET_SHA256", polygon_hash)
    monkeypatch.setattr(dataset_builder, "EXPECTED_SURAH_COUNT", 1)
    monkeypatch.setattr(dataset_builder, "EXPECTED_AYAH_COUNT", 1)
    monkeypatch.setattr(dataset_builder, "EXPECTED_PAGE_COUNT", 1)
    monkeypatch.setattr(dataset_builder, "EXPECTED_JUZ_COUNT", 1)
    monkeypatch.setattr(dataset_builder, "RUSSIAN_SURAH_NAMES", ("Аль-Фатиха",))

    result = dataset_builder.build_madani_hafs_dataset(
        corpus_path=corpus,
        polygons_dir=polygons,
        asset_manifest_path=asset_manifest,
        output=tmp_path / "output",
    )

    manifest = json.loads((result.output / "manifest.json").read_text(encoding="utf-8"))
    page_payload = json.loads((result.output / "pages.jsonl").read_text(encoding="utf-8"))
    assert manifest["content_sha256"] == result.content_sha256
    assert manifest["counts"] == {"surahs": 1, "ayahs": 1, "pages": 1, "juz": 1}
    assert result.page_mapping_differences == 1
    assert page_payload["regions"][0]["polygon"][0] == pytest.approx([0.2208583, 0.3179511])
    assert page_payload["assets"][0]["path"] == "quran/madani-hafs/1.0.0/page.webp"


def test_rejects_changed_corpus(tmp_path: Path) -> None:
    corpus, polygons, asset_manifest = _write_sources(tmp_path)

    with pytest.raises(dataset_builder.QuranDatasetBuildError, match="corpus checksum mismatch"):
        dataset_builder.build_madani_hafs_dataset(
            corpus_path=corpus,
            polygons_dir=polygons,
            asset_manifest_path=asset_manifest,
            output=tmp_path / "output",
        )


def test_parse_polygons_preserves_disconnected_subpaths() -> None:
    polygons = dataset_builder._parse_polygons(
        "M 0 0 L 10 0 L 10 5 L 0 5 Z M 20 10 L 30 10 L 30 15 L 20 15 Z"
    )

    assert polygons == [
        [(0.0, 0.0), (10.0, 0.0), (10.0, 5.0), (0.0, 5.0)],
        [(20.0, 10.0), (30.0, 10.0), (30.0, 15.0), (20.0, 15.0)],
    ]
