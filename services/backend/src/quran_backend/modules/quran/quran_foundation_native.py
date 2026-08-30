from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import tempfile
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol, cast

from django.db import transaction
from django.utils import timezone

from quran_backend.modules.core.object_storage import (
    ImmutableObjectSpec,
    ObjectUploader,
    configured_object_uploader,
)
from quran_backend.modules.quran.models import (
    QuranFoundationMushaf,
    QuranFoundationMushafPage,
    QuranFoundationNativePageAsset,
    QuranFoundationNativePublication,
    QuranFoundationNativePublicationStatus,
)
from quran_backend.modules.quran.quran_foundation_rendering import (
    quran_foundation_rendering,
)

SUPPORTED_NATIVE_SOURCE_IDS = frozenset({1, 5, 19})
BLOCKED_NATIVE_SOURCE_IDS = frozenset({11})
DEFAULT_NATIVE_WIDTHS = (720, 1080, 1440)
MAX_PREPARE_BATCH_PAGES = 100
_SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
_VERSION_RE = re.compile(r"[a-z0-9]+(?:[a-z0-9._-]*[a-z0-9])?\Z")


class QuranFoundationNativeError(ValueError):
    """A native Mushaf rendition could not be prepared or published safely."""


@dataclass(frozen=True, slots=True)
class RenderedNativeAsset:
    page_number: int
    width: int
    height: int
    content_type: str
    path: Path


class QuranFoundationNativeRenderer(Protocol):
    @property
    def name(self) -> str: ...

    @property
    def version(self) -> str: ...

    def render_page(
        self,
        page: QuranFoundationMushafPage,
        *,
        widths: tuple[int, ...],
        output: Path,
    ) -> Sequence[RenderedNativeAsset]: ...


@dataclass(frozen=True, slots=True)
class NativePreparationResult:
    publication: QuranFoundationNativePublication
    requested_pages: int
    rendered_pages: int
    resumed_pages: int
    created_assets: int
    verified_assets: int


@dataclass(frozen=True, slots=True)
class NativePublicationResult:
    publication: QuranFoundationNativePublication
    activated: bool


class ExternalCommandQuranFoundationRenderer:
    """Adapter boundary for a pinned browser/font renderer installed by operations.

    The executable receives only a JSON request and an output directory. It must write
    ``manifest.json`` plus lossless WebP files; no command is invoked through a shell.
    """

    def __init__(
        self,
        executable: Path,
        *,
        timeout_seconds: int = 180,
    ) -> None:
        try:
            resolved = executable.resolve(strict=True)
        except (OSError, RuntimeError) as exc:
            raise QuranFoundationNativeError(
                "Native renderer executable cannot be resolved."
            ) from exc
        if not resolved.is_file() or not os.access(resolved, os.X_OK):
            raise QuranFoundationNativeError("Native renderer must be an executable file.")
        if timeout_seconds <= 0:
            raise QuranFoundationNativeError("Native renderer timeout must be positive.")
        self._executable = resolved
        self._timeout_seconds = timeout_seconds
        self._version = self._read_version()

    @property
    def name(self) -> str:
        return "qf-external-page-renderer"

    @property
    def version(self) -> str:
        return self._version

    def render_page(
        self,
        page: QuranFoundationMushafPage,
        *,
        widths: tuple[int, ...],
        output: Path,
    ) -> Sequence[RenderedNativeAsset]:
        request_path = output / "request.json"
        request_path.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "source": {
                        "resource_id": page.mushaf.source_id,
                        "source_checksum_sha256": page.mushaf.source_checksum_sha256,
                        "schema_version": page.mushaf.schema_version,
                        "font": quran_foundation_rendering(
                            page.mushaf.source_id,
                            page_number=page.page_number,
                        ),
                    },
                    "page": {
                        "number": page.page_number,
                        "lines_per_page": page.mushaf.lines_per_page,
                        "verse_mapping": page.verse_mapping,
                        "words": page.words,
                    },
                    "output": {"format": "webp", "lossless": True, "widths": widths},
                },
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            ),
            encoding="utf-8",
        )
        try:
            completed = subprocess.run(  # noqa: S603 - fixed argv, never a shell.
                (
                    os.fspath(self._executable),
                    "render-page",
                    "--request",
                    os.fspath(request_path),
                    "--output",
                    os.fspath(output),
                ),
                check=False,
                capture_output=True,
                timeout=self._timeout_seconds,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise QuranFoundationNativeError("Native renderer execution failed.") from exc
        if completed.returncode != 0:
            raise QuranFoundationNativeError("Native renderer returned a failure status.")
        return _load_external_manifest(page, widths=widths, output=output)

    def _read_version(self) -> str:
        try:
            completed = subprocess.run(  # noqa: S603 - fixed argv, never a shell.
                (os.fspath(self._executable), "--version"),
                check=False,
                capture_output=True,
                text=True,
                timeout=15,
            )
        except (OSError, subprocess.TimeoutExpired, UnicodeError) as exc:
            raise QuranFoundationNativeError("Could not inspect native renderer version.") from exc
        version = completed.stdout.strip()
        if completed.returncode != 0 or not version or len(version) > 96:
            raise QuranFoundationNativeError("Native renderer returned an invalid version.")
        return version


def prepare_quran_foundation_native_pages(  # noqa: PLR0913
    mushaf: QuranFoundationMushaf,
    *,
    render_version: str,
    renderer: QuranFoundationNativeRenderer,
    first_page: int,
    limit: int,
    widths: Sequence[int] = DEFAULT_NATIVE_WIDTHS,
    uploader: ObjectUploader | None = None,
    work_root: Path | None = None,
) -> NativePreparationResult:
    normalized_widths = _validate_preparation_request(
        mushaf,
        render_version=render_version,
        first_page=first_page,
        limit=limit,
        widths=widths,
    )
    publication = _get_or_create_publication(
        mushaf,
        render_version=render_version,
        renderer=renderer,
        widths=normalized_widths,
    )
    actual_uploader = uploader or configured_object_uploader()
    last_page = min(mushaf.pages_count, first_page + limit - 1)
    pages = list(
        mushaf.cached_pages.filter(page_number__range=(first_page, last_page)).order_by(
            "page_number"
        )
    )
    if len(pages) != last_page - first_page + 1:
        raise QuranFoundationNativeError(
            "Synced Mushaf pages are incomplete for the requested batch."
        )

    rendered_pages = 0
    resumed_pages = 0
    created_assets = 0
    verified_assets = 0
    try:
        for page in pages:
            if _page_is_complete(publication, page.page_number, normalized_widths):
                resumed_pages += 1
                continue
            with tempfile.TemporaryDirectory(dir=work_root) as temporary:
                output = Path(temporary)
                rendered = renderer.render_page(page, widths=normalized_widths, output=output)
                assets = _validate_rendered_assets(
                    rendered,
                    page_number=page.page_number,
                    widths=normalized_widths,
                    output=output,
                )
                for asset in assets:
                    checksum = _sha256_file(asset.path)
                    size_bytes = asset.path.stat().st_size
                    key = _native_storage_key(
                        publication,
                        page_number=page.page_number,
                        width=asset.width,
                        checksum_sha256=checksum,
                    )
                    stored = actual_uploader.upload_path(
                        asset.path,
                        ImmutableObjectSpec(
                            key=key,
                            content_type=asset.content_type,
                            size_bytes=size_bytes,
                            checksum_sha256=checksum,
                        ),
                    )
                    _record_asset(
                        publication,
                        asset=asset,
                        storage_key=key,
                        checksum_sha256=checksum,
                        size_bytes=size_bytes,
                    )
                    if stored.created:
                        created_assets += 1
                    else:
                        verified_assets += 1
                rendered_pages += 1
        _refresh_progress(publication)
        _verify_source_binding(publication)
    except Exception:
        _record_preparation_failure(publication)
        raise

    publication.refresh_from_db()
    return NativePreparationResult(
        publication=publication,
        requested_pages=len(pages),
        rendered_pages=rendered_pages,
        resumed_pages=resumed_pages,
        created_assets=created_assets,
        verified_assets=verified_assets,
    )


@transaction.atomic
def publish_quran_foundation_native_pages(
    mushaf: QuranFoundationMushaf,
    *,
    render_version: str,
    activate_existing: bool = False,
) -> NativePublicationResult:
    try:
        publication = (
            QuranFoundationNativePublication.objects.select_for_update()
            .select_related("mushaf")
            .get(mushaf=mushaf, render_version=render_version)
        )
    except QuranFoundationNativePublication.DoesNotExist as exc:
        raise QuranFoundationNativeError("Native render version has not been prepared.") from exc
    _verify_source_binding(publication)
    if publication.status == QuranFoundationNativePublicationStatus.PUBLISHED:
        if not activate_existing and publication.is_active:
            return NativePublicationResult(publication=publication, activated=False)
        if not activate_existing:
            raise QuranFoundationNativeError(
                "Published rollback candidates require explicit activate_existing."
            )
    elif activate_existing:
        raise QuranFoundationNativeError(
            "Only a previously published rendition can be reactivated."
        )
    else:
        _validate_complete_publication(publication)
        publication.manifest_checksum_sha256 = _publication_manifest_checksum(publication)
        publication.status = QuranFoundationNativePublicationStatus.PUBLISHED
        publication.published_at = timezone.now()

    QuranFoundationNativePublication.objects.filter(mushaf=mushaf, is_active=True).exclude(
        pk=publication.pk
    ).update(is_active=False)
    publication.is_active = True
    publication.last_error_code = ""
    publication.last_error_message = ""
    publication.full_clean()
    publication.save(
        update_fields=[
            "manifest_checksum_sha256",
            "status",
            "is_active",
            "published_at",
            "last_error_code",
            "last_error_message",
            "updated_at",
        ]
    )
    return NativePublicationResult(publication=publication, activated=True)


def active_native_publication(
    mushaf: QuranFoundationMushaf,
) -> QuranFoundationNativePublication | None:
    publications = getattr(mushaf, "_prefetched_objects_cache", {}).get("native_publications")
    candidates: list[QuranFoundationNativePublication]
    if publications is not None:
        candidates = cast(list[QuranFoundationNativePublication], list(publications))
    else:
        candidates = list(
            mushaf.native_publications.filter(is_active=True).prefetch_related("page_assets")
        )
    for publication in candidates:
        expected_assets = mushaf.pages_count * len(publication.required_widths)
        if (
            publication.is_active
            and publication.status == QuranFoundationNativePublicationStatus.PUBLISHED
            and publication.source_checksum_sha256 == mushaf.source_checksum_sha256
            and publication.expected_pages == mushaf.pages_count
            and publication.prepared_pages == mushaf.pages_count
            and publication.assets_count == expected_assets
            and publication.page_assets.count() == expected_assets
        ):
            return publication
    return None


def native_rendering_catalog(mushaf: QuranFoundationMushaf) -> dict[str, Any]:
    if mushaf.source_id == 11:
        return {
            "available": False,
            "status": "not_ready",
            "reason": "official_asset_base_url_unavailable",
            "assets": [],
        }
    if mushaf.source_id not in SUPPORTED_NATIVE_SOURCE_IDS:
        return {
            "available": False,
            "status": "not_ready",
            "reason": "unsupported_mushaf",
            "assets": [],
        }
    publication = active_native_publication(mushaf)
    if publication is None:
        return {
            "available": False,
            "status": "not_ready",
            "reason": _native_not_ready_reason(mushaf),
            "assets": [],
        }
    return {
        "available": True,
        "status": "ready",
        "render_version": publication.render_version,
        "source_checksum_sha256": publication.source_checksum_sha256,
        "manifest_checksum_sha256": publication.manifest_checksum_sha256,
        "page_count": publication.expected_pages,
        "assets": [
            {"format": "webp", "content_type": "image/webp", "width": width}
            for width in publication.required_widths
        ],
    }


def native_page_assets(
    page: QuranFoundationMushafPage,
    *,
    public_media_base_url: str,
) -> list[dict[str, Any]]:
    publication = active_native_publication(page.mushaf)
    if publication is None:
        return []
    assets = list(publication.page_assets.filter(page_number=page.page_number))
    if {asset.width for asset in assets} != set(publication.required_widths):
        return []
    base_url = public_media_base_url.rstrip("/")
    return [
        {
            "format": "webp",
            "content_type": asset.content_type,
            "width": asset.width,
            "height": asset.height,
            "bytes": asset.size_bytes,
            "sha256": asset.checksum_sha256,
            "url": f"{base_url}/{asset.storage_key}",
        }
        for asset in sorted(assets, key=lambda item: item.width)
    ]


def _validate_preparation_request(
    mushaf: QuranFoundationMushaf,
    *,
    render_version: str,
    first_page: int,
    limit: int,
    widths: Sequence[int],
) -> tuple[int, ...]:
    if mushaf.source_id == 11:
        raise QuranFoundationNativeError(
            "Resource 11 is blocked until an official asset base URL is configured."
        )
    if mushaf.source_id not in SUPPORTED_NATIVE_SOURCE_IDS:
        raise QuranFoundationNativeError("This Quran.Foundation Mushaf is not renderable.")
    if _VERSION_RE.fullmatch(render_version) is None:
        raise QuranFoundationNativeError("Render version must be a safe lowercase version token.")
    if first_page <= 0 or first_page > mushaf.pages_count:
        raise QuranFoundationNativeError("First page is outside the synced Mushaf.")
    if limit <= 0 or limit > MAX_PREPARE_BATCH_PAGES:
        raise QuranFoundationNativeError(
            f"Preparation limit must be between 1 and {MAX_PREPARE_BATCH_PAGES}."
        )
    if not widths or any(isinstance(width, bool) or not isinstance(width, int) for width in widths):
        raise QuranFoundationNativeError("Native widths must be positive integers.")
    normalized = tuple(sorted(set(widths)))
    if any(width < 320 or width > 4096 for width in normalized):
        raise QuranFoundationNativeError("Native widths must be between 320 and 4096 pixels.")
    return normalized


@transaction.atomic
def _get_or_create_publication(
    mushaf: QuranFoundationMushaf,
    *,
    render_version: str,
    renderer: QuranFoundationNativeRenderer,
    widths: tuple[int, ...],
) -> QuranFoundationNativePublication:
    publication, created = (
        QuranFoundationNativePublication.objects.select_for_update().get_or_create(
            mushaf=mushaf,
            render_version=render_version,
            defaults={
                "renderer_name": renderer.name,
                "renderer_version": renderer.version,
                "source_checksum_sha256": mushaf.source_checksum_sha256,
                "expected_pages": mushaf.pages_count,
                "required_widths": list(widths),
            },
        )
    )
    expected = (
        publication.renderer_name == renderer.name,
        publication.renderer_version == renderer.version,
        publication.source_checksum_sha256 == mushaf.source_checksum_sha256,
        publication.expected_pages == mushaf.pages_count,
        publication.required_widths == list(widths),
    )
    if not all(expected):
        raise QuranFoundationNativeError(
            "Render version already exists with different source, renderer or widths."
        )
    if publication.status in {
        QuranFoundationNativePublicationStatus.PUBLISHED,
        QuranFoundationNativePublicationStatus.WITHDRAWN,
    }:
        raise QuranFoundationNativeError("Published or withdrawn renditions are immutable.")
    if not created and publication.status == QuranFoundationNativePublicationStatus.FAILED:
        publication.status = QuranFoundationNativePublicationStatus.PREPARING
        publication.last_error_code = ""
        publication.last_error_message = ""
        publication.save(
            update_fields=["status", "last_error_code", "last_error_message", "updated_at"]
        )
    publication.full_clean()
    return publication


def _page_is_complete(
    publication: QuranFoundationNativePublication,
    page_number: int,
    widths: tuple[int, ...],
) -> bool:
    return set(
        publication.page_assets.filter(page_number=page_number).values_list("width", flat=True)
    ) == set(widths)


def _validate_rendered_assets(
    rendered: Sequence[RenderedNativeAsset],
    *,
    page_number: int,
    widths: tuple[int, ...],
    output: Path,
) -> list[RenderedNativeAsset]:
    assets = list(rendered)
    if {asset.width for asset in assets} != set(widths) or len(assets) != len(widths):
        raise QuranFoundationNativeError(
            "Renderer did not return every requested width exactly once."
        )
    resolved_output = output.resolve(strict=True)
    for asset in assets:
        try:
            path = asset.path.resolve(strict=True)
        except (OSError, RuntimeError) as exc:
            raise QuranFoundationNativeError("Rendered asset cannot be resolved.") from exc
        if (
            asset.page_number != page_number
            or asset.height <= 0
            or asset.content_type != "image/webp"
            or not path.is_relative_to(resolved_output)
            or asset.path.is_symlink()
            or not path.is_file()
        ):
            raise QuranFoundationNativeError("Renderer returned an invalid WebP asset.")
        if not _is_webp(path):
            raise QuranFoundationNativeError("Renderer output is not a WebP file.")
    return sorted(assets, key=lambda asset: asset.width)


@transaction.atomic
def _record_asset(
    publication: QuranFoundationNativePublication,
    *,
    asset: RenderedNativeAsset,
    storage_key: str,
    checksum_sha256: str,
    size_bytes: int,
) -> None:
    existing = (
        QuranFoundationNativePageAsset.objects.select_for_update()
        .filter(
            publication=publication,
            page_number=asset.page_number,
            width=asset.width,
        )
        .first()
    )
    values = (
        asset.height,
        asset.content_type,
        storage_key,
        checksum_sha256,
        size_bytes,
    )
    if existing is not None:
        current = (
            existing.height,
            existing.content_type,
            existing.storage_key,
            existing.checksum_sha256,
            existing.size_bytes,
        )
        if current != values:
            raise QuranFoundationNativeError(
                "Existing native asset conflicts with rendered output."
            )
        return
    row = QuranFoundationNativePageAsset(
        publication=publication,
        page_number=asset.page_number,
        width=asset.width,
        height=asset.height,
        content_type=asset.content_type,
        storage_key=storage_key,
        checksum_sha256=checksum_sha256,
        size_bytes=size_bytes,
    )
    row.full_clean()
    row.save()


def _refresh_progress(publication: QuranFoundationNativePublication) -> None:
    expected_widths = set(publication.required_widths)
    page_widths: dict[int, set[int]] = {}
    for page_number, width in publication.page_assets.values_list("page_number", "width"):
        page_widths.setdefault(page_number, set()).add(width)
    publication.prepared_pages = sum(widths == expected_widths for widths in page_widths.values())
    publication.assets_count = publication.page_assets.count()
    publication.last_error_code = ""
    publication.last_error_message = ""
    publication.save(
        update_fields=[
            "prepared_pages",
            "assets_count",
            "last_error_code",
            "last_error_message",
            "updated_at",
        ]
    )


def _record_preparation_failure(publication: QuranFoundationNativePublication) -> None:
    QuranFoundationNativePublication.objects.filter(pk=publication.pk).update(
        status=QuranFoundationNativePublicationStatus.FAILED,
        is_active=False,
        last_error_code="page_preparation_failed",
        last_error_message="Страница не подготовлена; подробности доступны в журнале команды.",
        updated_at=timezone.now(),
    )


def _verify_source_binding(publication: QuranFoundationNativePublication) -> None:
    publication.mushaf.refresh_from_db(fields=["source_checksum_sha256", "pages_count"])
    if (
        publication.source_checksum_sha256 != publication.mushaf.source_checksum_sha256
        or publication.expected_pages != publication.mushaf.pages_count
    ):
        raise QuranFoundationNativeError(
            "Synced Mushaf source changed; create a new render version."
        )


def _validate_complete_publication(publication: QuranFoundationNativePublication) -> None:
    expected = {
        (page_number, width)
        for page_number in range(1, publication.expected_pages + 1)
        for width in publication.required_widths
    }
    actual = set(publication.page_assets.values_list("page_number", "width"))
    cached_pages = set(publication.mushaf.cached_pages.values_list("page_number", flat=True))
    if actual != expected or cached_pages != set(range(1, publication.expected_pages + 1)):
        raise QuranFoundationNativeError(
            "Native publication is incomplete and cannot be advertised to clients."
        )
    _refresh_progress(publication)


def _publication_manifest_checksum(publication: QuranFoundationNativePublication) -> str:
    assets = list(
        publication.page_assets.order_by("page_number", "width").values(
            "page_number",
            "width",
            "height",
            "content_type",
            "storage_key",
            "checksum_sha256",
            "size_bytes",
        )
    )
    payload = {
        "schema_version": 1,
        "mushaf_source_id": publication.mushaf.source_id,
        "source_checksum_sha256": publication.source_checksum_sha256,
        "render_version": publication.render_version,
        "renderer": {
            "name": publication.renderer_name,
            "version": publication.renderer_version,
        },
        "expected_pages": publication.expected_pages,
        "required_widths": publication.required_widths,
        "assets": assets,
    }
    return hashlib.sha256(
        json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def _native_storage_key(
    publication: QuranFoundationNativePublication,
    *,
    page_number: int,
    width: int,
    checksum_sha256: str,
) -> str:
    if (
        _SHA256_RE.fullmatch(checksum_sha256) is None
        or _SHA256_RE.fullmatch(publication.source_checksum_sha256) is None
    ):
        raise QuranFoundationNativeError("Native asset checksum is invalid.")
    key = (
        f"quran/quran-foundation/native/{publication.mushaf.environment}/"
        f"mushaf-{publication.mushaf.source_id}/{publication.source_checksum_sha256}/"
        f"{publication.render_version}/page-{page_number:03d}/"
        f"w{width}-{checksum_sha256}.webp"
    )
    if ".." in key.split("/") or key.startswith("/") or "\\" in key:
        raise QuranFoundationNativeError("Native asset storage key is unsafe.")
    return key


def _load_external_manifest(
    page: QuranFoundationMushafPage,
    *,
    widths: tuple[int, ...],
    output: Path,
) -> list[RenderedNativeAsset]:
    manifest_path = output / "manifest.json"
    try:
        payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise QuranFoundationNativeError("Native renderer manifest is invalid.") from exc
    if (
        not isinstance(payload, dict)
        or payload.get("schema_version") != 1
        or payload.get("page_number") != page.page_number
        or payload.get("source_checksum_sha256") != page.mushaf.source_checksum_sha256
        or payload.get("lossless") is not True
        or not isinstance(payload.get("assets"), list)
    ):
        raise QuranFoundationNativeError("Native renderer manifest does not match the request.")
    assets: list[RenderedNativeAsset] = []
    for value in payload["assets"]:
        if not isinstance(value, Mapping):
            raise QuranFoundationNativeError("Native renderer asset manifest is invalid.")
        try:
            relative_path = Path(str(value["path"]))
            asset = RenderedNativeAsset(
                page_number=page.page_number,
                width=int(value["width"]),
                height=int(value["height"]),
                content_type=str(value["content_type"]),
                path=output / relative_path,
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise QuranFoundationNativeError("Native renderer asset manifest is invalid.") from exc
        if relative_path.is_absolute() or ".." in relative_path.parts:
            raise QuranFoundationNativeError("Native renderer asset path is unsafe.")
        assets.append(asset)
    if {asset.width for asset in assets} != set(widths):
        raise QuranFoundationNativeError("Native renderer manifest omitted requested widths.")
    return assets


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _is_webp(path: Path) -> bool:
    try:
        header = path.read_bytes()[:12]
    except OSError:
        return False
    return len(header) == 12 and header[:4] == b"RIFF" and header[8:12] == b"WEBP"


def _native_not_ready_reason(mushaf: QuranFoundationMushaf) -> str:
    active = mushaf.native_publications.filter(is_active=True).first()
    if active is None:
        return "complete_publication_required"
    if active.source_checksum_sha256 != mushaf.source_checksum_sha256:
        return "source_changed"
    return "incomplete_publication"
