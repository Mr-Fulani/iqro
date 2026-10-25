"""Compiles a validated snapshot into the course document of one language.

The document (docs/salah/learning-spec.md §6) is what the app and the site
render: every text already in the requested language, prayers unrolled into
linear steps, formulas resolved. Clients hold no fiqh logic.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from quran_backend.modules.courses.snapshot_media import lesson_media
from quran_backend.modules.salah.models import SALAH_LANGUAGES
from quran_backend.modules.salah.snapshot import (
    audio_media_key,
    expand_lesson_steps,
    template_counts_rakats,
)

DOCUMENT_SCHEMA_VERSION = 1

_STEP_FIELDS = ("kind", "position", "ruling", "rakat", "media", "repeat")


def _text(value: Mapping[str, str] | None, language: str) -> str | None:
    # A draft may still miss a translation; a published version never does.
    return None if value is None else value.get(language, "")


def _notes(step: Mapping[str, Any], language: str) -> list[dict[str, str]]:
    """The «?» and «!» notes in their order; an untranslated draft note is left out."""
    return [
        {"kind": note["kind"], "text": text}
        for note in step.get("notes", [])
        if (text := _text(note["text"], language))
    ]


def _sources(owner: Mapping[str, Any], language: str) -> dict[str, list[str]]:
    """`sources`, one per line in the author's order; none, no key (docs/salah/sources.md)."""
    text = _text(owner.get("sources"), language) or ""
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    return {"sources": lines} if lines else {}


def _course(
    snapshot: Mapping[str, Any], course_meta: Mapping[str, Any], language: str
) -> dict[str, Any]:
    """The course's meta; «Автор и источники» only when written."""
    source = (_text(snapshot["course"].get("source"), language) or "").strip()
    return {**course_meta, "language": language, **({"source": source} if source else {})}


def compile_document(
    snapshot: Mapping[str, Any],
    *,
    language: str,
    course_meta: Mapping[str, Any],
    formulas: Mapping[str, Mapping[str, Any]],
    media: Mapping[str, Mapping[str, Any]],
) -> dict[str, Any]:
    """`formulas` and `media` are already resolved for `language`, by id/key.

    `media` holds every stored file; only the pictures steps show go to the
    document's `media`, a step's recording goes to the step itself.
    """
    templates = {template["id"]: template for template in snapshot.get("templates", [])}
    kind_titles = {kind["code"]: kind["title"] for kind in snapshot["prayer_kinds"]}
    used_formulas: set[str] = set()
    used_media: set[str] = set()
    lessons: list[dict[str, Any]] = []
    for lesson in snapshot["lessons"]:
        steps: list[dict[str, Any]] = []
        for step in expand_lesson_steps(lesson, templates):
            compiled: dict[str, Any] = {"slug": step["slug"]}
            for field in _STEP_FIELDS:
                if step.get(field) is not None:
                    compiled[field] = step[field]
            compiled["title"] = _text(step["title"], language)
            compiled["instruction"] = _text(step["instruction"], language)
            if step.get("details") is not None:
                compiled["details"] = _text(step["details"], language)
            notes = _notes(step, language)
            if notes:
                compiled["notes"] = notes
            audio_key = audio_media_key(step, language)
            if audio_key is not None and audio_key in media:
                compiled["audio"] = {"url": media[audio_key]["url"]}
            compiled["formulas"] = [
                formula_id for formula_id in step.get("formulas", []) if formula_id in formulas
            ]
            used_formulas.update(compiled["formulas"])
            if "media" in compiled:
                if compiled["media"] in media:
                    used_media.add(compiled["media"])
                else:
                    del compiled["media"]
            steps.append(compiled)
        entry: dict[str, Any] = {
            "slug": lesson["slug"],
            "kind": lesson["kind"],
            "title": _text(lesson["title"], language),
            "summary": _text(lesson["summary"], language),
            "minutes": int(lesson.get("minutes", 0)),
            "steps": steps,
        }
        # A lesson without media has no key, as a step without notes (docs/salah/lesson-media.md).
        blocks = lesson_media(lesson, language, SALAH_LANGUAGES)
        if blocks:
            entry["media"] = blocks
        entry.update(_sources(lesson, language))
        prayer = lesson.get("prayer")
        if prayer:
            entry["prayer"] = {
                "code": prayer["code"],
                "kind": prayer["kind"],
                "kind_title": _text(kind_titles[prayer["kind"]], language),
                "rakats": (
                    len(prayer["rakat_rules"])
                    if template_counts_rakats(templates[prayer["template"]])
                    else 0
                ),
            }
        lessons.append(entry)

    return {
        "schema_version": DOCUMENT_SCHEMA_VERSION,
        "course": _course(snapshot, course_meta, language),
        "sections": [
            {
                "slug": section["slug"],
                "title": _text(section["title"], language),
                "lessons": list(section["lessons"]),
            }
            for section in snapshot["sections"]
        ],
        "lessons": lessons,
        "formulas": {
            formula_id: dict(formulas[formula_id]) for formula_id in sorted(used_formulas)
        },
        "media": {key: dict(media[key]) for key in sorted(used_media)},
    }
