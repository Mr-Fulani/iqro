# Russian messages for the editor intentionally contain Cyrillic letters.
# ruff: noqa: RUF001
"""Imports the tajweed course snapshot, compiles its documents and publishes versions.

Flow, as for the prayer course: import (draft, documents compiled) or a draft
copied from another version in the admin → the owner edits the draft in the
admin editor → signs off → publish (previous version withdrawn, documents
compiled again with the publication stamp, web content revalidated).
"""

from __future__ import annotations

import copy
import hashlib
import json
from collections.abc import Mapping
from typing import Any

from django.db import transaction
from django.utils import timezone

from quran_backend.modules.alerts.services import course_version_event
from quran_backend.modules.core.content_revalidation import enqueue_tajweed_content_change
from quran_backend.modules.courses.links import LinkChecker
from quran_backend.modules.tajweed.course import (
    MARKUP_TEXTS,
    TajweedCourseError,
    compile_course_document,
    course_video_files,
    snapshot_checksum,
    validate_course_snapshot,
)
from quran_backend.modules.tajweed.models import (
    TAJWEED_COURSE_LANGUAGES,
    TajweedCourse,
    TajweedCourseDocument,
    TajweedCourseStatus,
    TajweedCourseVersion,
)


def compile_course_version(version: TajweedCourseVersion) -> list[TajweedCourseDocument]:
    """(Re)builds the document of every language from the stored snapshot."""
    documents = []
    for language in TAJWEED_COURSE_LANGUAGES:
        payload = compile_course_document(
            version.snapshot,
            language=language,
            course_meta={
                "slug": version.course.slug,
                "version": version.version,
                "reviewed_at": version.reviewed_at.isoformat() if version.reviewed_at else None,
                "published_at": version.published_at.isoformat() if version.published_at else None,
                "checksum_sha256": version.checksum_sha256,
            },
        )
        encoded = json.dumps(
            payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")
        ).encode()
        document, _ = TajweedCourseDocument.objects.update_or_create(
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
def import_tajweed_course(snapshot: Mapping[str, Any]) -> TajweedCourseVersion:
    """Creates a draft version; re-importing the same content is a no-op."""
    validate_course_snapshot(snapshot)
    checksum = snapshot_checksum(snapshot)
    course_data = snapshot["course"]
    course, _ = TajweedCourse.objects.get_or_create(slug=course_data["slug"])
    existing = TajweedCourseVersion.objects.filter(
        course=course, version=course_data["version"]
    ).first()
    if existing is not None:
        if existing.checksum_sha256 != checksum:
            raise TajweedCourseError(
                [
                    f"Версия {course_data['version']} уже импортирована, но содержимое "
                    "изменилось. Поднимите course.version."
                ]
            )
        return existing
    version = TajweedCourseVersion.objects.create(
        course=course,
        version=course_data["version"],
        schema_version=snapshot["schema_version"],
        snapshot=dict(snapshot),
        checksum_sha256=checksum,
    )
    compile_course_version(version)
    return version


def save_course_draft(version: TajweedCourseVersion, snapshot: Mapping[str, Any]) -> None:
    """Stores an edited draft: the structure must hold, translations may still be missing."""
    if version.status != TajweedCourseStatus.DRAFT or version.is_signed:
        raise TajweedCourseError(["Менять можно только неподписанный черновик."])
    validate_course_snapshot(snapshot, complete=False)
    version.snapshot = dict(snapshot)
    version.checksum_sha256 = snapshot_checksum(snapshot)
    version.save(update_fields=["snapshot", "checksum_sha256", "updated_at"])
    compile_course_version(version)


def new_videos(version: TajweedCourseVersion) -> set[str]:
    """SHA-256 of the video and dub files students get anew with this version."""
    active = version.course.active_version
    before = (
        course_video_files(active.snapshot)
        if active is not None and active.pk != version.pk
        else set()
    )
    return course_video_files(version.snapshot) - before


@transaction.atomic
def mark_tajweed_watched(version: TajweedCourseVersion, *, sha256: str, watched: bool) -> None:
    """The owner's «Просмотрено» on one new video or dub of an unsigned draft."""
    version = TajweedCourseVersion.objects.select_for_update().get(pk=version.pk)
    if version.status != TajweedCourseStatus.DRAFT or version.is_signed:
        raise TajweedCourseError(["Отмечать можно только неподписанный черновик."])
    if sha256 not in new_videos(version):
        raise TajweedCourseError(["Этого файла нет среди новых видео и озвучек версии."])
    marks = set(version.watched_videos) - {sha256}
    if watched:
        marks.add(sha256)
    version.watched_videos = sorted(marks)
    version.save(update_fields=["watched_videos", "updated_at"])


MARKUP_LABELS = {"explanation": "объяснение правила", "how": "как читать"}


def markup_problems(snapshot: Mapping[str, Any]) -> list[str]:
    """Brackets that are not a link or a note and links that lead nowhere, lesson by lesson."""
    lessons = snapshot.get("lessons") or []
    links = LinkChecker(tajweed_lessons=[str(lesson.get("slug", "")) for lesson in lessons])
    return [
        f"Урок «{lesson.get('slug', '')}»: {MARKUP_LABELS[field]} [{language}], {problem}"
        for lesson in lessons
        for field in MARKUP_TEXTS
        for language in TAJWEED_COURSE_LANGUAGES
        for problem in links.problems(str((lesson.get(field) or {}).get(language) or ""))
    ]


def sign_tajweed_course(version: TajweedCourseVersion, user: Any, note: str = "") -> None:
    """The owner's sign-off of a complete draft: every text in every language, every link
    leading somewhere, every new video watched."""
    validate_course_snapshot(version.snapshot)
    problems = markup_problems(version.snapshot)
    if problems:
        raise TajweedCourseError(problems)
    if new_videos(version) - set(version.watched_videos):
        raise TajweedCourseError(["Отметьте «Просмотрено» у каждого нового видео и озвучки."])
    version.sign(user, note)
    compile_course_version(version)


@transaction.atomic
def copy_tajweed_course(source: TajweedCourseVersion, version: str) -> TajweedCourseVersion:
    """A new draft with the content of `source`, which stays as it is."""
    snapshot = copy.deepcopy(source.snapshot)
    snapshot["course"]["version"] = version
    draft = TajweedCourseVersion.objects.create(
        course=source.course,
        version=version,
        schema_version=source.schema_version,
        snapshot=snapshot,
        checksum_sha256=snapshot_checksum(snapshot),
    )
    compile_course_version(draft)
    course_version_event(draft, "draft")
    return draft


@transaction.atomic
def publish_tajweed_course(version: TajweedCourseVersion) -> TajweedCourseVersion:
    """Publishes a signed draft and makes it the course's active version."""
    version = (
        TajweedCourseVersion.objects.select_for_update().select_related("course").get(pk=version.pk)
    )
    if version.status != TajweedCourseStatus.DRAFT:
        raise TajweedCourseError(["Опубликовать можно только черновик."])
    if not version.is_signed:
        raise TajweedCourseError(["Версию нужно сначала подписать."])
    validate_course_snapshot(version.snapshot)
    course = TajweedCourse.objects.select_for_update().get(pk=version.course_id)
    previous = course.active_version
    if previous is not None:
        previous.status = TajweedCourseStatus.WITHDRAWN
        previous.save(update_fields=["status", "updated_at"])
    version.status = TajweedCourseStatus.PUBLISHED
    version.published_at = timezone.now()
    version.save(update_fields=["status", "published_at", "updated_at"])
    compile_course_version(version)
    course.active_version = version
    course.save(update_fields=["active_version", "updated_at"])
    enqueue_tajweed_content_change(action="activated", course=course.slug, version=version.version)
    course_version_event(version, "published")
    return version
