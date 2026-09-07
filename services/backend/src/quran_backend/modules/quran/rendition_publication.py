"""Immutable staging rendition publication, independent of canonical/audio imports."""

from __future__ import annotations

import hashlib
import json
import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from quran_backend.modules.core.object_storage import (
    ImmutableObjectSpec,
    ObjectUploader,
    configured_object_uploader,
)
from quran_backend.modules.quran.models import (
    Ayah,
    AyahPageRegion,
    MushafRendition,
    MushafRenditionPage,
    MushafRenditionRelease,
    PublicationStatus,
    QuranEdition,
    QuranEditionVersion,
)

SOURCE_COMMIT = "1d040f68d284f8e6db515157f8425abfefd78df6"


def require(value: object, message: str) -> None:
    if not value:
        raise ValueError(message)


def checked_file(root: Path, spec: dict[str, Any]) -> Path:
    name = spec["path"]
    require(
        isinstance(name, str) and Path(name).name == name and "\\" not in name, "Unsafe bundle path"
    )
    assert isinstance(name, str)
    file = root / name
    require(not file.is_symlink() and file.is_file(), "Missing regular bundle file")
    require(0 < file.stat().st_size == spec["bytes"] <= 4 * 1024 * 1024, "Invalid bundle file size")
    with file.open("rb") as stream:
        checksum = hashlib.file_digest(stream, "sha256").hexdigest()
    require(checksum == spec["sha256"], "Bundle file checksum mismatch")
    return file


def webp_dimensions(data: bytes) -> tuple[int, int]:
    require(
        len(data) >= 25
        and data[:4] == b"RIFF"
        and data[8:12] == b"WEBP"
        and int.from_bytes(data[4:8], "little") == len(data) - 8,
        "Invalid WebP container",
    )
    dimensions = None
    offset = 12
    while offset + 8 <= len(data):
        kind = data[offset : offset + 4]
        size = int.from_bytes(data[offset + 4 : offset + 8], "little")
        start = offset + 8
        require(start + size <= len(data), "Truncated WebP chunk")
        require(kind not in (b"VP8 ", b"ANIM", b"ANMF"), "Only static lossless WebP accepted")
        if kind == b"VP8L":
            require(
                dimensions is None and size >= 5 and data[start] == 0x2F,
                "Invalid lossless WebP frame",
            )
            bits = int.from_bytes(data[start + 1 : start + 5], "little")
            require(bits >> 29 == 0, "Unknown WebP version")
            dimensions = ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1)
        offset = start + size + size % 2
    require(dimensions is not None and offset == len(data), "Missing WebP frame")
    assert dimensions is not None
    return dimensions


@dataclass(frozen=True)
class PreparedRendition:
    manifest: dict[str, Any]
    checksum: str
    canonical: QuranEditionVersion
    pages: list[dict[str, Any]]
    uploads: list[tuple[Path, ImmutableObjectSpec]]


def load_manifest(manifest_path: Path) -> tuple[dict[str, Any], str]:
    require(
        getattr(settings, "MUSHAF_STAGING_PREVIEWS", False),
        "This command only enables staging previews; production publication is forbidden",
    )
    require(not manifest_path.is_symlink() and manifest_path.is_file(), "Missing bundle manifest")
    root = manifest_path.parent.resolve()
    require(manifest_path.stat().st_size <= 10 * 1024 * 1024, "Manifest too large")
    raw = manifest_path.read_bytes()
    checksum = hashlib.sha256(raw).hexdigest()
    require(
        (root / "manifest.sha256").read_text() == f"{checksum}  manifest.json\n",
        "Manifest checksum mismatch",
    )
    manifest = json.loads(raw)
    require(
        manifest.get("schema_version") == 1
        and manifest.get("status") == "prepared"
        and manifest.get("publication_scope") == "staging"
        and manifest.get("source_commit") == SOURCE_COMMIT
        and manifest.get("canonical_edition") == "madani-hafs"
        and manifest.get("edition") == "qcf-v2-hafs"
        and manifest.get("page_count") == 604
        and manifest.get("widths") == [720, 1440, 2160],
        "Unsupported complete rendition",
    )
    version = manifest.get("version", "")
    require(
        isinstance(version, str) and re.fullmatch(r"[a-zA-Z0-9._-]{1,64}", version),
        "Invalid version",
    )
    entries = manifest["pages"]
    require([entry["page"] for entry in entries] == list(range(1, 605)), "Incomplete page coverage")
    return manifest, checksum


def prepare_rendition(manifest_path: Path) -> PreparedRendition:
    manifest, checksum = load_manifest(manifest_path)
    root = manifest_path.parent.resolve()
    version = manifest["version"]
    entries = manifest["pages"]
    edition = QuranEdition.objects.select_related("active_version").get(code="madani-hafs")
    canonical = edition.active_version
    require(
        canonical and canonical.status == PublicationStatus.PUBLISHED, "Canonical Quran unavailable"
    )
    assert canonical is not None
    references = {
        (s, a): str(pk)
        for s, a, pk in Ayah.objects.filter(
            surah__edition_version=canonical,
        ).values_list("surah__number", "number", "id")
    }
    require(len(references) == 6236, "Canonical Hafs corpus is incomplete")
    expected_mapping: dict[int, set[tuple[int, int]]] = {}
    for page, surah, ayah in AyahPageRegion.objects.filter(
        page__edition_version=canonical
    ).values_list(
        "page__number",
        "ayah__surah__number",
        "ayah__number",
    ):
        expected_mapping.setdefault(page, set()).add((surah, ayah))
    prepared = []
    uploads = []
    all_verses = set()
    for entry in entries:
        number = entry["page"]
        geometry_path = checked_file(root, entry["geometry"])
        geometry = json.loads(geometry_path.read_bytes())
        require(
            geometry.get("number") == number
            and geometry.get("edition") == manifest["edition"]
            and geometry.get("status") == "draft"
            and geometry.get("assets") == []
            and geometry.get("image_width") == 1000
            and geometry.get("image_height") == 1600,
            "Geometry page identity mismatch",
        )
        regions = []
        page_verses = set()
        boxes: list[list[float]] = []
        for index, region in enumerate(geometry["regions"]):
            key = (region["ayah"]["surah"], region["ayah"]["number"])
            require(key in references, "Unknown canonical ayah")
            bounds = [float(region[k]) for k in ("x", "y", "width", "height")]
            x, y, w, h = bounds
            require(
                all(math.isfinite(v) for v in bounds)
                and 0 <= x < x + w <= 1
                and 0 <= y < y + h <= 1,
                "Invalid ayah bounds",
            )
            require(
                region["reading_order"] == index and region["polygon"] == [],
                "Unsupported region order/polygon",
            )
            for bx, by, bw, bh in boxes:
                require(
                    min(x + w, bx + bw) - max(x, bx) <= 1e-7
                    or min(y + h, by + bh) - max(y, by) <= 1e-7,
                    "Overlapping ayah regions",
                )
            boxes.append(bounds)
            # Decimal strings keep offline checksums stable across Python/Dart JSON encoders.
            regions.append(
                {
                    "id": f"{version}:{number}:{index}",
                    "reading_order": index,
                    "ayah": {"id": references[key], "surah": key[0], "number": key[1]},
                    "polygon": [],
                    **{
                        k: f"{v:.8f}"
                        for k, v in zip(("x", "y", "width", "height"), bounds, strict=True)
                    },
                }
            )
            page_verses.add(key)
        require(
            page_verses and page_verses == expected_mapping.get(number),
            f"Page {number} differs from canonical navigation mapping",
        )
        all_verses.update(page_verses)
        require(
            [a["width"] for a in entry["assets"]] == manifest["widths"], "Incomplete page widths"
        )
        assets = []
        for spec in entry["assets"]:
            file = checked_file(root, spec)
            require(
                spec.get("lossless") is True
                and webp_dimensions(file.read_bytes()) == (spec["width"], spec["height"]),
                "Raster dimensions/format differ",
            )
            require(spec["height"] * 5 == spec["width"] * 8, "Distorted page ratio")
            storage_key = (
                f"quran/mushaf-renditions/staging/{manifest['edition']}/"
                f"{version}/{checksum}/{file.name}"
            )
            assets.append(
                {
                    "path": storage_key,
                    "format": "webp",
                    "width": spec["width"],
                    "height": spec["height"],
                    "bytes": spec["bytes"],
                    "sha256": spec["sha256"],
                }
            )
            uploads.append(
                (
                    file,
                    ImmutableObjectSpec(
                        key=storage_key,
                        content_type="image/webp",
                        size_bytes=spec["bytes"],
                        checksum_sha256=spec["sha256"],
                    ),
                )
            )
        prepared.append(
            {
                "number": number,
                "image_width": 1000,
                "image_height": 1600,
                "checksum_sha256": entry["geometry"]["sha256"],
                "assets": assets,
                "regions": regions,
            }
        )
    require(all_verses == set(references), "Missing canonical ayahs")
    return PreparedRendition(manifest, checksum, canonical, prepared, uploads)


def publish_rendition(
    manifest_path: Path,
    *,
    uploader: ObjectUploader | None = None,
    validate_only: bool = False,
) -> MushafRenditionRelease | None:
    bundle = prepare_rendition(manifest_path)
    if validate_only:
        return None
    manifest, checksum, canonical = bundle.manifest, bundle.checksum, bundle.canonical
    version = manifest["version"]
    prepared = bundle.pages
    actual_uploader = uploader or configured_object_uploader()
    # No public pointers until every immutable object has been uploaded/verified.
    for file, spec in bundle.uploads:
        actual_uploader.upload_path(file, spec)
    with transaction.atomic():
        locked_edition = QuranEdition.objects.select_for_update().get(pk=canonical.edition_id)
        require(
            locked_edition.active_version_id == canonical.pk,
            "Canonical version changed during upload",
        )
        rendition, _ = MushafRendition.objects.get_or_create(
            code=manifest["edition"],
            defaults={
                "names": {
                    "ru": "QCF V2 · IQRO",
                    "en": "QCF V2 · IQRO",
                    "ar": "مصحف QCF V2",
                    "tr": "QCF V2 · IQRO",
                },
            },
        )
        rendition = MushafRendition.objects.select_for_update().get(pk=rendition.pk)
        release, created = MushafRenditionRelease.objects.get_or_create(
            rendition=rendition,
            version=version,
            defaults={
                "canonical_version": canonical,
                "checksum_sha256": checksum,
                "source_commit": SOURCE_COMMIT,
                "source_url": f"https://github.com/JMApps/mymushaf/tree/{SOURCE_COMMIT}",
                "renderer": manifest["renderer"],
                "widths": manifest["widths"],
                "page_count": 604,
                "staging_only": True,
            },
        )
        require(
            release.checksum_sha256 == checksum
            and release.canonical_version_id == canonical.pk
            and release.staging_only,
            "Existing rendition version differs",
        )
        if created:
            MushafRenditionPage.objects.bulk_create(
                [MushafRenditionPage(release=release, **page) for page in prepared], batch_size=100
            )
        else:
            stored = list(
                release.pages.values(
                    "number", "image_width", "image_height", "checksum_sha256", "assets", "regions"
                )
            )
            require(stored == prepared, "Existing stored page bundle differs")
        release.published_at = release.published_at or timezone.now()
        release.save(update_fields=["published_at", "updated_at"])
        rendition.active_release = release
        rendition.save(update_fields=["active_release", "updated_at"])
    return release
