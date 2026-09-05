from __future__ import annotations

import hashlib
import json
from dataclasses import replace
from pathlib import Path

import pytest
from django.core.management import call_command

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
                                "hizb": 1,
                                "hizb_quarter": 1,
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


def _write_warsh_build_spec(root: Path, corpus: Path, polygons: Path) -> Path:
    polygon_hash = hashlib.sha256(
        (f"001.json:{hashlib.sha256((polygons / '001.json').read_bytes()).hexdigest()}\n").encode()
    ).hexdigest()
    path = root / "warsh-build-spec.json"
    path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "source_version": "official-warsh-test-2026.08.25",
                "edition": {
                    "code": "madani-warsh",
                    "version": "0.1.0-test",
                    "asset_version": "0.1.0",
                    "name_ar": "مصحف ورش",
                    "name_en": "Warsh Mushaf",
                    "name_ru": "Мусхаф Варш",
                    "riwayah": "Warsh 'an Nafi",
                    "source_name": "Synthetic official-format fixture",
                    "source_url": "https://example.test/warsh",
                    "license_name": "Synthetic test license",
                    "license_url": "https://example.test/terms",
                },
                "corpus_sha256": hashlib.sha256(corpus.read_bytes()).hexdigest(),
                "polygon_set_sha256": polygon_hash,
                "expected_counts": {
                    "surahs": 1,
                    "ayahs": 1,
                    "pages": 1,
                    "juz": 1,
                    "hizb": 1,
                    "rub_el_hizb": 1,
                },
                "geometry": {
                    "registered_page_scale": dataset_builder.REGISTERED_PAGE_SCALE,
                    "registered_image_width": dataset_builder.REGISTERED_IMAGE_WIDTH,
                    "registered_image_height": dataset_builder.REGISTERED_IMAGE_HEIGHT,
                    "standard_viewbox": list(dataset_builder.STANDARD_VIEWBOX),
                    "opening_viewbox": list(dataset_builder.OPENING_VIEWBOX),
                    "opening_page_count": 1,
                    "page_assignment_authority": "Synthetic Warsh polygon geometry",
                },
                "surah_names_ru": ["Аль-Фатиха"],
                "sources": {
                    "corpus": {"provider": "Synthetic Warsh text fixture"},
                    "regions": {"provider": "Synthetic Warsh regions fixture"},
                    "assets": {"provider": "Synthetic Warsh page fixture"},
                },
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    return path


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
    monkeypatch.setattr(dataset_builder, "EXPECTED_HIZB_COUNT", 1)
    monkeypatch.setattr(dataset_builder, "EXPECTED_RUB_EL_HIZB_COUNT", 1)
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
    assert manifest["schema_version"] == 2
    assert manifest["counts"] == {
        "surahs": 1,
        "ayahs": 1,
        "pages": 1,
        "juz": 1,
        "hizb": 1,
        "rub_el_hizb": 1,
    }
    assert result.page_mapping_differences == 1
    assert page_payload["regions"][0]["polygon"][0] == pytest.approx([0.2208583, 0.3179511])
    assert page_payload["assets"][0]["path"] == "quran/madani-hafs/1.0.0/page.webp"
    assert json.loads((result.output / "hizb.json").read_text())[0]["number"] == 1
    assert json.loads((result.output / "rub-el-hizb.json").read_text())[0]["number"] == 1


def test_keeps_all_page_renditions_without_changing_registered_geometry(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    corpus, polygons, asset_manifest = _write_sources(tmp_path)
    asset_root = asset_manifest.parent
    high_resolution = asset_root / "page-w1800.webp"
    high_resolution.write_bytes(b"test-page-high-resolution")
    manifest = json.loads(asset_manifest.read_text(encoding="utf-8"))
    manifest["assets"].insert(
        0,
        {
            "logical_page": 1,
            "dimensions": {"width": 1800, "height": 2760},
            "format": "webp",
            "path": high_resolution.name,
            "sha256": hashlib.sha256(high_resolution.read_bytes()).hexdigest(),
            "bytes": high_resolution.stat().st_size,
        },
    )
    asset_manifest.write_text(json.dumps(manifest), encoding="utf-8")
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
    monkeypatch.setattr(dataset_builder, "EXPECTED_HIZB_COUNT", 1)
    monkeypatch.setattr(dataset_builder, "EXPECTED_RUB_EL_HIZB_COUNT", 1)
    monkeypatch.setattr(dataset_builder, "RUSSIAN_SURAH_NAMES", ("Аль-Фатиха",))

    result = dataset_builder.build_madani_hafs_dataset(
        corpus_path=corpus,
        polygons_dir=polygons,
        asset_manifest_path=asset_manifest,
        output=tmp_path / "multi-resolution-output",
    )

    page = json.loads((result.output / "pages.jsonl").read_text(encoding="utf-8"))
    assert (page["image_width"], page["image_height"]) == (900, 1380)
    assert [asset["width"] for asset in page["assets"]] == [900, 1800]
    assert page["checksum_sha256"] == page["assets"][0]["sha256"]


def test_rejects_page_assets_without_the_registered_geometry_rendition(tmp_path: Path) -> None:
    _, _, asset_manifest = _write_sources(tmp_path)
    manifest = json.loads(asset_manifest.read_text(encoding="utf-8"))
    manifest["assets"][0]["dimensions"] = {"width": 1800, "height": 2760}
    asset_manifest.write_text(json.dumps(manifest), encoding="utf-8")

    with pytest.raises(dataset_builder.QuranDatasetBuildError, match="registered geometry asset"):
        dataset_builder._prepare_assets(
            manifest["assets"],
            asset_manifest.parent,
            spec=replace(
                dataset_builder.madani_hafs_build_spec(),
                expected_page_count=1,
            ),
        )


def test_rejects_changed_corpus(tmp_path: Path) -> None:
    corpus, polygons, asset_manifest = _write_sources(tmp_path)

    with pytest.raises(dataset_builder.QuranDatasetBuildError, match="corpus checksum mismatch"):
        dataset_builder.build_madani_hafs_dataset(
            corpus_path=corpus,
            polygons_dir=polygons,
            asset_manifest_path=asset_manifest,
            output=tmp_path / "output",
        )


def test_builds_warsh_dataset_from_an_explicit_edition_spec(tmp_path: Path) -> None:
    corpus, polygons, asset_manifest = _write_sources(tmp_path)
    spec_path = _write_warsh_build_spec(tmp_path, corpus, polygons)

    result = dataset_builder.build_quran_dataset(
        spec=dataset_builder.load_quran_dataset_build_spec(spec_path),
        corpus_path=corpus,
        polygons_dir=polygons,
        asset_manifest_path=asset_manifest,
        output=tmp_path / "warsh-output",
    )

    manifest = json.loads((result.output / "manifest.json").read_text(encoding="utf-8"))
    page_payload = json.loads((result.output / "pages.jsonl").read_text(encoding="utf-8"))
    assert manifest["edition"]["code"] == "madani-warsh"
    assert manifest["edition"]["riwayah"] == "Warsh 'an Nafi"
    assert manifest["edition"]["version"] == "0.1.0-test"
    assert manifest["verification"]["page_assignment_authority"] == (
        "Synthetic Warsh polygon geometry"
    )
    assert (
        manifest["sources"]["corpus"]["sha256"] == hashlib.sha256(corpus.read_bytes()).hexdigest()
    )
    assert page_payload["assets"][0]["path"] == "quran/madani-warsh/0.1.0/page.webp"


def test_rejects_unsafe_edition_code_in_build_spec(tmp_path: Path) -> None:
    corpus, polygons, _ = _write_sources(tmp_path)
    spec_path = _write_warsh_build_spec(tmp_path, corpus, polygons)
    payload = json.loads(spec_path.read_text(encoding="utf-8"))
    payload["edition"]["code"] = "../../warsh"
    spec_path.write_text(json.dumps(payload), encoding="utf-8")

    with pytest.raises(dataset_builder.QuranDatasetBuildError, match="lowercase ASCII slug"):
        dataset_builder.load_quran_dataset_build_spec(spec_path)


def test_management_command_accepts_an_edition_build_spec(tmp_path: Path) -> None:
    corpus, polygons, asset_manifest = _write_sources(tmp_path)
    spec_path = _write_warsh_build_spec(tmp_path, corpus, polygons)
    output = tmp_path / "command-output"

    call_command(
        "build_quran_dataset",
        str(corpus),
        str(polygons),
        str(asset_manifest),
        str(output),
        spec=spec_path,
    )

    manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["edition"]["code"] == "madani-warsh"


def test_parse_polygons_preserves_disconnected_subpaths() -> None:
    polygons = dataset_builder._parse_polygons(
        "M 0 0 L 10 0 L 10 5 L 0 5 Z M 20 10 L 30 10 L 30 15 L 20 15 Z"
    )

    assert polygons == [
        [(0.0, 0.0), (10.0, 0.0), (10.0, 5.0), (0.0, 5.0)],
        [(20.0, 10.0), (30.0, 10.0), (30.0, 15.0), (20.0, 15.0)],
    ]
