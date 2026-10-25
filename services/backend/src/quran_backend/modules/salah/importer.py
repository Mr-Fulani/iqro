"""Imports a course snapshot, compiles its documents and publishes versions.

Flow: import (draft, media uploaded, documents compiled) or a draft copied
from another version in the admin → the owner edits the draft in the admin
editor → signs off → publish (previous version withdrawn, documents compiled
again with the publication stamp, web content revalidated).
"""

from __future__ import annotations

import copy
import hashlib
import json
import struct
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from django.db import transaction
from django.utils import timezone

from quran_backend.modules.alerts.services import course_version_event
from quran_backend.modules.audio.player_background_upload import player_background_uploader
from quran_backend.modules.audio.serializers import public_audio_url
from quran_backend.modules.core.content_revalidation import enqueue_salah_content_change
from quran_backend.modules.core.object_storage import ImmutableObjectSpec, ObjectUploader
from quran_backend.modules.salah.compiler import compile_document
from quran_backend.modules.salah.models import (
    SALAH_LANGUAGES,
    SalahCompiledDocument,
    SalahCourse,
    SalahCourseVersion,
    SalahMediaAsset,
    SalahPublicationStatus,
)
from quran_backend.modules.salah.resolvers import FormulaResolver
from quran_backend.modules.salah.snapshot import (
    SalahSnapshotError,
    snapshot_checksum,
    validate_snapshot,
)

# A step image is decoded on a phone as the user turns pages; keep it light.
MAX_IMAGE_BYTES = 200 * 1024
MAX_AUDIO_BYTES = 2 * 1024 * 1024
CONTENT_TYPES = {".webp": "image/webp", ".m4a": "audio/mp4", ".mp3": "audio/mpeg"}
PUBLIC_REVIEWER = "IQRO"


def webp_size(data: bytes) -> tuple[int, int] | None:
    """Width and height from a WebP header (VP8, VP8L or VP8X), without Pillow."""
    if len(data) < 30 or data[:4] != b"RIFF" or data[8:12] != b"WEBP":
        return None
    chunk = data[12:16]
    if chunk == b"VP8X":
        width = 1 + int.from_bytes(data[24:27], "little")
        height = 1 + int.from_bytes(data[27:30], "little")
        return width, height
    if chunk == b"VP8L":
        bits = struct.unpack("<I", data[21:25])[0]
        return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
    if chunk == b"VP8 ":
        width, height = struct.unpack("<HH", data[26:30])
        return width & 0x3FFF, height & 0x3FFF
    return None


def store_media(
    version: SalahCourseVersion,
    key: str,
    path: Path,
    uploader: ObjectUploader,
    *,
    duration_ms: int | None = None,
) -> SalahMediaAsset:
    """Stores one file under an immutable key; a new file for the key replaces the old."""
    data = path.read_bytes()
    content_type = CONTENT_TYPES[path.suffix.lower()]
    size = webp_size(data) if content_type == "image/webp" else None
    checksum = hashlib.sha256(data).hexdigest()
    folder = f"salah/{version.course.slug}/{version.version}"
    stored = uploader.upload_path(
        path,
        ImmutableObjectSpec(
            key=f"{folder}/{key}-{checksum[:12]}{path.suffix.lower()}",
            content_type=content_type,
            size_bytes=len(data),
            checksum_sha256=checksum,
        ),
    )
    asset, _ = SalahMediaAsset.objects.update_or_create(
        version=version,
        key=key,
        defaults={
            "object_key": stored.key,
            "content_type": content_type,
            "width": size[0] if size else None,
            "height": size[1] if size else None,
            "duration_ms": duration_ms,
            "bytes": len(data),
            "sha256": checksum,
        },
    )
    return asset


def _upload_media(
    version: SalahCourseVersion,
    snapshot: Mapping[str, Any],
    data_dir: Path,
    uploader: ObjectUploader,
) -> None:
    """Uploads the media files present in git; missing ones are added later in the admin."""
    problems: list[str] = []
    for asset in snapshot.get("media", []):
        path = data_dir / asset["file"]
        content_type = CONTENT_TYPES.get(path.suffix.lower())
        if content_type is None:
            problems.append(f"Медиа «{asset['key']}»: формат {path.suffix} не поддерживается.")
            continue
        if not path.is_file():
            continue
        data = path.read_bytes()
        limit = MAX_IMAGE_BYTES if content_type.startswith("image/") else MAX_AUDIO_BYTES
        if len(data) > limit:
            problems.append(f"Медиа «{asset['key']}»: {len(data)} байт, допустимо до {limit}.")
            continue
        if content_type == "image/webp" and webp_size(data) is None:
            problems.append(f"Медиа «{asset['key']}»: файл не WebP.")
            continue
        store_media(version, asset["key"], path, uploader)
    if problems:
        raise SalahSnapshotError(problems)


def _media_documents(version: SalahCourseVersion, language: str) -> dict[str, dict[str, Any]]:
    sources = {asset["key"]: asset for asset in version.snapshot.get("media", [])}
    media: dict[str, dict[str, Any]] = {}
    for asset in version.media.all():
        entry: dict[str, Any] = {
            "url": public_audio_url(asset.object_key),
            "bytes": asset.bytes,
            "sha256": asset.sha256,
        }
        if asset.width and asset.height:
            entry["width"] = asset.width
            entry["height"] = asset.height
        source = sources.get(asset.key, {})
        alt = source.get("alt", {}).get(language)
        if alt:
            entry["alt"] = alt
        if source.get("scene"):
            # The picture is a still of this 3D pose; older clients just show the picture.
            entry["scene"] = dict(source["scene"])
        media[asset.key] = entry
    return media


def compile_version(version: SalahCourseVersion) -> list[SalahCompiledDocument]:
    """(Re)builds the document of every language from the stored snapshot."""
    snapshot = version.snapshot
    media_by_language = {
        language: _media_documents(version, language) for language in SALAH_LANGUAGES
    }
    resolver = FormulaResolver(snapshot.get("formulas", []), media_by_language["ru"])
    documents = []
    for language in SALAH_LANGUAGES:
        payload = compile_document(
            snapshot,
            language=language,
            course_meta={
                "slug": version.course.slug,
                "version": version.version,
                "methodology": version.methodology,
                "source_title": version.source_title.get(language, ""),
                "reviewed_by": PUBLIC_REVIEWER if version.is_signed else None,
                "reviewed_at": version.reviewed_at.isoformat() if version.reviewed_at else None,
                "published_at": version.published_at.isoformat() if version.published_at else None,
                "checksum_sha256": version.checksum_sha256,
            },
            formulas=resolver.resolve(language),
            media=media_by_language[language],
        )
        encoded = json.dumps(
            payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")
        ).encode()
        document, _ = SalahCompiledDocument.objects.update_or_create(
            version=version,
            language=language,
            defaults={
                "payload": payload,
                "checksum_sha256": hashlib.sha256(encoded).hexdigest(),
                "bytes": len(encoded),
            },
        )
        documents.append(document)
    return documents


@transaction.atomic
def import_salah_snapshot(
    snapshot: Mapping[str, Any],
    *,
    data_dir: Path,
    uploader: ObjectUploader | None = None,
) -> SalahCourseVersion:
    """Creates a draft version; re-importing the same content is a no-op."""
    validate_snapshot(snapshot)
    checksum = snapshot_checksum(snapshot)
    course_data = snapshot["course"]
    course, _ = SalahCourse.objects.get_or_create(slug=course_data["slug"])
    existing = SalahCourseVersion.objects.filter(
        course=course, version=course_data["version"]
    ).first()
    if existing is not None:
        if existing.checksum_sha256 != checksum:
            raise SalahSnapshotError(
                [
                    f"Версия {course_data['version']} уже импортирована, но содержимое "
                    "изменилось. Поднимите course.version."
                ]
            )
        return existing
    version = SalahCourseVersion.objects.create(
        course=course,
        version=course_data["version"],
        schema_version=snapshot["schema_version"],
        methodology=course_data["methodology"],
        source_title=dict(course_data["source_title"]),
        snapshot=dict(snapshot),
        checksum_sha256=checksum,
    )
    _upload_media(version, snapshot, data_dir, uploader or player_background_uploader())
    compile_version(version)
    return version


def sign_salah_version(version: SalahCourseVersion, user: Any, note: str = "") -> None:
    """The owner's sign-off of a complete draft: every text in every language."""
    validate_snapshot(version.snapshot)
    version.sign(user, note)
    compile_version(version)


@transaction.atomic
def copy_salah_version(source: SalahCourseVersion, version: str) -> SalahCourseVersion:
    """A new draft with the content and the stored files of `source`, which stays as it is."""
    snapshot = copy.deepcopy(source.snapshot)
    snapshot["course"]["version"] = version
    draft = SalahCourseVersion.objects.create(
        course=source.course,
        version=version,
        schema_version=source.schema_version,
        methodology=source.methodology,
        source_title=dict(source.source_title),
        snapshot=snapshot,
        checksum_sha256=snapshot_checksum(snapshot),
    )
    # Stored objects are immutable, so the draft points at the same files.
    SalahMediaAsset.objects.bulk_create(
        SalahMediaAsset(
            version=draft,
            key=asset.key,
            object_key=asset.object_key,
            content_type=asset.content_type,
            width=asset.width,
            height=asset.height,
            duration_ms=asset.duration_ms,
            bytes=asset.bytes,
            sha256=asset.sha256,
        )
        for asset in source.media.all()
    )
    compile_version(draft)
    course_version_event(draft, "draft")
    return draft


@transaction.atomic
def publish_salah_version(version: SalahCourseVersion) -> SalahCourseVersion:
    """Publishes a signed draft and makes it the course's active version."""
    version = (
        SalahCourseVersion.objects.select_for_update().select_related("course").get(pk=version.pk)
    )
    if version.status != SalahPublicationStatus.DRAFT:
        raise SalahSnapshotError(["Опубликовать можно только черновик."])
    if not version.is_signed:
        raise SalahSnapshotError(
            ["Версию нужно сначала подписать: религиозная проверка обязательна."]
        )
    validate_snapshot(version.snapshot)
    course = SalahCourse.objects.select_for_update().get(pk=version.course_id)
    previous = course.active_version
    if previous is not None:
        previous.status = SalahPublicationStatus.WITHDRAWN
        previous.save(update_fields=["status", "updated_at"])
    version.status = SalahPublicationStatus.PUBLISHED
    version.published_at = timezone.now()
    version.save(update_fields=["status", "published_at", "updated_at"])
    compile_version(version)
    course.active_version = version
    course.save(update_fields=["active_version", "updated_at"])
    enqueue_salah_content_change(action="activated", course=course.slug, version=version.version)
    course_version_event(version, "published")
    return version
