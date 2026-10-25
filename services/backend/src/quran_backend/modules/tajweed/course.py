# Russian messages for the editor intentionally contain Cyrillic letters.
# ruff: noqa: RUF001
"""The tajweed course snapshot: validation and compilation into one document per language.

Pure functions over plain JSON, no database (docs/tajweed/course.md). Lesson
texts are written by the course; rule names and colours of Quran.Foundation
classes come from the rule reference (`rules.py`), so a lesson's chip matches
the coloured Mushaf.
"""

from __future__ import annotations

import hashlib
import json
import re
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

from quran_backend.modules.audio.serializers import public_audio_url
from quran_backend.modules.core.editorial.markup import parse_notes, plain_markup
from quran_backend.modules.courses.document import shown_files, video_payload
from quran_backend.modules.courses.lesson_media import (
    KINDS,
    MAX_BLOCKS,
    VIDEO,
    media_payload,
    media_snapshot,
)
from quran_backend.modules.tajweed.course_markers import DERIVED_TARGETS, TARGETS
from quran_backend.modules.tajweed.models import TAJWEED_COURSE_LANGUAGES
from quran_backend.modules.tajweed.rules import RULES_BY_CODE

SNAPSHOT_SCHEMA_VERSION = 1
DOCUMENT_SCHEMA_VERSION = 1
REVIEW_STATUSES = frozenset({"pending_teacher_review", "reviewed"})
DEFAULT_SNAPSHOT = Path(__file__).parent / "data" / "tajweed-course-v1.json"

SLUG = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
VERSION_NAME = re.compile(r"^[0-9A-Za-z][0-9A-Za-z._-]{0,63}$")
COLOR = re.compile(r"^#[0-9A-F]{6}$")
VERSE_KEY = re.compile(r"^(\d{1,3}):(\d{1,3})$")
MAX_PREFERRED_EXAMPLES = 20
LESSON_TEXTS = ("title", "summary", "explanation", "how")
# Written in the markup of course notes: links and «!»/«?» notes (docs/tajweed/course.md).
MARKUP_TEXTS = ("explanation", "how")


class TajweedCourseError(ValueError):
    """Every problem found in a snapshot, so an editor fixes them in one pass."""

    def __init__(self, problems: Sequence[str]) -> None:
        self.problems = list(problems)
        super().__init__("\n".join(self.problems))


def load_course_snapshot(path: Path = DEFAULT_SNAPSHOT) -> dict[str, Any]:
    with path.open(encoding="utf-8") as file:
        data = json.load(file)
    if not isinstance(data, dict):
        raise TajweedCourseError(["Снимок должен быть JSON-объектом."])
    return data


def snapshot_checksum(snapshot: Mapping[str, Any]) -> str:
    canonical = json.dumps(snapshot, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode()).hexdigest()


def snapshot_json(snapshot: Mapping[str, Any]) -> str:
    """The snapshot as it is kept in git: indent 2, Unicode as is, final newline."""
    return json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n"


def valid_verse_key(value: object) -> bool:
    match = VERSE_KEY.match(value) if isinstance(value, str) else None
    return bool(match and 1 <= int(match[1]) <= 114 and int(match[2]) >= 1)


def missing_texts(snapshot: Mapping[str, Any]) -> dict[str, int]:
    """Untranslated texts per language: a draft may have them, a signed version may not."""
    counts = dict.fromkeys(TAJWEED_COURSE_LANGUAGES, 0)
    for texts in _all_texts(snapshot):
        for language in TAJWEED_COURSE_LANGUAGES:
            if not str(texts.get(language) or "").strip():
                counts[language] += 1
    return counts


def _all_texts(snapshot: Mapping[str, Any]) -> list[Mapping[str, Any]]:
    course = snapshot.get("course") or {}
    found: list[Any] = [course.get("title"), course.get("summary")]
    found += [target.get("name") for target in snapshot.get("targets") or []]
    found += [section.get("title") for section in snapshot.get("sections") or []]
    for lesson in snapshot.get("lessons") or []:
        found += [lesson.get(field) for field in LESSON_TEXTS]
    return [texts for texts in found if isinstance(texts, Mapping)]


class _Checker:
    """Collects the problems of one snapshot, part by part."""

    def __init__(self, *, complete: bool) -> None:
        self.complete = complete
        self.problems: list[str] = []

    def texts(self, value: object, where: str) -> None:
        if not isinstance(value, Mapping):
            self.problems.append(f"{where}: нужен объект с текстами по языкам.")
            return
        unknown = set(value) - set(TAJWEED_COURSE_LANGUAGES)
        if unknown:
            self.problems.append(f"{where}: неизвестные языки {', '.join(sorted(unknown))}.")
        for language in TAJWEED_COURSE_LANGUAGES:
            text = value.get(language, "")
            if not isinstance(text, str):
                self.problems.append(f"{where} [{language}]: текст должен быть строкой.")
            elif self.complete and not text.strip():
                self.problems.append(f"{where} [{language}]: нет текста.")

    def course(self, course: Mapping[str, Any]) -> None:
        if not SLUG.match(str(course.get("slug", ""))):
            self.problems.append("course.slug: латинские буквы, цифры и дефисы.")
        if not VERSION_NAME.match(str(course.get("version", ""))):
            self.problems.append(
                "course.version: латинские буквы, цифры, точка, дефис, до 64 знаков."
            )
        if course.get("review_status") not in REVIEW_STATUSES:
            self.problems.append(
                f"course.review_status: одно из {', '.join(sorted(REVIEW_STATUSES))}."
            )
        self.texts(course.get("title"), "Курс: название")
        self.texts(course.get("summary"), "Курс: описание")

    def targets(self, items: Sequence[Mapping[str, Any]]) -> set[str]:
        keys: set[str] = set()
        for target in items:
            key = str(target.get("key", ""))
            where = f"Цель «{key}»"
            if key not in DERIVED_TARGETS:
                known = ", ".join(DERIVED_TARGETS)
                self.problems.append(f"{where}: такой производной цели нет ({known}).")
                continue
            if key in keys:
                self.problems.append(f"{where}: повторяется.")
            keys.add(key)
            if target.get("rule") != DERIVED_TARGETS[key]:
                self.problems.append(f"{where}: rule должно быть {DERIVED_TARGETS[key]!r}.")
            if not COLOR.match(str(target.get("color", ""))):
                self.problems.append(f"{where}: цвет в виде #RRGGBB.")
            if not str(target.get("arabic_name", "")).strip():
                self.problems.append(f"{where}: нет арабского названия.")
            self.texts(target.get("name"), f"{where}: название")
        return keys

    def lesson(self, lesson: Mapping[str, Any], targets: set[str]) -> None:
        where = f"Урок «{lesson.get('slug', '')}»"
        if not SLUG.match(str(lesson.get("slug", ""))):
            self.problems.append(f"{where}: slug из латинских букв, цифр и дефисов.")
        target = lesson.get("target")
        if target not in TARGETS:
            self.problems.append(f"{where}: неизвестная цель {target!r}.")
        elif target in DERIVED_TARGETS and target not in targets:
            self.problems.append(f"{where}: цель {target!r} не описана в targets.")
        minutes = lesson.get("minutes")
        if not isinstance(minutes, int) or not 1 <= minutes <= 30:
            self.problems.append(f"{where}: minutes — целое от 1 до 30.")
        for field in LESSON_TEXTS:
            self.texts(lesson.get(field), f"{where}: {field}")
        letters = lesson.get("letters", "")
        if not isinstance(letters, str) or len(letters) > 80:
            self.problems.append(f"{where}: letters — строка до 80 знаков.")
        examples = lesson.get("examples", [])
        if (
            not isinstance(examples, list)
            or len(examples) > MAX_PREFERRED_EXAMPLES
            or not all(valid_verse_key(key) for key in examples)
        ):
            self.problems.append(
                f"{where}: examples — до {MAX_PREFERRED_EXAMPLES} ключей аятов вида 112:4."
            )
        media = lesson.get("media", [])
        if (
            not isinstance(media, list)
            or len(media) > MAX_BLOCKS
            or not all(
                isinstance(block, Mapping)
                and block.get("type") in KINDS
                and (block.get("type") == VIDEO or isinstance(block.get("slides"), list))
                for block in media
            )
            or sum(1 for block in media if block.get("type") == VIDEO) > 1
        ):
            self.problems.append(
                f"{where}: media — до {MAX_BLOCKS} блоков видео, слайдов и баннеров, видео одно."
            )

    def sections(self, items: Sequence[Mapping[str, Any]], lessons: Sequence[str]) -> None:
        placed: list[str] = []
        slugs: set[str] = set()
        for section in items:
            slug = str(section.get("slug", ""))
            where = f"Раздел «{slug}»"
            if not SLUG.match(slug) or slug in slugs:
                self.problems.append(f"{where}: slug пустой, неверный или повторяется.")
            slugs.add(slug)
            self.texts(section.get("title"), f"{where}: название")
            members = section.get("lessons")
            if not isinstance(members, list) or not members:
                self.problems.append(f"{where}: нет уроков.")
                continue
            self.problems += [
                f"{where}: нет урока {member!r}." for member in members if member not in lessons
            ]
            placed += [str(member) for member in members]
        self.problems += [
            f"Урок «{slug}» должен быть ровно в одном разделе."
            for slug in dict.fromkeys(lessons)
            if placed.count(slug) != 1
        ]


def validate_course_snapshot(snapshot: Mapping[str, Any], *, complete: bool = True) -> None:
    """Raises TajweedCourseError with every problem; `complete` also requires every language."""
    checker = _Checker(complete=complete)
    if snapshot.get("schema_version") != SNAPSHOT_SCHEMA_VERSION:
        checker.problems.append(f"schema_version должна быть {SNAPSHOT_SCHEMA_VERSION}.")
    course = snapshot.get("course")
    if not isinstance(course, Mapping):
        raise TajweedCourseError([*checker.problems, "Нет раздела course."])
    checker.course(course)
    targets = checker.targets(snapshot.get("targets") or [])
    lessons = [str(lesson.get("slug", "")) for lesson in snapshot.get("lessons") or []]
    for slug in {slug for slug in lessons if lessons.count(slug) > 1}:
        checker.problems.append(f"Урок «{slug}»: повторяется.")
    for lesson in snapshot.get("lessons") or []:
        checker.lesson(lesson, targets)
    checker.sections(snapshot.get("sections") or [], lessons)
    if not lessons:
        checker.problems.append("В курсе нет уроков.")
    if checker.problems:
        raise TajweedCourseError(checker.problems)


def lesson_video(lesson: Mapping[str, Any]) -> dict[str, Any] | None:
    """The lesson's video with its poster and dubs, as a course release keeps one."""
    return next(
        (
            block["video"]
            for block in lesson.get("media") or []
            if block.get("type") == VIDEO and block.get("video")
        ),
        None,
    )


def lesson_media(lesson: Mapping[str, Any], language: str) -> list[dict[str, Any]]:
    """The media blocks of one language (docs/courses/README.md, «Медиа темы»)."""
    video = lesson_video(lesson)
    blocks = media_snapshot(
        lesson.get("media") or [],
        has_video=video is not None,
        languages=TAJWEED_COURSE_LANGUAGES,
    )
    return media_payload(
        blocks,
        language=language,
        video=video_payload(video, language),
        public_url=public_audio_url,
    )


def course_video_files(snapshot: Mapping[str, Any]) -> set[str]:
    """SHA-256 of the video and dub files the course's documents give students."""
    lessons = [{"video": lesson_video(lesson)} for lesson in snapshot.get("lessons") or []]
    return shown_files({"lessons": lessons}, list(TAJWEED_COURSE_LANGUAGES))


def _text(value: Mapping[str, str] | None, language: str) -> str:
    # A draft may still miss a translation; a published version never does.
    return "" if value is None else str(value.get(language, ""))


def compile_course_document(
    snapshot: Mapping[str, Any], *, language: str, course_meta: Mapping[str, Any]
) -> dict[str, Any]:
    """The document clients render: every text already in `language`."""
    course = snapshot["course"]
    derived = {target["key"]: target for target in snapshot.get("targets", [])}
    sections = {
        member: section["slug"] for section in snapshot["sections"] for member in section["lessons"]
    }
    targets: dict[str, dict[str, Any]] = {}
    lessons: list[dict[str, Any]] = []
    for section in snapshot["sections"]:
        for slug in section["lessons"]:
            lesson = next(item for item in snapshot["lessons"] if item["slug"] == slug)
            key = lesson["target"]
            if key in derived:
                source = derived[key]
                targets[key] = {
                    "name": _text(source["name"], language),
                    "arabic_name": source["arabic_name"],
                    "color": source["color"],
                    "rule": source["rule"],
                }
            else:
                rule = RULES_BY_CODE[key]
                targets[key] = {
                    "name": _text(rule.name, language),
                    "arabic_name": rule.arabic_name,
                    "color": rule.color,
                    "rule": rule.code,
                }
            lessons.append(
                {
                    "slug": slug,
                    "section": sections[slug],
                    "target": key,
                    "minutes": int(lesson["minutes"]),
                    **{field: _text(lesson[field], language) for field in LESSON_TEXTS},
                    # Clients before links and notes read the text without markup.
                    **{
                        field: plain_markup(_text(lesson[field], language))
                        for field in MARKUP_TEXTS
                    },
                    **{
                        f"{field}_blocks": parse_notes(_text(lesson[field], language))
                        for field in MARKUP_TEXTS
                    },
                    "letters": str(lesson.get("letters", "")),
                    "media": lesson_media(lesson, language),
                }
            )
    return {
        "schema_version": DOCUMENT_SCHEMA_VERSION,
        "course": {
            **course_meta,
            "language": language,
            "title": _text(course["title"], language),
            "summary": _text(course["summary"], language),
            "review_status": course["review_status"],
        },
        "targets": targets,
        "sections": [
            {
                "slug": section["slug"],
                "title": _text(section["title"], language),
                "lessons": list(section["lessons"]),
            }
            for section in snapshot["sections"]
        ],
        "lessons": lessons,
    }
