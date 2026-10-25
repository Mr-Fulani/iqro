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

from quran_backend.modules.core.editorial.markup import parse_notes, plain_markup
from quran_backend.modules.courses import snapshot_media
from quran_backend.modules.courses.snapshot_media import MEDIA_PROBLEM, media_valid
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
# «Автор и источники» of the course and «Источники» of a lesson, one per line: optional,
# but once written in one language due in all (docs/tajweed/course.md, «Источники»).
COURSE_SOURCE = "source"
LESSON_SOURCES = "sources"
SOURCE_MAX_LENGTH = 300
SOURCES_MAX_LENGTH = 2000


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


def _written(value: object) -> bool:
    """An optional text written in at least one language."""
    return isinstance(value, Mapping) and any(
        isinstance(text, str) and text.strip() for text in value.values()
    )


def _all_texts(snapshot: Mapping[str, Any]) -> list[Mapping[str, Any]]:
    course = snapshot.get("course") or {}
    found: list[Any] = [course.get("title"), course.get("summary")]
    optional: list[Any] = [course.get(COURSE_SOURCE)]
    found += [target.get("name") for target in snapshot.get("targets") or []]
    found += [section.get("title") for section in snapshot.get("sections") or []]
    for lesson in snapshot.get("lessons") or []:
        found += [lesson.get(field) for field in LESSON_TEXTS]
        optional.append(lesson.get(LESSON_SOURCES))
    found += [texts for texts in optional if _written(texts)]
    return [texts for texts in found if isinstance(texts, Mapping)]


class _Checker:
    """Collects the problems of one snapshot, part by part."""

    def __init__(self, *, complete: bool) -> None:
        self.complete = complete
        self.problems: list[str] = []

    def texts(self, value: object, where: str, *, required: bool = True) -> None:
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
            elif self.complete and required and not text.strip():
                self.problems.append(f"{where} [{language}]: нет текста.")

    def optional_texts(self, value: object, where: str, maximum: int) -> None:
        """Absent or empty in every language is fine; once written, as `texts`."""
        if value is None:
            return
        self.texts(value, where, required=_written(value))
        if isinstance(value, Mapping):
            self.problems += [
                f"{where} [{language}]: длиннее {maximum} знаков."
                for language, text in value.items()
                if isinstance(text, str) and len(text) > maximum
            ]

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
        self.optional_texts(course.get(COURSE_SOURCE), "Курс: автор и источники", SOURCE_MAX_LENGTH)

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
        self.optional_texts(lesson.get(LESSON_SOURCES), f"{where}: источники", SOURCES_MAX_LENGTH)
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
        if not media_valid(lesson.get("media", [])):
            self.problems.append(f"{where}: {MEDIA_PROBLEM}")

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


def lesson_media(lesson: Mapping[str, Any], language: str) -> list[dict[str, Any]]:
    """The media blocks of one language (docs/courses/README.md, «Медиа темы»)."""
    return snapshot_media.lesson_media(lesson, language, TAJWEED_COURSE_LANGUAGES)


def course_video_files(snapshot: Mapping[str, Any]) -> set[str]:
    """SHA-256 of the video and dub files the course's documents give students."""
    return snapshot_media.video_files(snapshot.get("lessons") or [], TAJWEED_COURSE_LANGUAGES)


def _text(value: Mapping[str, str] | None, language: str) -> str:
    # A draft may still miss a translation; a published version never does.
    return "" if value is None else str(value.get(language, ""))


def _sources(value: Mapping[str, str] | None, language: str) -> list[str]:
    """One source per line, in the author's order; empty lines are left out."""
    return [line.strip() for line in _text(value, language).splitlines() if line.strip()]


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
                    "sources": _sources(lesson.get(LESSON_SOURCES), language),
                }
            )
    return {
        "schema_version": DOCUMENT_SCHEMA_VERSION,
        "course": {
            **course_meta,
            "language": language,
            "title": _text(course["title"], language),
            "summary": _text(course["summary"], language),
            "source": _text(course.get(COURSE_SOURCE), language).strip(),
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
