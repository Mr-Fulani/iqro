from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import shutil
import struct
import subprocess
import tempfile
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol

KNOWN_SOURCE_SHA256 = "76c690a92e0b464377e765f75d76976cc432877d297091a863b424ec782d234a"
EXPECTED_PDF_PAGE_COUNT = 605
COVER_PDF_PAGE_COUNT = 1
LOGICAL_PAGE_COUNT = 604
EXPECTED_MEDIA_BOX = (0.0, 0.0, 900.0, 1379.25)
DEFAULT_VARIANT_WIDTHS = (480, 900, 1800)
MIN_VARIANT_WIDTH = 240
MAX_VARIANT_WIDTH = 4096
MANIFEST_SCHEMA_VERSION = 2

_REQUIRED_METADATA = {
    "Title": "Qur\u2019an — Hafs (Hafs from Asim) — Complete Mushaf",
    "Author": "quran.ws",
    "Creator": "pdf.quran.ws",
    "Producer": "pdf.quran.ws",
}
_MANIFEST_METADATA_KEYS = (
    "Title",
    "Subject",
    "Keywords",
    "Author",
    "Creator",
    "Producer",
    "CreationDate",
    "ModDate",
    "PDF version",
)
_SHA256_RE = re.compile(r"[0-9a-fA-F]{64}\Z")
_EDITION_CODE_RE = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
_NUMBER_PATTERN = r"-?(?:\d+(?:\.\d*)?|\.\d+)"
_MEDIA_BOX_RE = re.compile(
    rf"^Page\s+(\d+)\s+MediaBox:\s+({_NUMBER_PATTERN})\s+({_NUMBER_PATTERN})\s+"
    rf"({_NUMBER_PATTERN})\s+({_NUMBER_PATTERN})\s*$"
)
_ROTATION_RE = re.compile(r"^Page\s+(\d+)\s+rot:\s+(-?\d+)\s*$")


class MushafAssetError(ValueError):
    """Raised when source validation or deterministic asset preparation fails."""


@dataclass(frozen=True, slots=True)
class MushafAssetBuildSpec:
    edition_code: str
    name_ar: str
    name_en: str
    name_ru: str
    riwayah: str
    source_name: str
    source_url: str
    license_name: str
    license_url: str
    surah_count: int
    juz_count: int
    expected_sha256: str
    expected_pdf_page_count: int
    cover_pdf_page_count: int
    logical_page_count: int
    expected_media_box: tuple[float, float, float, float]
    required_metadata: Mapping[str, str]


def legacy_hafs_mushaf_asset_spec(
    *,
    expected_sha256: str = KNOWN_SOURCE_SHA256,
) -> MushafAssetBuildSpec:
    return MushafAssetBuildSpec(
        edition_code="madani-hafs",
        name_ar="مصحف المدينة",
        name_en="Madani Mushaf",
        name_ru="Мединский мусхаф",
        riwayah="Hafs 'an Asim",
        source_name="Tanzil + quranpedia/quran-svg + pinned KFQC PDF",
        source_url="https://tanzil.net/download/",
        license_name="Tanzil CC BY 3.0; regions CC0 1.0; KFQC digital-use terms",
        license_url="https://tanzil.net/docs/Text_License",
        surah_count=114,
        juz_count=30,
        expected_sha256=_normalize_checksum(expected_sha256),
        expected_pdf_page_count=EXPECTED_PDF_PAGE_COUNT,
        cover_pdf_page_count=COVER_PDF_PAGE_COUNT,
        logical_page_count=LOGICAL_PAGE_COUNT,
        expected_media_box=EXPECTED_MEDIA_BOX,
        required_metadata=_REQUIRED_METADATA,
    )


def load_mushaf_asset_build_spec(path: Path) -> MushafAssetBuildSpec:
    try:
        payload = json.loads(path.resolve(strict=True).read_text(encoding="utf-8"))
    except (OSError, RuntimeError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise MushafAssetError(f"Could not read Mushaf asset build spec: {exc}.") from exc
    if not isinstance(payload, dict) or payload.get("schema_version") != 1:
        raise MushafAssetError("Mushaf asset build spec schema_version must be 1.")
    edition = _spec_mapping(payload.get("edition"), "edition")
    source = _spec_mapping(payload.get("pdf_source"), "pdf_source")
    raw_media_box = source.get("expected_media_box")
    if (
        not isinstance(raw_media_box, list)
        or len(raw_media_box) != 4
        or any(
            not isinstance(value, int | float) or isinstance(value, bool) for value in raw_media_box
        )
    ):
        raise MushafAssetError("Mushaf asset spec expected_media_box must contain four numbers.")
    raw_metadata = _spec_mapping(source.get("required_metadata", {}), "required_metadata")
    if not all(
        isinstance(key, str) and isinstance(value, str) for key, value in raw_metadata.items()
    ):
        raise MushafAssetError("Mushaf asset spec required_metadata must contain strings.")
    spec = MushafAssetBuildSpec(
        edition_code=_spec_string(edition, "code"),
        name_ar=_spec_string(edition, "name_ar"),
        name_en=_spec_string(edition, "name_en"),
        name_ru=_spec_string(edition, "name_ru"),
        riwayah=_spec_string(edition, "riwayah"),
        source_name=_spec_string(edition, "source_name"),
        source_url=str(edition.get("source_url", "")).strip(),
        license_name=_spec_string(edition, "license_name"),
        license_url=str(edition.get("license_url", "")).strip(),
        surah_count=_spec_positive_int(edition, "surah_count"),
        juz_count=_spec_positive_int(edition, "juz_count"),
        expected_sha256=_normalize_checksum(_spec_string(source, "expected_sha256")),
        expected_pdf_page_count=_spec_positive_int(source, "expected_pdf_page_count"),
        cover_pdf_page_count=_spec_nonnegative_int(source, "cover_pdf_page_count"),
        logical_page_count=_spec_positive_int(source, "logical_page_count"),
        expected_media_box=(
            float(raw_media_box[0]),
            float(raw_media_box[1]),
            float(raw_media_box[2]),
            float(raw_media_box[3]),
        ),
        required_metadata=dict(raw_metadata),
    )
    _validate_asset_build_spec(spec)
    return spec


@dataclass(frozen=True, slots=True)
class ProcessOutput:
    stdout: str
    stderr: str


class ProcessRunner(Protocol):
    def run(self, arguments: Sequence[str], *, timeout_seconds: int) -> ProcessOutput: ...


class SubprocessRunner:
    """Run a fixed argument vector without involving a shell."""

    def run(self, arguments: Sequence[str], *, timeout_seconds: int) -> ProcessOutput:
        if not arguments:
            raise MushafAssetError("An empty external command was requested.")
        executable = shutil.which(arguments[0])
        if executable is None:
            raise MushafAssetError(f"Required executable is not available: {arguments[0]}.")
        command = (executable, *arguments[1:])
        environment = os.environ.copy()
        environment.update({"LANG": "C", "LC_ALL": "C", "TZ": "UTC"})
        try:
            completed = subprocess.run(  # noqa: S603 - arguments are never passed to a shell.
                command,
                check=False,
                capture_output=True,
                encoding="utf-8",
                errors="strict",
                env=environment,
                timeout=timeout_seconds,
            )
        except subprocess.TimeoutExpired as exc:
            raise MushafAssetError(
                f"External command timed out after {timeout_seconds} seconds: {arguments[0]}."
            ) from exc
        except (OSError, UnicodeError) as exc:
            raise MushafAssetError(f"Could not execute {arguments[0]}: {exc}.") from exc
        if completed.returncode != 0:
            details = (completed.stderr or completed.stdout).strip()[:2_000]
            suffix = f" Details: {details}" if details else ""
            raise MushafAssetError(
                f"External command failed with exit code {completed.returncode}: "
                f"{arguments[0]}.{suffix}"
            )
        return ProcessOutput(stdout=completed.stdout, stderr=completed.stderr)


@dataclass(frozen=True, slots=True)
class SourceFingerprint:
    device: int
    inode: int
    size: int
    modified_ns: int


@dataclass(frozen=True, slots=True)
class MushafSource:
    path: Path
    sha256: str
    bytes: int
    pdf_page_count: int
    media_box: tuple[float, float, float, float]
    metadata: Mapping[str, str]
    pdfinfo_version: str
    fingerprint: SourceFingerprint
    build_spec: MushafAssetBuildSpec


@dataclass(frozen=True, slots=True)
class RenderedVariant:
    width: int
    height: int
    relative_path: Path


@dataclass(frozen=True, slots=True)
class PageRenderRequest:
    source: Path
    pdf_page: int
    logical_page: int
    variant_widths: tuple[int, ...]
    staging_root: Path
    work_root: Path
    expected_media_box: tuple[float, float, float, float] = EXPECTED_MEDIA_BOX


@dataclass(frozen=True, slots=True)
class AssetRecord:
    logical_page: int
    pdf_page: int
    variant: str
    width: int
    height: int
    sha256: str
    bytes: int
    path: str

    def as_manifest_value(self) -> dict[str, object]:
        return {
            "logical_page": self.logical_page,
            "pdf_page": self.pdf_page,
            "variant": self.variant,
            "format": "webp",
            "dimensions": {"width": self.width, "height": self.height},
            "sha256": self.sha256,
            "bytes": self.bytes,
            "path": self.path,
        }


@dataclass(frozen=True, slots=True)
class BuildPlan:
    source: MushafSource
    output: Path
    first_logical_page: int
    last_logical_page: int
    variant_widths: tuple[int, ...]

    @property
    def page_count(self) -> int:
        return self.last_logical_page - self.first_logical_page + 1

    @property
    def asset_count(self) -> int:
        return self.page_count * len(self.variant_widths)


@dataclass(frozen=True, slots=True)
class BuildResult:
    output: Path
    manifest: Mapping[str, object]
    asset_count: int


class PageRenderer(Protocol):
    def tool_metadata(self) -> Mapping[str, str]: ...

    def render_page(self, request: PageRenderRequest) -> Sequence[RenderedVariant]: ...


class PopplerWebpRenderer:
    """Rasterize with Poppler and encode deterministic lossless WebP variants."""

    def __init__(self, runner: ProcessRunner | None = None) -> None:
        self._runner = runner or SubprocessRunner()

    def tool_metadata(self) -> Mapping[str, str]:
        return {
            "pdftoppm": _tool_version(self._runner.run(("pdftoppm", "-v"), timeout_seconds=30)),
            "cwebp": _tool_version(self._runner.run(("cwebp", "-version"), timeout_seconds=30)),
        }

    def render_page(self, request: PageRenderRequest) -> Sequence[RenderedVariant]:
        maximum_width = max(request.variant_widths)
        with tempfile.TemporaryDirectory(
            dir=request.work_root,
            prefix=f"page-{request.logical_page:03d}-",
        ) as page_work_value:
            page_work = Path(page_work_value)
            raster_prefix = page_work / "source"
            self._runner.run(
                (
                    "pdftoppm",
                    "-f",
                    str(request.pdf_page),
                    "-l",
                    str(request.pdf_page),
                    "-singlefile",
                    "-png",
                    "-cropbox",
                    "-scale-to-x",
                    str(maximum_width),
                    "-scale-to-y",
                    "-1",
                    os.fspath(request.source),
                    os.fspath(raster_prefix),
                ),
                timeout_seconds=180,
            )
            raster_path = raster_prefix.with_suffix(".png")
            raster_width, raster_height = _read_png_dimensions(raster_path)
            if raster_width != maximum_width:
                raise MushafAssetError(
                    f"pdftoppm produced width {raster_width}; expected {maximum_width}."
                )
            source_width = request.expected_media_box[2] - request.expected_media_box[0]
            source_height = request.expected_media_box[3] - request.expected_media_box[1]
            source_ratio = source_height / source_width
            actual_ratio = raster_height / raster_width
            if abs(actual_ratio - source_ratio) > 0.002:
                raise MushafAssetError("pdftoppm produced an unexpected page aspect ratio.")

            rendered: list[RenderedVariant] = []
            for width in request.variant_widths:
                relative_path = _asset_relative_path(request.logical_page, width)
                target = _safe_staging_path(request.staging_root, relative_path)
                target.parent.mkdir(parents=True, exist_ok=True)
                self._runner.run(
                    (
                        "cwebp",
                        "-quiet",
                        "-lossless",
                        "-exact",
                        "-m",
                        "4",
                        "-mt",
                        "-q",
                        "100",
                        "-metadata",
                        "none",
                        "-resize",
                        str(width),
                        "0",
                        os.fspath(raster_path),
                        "-o",
                        os.fspath(target),
                    ),
                    timeout_seconds=180,
                )
                actual_width, actual_height = _read_webp_dimensions(target)
                if actual_width != width:
                    raise MushafAssetError(
                        f"cwebp produced width {actual_width}; expected {width}."
                    )
                target.chmod(0o644)
                rendered.append(
                    RenderedVariant(
                        width=actual_width,
                        height=actual_height,
                        relative_path=relative_path,
                    )
                )
            return rendered


def inspect_mushaf_source(
    source_path: Path,
    *,
    expected_sha256: str | None = None,
    build_spec: MushafAssetBuildSpec | None = None,
    runner: ProcessRunner | None = None,
) -> MushafSource:
    """Pin and inspect a spec-defined Mushaf PDF without modifying it."""

    if build_spec is not None and expected_sha256 is not None:
        raise MushafAssetError("Use either build_spec or expected_sha256, not both.")
    spec = build_spec or legacy_hafs_mushaf_asset_spec(
        expected_sha256=expected_sha256 or KNOWN_SOURCE_SHA256
    )
    _validate_asset_build_spec(spec)
    source = _resolve_source(source_path)
    normalized_expected_checksum = _normalize_checksum(spec.expected_sha256)
    fingerprint = _source_fingerprint(source)
    actual_checksum = _sha256_file(source)
    if not hmac.compare_digest(actual_checksum, normalized_expected_checksum):
        raise MushafAssetError(
            f"Source SHA-256 mismatch: expected {normalized_expected_checksum}, "
            f"got {actual_checksum}."
        )

    actual_runner = runner or SubprocessRunner()
    version = _tool_version(actual_runner.run(("pdfinfo", "-v"), timeout_seconds=30))
    result = actual_runner.run(
        (
            "pdfinfo",
            "-f",
            "1",
            "-l",
            str(spec.expected_pdf_page_count),
            "-box",
            os.fspath(source),
        ),
        timeout_seconds=180,
    )
    metadata, page_count, media_boxes, rotations = _parse_pdfinfo(result.stdout)
    _validate_pdfinfo(
        metadata=metadata,
        page_count=page_count,
        media_boxes=media_boxes,
        rotations=rotations,
        actual_size=fingerprint.size,
        build_spec=spec,
    )
    current_fingerprint = _source_fingerprint(source)
    if current_fingerprint != fingerprint:
        raise MushafAssetError("Source PDF changed while it was being inspected.")

    selected_metadata = {key: metadata[key] for key in _MANIFEST_METADATA_KEYS if key in metadata}
    return MushafSource(
        path=source,
        sha256=actual_checksum,
        bytes=fingerprint.size,
        pdf_page_count=page_count,
        media_box=spec.expected_media_box,
        metadata=selected_metadata,
        pdfinfo_version=version,
        fingerprint=fingerprint,
        build_spec=spec,
    )


def create_build_plan(
    source: MushafSource,
    output_path: Path,
    *,
    first_logical_page: int = 1,
    last_logical_page: int | None = None,
    variant_widths: Sequence[int] = DEFAULT_VARIANT_WIDTHS,
) -> BuildPlan:
    logical_page_count = source.build_spec.logical_page_count
    resolved_last_page = logical_page_count if last_logical_page is None else last_logical_page
    if not 1 <= first_logical_page <= resolved_last_page <= logical_page_count:
        raise MushafAssetError(
            f"Logical page range must satisfy 1 <= first <= last <= {logical_page_count}."
        )
    widths = _normalize_variant_widths(variant_widths)
    output = _resolve_output(output_path, source.path)
    return BuildPlan(
        source=source,
        output=output,
        first_logical_page=first_logical_page,
        last_logical_page=resolved_last_page,
        variant_widths=widths,
    )


def build_mushaf_assets(
    plan: BuildPlan,
    *,
    renderer: PageRenderer | None = None,
    progress: Callable[[int, int], None] | None = None,
) -> BuildResult:
    """Build into a sibling staging directory and atomically promote a fresh output."""

    try:
        return _build_mushaf_assets(plan, renderer=renderer, progress=progress)
    except MushafAssetError:
        raise
    except OSError as exc:
        raise MushafAssetError(f"Asset build filesystem operation failed: {exc}.") from exc


def _build_mushaf_assets(
    plan: BuildPlan,
    *,
    renderer: PageRenderer | None,
    progress: Callable[[int, int], None] | None,
) -> BuildResult:
    _assert_source_unchanged(plan.source, verify_checksum=True)
    if plan.output.exists():
        raise MushafAssetError(f"Output path already exists: {plan.output}.")
    output_parent = plan.output.parent
    output_parent.mkdir(parents=True, exist_ok=True)
    if not output_parent.is_dir():
        raise MushafAssetError(f"Output parent is not a directory: {output_parent}.")

    actual_renderer = renderer or PopplerWebpRenderer()
    tool_metadata = dict(sorted(actual_renderer.tool_metadata().items()))
    with tempfile.TemporaryDirectory(
        dir=output_parent,
        prefix=f".{plan.output.name}.staging-",
    ) as staging_value:
        staging_root = Path(staging_value)
        staging_root.chmod(0o755)
        records: list[AssetRecord] = []
        with tempfile.TemporaryDirectory(dir=staging_root, prefix=".work-") as work_value:
            work_root = Path(work_value)
            for completed_pages, logical_page in enumerate(
                range(plan.first_logical_page, plan.last_logical_page + 1),
                start=1,
            ):
                pdf_page = logical_page + plan.source.build_spec.cover_pdf_page_count
                variants = actual_renderer.render_page(
                    PageRenderRequest(
                        source=plan.source.path,
                        pdf_page=pdf_page,
                        logical_page=logical_page,
                        variant_widths=plan.variant_widths,
                        staging_root=staging_root,
                        work_root=work_root,
                        expected_media_box=plan.source.media_box,
                    )
                )
                records.extend(
                    _record_rendered_variants(
                        staging_root=staging_root,
                        logical_page=logical_page,
                        pdf_page=pdf_page,
                        expected_widths=plan.variant_widths,
                        variants=variants,
                    )
                )
                if progress is not None:
                    progress(completed_pages, plan.page_count)

        _assert_source_unchanged(plan.source, verify_checksum=True)
        manifest = _build_manifest(plan, records, tool_metadata)
        _write_manifest(staging_root, manifest)
        _verify_staged_output(staging_root, records)
        try:
            os.rename(staging_root, plan.output)
        except OSError as exc:
            raise MushafAssetError(
                f"Could not atomically promote staging output to {plan.output}: {exc}."
            ) from exc

    return BuildResult(output=plan.output, manifest=manifest, asset_count=len(records))


def _resolve_source(source_path: Path) -> Path:
    try:
        source = source_path.resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise MushafAssetError(f"Source PDF cannot be resolved: {source_path}.") from exc
    if not source.is_file():
        raise MushafAssetError("Source PDF must be a regular file.")
    if source.suffix.lower() != ".pdf":
        raise MushafAssetError("Source file must have a .pdf extension.")
    return source


def _resolve_output(output_path: Path, source: Path) -> Path:
    try:
        output = output_path.resolve(strict=False)
    except (OSError, RuntimeError) as exc:
        raise MushafAssetError(f"Output path cannot be resolved: {output_path}.") from exc
    if output == Path(output.anchor):
        raise MushafAssetError("Filesystem root cannot be used as the output path.")
    if output in (source, source.parent):
        raise MushafAssetError("Output path conflicts with the source PDF location.")
    if output.exists():
        raise MushafAssetError(f"Output path already exists: {output}.")
    existing_ancestor = output.parent
    while not existing_ancestor.exists():
        existing_ancestor = existing_ancestor.parent
    if not existing_ancestor.is_dir():
        raise MushafAssetError(f"Output path has a non-directory ancestor: {existing_ancestor}.")
    return output


def _normalize_checksum(value: str) -> str:
    checksum = value.strip().lower()
    if _SHA256_RE.fullmatch(checksum) is None:
        raise MushafAssetError("Expected SHA-256 must contain exactly 64 hexadecimal characters.")
    return checksum


def _validate_asset_build_spec(spec: MushafAssetBuildSpec) -> None:
    if not _EDITION_CODE_RE.fullmatch(spec.edition_code):
        raise MushafAssetError("Mushaf asset spec edition code must be a lowercase ASCII slug.")
    for label, value in (
        ("Arabic name", spec.name_ar),
        ("English name", spec.name_en),
        ("Russian name", spec.name_ru),
        ("riwayah", spec.riwayah),
        ("source name", spec.source_name),
        ("license name", spec.license_name),
    ):
        if not value.strip():
            raise MushafAssetError(f"Mushaf asset spec {label} is required.")
    _normalize_checksum(spec.expected_sha256)
    if any(
        value <= 0
        for value in (
            spec.surah_count,
            spec.juz_count,
            spec.expected_pdf_page_count,
            spec.logical_page_count,
        )
    ):
        raise MushafAssetError("Mushaf asset spec counts must be positive integers.")
    if spec.cover_pdf_page_count < 0:
        raise MushafAssetError("Mushaf asset spec cover page count cannot be negative.")
    if spec.cover_pdf_page_count + spec.logical_page_count != spec.expected_pdf_page_count:
        raise MushafAssetError(
            "Mushaf asset spec PDF page count must equal cover plus logical pages."
        )
    x_min, y_min, x_max, y_max = spec.expected_media_box
    if x_max <= x_min or y_max <= y_min:
        raise MushafAssetError("Mushaf asset spec MediaBox must have positive dimensions.")


def _spec_mapping(value: Any, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise MushafAssetError(f"Mushaf asset spec {field} must be a JSON object.")
    return value


def _spec_string(value: dict[str, Any], field: str) -> str:
    result = value.get(field)
    if not isinstance(result, str) or not result.strip():
        raise MushafAssetError(f"Mushaf asset spec {field} must be a non-empty string.")
    return result.strip()


def _spec_positive_int(value: dict[str, Any], field: str) -> int:
    result = value.get(field)
    if not isinstance(result, int) or isinstance(result, bool) or result <= 0:
        raise MushafAssetError(f"Mushaf asset spec {field} must be a positive integer.")
    return result


def _spec_nonnegative_int(value: dict[str, Any], field: str) -> int:
    result = value.get(field)
    if not isinstance(result, int) or isinstance(result, bool) or result < 0:
        raise MushafAssetError(f"Mushaf asset spec {field} must be a non-negative integer.")
    return result


def _normalize_variant_widths(values: Sequence[int]) -> tuple[int, ...]:
    widths = tuple(sorted(set(values)))
    if not widths:
        raise MushafAssetError("At least one WebP variant width is required.")
    for width in widths:
        if not MIN_VARIANT_WIDTH <= width <= MAX_VARIANT_WIDTH:
            raise MushafAssetError(
                f"Variant width must be between {MIN_VARIANT_WIDTH} and {MAX_VARIANT_WIDTH}."
            )
    return widths


def _source_fingerprint(path: Path) -> SourceFingerprint:
    try:
        stat = path.stat()
    except OSError as exc:
        raise MushafAssetError(f"Could not stat source PDF: {exc}.") from exc
    return SourceFingerprint(
        device=stat.st_dev,
        inode=stat.st_ino,
        size=stat.st_size,
        modified_ns=stat.st_mtime_ns,
    )


def _assert_source_unchanged(source: MushafSource, *, verify_checksum: bool) -> None:
    if _source_fingerprint(source.path) != source.fingerprint:
        raise MushafAssetError("Source PDF changed after validation.")
    if verify_checksum and not hmac.compare_digest(_sha256_file(source.path), source.sha256):
        raise MushafAssetError("Source PDF checksum changed after validation.")


def _parse_pdfinfo(
    output: str,
) -> tuple[
    dict[str, str],
    int,
    dict[int, tuple[float, float, float, float]],
    dict[int, int],
]:
    metadata: dict[str, str] = {}
    media_boxes: dict[int, tuple[float, float, float, float]] = {}
    rotations: dict[int, int] = {}
    for line in output.splitlines():
        media_match = _MEDIA_BOX_RE.match(line)
        if media_match is not None:
            page = int(media_match.group(1))
            media_boxes[page] = (
                float(media_match.group(2)),
                float(media_match.group(3)),
                float(media_match.group(4)),
                float(media_match.group(5)),
            )
            continue
        rotation_match = _ROTATION_RE.match(line)
        if rotation_match is not None:
            rotations[int(rotation_match.group(1))] = int(rotation_match.group(2))
            continue
        if ":" in line:
            key, value = line.split(":", maxsplit=1)
            metadata[key.strip()] = value.strip()
    try:
        page_count = int(metadata["Pages"])
    except (KeyError, ValueError) as exc:
        raise MushafAssetError("pdfinfo did not return a valid page count.") from exc
    return metadata, page_count, media_boxes, rotations


def _validate_pdfinfo(  # noqa: PLR0913
    *,
    metadata: Mapping[str, str],
    page_count: int,
    media_boxes: Mapping[int, tuple[float, float, float, float]],
    rotations: Mapping[int, int],
    actual_size: int,
    build_spec: MushafAssetBuildSpec,
) -> None:
    if page_count != build_spec.expected_pdf_page_count:
        raise MushafAssetError(
            f"Expected {build_spec.expected_pdf_page_count} PDF pages, got {page_count}."
        )
    for key, expected_value in build_spec.required_metadata.items():
        if metadata.get(key) != expected_value:
            raise MushafAssetError(f"Unexpected or missing PDF metadata field: {key}.")
    if metadata.get("Encrypted", "").lower() != "no":
        raise MushafAssetError("Encrypted source PDFs are not accepted.")
    if metadata.get("JavaScript", "").lower() != "no":
        raise MushafAssetError("PDFs containing JavaScript are not accepted.")
    try:
        reported_size = int(metadata["File size"].split(maxsplit=1)[0])
    except (KeyError, ValueError) as exc:
        raise MushafAssetError("pdfinfo did not return a valid file size.") from exc
    if reported_size != actual_size:
        raise MushafAssetError("pdfinfo file size does not match the source file.")

    expected_pages = set(range(1, build_spec.expected_pdf_page_count + 1))
    if set(media_boxes) != expected_pages:
        raise MushafAssetError("pdfinfo did not return a MediaBox for every PDF page.")
    if set(rotations) != expected_pages:
        raise MushafAssetError("pdfinfo did not return a rotation for every PDF page.")
    for page in expected_pages:
        media_box = media_boxes[page]
        if page > build_spec.cover_pdf_page_count and any(
            abs(actual - expected) > 0.01
            for actual, expected in zip(
                media_box,
                build_spec.expected_media_box,
                strict=True,
            )
        ):
            raise MushafAssetError(f"Unexpected MediaBox on PDF page {page}.")
        if rotations[page] != 0:
            raise MushafAssetError(f"Unexpected rotation on PDF page {page}.")


def _record_rendered_variants(
    *,
    staging_root: Path,
    logical_page: int,
    pdf_page: int,
    expected_widths: tuple[int, ...],
    variants: Sequence[RenderedVariant],
) -> list[AssetRecord]:
    by_width = {variant.width: variant for variant in variants}
    if len(by_width) != len(variants) or tuple(sorted(by_width)) != expected_widths:
        raise MushafAssetError(
            f"Renderer returned an unexpected variant set for logical page {logical_page}."
        )
    records: list[AssetRecord] = []
    for width in expected_widths:
        variant = by_width[width]
        expected_path = _asset_relative_path(logical_page, width)
        if variant.relative_path != expected_path:
            raise MushafAssetError("Renderer returned an unexpected asset path.")
        target = _safe_staging_path(staging_root, variant.relative_path)
        actual_width, actual_height = _read_webp_dimensions(target)
        if (actual_width, actual_height) != (variant.width, variant.height):
            raise MushafAssetError("Renderer-reported dimensions do not match the WebP file.")
        records.append(
            AssetRecord(
                logical_page=logical_page,
                pdf_page=pdf_page,
                variant=f"w{width}",
                width=actual_width,
                height=actual_height,
                sha256=_sha256_file(target),
                bytes=target.stat().st_size,
                path=variant.relative_path.as_posix(),
            )
        )
    return records


def _build_manifest(
    plan: BuildPlan,
    records: Sequence[AssetRecord],
    tool_metadata: Mapping[str, str],
) -> dict[str, object]:
    spec = plan.source.build_spec
    return {
        "schema_version": MANIFEST_SCHEMA_VERSION,
        "edition": {
            "code": spec.edition_code,
            "name_ar": spec.name_ar,
            "name_en": spec.name_en,
            "name_ru": spec.name_ru,
            "riwayah": spec.riwayah,
            "source_name": spec.source_name,
            "source_url": spec.source_url,
            "license_name": spec.license_name,
            "license_url": spec.license_url,
            "surah_count": spec.surah_count,
            "juz_count": spec.juz_count,
        },
        "source": {
            "filename": plan.source.path.name,
            "sha256": plan.source.sha256,
            "bytes": plan.source.bytes,
            "pdf_page_count": plan.source.pdf_page_count,
            "cover_pdf_pages": list(range(1, spec.cover_pdf_page_count + 1)),
            "logical_page_count": spec.logical_page_count,
            "media_box_points": {
                "x_min": plan.source.media_box[0],
                "y_min": plan.source.media_box[1],
                "x_max": plan.source.media_box[2],
                "y_max": plan.source.media_box[3],
            },
            "metadata": dict(sorted(plan.source.metadata.items())),
            "pdfinfo_version": plan.source.pdfinfo_version,
        },
        "render": {
            "first_logical_page": plan.first_logical_page,
            "last_logical_page": plan.last_logical_page,
            "page_count": plan.page_count,
            "variant_widths": list(plan.variant_widths),
            "asset_count": len(records),
            "format": "webp",
            "lossless": True,
            "tools": dict(sorted(tool_metadata.items())),
        },
        "assets": [record.as_manifest_value() for record in records],
    }


def _write_manifest(staging_root: Path, manifest: Mapping[str, object]) -> None:
    payload = (json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()
    manifest_path = _safe_staging_path(staging_root, Path("manifest.json"))
    with manifest_path.open("xb") as stream:
        stream.write(payload)
        stream.flush()
        os.fsync(stream.fileno())
    manifest_path.chmod(0o644)
    checksum_path = _safe_staging_path(staging_root, Path("manifest.sha256"))
    checksum_path.write_text(
        f"{hashlib.sha256(payload).hexdigest()}  manifest.json\n",
        encoding="ascii",
    )
    checksum_path.chmod(0o644)


def _verify_staged_output(staging_root: Path, records: Sequence[AssetRecord]) -> None:
    expected_files = {Path(record.path) for record in records}
    expected_files.update({Path("manifest.json"), Path("manifest.sha256")})
    actual_files: set[Path] = set()
    for candidate in staging_root.rglob("*"):
        if candidate.is_symlink():
            raise MushafAssetError("Staging output must not contain symbolic links.")
        if candidate.is_file():
            actual_files.add(candidate.relative_to(staging_root))
        elif candidate.is_dir():
            candidate.chmod(0o755)
    if actual_files != expected_files:
        raise MushafAssetError("Staging output contains missing or unexpected files.")
    for record in records:
        path = _safe_staging_path(staging_root, Path(record.path))
        if path.stat().st_size != record.bytes or _sha256_file(path) != record.sha256:
            raise MushafAssetError(f"Staged asset failed integrity validation: {record.path}.")
        if _read_webp_dimensions(path) != (record.width, record.height):
            raise MushafAssetError(f"Staged asset dimensions changed: {record.path}.")

    manifest_path = _safe_staging_path(staging_root, Path("manifest.json"))
    expected_manifest_line = f"{_sha256_file(manifest_path)}  manifest.json\n"
    checksum_path = _safe_staging_path(staging_root, Path("manifest.sha256"))
    if checksum_path.read_text(encoding="ascii") != expected_manifest_line:
        raise MushafAssetError("Manifest checksum verification failed.")


def _safe_staging_path(staging_root: Path, relative_path: Path) -> Path:
    if relative_path.is_absolute() or ".." in relative_path.parts:
        raise MushafAssetError("Asset path must be a safe relative path.")
    root = staging_root.resolve(strict=True)
    target = (root / relative_path).resolve(strict=False)
    if not target.is_relative_to(root):
        raise MushafAssetError("Asset path escapes the staging directory.")
    return target


def _asset_relative_path(logical_page: int, width: int) -> Path:
    return Path("pages") / f"{logical_page:03d}" / f"page-{logical_page:03d}-w{width:04d}.webp"


def _read_png_dimensions(path: Path) -> tuple[int, int]:
    try:
        with path.open("rb") as stream:
            header = stream.read(24)
    except OSError as exc:
        raise MushafAssetError(f"Could not read rendered PNG: {exc}.") from exc
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise MushafAssetError("pdftoppm did not produce a valid PNG file.")
    return struct.unpack(">II", header[16:24])


def _read_webp_dimensions(path: Path) -> tuple[int, int]:
    try:
        payload = path.read_bytes()
    except OSError as exc:
        raise MushafAssetError(f"Could not read rendered WebP: {exc}.") from exc
    if len(payload) < 20 or payload[:4] != b"RIFF" or payload[8:12] != b"WEBP":
        raise MushafAssetError("cwebp did not produce a valid WebP file.")
    offset = 12
    while offset + 8 <= len(payload):
        chunk_name = payload[offset : offset + 4]
        chunk_size = int.from_bytes(payload[offset + 4 : offset + 8], "little")
        chunk_start = offset + 8
        chunk_end = chunk_start + chunk_size
        if chunk_end > len(payload):
            break
        chunk = payload[chunk_start:chunk_end]
        if chunk_name == b"VP8X" and len(chunk) >= 10:
            width = int.from_bytes(chunk[4:7], "little") + 1
            height = int.from_bytes(chunk[7:10], "little") + 1
            return width, height
        if chunk_name == b"VP8L" and len(chunk) >= 5 and chunk[0] == 0x2F:
            packed = int.from_bytes(chunk[1:5], "little")
            return (packed & 0x3FFF) + 1, ((packed >> 14) & 0x3FFF) + 1
        if chunk_name == b"VP8 " and len(chunk) >= 10 and chunk[3:6] == b"\x9d\x01\x2a":
            width = int.from_bytes(chunk[6:8], "little") & 0x3FFF
            height = int.from_bytes(chunk[8:10], "little") & 0x3FFF
            return width, height
        offset = chunk_end + (chunk_size % 2)
    raise MushafAssetError("Could not determine WebP dimensions.")


def _tool_version(output: ProcessOutput) -> str:
    lines = [line.strip() for line in (output.stdout + "\n" + output.stderr).splitlines()]
    version = " | ".join(line for line in lines if line)
    if not version:
        raise MushafAssetError("External tool did not report its version.")
    return version[:500]


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            while chunk := stream.read(1024 * 1024):
                digest.update(chunk)
    except OSError as exc:
        raise MushafAssetError(f"Could not checksum file {path.name}: {exc}.") from exc
    return digest.hexdigest()
