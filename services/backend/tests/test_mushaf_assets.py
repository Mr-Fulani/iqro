from __future__ import annotations

import hashlib
import json
import math
from collections.abc import Sequence
from pathlib import Path
from typing import cast

import pytest
from django.core.management import CommandError, call_command

from quran_backend.modules.quran.mushaf_assets import (
    EXPECTED_MEDIA_BOX,
    EXPECTED_PDF_PAGE_COUNT,
    AssetRecord,
    MushafAssetError,
    MushafSource,
    PageRenderRequest,
    PopplerWebpRenderer,
    ProcessOutput,
    RenderedVariant,
    SourceFingerprint,
    build_mushaf_assets,
    create_build_plan,
    inspect_mushaf_source,
    legacy_hafs_mushaf_asset_spec,
    load_mushaf_asset_build_spec,
)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _fingerprint(path: Path) -> SourceFingerprint:
    stat = path.stat()
    return SourceFingerprint(
        device=stat.st_dev,
        inode=stat.st_ino,
        size=stat.st_size,
        modified_ns=stat.st_mtime_ns,
    )


def _source(tmp_path: Path) -> MushafSource:
    source_path = tmp_path / "source.pdf"
    source_path.write_bytes(b"%PDF-1.3\nsmall test source\n")
    return MushafSource(
        path=source_path.resolve(),
        sha256=_sha256(source_path),
        bytes=source_path.stat().st_size,
        pdf_page_count=EXPECTED_PDF_PAGE_COUNT,
        media_box=EXPECTED_MEDIA_BOX,
        metadata={"Title": "Test"},
        pdfinfo_version="pdfinfo test",
        fingerprint=_fingerprint(source_path),
        build_spec=legacy_hafs_mushaf_asset_spec(expected_sha256=_sha256(source_path)),
    )


def _webp_payload(width: int, height: int) -> bytes:
    chunk = (
        b"VP8X"
        + (10).to_bytes(4, "little")
        + b"\x00\x00\x00\x00"
        + (width - 1).to_bytes(3, "little")
        + (height - 1).to_bytes(3, "little")
    )
    return b"RIFF" + (len(chunk) + 4).to_bytes(4, "little") + b"WEBP" + chunk


def _png_header(width: int, height: int) -> bytes:
    return (
        b"\x89PNG\r\n\x1a\n"
        + (13).to_bytes(4, "big")
        + b"IHDR"
        + width.to_bytes(4, "big")
        + height.to_bytes(4, "big")
    )


class FakeRenderer:
    def __init__(self, *, fail_on_page: int | None = None, mutate_source: bool = False) -> None:
        self.calls: list[PageRenderRequest] = []
        self.fail_on_page = fail_on_page
        self.mutate_source = mutate_source

    def tool_metadata(self) -> dict[str, str]:
        return {"pdftoppm": "test-poppler", "cwebp": "test-webp"}

    def render_page(self, request: PageRenderRequest) -> list[RenderedVariant]:
        self.calls.append(request)
        if request.logical_page == self.fail_on_page:
            raise MushafAssetError("synthetic render failure")
        variants: list[RenderedVariant] = []
        for width in request.variant_widths:
            height = math.ceil(width * EXPECTED_MEDIA_BOX[3] / EXPECTED_MEDIA_BOX[2])
            relative_path = (
                Path("pages")
                / f"{request.logical_page:03d}"
                / f"page-{request.logical_page:03d}-w{width:04d}.webp"
            )
            target = request.staging_root / relative_path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(_webp_payload(width, height))
            variants.append(
                RenderedVariant(width=width, height=height, relative_path=relative_path)
            )
        if self.mutate_source:
            request.source.write_bytes(request.source.read_bytes() + b"changed")
        return variants


class PdfInfoRunner:
    def __init__(self, pdfinfo_output: str) -> None:
        self.pdfinfo_output = pdfinfo_output
        self.calls: list[tuple[str, ...]] = []

    def run(self, arguments: Sequence[str], *, timeout_seconds: int) -> ProcessOutput:
        command = tuple(arguments)
        self.calls.append(command)
        assert timeout_seconds > 0
        if command[1:] == ("-v",):
            return ProcessOutput(stdout="", stderr="pdfinfo version test\n")
        return ProcessOutput(stdout=self.pdfinfo_output, stderr="")


def _pdfinfo_output(
    size: int,
    *,
    page_count: int = EXPECTED_PDF_PAGE_COUNT,
    author: str = "quran.ws",
    media_box_page_two_width: float = 900.0,
    title: str = "Qur\u2019an — Hafs (Hafs from Asim) — Complete Mushaf",
) -> str:
    lines = [
        f"Title:           {title}",
        f"Author:          {author}",
        "Creator:         pdf.quran.ws",
        "Producer:        pdf.quran.ws",
        "Encrypted:       no",
        "JavaScript:      no",
        f"Pages:           {page_count}",
        f"File size:       {size} bytes",
        "PDF version:     1.3",
    ]
    for page in range(1, page_count + 1):
        width = media_box_page_two_width if page == 2 else 900.0
        lines.append(f"Page {page:4d} rot:   0")
        lines.append(f"Page {page:4d} MediaBox: 0.00 0.00 {width:.2f} 1379.25")
    return "\n".join(lines)


def _write_warsh_asset_spec(source_path: Path) -> Path:
    path = source_path.with_name("warsh-asset-spec.json")
    path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "edition": {
                    "code": "madani-warsh",
                    "name_ar": "مصحف ورش",
                    "name_en": "Warsh Mushaf",
                    "name_ru": "Мусхаф Варш",
                    "riwayah": "Warsh 'an Nafi",
                    "source_name": "Synthetic Warsh source",
                    "source_url": "https://example.test/warsh",
                    "license_name": "Synthetic license",
                    "license_url": "https://example.test/terms",
                    "surah_count": 114,
                    "juz_count": 30,
                },
                "pdf_source": {
                    "expected_sha256": _sha256(source_path),
                    "expected_pdf_page_count": 2,
                    "cover_pdf_page_count": 1,
                    "logical_page_count": 1,
                    "expected_media_box": list(EXPECTED_MEDIA_BOX),
                    "required_metadata": {
                        "Title": "Synthetic Warsh Mushaf",
                        "Author": "quran.ws",
                        "Creator": "pdf.quran.ws",
                        "Producer": "pdf.quran.ws",
                    },
                },
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    return path


class RenderingRunner:
    def __init__(self) -> None:
        self.calls: list[tuple[str, ...]] = []

    def run(self, arguments: Sequence[str], *, timeout_seconds: int) -> ProcessOutput:
        command = tuple(arguments)
        self.calls.append(command)
        assert timeout_seconds > 0
        if command[0] == "pdftoppm" and command[1:] == ("-v",):
            return ProcessOutput(stdout="", stderr="pdftoppm version test")
        if command[0] == "cwebp" and command[1:] == ("-version",):
            return ProcessOutput(stdout="cwebp test", stderr="")
        if command[0] == "pdftoppm":
            maximum_width = int(command[command.index("-scale-to-x") + 1])
            prefix = Path(command[-1])
            height = math.ceil(maximum_width * EXPECTED_MEDIA_BOX[3] / EXPECTED_MEDIA_BOX[2])
            prefix.with_suffix(".png").write_bytes(_png_header(maximum_width, height))
            return ProcessOutput(stdout="", stderr="")
        width = int(command[command.index("-resize") + 1])
        target = Path(command[command.index("-o") + 1])
        height = math.ceil(width * EXPECTED_MEDIA_BOX[3] / EXPECTED_MEDIA_BOX[2])
        target.write_bytes(_webp_payload(width, height))
        return ProcessOutput(stdout="", stderr="")


def test_inspect_mushaf_source_validates_checksum_metadata_and_all_pages(tmp_path: Path) -> None:
    source_path = tmp_path / "known.pdf"
    source_path.write_bytes(b"known input")
    runner = PdfInfoRunner(_pdfinfo_output(source_path.stat().st_size))

    source = inspect_mushaf_source(
        source_path,
        expected_sha256=_sha256(source_path),
        runner=runner,
    )

    assert source.sha256 == _sha256(source_path)
    assert source.pdf_page_count == 605
    assert source.media_box == (0.0, 0.0, 900.0, 1379.25)
    assert source.pdfinfo_version == "pdfinfo version test"
    assert runner.calls[1][1:7] == ("-f", "1", "-l", "605", "-box", str(source.path))


def test_inspection_rejects_checksum_before_running_pdfinfo(tmp_path: Path) -> None:
    source_path = tmp_path / "known.pdf"
    source_path.write_bytes(b"known input")
    runner = PdfInfoRunner("")

    with pytest.raises(MushafAssetError, match="SHA-256 mismatch"):
        inspect_mushaf_source(source_path, expected_sha256="0" * 64, runner=runner)

    assert runner.calls == []


@pytest.mark.parametrize(
    ("output", "message"),
    [
        (_pdfinfo_output(11, page_count=604), "Expected 605 PDF pages"),
        (_pdfinfo_output(11, author="unexpected"), "metadata field: Author"),
        (_pdfinfo_output(11, media_box_page_two_width=901), "MediaBox on PDF page 2"),
    ],
)
def test_inspection_rejects_invalid_pdf_structure(
    tmp_path: Path,
    output: str,
    message: str,
) -> None:
    source_path = tmp_path / "known.pdf"
    source_path.write_bytes(b"known input")

    with pytest.raises(MushafAssetError, match=message):
        inspect_mushaf_source(
            source_path,
            expected_sha256=_sha256(source_path),
            runner=PdfInfoRunner(output),
        )


def test_warsh_asset_spec_controls_pdf_validation_page_mapping_and_manifest(
    tmp_path: Path,
) -> None:
    source_path = tmp_path / "warsh.pdf"
    source_path.write_bytes(b"synthetic warsh source")
    spec = load_mushaf_asset_build_spec(_write_warsh_asset_spec(source_path))
    runner = PdfInfoRunner(
        _pdfinfo_output(
            source_path.stat().st_size,
            page_count=2,
            title="Synthetic Warsh Mushaf",
        )
    )
    source = inspect_mushaf_source(source_path, build_spec=spec, runner=runner)
    plan = create_build_plan(source, tmp_path / "warsh-assets", variant_widths=(480,))

    result = build_mushaf_assets(plan, renderer=FakeRenderer())

    assert result.asset_count == 1
    manifest = cast(dict[str, object], result.manifest)
    edition = cast(dict[str, object], manifest["edition"])
    source_manifest = cast(dict[str, object], manifest["source"])
    assets = cast(list[dict[str, object]], manifest["assets"])
    assert manifest["schema_version"] == 2
    assert edition["code"] == "madani-warsh"
    assert edition["riwayah"] == "Warsh 'an Nafi"
    assert source_manifest["logical_page_count"] == 1
    assert assets[0]["pdf_page"] == 2


def test_mushaf_asset_spec_rejects_unsafe_edition_code(tmp_path: Path) -> None:
    source_path = tmp_path / "warsh.pdf"
    source_path.write_bytes(b"synthetic warsh source")
    spec_path = _write_warsh_asset_spec(source_path)
    payload = json.loads(spec_path.read_text(encoding="utf-8"))
    payload["edition"]["code"] = "../warsh"
    spec_path.write_text(json.dumps(payload), encoding="utf-8")

    with pytest.raises(MushafAssetError, match="lowercase ASCII slug"):
        load_mushaf_asset_build_spec(spec_path)


def test_build_partial_range_skips_cover_and_atomically_promotes(tmp_path: Path) -> None:
    source = _source(tmp_path)
    output = tmp_path / "prepared-assets"
    renderer = FakeRenderer()
    progress: list[tuple[int, int]] = []
    plan = create_build_plan(
        source,
        output,
        first_logical_page=1,
        last_logical_page=2,
        variant_widths=(900, 480, 900),
    )

    result = build_mushaf_assets(
        plan,
        renderer=renderer,
        progress=lambda done, total: progress.append((done, total)),
    )

    assert result.output == output.resolve()
    assert result.asset_count == 4
    assert [request.pdf_page for request in renderer.calls] == [2, 3]
    assert [request.logical_page for request in renderer.calls] == [1, 2]
    assert progress == [(1, 2), (2, 2)]
    manifest = cast(dict[str, object], json.loads((output / "manifest.json").read_text()))
    source_manifest = cast(dict[str, object], manifest["source"])
    render_manifest = cast(dict[str, object], manifest["render"])
    assets = cast(list[dict[str, object]], manifest["assets"])
    assert source_manifest["cover_pdf_pages"] == [1]
    assert source_manifest["logical_page_count"] == 604
    assert render_manifest["variant_widths"] == [480, 900]
    assert [(asset["logical_page"], asset["pdf_page"]) for asset in assets] == [
        (1, 2),
        (1, 2),
        (2, 3),
        (2, 3),
    ]
    assert all(set(asset) >= {"dimensions", "sha256", "bytes", "path"} for asset in assets)
    manifest_line = (output / "manifest.sha256").read_text()
    assert manifest_line == f"{_sha256(output / 'manifest.json')}  manifest.json\n"
    assert list(tmp_path.glob(".prepared-assets.staging-*")) == []


def test_build_failure_removes_staging_and_never_exposes_output(tmp_path: Path) -> None:
    source = _source(tmp_path)
    output = tmp_path / "prepared-assets"
    plan = create_build_plan(
        source,
        output,
        first_logical_page=1,
        last_logical_page=2,
        variant_widths=(480,),
    )

    with pytest.raises(MushafAssetError, match="synthetic render failure"):
        build_mushaf_assets(plan, renderer=FakeRenderer(fail_on_page=2))

    assert not output.exists()
    assert list(tmp_path.glob(".prepared-assets.staging-*")) == []


def test_last_logical_page_maps_to_last_pdf_page(tmp_path: Path) -> None:
    source = _source(tmp_path)
    renderer = FakeRenderer()
    plan = create_build_plan(
        source,
        tmp_path / "last-page",
        first_logical_page=604,
        last_logical_page=604,
        variant_widths=(480,),
    )

    result = build_mushaf_assets(plan, renderer=renderer)

    assert result.asset_count == 1
    assert renderer.calls[0].logical_page == 604
    assert renderer.calls[0].pdf_page == 605


def test_build_rechecks_source_before_promotion(tmp_path: Path) -> None:
    source = _source(tmp_path)
    output = tmp_path / "prepared-assets"
    plan = create_build_plan(
        source,
        output,
        first_logical_page=1,
        last_logical_page=1,
        variant_widths=(480,),
    )

    with pytest.raises(MushafAssetError, match="Source PDF changed"):
        build_mushaf_assets(plan, renderer=FakeRenderer(mutate_source=True))

    assert not output.exists()


@pytest.mark.parametrize(
    ("first_page", "last_page", "widths", "message"),
    [
        (0, 1, (480,), "Logical page range"),
        (1, 605, (480,), "Logical page range"),
        (1, 1, (), "At least one WebP"),
        (1, 1, (100,), "Variant width"),
    ],
)
def test_build_plan_rejects_unsafe_parameters(
    tmp_path: Path,
    first_page: int,
    last_page: int,
    widths: tuple[int, ...],
    message: str,
) -> None:
    source = _source(tmp_path)

    with pytest.raises(MushafAssetError, match=message):
        create_build_plan(
            source,
            tmp_path / "output",
            first_logical_page=first_page,
            last_logical_page=last_page,
            variant_widths=widths,
        )


def test_build_plan_rejects_existing_output(tmp_path: Path) -> None:
    source = _source(tmp_path)
    output = tmp_path / "output"
    output.mkdir()

    with pytest.raises(MushafAssetError, match="already exists"):
        create_build_plan(source, output)


def test_build_plan_rejects_non_directory_output_ancestor(tmp_path: Path) -> None:
    source = _source(tmp_path)
    invalid_parent = tmp_path / "not-a-directory"
    invalid_parent.write_text("file")

    with pytest.raises(MushafAssetError, match="non-directory ancestor"):
        create_build_plan(source, invalid_parent / "output")


def test_poppler_renderer_uses_exact_pdf_page_and_lossless_webp(tmp_path: Path) -> None:
    runner = RenderingRunner()
    renderer = PopplerWebpRenderer(runner)
    staging_root = tmp_path / "stage"
    work_root = tmp_path / "work"
    staging_root.mkdir()
    work_root.mkdir()
    source = tmp_path / "source.pdf"
    source.write_bytes(b"source")

    variants = renderer.render_page(
        PageRenderRequest(
            source=source,
            pdf_page=2,
            logical_page=1,
            variant_widths=(480, 900),
            staging_root=staging_root,
            work_root=work_root,
        )
    )

    pdftoppm_call = runner.calls[0]
    assert pdftoppm_call[pdftoppm_call.index("-f") + 1] == "2"
    assert pdftoppm_call[pdftoppm_call.index("-l") + 1] == "2"
    assert "-singlefile" in pdftoppm_call
    assert all("-lossless" in call and "-metadata" in call for call in runner.calls[1:])
    assert [(variant.width, variant.height) for variant in variants] == [(480, 736), (900, 1380)]


def test_validate_only_command_does_not_require_output(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    source = _source(tmp_path)

    def fake_inspect(source_path: Path, *, expected_sha256: str) -> MushafSource:
        assert source_path == source.path
        assert len(expected_sha256) == 64
        return source

    monkeypatch.setattr(
        "quran_backend.modules.quran.management.commands.prepare_mushaf_pages.inspect_mushaf_source",
        fake_inspect,
    )

    call_command("prepare_mushaf_pages", source.path, "--validate-only")

    assert "Source is valid" in capsys.readouterr().out


def test_command_requires_output_for_build(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    source = _source(tmp_path)

    def fake_inspect(source_path: Path, *, expected_sha256: str) -> MushafSource:
        assert source_path == source.path
        assert len(expected_sha256) == 64
        return source

    monkeypatch.setattr(
        "quran_backend.modules.quran.management.commands.prepare_mushaf_pages.inspect_mushaf_source",
        fake_inspect,
    )

    with pytest.raises(CommandError, match="--output is required"):
        call_command("prepare_mushaf_pages", source.path)


def test_asset_record_manifest_has_required_fields() -> None:
    record = AssetRecord(
        logical_page=1,
        pdf_page=2,
        variant="w480",
        width=480,
        height=736,
        sha256="a" * 64,
        bytes=100,
        path="pages/001/page-001-w0480.webp",
    )

    assert record.as_manifest_value()["dimensions"] == {"width": 480, "height": 736}
