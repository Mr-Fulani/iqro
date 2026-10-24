# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""A course's snapshot, its readiness per language and the documents clients get.

The snapshot keeps the source texts of every language; the document of one
language is what `GET /api/v1/courses/{slug}` returns (docs/courses/README.md),
without `published_at` and `checksum_sha256`, which are added on the way out.
"""

from __future__ import annotations

import hashlib
import json
import math
from dataclasses import dataclass
from typing import Any

from quran_backend.modules.audio.serializers import public_audio_url
from quran_backend.modules.core.editorial.markup import parse_notes, plain_text
from quran_backend.modules.courses.lesson_media import (
    default_media,
    media_changes,
    media_payload,
    media_snapshot,
)
from quran_backend.modules.courses.models import (
    COURSE_LANGUAGES,
    MAX_NOTES_CHARS,
    MAX_SOURCES_CHARS,
    Course,
    CourseVideo,
)

SCHEMA_VERSION = 1
WORDS_PER_MINUTE = 180
MAX_DOCUMENT_BYTES = 2 * 1024 * 1024
COURSE_TEXTS = ("title", "summary", "source")
LESSON_TEXTS = ("title", "summary", "notes", "sources")
LANGUAGE_NAMES = {"ru": "русский", "en": "английский", "ar": "арабский", "tr": "турецкий"}
CHANGED = {
    "title": "изменено название",
    "summary": "изменено «Кратко»",
    "source": "изменены «Автор и источники»",
    "notes": "изменён конспект",
    "sources": "изменены источники",
    "minutes": "изменены минуты",
    "slug": "изменён адрес",
}


def editor_languages() -> list[str]:
    """Russian first: a course is written in it and translated from it."""
    return sorted(COURSE_LANGUAGES, key=lambda code: (code != "ru", code))


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def checksum(value: Any) -> str:
    return hashlib.sha256(canonical_json(value)).hexdigest()


def build_snapshot(course: Course) -> dict[str, Any]:
    """The course as it is now in the admin, every language."""
    cover = None
    if course.cover_object_key:
        cover = {
            "object_key": course.cover_object_key,
            "thumb_object_key": course.cover_thumb_object_key,
            "width": course.cover_width,
            "height": course.cover_height,
        }
    lessons = []
    for lesson in course.lessons.order_by("position", "created_at").select_related("video"):
        item: dict[str, Any] = {
            "id": str(lesson.pk),
            "slug": lesson.slug,
            "minutes": lesson.minutes,
            "video": video_snapshot(lesson.video),
        }
        media = media_snapshot(
            lesson.media, has_video=lesson.video is not None, languages=COURSE_LANGUAGES
        )
        # Only a lesson with slides or banners has the key: the checksums of the rest stay.
        if media != default_media(has_video=lesson.video is not None):
            item["media"] = media
        for field in LESSON_TEXTS:
            item[field] = {language: lesson.text(field, language) for language in COURSE_LANGUAGES}
        item["checksum"] = checksum(item)
        lessons.append(item)
    return {
        "course": {
            "slug": course.slug,
            "cover": cover,
            **{
                field: {language: course.text(field, language) for language in COURSE_LANGUAGES}
                for field in COURSE_TEXTS
            },
        },
        "lessons": lessons,
    }


def video_snapshot(video: CourseVideo | None) -> dict[str, Any] | None:
    """The lesson's video file, its poster and the current dub of each other language."""
    if video is None:
        return None
    return {
        "sha256": video.sha256,
        "object_key": video.object_key,
        "bytes": video.bytes,
        "duration_ms": video.duration_ms,
        "width": video.width,
        "height": video.height,
        "spoken_language": video.spoken_language,
        "poster": {
            "object_key": video.poster_object_key,
            "small_object_key": video.poster_small_object_key,
            "width": video.poster_width,
            "height": video.poster_height,
        },
        "dubs": {
            dub.language: {
                "sha256": dub.sha256,
                "object_key": dub.object_key,
                "bytes": dub.bytes,
                "duration_ms": dub.duration_ms,
            }
            for dub in video.dubs.filter(retired_at__isnull=True).order_by("language")
        },
    }


def lesson_media(lesson: dict[str, Any]) -> list[dict[str, Any]]:
    """The media blocks of a snapshot's lesson; a lesson without them shows its video alone."""
    media = lesson.get("media")
    return default_media(has_video=lesson["video"] is not None) if media is None else media


def snapshot_files(snapshot: dict[str, Any]) -> set[str]:
    """SHA-256 of every video and dub file the snapshot's lessons show."""
    found: set[str] = set()
    for lesson in snapshot.get("lessons", []):
        video = lesson.get("video")
        if video:
            found.add(video["sha256"])
            found.update(dub["sha256"] for dub in video.get("dubs", {}).values())
    return found


def shown_files(snapshot: dict[str, Any], languages: list[str]) -> set[str]:
    """SHA-256 of the files the documents of these languages give students."""
    found: set[str] = set()
    for lesson in snapshot.get("lessons", []):
        video = lesson.get("video")
        if video:
            dubs = video.get("dubs", {})
            found.update(
                dubs[language]["sha256"] if language in dubs else video["sha256"]
                for language in languages
            )
    return found


@dataclass(frozen=True, slots=True)
class Problem:
    """What a language lacks; `lesson` is the lesson id to link to, or "" for the course."""

    text: str
    lesson: str = ""


def readiness(snapshot: dict[str, Any]) -> dict[str, list[Problem]]:
    """Problems per language; a language without problems may be released."""
    result: dict[str, list[Problem]] = {}
    course = snapshot["course"]
    lessons = snapshot["lessons"]
    for language in COURSE_LANGUAGES:
        problems = []
        if not course["title"][language].strip():
            problems.append(Problem("Нет названия курса."))
        if not course["summary"][language].strip():
            problems.append(Problem("Нет описания «Кратко»."))
        if not lessons:
            problems.append(Problem("В курсе нет ни одной темы."))
        for number, lesson in enumerate(lessons, start=1):
            name = f"Тема {number}"
            title = lesson["title"][language].strip()
            if title:
                name += f" «{title}»"
            if not title:
                problems.append(Problem(f"{name}: нет названия.", lesson["id"]))
            notes = lesson["notes"][language]
            if not notes.strip():
                problems.append(Problem(f"{name}: нет конспекта.", lesson["id"]))
            elif len(notes) > MAX_NOTES_CHARS:
                problems.append(
                    Problem(f"{name}: конспект длиннее {MAX_NOTES_CHARS} знаков.", lesson["id"])
                )
            if len(lesson["sources"][language]) > MAX_SOURCES_CHARS:
                problems.append(
                    Problem(f"{name}: источники длиннее {MAX_SOURCES_CHARS} знаков.", lesson["id"])
                )
        result[language] = problems
    return result


def untranslated(snapshot: dict[str, Any], language: str) -> bool:
    """Nothing of the course is written on this language yet."""
    texts = [snapshot["course"][field][language] for field in COURSE_TEXTS]
    texts += [lesson[field][language] for lesson in snapshot["lessons"] for field in LESSON_TEXTS]
    return not any(text.strip() for text in texts)


def ready_languages(snapshot: dict[str, Any]) -> list[str]:
    return [language for language, problems in readiness(snapshot).items() if not problems]


def cover_payload(cover: dict[str, Any] | None) -> dict[str, Any] | None:
    if not cover:
        return None
    return {
        "url": public_audio_url(cover["object_key"]),
        "thumb_url": public_audio_url(cover["thumb_object_key"]),
        "width": cover["width"],
        "height": cover["height"],
    }


def video_payload(video: dict[str, Any] | None, language: str) -> dict[str, Any] | None:
    """The file students of this language get: its dub if there is one, else the video."""
    if not video:
        return None
    dub = video.get("dubs", {}).get(language)
    file = dub or video
    poster = video["poster"]
    return {
        "url": public_audio_url(file["object_key"]),
        "bytes": file["bytes"],
        "duration_ms": file["duration_ms"],
        "width": video["width"],
        "height": video["height"],
        "spoken_language": language if dub else video["spoken_language"],
        "poster": {
            "url": public_audio_url(poster["object_key"]),
            "small_url": public_audio_url(poster["small_object_key"]),
            "width": poster["width"],
            "height": poster["height"],
        },
    }


def lesson_minutes(
    lesson: dict[str, Any], blocks: list[dict[str, Any]], video: dict[str, Any] | None
) -> int:
    if lesson["minutes"]:
        return int(lesson["minutes"])
    words = len(plain_text(blocks).split())
    video_minutes = video["duration_ms"] / 60_000 if video else 0
    return max(1, math.ceil(video_minutes + words / WORDS_PER_MINUTE))


def build_document(
    snapshot: dict[str, Any], *, language: str, version: str, languages: list[str]
) -> dict[str, Any]:
    """The document of one language, without `published_at` and `checksum_sha256`."""
    course = snapshot["course"]
    lessons = []
    for number, lesson in enumerate(snapshot["lessons"], start=1):
        blocks = parse_notes(lesson["notes"][language])
        video = video_payload(lesson["video"], language)
        lessons.append(
            {
                "slug": lesson["slug"],
                "number": number,
                "title": lesson["title"][language].strip(),
                "summary": lesson["summary"][language].strip(),
                "minutes": lesson_minutes(lesson, blocks, video),
                "video": video,
                "media": media_payload(
                    lesson_media(lesson),
                    language=language,
                    video=video,
                    public_url=public_audio_url,
                ),
                "notes": blocks,
                "sources": [
                    line.strip()
                    for line in lesson["sources"][language].splitlines()
                    if line.strip()
                ],
            }
        )
    return {
        "schema_version": SCHEMA_VERSION,
        "course": {
            "slug": course["slug"],
            "version": version,
            "language": language,
            "languages": sorted(languages),
            "title": course["title"][language].strip(),
            "summary": course["summary"][language].strip(),
            "source": course["source"][language].strip(),
            "cover": cover_payload(course["cover"]),
        },
        "lessons": lessons,
    }


def catalog_card(document: dict[str, Any]) -> dict[str, Any]:
    """The list entry of the course on the document's language, without `published_at`."""
    course = document["course"]
    lessons = document["lessons"]
    return {
        "slug": course["slug"],
        "version": course["version"],
        "title": course["title"],
        "summary": course["summary"],
        "source": course["source"],
        "cover": course["cover"],
        "lesson_count": len(lessons),
        "minutes": sum(lesson["minutes"] for lesson in lessons),
        # The videos' milliseconds summed, then rounded up.
        "video_minutes": math.ceil(
            sum(lesson["video"]["duration_ms"] for lesson in lessons if lesson["video"]) / 60_000
        ),
    }


def changes(old: dict[str, Any] | None, new: dict[str, Any]) -> list[str]:
    """Human-readable differences between two snapshots, in course order."""
    if old is None:
        return []
    found: list[str] = []
    old_course, new_course = old["course"], new["course"]
    for field in COURSE_TEXTS:
        languages = _changed_languages(old_course[field], new_course[field])
        if languages:
            found.append(f"Курс: {CHANGED[field]} ({languages})")
    if old_course["cover"] != new_course["cover"]:
        found.append("Курс: заменена обложка")
    old_lessons = {lesson["id"]: lesson for lesson in old["lessons"]}
    new_ids = [lesson["id"] for lesson in new["lessons"]]
    for number, lesson in enumerate(new["lessons"], start=1):
        before = old_lessons.get(lesson["id"])
        name = f"Тема {number}"
        if before is None:
            found.append(f"{name}: новая тема «{lesson['title']['ru'] or lesson['slug']}»")
            continue
        if before["checksum"] == lesson["checksum"]:
            continue
        parts = [
            f"{CHANGED[field]} ({languages})"
            for field in LESSON_TEXTS
            if (languages := _changed_languages(before[field], lesson[field]))
        ]
        parts += [CHANGED[field] for field in ("slug", "minutes") if before[field] != lesson[field]]
        parts += video_changes(before["video"], lesson["video"])
        parts += media_changes(lesson_media(before), lesson_media(lesson), editor_languages())
        found.append(f"{name}: {'; '.join(parts)}")
    found.extend(
        f"Удалена тема «{lesson['title']['ru'] or lesson['slug']}»"
        for lesson in old["lessons"]
        if lesson["id"] not in new_ids
    )
    kept_old = [lesson["id"] for lesson in old["lessons"] if lesson["id"] in new_ids]
    if kept_old != [lesson_id for lesson_id in new_ids if lesson_id in old_lessons]:
        found.append("Изменён порядок тем")
    return found


def video_changes(old: dict[str, Any] | None, new: dict[str, Any] | None) -> list[str]:
    if old is None or new is None:
        return [] if old == new else ["добавлено видео" if old is None else "убрано видео"]
    if old["sha256"] != new["sha256"]:
        return ["заменено видео"]
    found = []
    if old["poster"] != new["poster"]:
        found.append("заменена обложка видео")
    if old["spoken_language"] != new["spoken_language"]:
        found.append("изменён язык речи видео")
    old_dubs, new_dubs = old.get("dubs", {}), new["dubs"]
    for change, languages in (
        ("добавлена озвучка", [code for code in new_dubs if code not in old_dubs]),
        (
            "заменена озвучка",
            [
                code
                for code in new_dubs
                if code in old_dubs and old_dubs[code]["sha256"] != new_dubs[code]["sha256"]
            ],
        ),
        ("удалена озвучка", [code for code in old_dubs if code not in new_dubs]),
    ):
        ordered = [code for code in editor_languages() if code in languages]
        if ordered:
            found.append(f"{change} ({', '.join(ordered)})")
    return found


def _changed_languages(old: dict[str, str], new: dict[str, str]) -> str:
    return ", ".join(
        language for language in editor_languages() if old.get(language) != new.get(language)
    )
