from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any

from django.db import transaction

from quran_backend.modules.core.content_revalidation import enqueue_quran_content_change
from quran_backend.modules.core.object_storage import (
    ImmutableObjectSpec,
    ObjectUploader,
    configured_object_uploader,
)
from quran_backend.modules.quran.models import (
    MushafPage,
    PublicationStatus,
    QuranEdition,
    QuranEditionVersion,
)

EXPECTED_LOGICAL_PAGE_COUNT = 604
MAX_MANIFEST_BYTES = 10 * 1024 * 1024
EDITION_CODE_PATTERN = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")


class MushafPublicationError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class PreparedMushafPage:
    number: int
    image_width: int
    image_height: int
    checksum_sha256: str
    asset_variants: list[dict[str, object]]


@dataclass(frozen=True, slots=True)
class PreparedMushafCatalog:
    manifest_path: Path
    checksum_sha256: str
    pages: list[PreparedMushafPage]
    logical_page_count: int
    cover_pdf_page_count: int
    edition_metadata: dict[str, Any]


@dataclass(frozen=True, slots=True)
class PublicationResult:
    edition: QuranEdition
    version: QuranEditionVersion
    created: bool
    activated: bool


@dataclass(frozen=True, slots=True)
class MushafUploadResult:
    assets: int
    created: int
    verified_existing: int


def load_prepared_mushaf_catalog(
    manifest_path: Path,
    *,
    media_root: Path,
) -> PreparedMushafCatalog:
    manifest = _resolve_manifest(manifest_path)
    root = manifest.parent
    resolved_media_root = media_root.resolve(strict=True)
    if not root.is_relative_to(resolved_media_root):
        raise MushafPublicationError("Prepared assets must be located inside MEDIA_ROOT.")

    payload = manifest.read_bytes()
    if len(payload) > MAX_MANIFEST_BYTES:
        raise MushafPublicationError("Prepared asset manifest is too large.")
    manifest_checksum = hashlib.sha256(payload).hexdigest()
    _validate_manifest_checksum(manifest, manifest_checksum)

    try:
        data = json.loads(payload)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise MushafPublicationError("Prepared asset manifest is not valid JSON.") from exc
    if not isinstance(data, dict):
        raise MushafPublicationError("Prepared asset manifest must be a JSON object.")
    logical_page_count, cover_pdf_page_count, edition_metadata = _validate_manifest_shape(data)

    assets = data.get("assets")
    if not isinstance(assets, list):
        raise MushafPublicationError("Prepared asset manifest has no assets array.")

    variants_by_page: dict[int, list[dict[str, object]]] = {}
    for asset in assets:
        logical_page, variant = _validate_asset(
            asset,
            asset_root=root,
            media_root=resolved_media_root,
            logical_page_count=logical_page_count,
            cover_pdf_page_count=cover_pdf_page_count,
        )
        variants_by_page.setdefault(logical_page, []).append(variant)

    expected_pages = set(range(1, logical_page_count + 1))
    if set(variants_by_page) != expected_pages:
        raise MushafPublicationError(
            f"Prepared assets must cover logical pages 1-{logical_page_count} exactly."
        )

    pages: list[PreparedMushafPage] = []
    for number in range(1, logical_page_count + 1):
        variants = sorted(variants_by_page[number], key=lambda item: int(str(item["width"])))
        largest = variants[-1]
        pages.append(
            PreparedMushafPage(
                number=number,
                image_width=int(str(largest["width"])),
                image_height=int(str(largest["height"])),
                checksum_sha256=str(largest["sha256"]),
                asset_variants=variants,
            )
        )

    return PreparedMushafCatalog(
        manifest_path=manifest,
        checksum_sha256=manifest_checksum,
        pages=pages,
        logical_page_count=logical_page_count,
        cover_pdf_page_count=cover_pdf_page_count,
        edition_metadata=edition_metadata,
    )


def upload_prepared_mushaf_catalog(
    catalog: PreparedMushafCatalog,
    *,
    media_root: Path,
    uploader: ObjectUploader | None = None,
) -> MushafUploadResult:
    try:
        resolved_media_root = media_root.resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise MushafPublicationError("MEDIA_ROOT cannot be resolved.") from exc
    actual_uploader = uploader or configured_object_uploader()
    created = 0
    verified_existing = 0
    assets = 0
    for page in catalog.pages:
        for variant in page.asset_variants:
            key = str(variant["path"])
            try:
                source = (resolved_media_root / Path(*PurePosixPath(key).parts)).resolve(
                    strict=True
                )
                size_bytes = int(str(variant["bytes"]))
            except (KeyError, OSError, RuntimeError, TypeError, ValueError) as exc:
                raise MushafPublicationError(
                    f"Prepared asset cannot be resolved for upload: {key}."
                ) from exc
            if not source.is_relative_to(resolved_media_root):
                raise MushafPublicationError(f"Prepared asset escaped MEDIA_ROOT: {key}.")
            stored = actual_uploader.upload_path(
                source,
                ImmutableObjectSpec(
                    key=key,
                    content_type="image/webp",
                    size_bytes=size_bytes,
                    checksum_sha256=str(variant["sha256"]),
                ),
            )
            assets += 1
            if stored.created:
                created += 1
            else:
                verified_existing += 1
    return MushafUploadResult(
        assets=assets,
        created=created,
        verified_existing=verified_existing,
    )


@transaction.atomic
def publish_prepared_mushaf_catalog(
    catalog: PreparedMushafCatalog,
    *,
    edition_code: str,
    version_value: str,
    activate: bool,
) -> PublicationResult:
    if not EDITION_CODE_PATTERN.fullmatch(edition_code):
        raise MushafPublicationError("Quran edition code must be a lowercase ASCII slug.")
    manifest_edition_code = str(catalog.edition_metadata.get("code", "")).strip()
    if manifest_edition_code and manifest_edition_code != edition_code:
        raise MushafPublicationError(
            "Requested edition code does not match the prepared asset manifest."
        )
    edition_defaults = _edition_defaults(catalog.edition_metadata)
    edition, _ = QuranEdition.objects.get_or_create(
        code=edition_code,
        defaults=edition_defaults,
    )
    _validate_edition_identity(edition, edition_defaults)
    version = (
        QuranEditionVersion.objects.select_for_update()
        .filter(
            edition=edition,
            version=version_value,
        )
        .first()
    )
    created = version is None
    if version is None:
        version = QuranEditionVersion.objects.create(
            edition=edition,
            version=version_value,
            checksum_sha256=catalog.checksum_sha256,
            page_count=catalog.logical_page_count,
            surah_count=int(catalog.edition_metadata.get("surah_count", 114)),
            juz_count=int(catalog.edition_metadata.get("juz_count", 30)),
        )
        MushafPage.objects.bulk_create(
            [
                MushafPage(
                    edition_version=version,
                    number=page.number,
                    image_width=page.image_width,
                    image_height=page.image_height,
                    checksum_sha256=page.checksum_sha256,
                    asset_variants=page.asset_variants,
                )
                for page in catalog.pages
            ],
            batch_size=200,
        )
    else:
        _validate_existing_version(version, catalog)

    activated = False
    if activate:
        if version.status != PublicationStatus.PUBLISHED:
            version.publish()
            version.full_clean()
            version.save(update_fields=["status", "published_at", "updated_at"])
        if edition.active_version_id != version.id:
            edition.active_version = version
            edition.full_clean()
            edition.save(update_fields=["active_version", "updated_at"])
        activated = True

    if activated:
        enqueue_quran_content_change(
            action="activated",
            edition=edition.code,
            version=version.version,
        )

    return PublicationResult(
        edition=edition,
        version=version,
        created=created,
        activated=activated,
    )


def _resolve_manifest(manifest_path: Path) -> Path:
    try:
        manifest = manifest_path.resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise MushafPublicationError(f"Manifest cannot be resolved: {manifest_path}.") from exc
    if not manifest.is_file() or manifest.name != "manifest.json":
        raise MushafPublicationError("Expected a regular file named manifest.json.")
    if manifest.is_symlink():
        raise MushafPublicationError("Manifest symlinks are not accepted.")
    return manifest


def _validate_manifest_checksum(manifest: Path, actual_checksum: str) -> None:
    checksum_path = manifest.with_name("manifest.sha256")
    try:
        checksum_line = checksum_path.read_text(encoding="ascii")
    except (OSError, UnicodeDecodeError) as exc:
        raise MushafPublicationError("Could not read manifest.sha256.") from exc
    if checksum_line != f"{actual_checksum}  manifest.json\n":
        raise MushafPublicationError("Manifest checksum verification failed.")


def _validate_manifest_shape(data: dict[str, Any]) -> tuple[int, int, dict[str, Any]]:
    source = data.get("source")
    render = data.get("render")
    schema_version = data.get("schema_version")
    if schema_version not in (1, 2) or not isinstance(source, dict) or not isinstance(render, dict):
        raise MushafPublicationError("Unsupported prepared asset manifest.")
    if schema_version == 1:
        logical_page_count = EXPECTED_LOGICAL_PAGE_COUNT
        cover_pdf_page_count = 1
        edition_metadata: dict[str, Any] = {}
    else:
        logical_page_count = _positive_manifest_int(
            source.get("logical_page_count"),
            "source.logical_page_count",
        )
        cover_pdf_pages = source.get("cover_pdf_pages")
        if not isinstance(cover_pdf_pages, list) or cover_pdf_pages != list(
            range(1, len(cover_pdf_pages) + 1)
        ):
            raise MushafPublicationError(
                "Source manifest cover_pdf_pages must be a leading consecutive sequence."
            )
        cover_pdf_page_count = len(cover_pdf_pages)
        edition_metadata = _validate_manifest_edition(data.get("edition"))
    if source.get("logical_page_count") != logical_page_count:
        raise MushafPublicationError(
            f"Source manifest must describe {logical_page_count} logical pages."
        )
    expected_render = {
        "first_logical_page": 1,
        "last_logical_page": logical_page_count,
        "page_count": logical_page_count,
        "format": "webp",
        "lossless": True,
    }
    if any(render.get(key) != value for key, value in expected_render.items()):
        raise MushafPublicationError("Only a complete lossless WebP render can be published.")
    return logical_page_count, cover_pdf_page_count, edition_metadata


def _validate_asset(
    asset: object,
    *,
    asset_root: Path,
    media_root: Path,
    logical_page_count: int,
    cover_pdf_page_count: int,
) -> tuple[int, dict[str, object]]:
    if not isinstance(asset, dict):
        raise MushafPublicationError("Prepared asset entry is malformed.")
    try:
        logical_page = int(asset["logical_page"])
        pdf_page = int(asset["pdf_page"])
        dimensions = asset["dimensions"]
        relative_value = str(asset["path"])
        expected_bytes = int(asset["bytes"])
        expected_sha256 = str(asset["sha256"])
    except (KeyError, TypeError, ValueError) as exc:
        raise MushafPublicationError("Prepared asset entry is malformed.") from exc
    if not isinstance(dimensions, dict):
        raise MushafPublicationError("Prepared asset dimensions are malformed.")
    try:
        width = int(dimensions["width"])
        height = int(dimensions["height"])
    except (KeyError, TypeError, ValueError) as exc:
        raise MushafPublicationError("Prepared asset dimensions are malformed.") from exc
    if (
        not 1 <= logical_page <= logical_page_count
        or pdf_page != logical_page + cover_pdf_page_count
        or asset.get("format") != "webp"
        or width <= 0
        or height <= 0
        or expected_bytes <= 0
        or len(expected_sha256) != 64
    ):
        raise MushafPublicationError("Prepared asset entry failed validation.")

    relative_path = PurePosixPath(relative_value)
    if relative_path.is_absolute() or ".." in relative_path.parts or "\\" in relative_value:
        raise MushafPublicationError("Prepared asset path is unsafe.")
    asset_path = (asset_root / Path(*relative_path.parts)).resolve(strict=True)
    if (
        not asset_path.is_relative_to(asset_root)
        or not asset_path.is_file()
        or asset_path.is_symlink()
    ):
        raise MushafPublicationError("Prepared asset path is invalid.")
    if asset_path.stat().st_size != expected_bytes or _sha256_file(asset_path) != expected_sha256:
        raise MushafPublicationError(f"Prepared asset integrity check failed: {relative_value}.")

    public_path = asset_path.relative_to(media_root).as_posix()
    return logical_page, {
        "format": "webp",
        "width": width,
        "height": height,
        "path": public_path,
        "sha256": expected_sha256,
        "bytes": expected_bytes,
    }


def _validate_existing_version(
    version: QuranEditionVersion,
    catalog: PreparedMushafCatalog,
) -> None:
    if version.checksum_sha256 != catalog.checksum_sha256:
        raise MushafPublicationError("Edition version exists with a different manifest checksum.")
    pages = list(version.pages.order_by("number"))
    if len(pages) != catalog.logical_page_count:
        raise MushafPublicationError("Edition version exists with an incomplete page catalog.")
    if any(page.number != expected for expected, page in enumerate(pages, start=1)):
        raise MushafPublicationError("Edition version page numbering is invalid.")


def _validate_manifest_edition(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise MushafPublicationError("Prepared asset manifest has no edition metadata.")
    required_strings = (
        "code",
        "name_ar",
        "name_en",
        "name_ru",
        "riwayah",
        "source_name",
        "license_name",
    )
    if any(
        not isinstance(value.get(field), str) or not value[field].strip()
        for field in required_strings
    ):
        raise MushafPublicationError("Prepared asset manifest edition metadata is incomplete.")
    if not EDITION_CODE_PATTERN.fullmatch(str(value["code"])):
        raise MushafPublicationError("Prepared asset manifest edition code is unsafe.")
    for field in ("surah_count", "juz_count"):
        _positive_manifest_int(value.get(field), f"edition.{field}")
    return dict(value)


def _positive_manifest_int(value: Any, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise MushafPublicationError(f"Prepared asset manifest {label} must be positive.")
    return value


def _edition_defaults(metadata: dict[str, Any]) -> dict[str, Any]:
    if metadata:
        return {
            "name_ar": str(metadata["name_ar"]),
            "name_en": str(metadata["name_en"]),
            "name_ru": str(metadata["name_ru"]),
            "riwayah": str(metadata["riwayah"]),
            "source_name": str(metadata["source_name"]),
            "source_url": str(metadata.get("source_url", "")),
            "license_name": str(metadata["license_name"]),
            "license_url": str(metadata.get("license_url", "")),
        }
    return {
        "name_ar": "مصحف المدينة",
        "name_en": "Madani Mushaf",
        "name_ru": "Мединский мусхаф",
        "riwayah": "Hafs 'an Asim",
        "source_name": "Tanzil + quranpedia/quran-svg + pinned KFQC PDF",
        "source_url": "https://tanzil.net/download/",
        "license_name": "Tanzil CC BY 3.0; regions CC0 1.0; KFQC digital-use terms",
        "license_url": "https://tanzil.net/docs/Text_License",
    }


def _validate_edition_identity(
    edition: QuranEdition,
    expected: dict[str, Any],
) -> None:
    for field in (
        "name_ar",
        "name_en",
        "name_ru",
        "riwayah",
        "source_name",
        "source_url",
        "license_name",
        "license_url",
    ):
        if getattr(edition, field) != expected[field]:
            raise MushafPublicationError(
                f"Existing Quran edition metadata does not match the manifest: {field}."
            )


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
