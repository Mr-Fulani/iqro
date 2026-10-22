"""The structure of a draft: adding, removing and reordering sections, lessons and steps.

Pure functions over the snapshot JSON, like `editor.py`. A prayer's steps are its
template's: adding, removing or moving one changes every prayer that uses the
template, so the editor says where before it does. Each function raises
StructureError with what went wrong in words the owner can act on.
"""

from __future__ import annotations

# Russian interface strings intentionally contain characters that resemble Latin glyphs.
# ruff: noqa: RUF001, RUF002
import copy
import re
from collections.abc import Iterable, Mapping
from typing import Any

from quran_backend.modules.salah.editor import (
    EditorNode,
    lesson_steps,
    localized_title,
    template_label,
    template_step_usage,
    variant_descriptions,
)
from quran_backend.modules.salah.snapshot import STEP_KINDS

# The same rule as the site's lesson address: /{locale}/salah/<slug>.
LESSON_SLUG = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
NEW_LESSON_KINDS = {"steps": "По шагам", "article": "Статья"}
NEW_LESSON_MINUTES = 3
_RUSSIAN = dict(
    zip(
        "абвгдеёжзийклмнопрстуфхцчшщъыьэюя",
        [
            "a", "b", "v", "g", "d", "e", "e", "zh", "z", "i", "i", "k", "l", "m", "n", "o",
            "p", "r", "s", "t", "u", "f", "kh", "ts", "ch", "sh", "sch", "", "y", "", "e",
            "yu", "ya",
        ],
        strict=True,
    )
)  # fmt: skip


class StructureError(ValueError):
    pass


def slugify(text: str, fallback: str, *, limit: int = 48) -> str:
    """A Latin address from a title: «Сухуд ас-сахв» → «sukhud-as-sakhv»."""
    latin = "".join(_RUSSIAN.get(letter, letter) for letter in text.lower())
    slug = re.sub(r"[^a-z0-9]+", "-", latin).strip("-")[:limit].strip("-")
    return slug or fallback


def _unique(base: str, taken: Iterable[str]) -> str:
    used = set(taken)
    if base not in used:
        return base
    number = 2
    while f"{base}-{number}" in used:
        number += 1
    return f"{base}-{number}"


def _source_title(texts: Mapping[str, str]) -> str:
    return localized_title(texts, "")


def _section(snapshot: Mapping[str, Any], slug: str) -> dict[str, Any]:
    items: list[dict[str, Any]] = snapshot.get("sections", [])
    for section in items:
        if section["slug"] == slug:
            return section
    raise StructureError(f"Раздела «{slug}» в черновике нет.")


def _lesson(snapshot: Mapping[str, Any], slug: str) -> dict[str, Any]:
    items: list[dict[str, Any]] = snapshot.get("lessons", [])
    for lesson in items:
        if lesson["slug"] == slug:
            return lesson
    raise StructureError(f"Урока «{slug}» в черновике нет.")


def _template(snapshot: Mapping[str, Any], node: EditorNode) -> dict[str, Any]:
    templates: list[dict[str, Any]] = snapshot.get("templates", [])
    for template in templates:
        if template.get("id") == node.template_id:
            return template
    raise StructureError(f"Шаблона «{node.template_id}» в черновике нет.")


def _sections_of(snapshot: Mapping[str, Any], lesson_slug: str) -> list[dict[str, Any]]:
    return [
        section
        for section in snapshot.get("sections", [])
        if lesson_slug in section.get("lessons", [])
    ]


def _move(items: list[Any], index: int, target: int, *, after: bool) -> None:
    """Puts items[index] just before (or after) items[target]."""
    item = items.pop(index)
    if index < target:
        target -= 1
    items.insert(target + 1 if after else target, item)


# Adding --------------------------------------------------------------------


def add_section(snapshot: dict[str, Any], title: dict[str, str]) -> str:
    sections = snapshot.setdefault("sections", [])
    slug = _unique(slugify(_source_title(title), "section"), (s["slug"] for s in sections))
    sections.append({"slug": slug, "title": title, "lessons": []})
    return slug


def add_lesson(  # noqa: PLR0913 - one new lesson and what it starts with
    snapshot: dict[str, Any],
    section_slug: str,
    *,
    kind: str,
    title: dict[str, str],
    summary: dict[str, str],
    slug: str = "",
) -> str:
    """A lesson of steps or an article at the end of the section, without steps yet.

    A prayer's lesson needs a template and rak'ah rules; it is not made here.
    """
    if kind not in NEW_LESSON_KINDS:
        raise StructureError("Новый урок может быть только «по шагам» или статьёй.")
    section = _section(snapshot, section_slug)
    taken = {lesson["slug"] for lesson in snapshot.get("lessons", [])}
    if slug:
        if len(slug) > 64 or not LESSON_SLUG.match(slug):
            raise StructureError(
                "Адрес урока: латинские буквы и цифры через дефис, например «night-prayer»."
            )
        if slug in taken:
            raise StructureError(f"Адрес «{slug}» уже занят другим уроком.")
    else:
        slug = _unique(slugify(_source_title(title), "lesson"), taken)
    snapshot.setdefault("lessons", []).append(
        {
            "slug": slug,
            "kind": kind,
            "title": title,
            "summary": summary,
            "minutes": NEW_LESSON_MINUTES,
            "steps": [],
        }
    )
    section.setdefault("lessons", []).append(slug)
    return slug


def add_step(  # noqa: PLR0913 - one new step and where it goes
    snapshot: dict[str, Any],
    lesson_slug: str,
    *,
    kind: str,
    title: dict[str, str],
    instruction: dict[str, str],
    after: EditorNode | None = None,
) -> str:
    """A new step after `after` (or at the end of the lesson); returns its node id.

    In a prayer the step joins the template right after `after` and takes its
    conditions, so it shows in the same rak'ahs of every prayer with that template.
    """
    if kind not in STEP_KINDS:
        raise StructureError("Выберите тип шага.")
    lesson = _lesson(snapshot, lesson_slug)
    step: dict[str, Any] = {
        "kind": kind,
        "title": title,
        "instruction": instruction,
        "formulas": [],
    }
    base = slugify(_source_title(title), "step")
    if lesson.get("prayer"):
        if after is None or after.template_id is None:
            raise StructureError(
                "В молитве шаг добавляется после другого шага: откройте шаг и нажмите "
                "«Добавить шаг после этого»."
            )
        template = _template(snapshot, after)
        step["slug"] = _unique(base, (item["slug"] for item in template["steps"]))
        if after.data.get("when"):
            step["when"] = copy.deepcopy(after.data["when"])
        template["steps"].insert((after.template_index or 0) + 1, step)
        middle = f"r{after.rakat}." if after.rakat is not None else ""
        return f"step:{lesson_slug}.{middle}{step['slug']}"
    steps = lesson.setdefault("steps", [])
    step["slug"] = _unique(base, (item["slug"] for item in steps))
    position = len(steps)
    if after is not None:
        position = next(i for i, item in enumerate(steps) if item is after.data) + 1
    steps.insert(position, step)
    return f"step:{lesson_slug}.{step['slug']}"


# Removing ------------------------------------------------------------------


def delete_lesson(snapshot: dict[str, Any], slug: str) -> list[dict[str, Any]]:
    """Removes the lesson from the course; returns its own steps (a prayer's stay in the
    template, which other prayers may use)."""
    lesson = _lesson(snapshot, slug)
    snapshot["lessons"] = [item for item in snapshot["lessons"] if item is not lesson]
    for section in _sections_of(snapshot, slug):
        section["lessons"] = [item for item in section["lessons"] if item != slug]
    return list(lesson.get("steps", []))


def delete_section(snapshot: dict[str, Any], slug: str) -> list[dict[str, Any]]:
    """Removes the section with the lessons it alone lists; returns their steps."""
    section = _section(snapshot, slug)
    snapshot["sections"] = [item for item in snapshot["sections"] if item is not section]
    removed: list[dict[str, Any]] = []
    for lesson_slug in section.get("lessons", []):
        if not _sections_of(snapshot, lesson_slug):
            removed += delete_lesson(snapshot, lesson_slug)
    return removed


def delete_step(snapshot: dict[str, Any], node: EditorNode) -> list[dict[str, Any]]:
    if node.kind != "step" or node.lesson is None:
        raise StructureError("Это не шаг.")
    if node.template_id is not None:
        template = _template(snapshot, node)
        template["steps"] = [item for item in template["steps"] if item is not node.data]
    else:
        lesson = _lesson(snapshot, node.lesson["slug"])
        lesson["steps"] = [item for item in lesson["steps"] if item is not node.data]
    return [node.data]


def removed_audio(steps: Iterable[Mapping[str, Any]]) -> set[str]:
    """Recordings of removed steps: candidates to drop once nothing else plays them."""
    keys: set[str] = set()
    for step in steps:
        if step.get("audio_media"):
            keys.add(step["audio_media"])
        keys.update((step.get("audio_media_languages") or {}).values())
    return keys


# Reordering ----------------------------------------------------------------


def move_section(snapshot: dict[str, Any], slug: str, delta: int) -> None:
    sections = snapshot.get("sections", [])
    index = sections.index(_section(snapshot, slug))
    target = index + delta
    if not 0 <= target < len(sections):
        raise StructureError("Раздел и так первый." if delta < 0 else "Раздел и так последний.")
    _move(sections, index, target, after=delta > 0)


def move_section_next_to(
    snapshot: dict[str, Any], slug: str, target_slug: str, *, after: bool
) -> None:
    sections = snapshot.get("sections", [])
    index = sections.index(_section(snapshot, slug))
    target = sections.index(_section(snapshot, target_slug))
    if index != target:
        _move(sections, index, target, after=after)


def move_lesson(snapshot: dict[str, Any], slug: str, delta: int) -> None:
    """Up or down within its section."""
    _lesson(snapshot, slug)
    section = _sections_of(snapshot, slug)[0]
    lessons = section["lessons"]
    index = lessons.index(slug)
    target = index + delta
    if not 0 <= target < len(lessons):
        raise StructureError(
            "Урок и так первый в разделе." if delta < 0 else "Урок и так последний в разделе."
        )
    _move(lessons, index, target, after=delta > 0)


def move_lesson_to_section(snapshot: dict[str, Any], slug: str, section_slug: str) -> None:
    """To the end of another section."""
    _lesson(snapshot, slug)
    target = _section(snapshot, section_slug)
    if slug in target.get("lessons", []):
        return
    for section in _sections_of(snapshot, slug):
        section["lessons"] = [item for item in section["lessons"] if item != slug]
    target.setdefault("lessons", []).append(slug)


def move_lesson_next_to(
    snapshot: dict[str, Any], slug: str, target_slug: str, *, after: bool
) -> None:
    """Before or after another lesson, in that lesson's section."""
    if slug == target_slug:
        return
    _lesson(snapshot, slug)
    sections = _sections_of(snapshot, target_slug)
    if not sections:
        raise StructureError(f"Урок «{target_slug}» не входит ни в один раздел.")
    for section in _sections_of(snapshot, slug):
        section["lessons"] = [item for item in section["lessons"] if item != slug]
    lessons = sections[0]["lessons"]
    position = lessons.index(target_slug) + (1 if after else 0)
    lessons.insert(position, slug)


def _rakat_sequence(snapshot: dict[str, Any], node: EditorNode) -> list[EditorNode]:
    """The steps the learner meets around this one: its lesson, its rak'ah."""
    if node.lesson is None:
        raise StructureError("Это не шаг.")
    return [step for step in lesson_steps(snapshot, node.lesson) if step.rakat == node.rakat]


def move_step(snapshot: dict[str, Any], node: EditorNode, delta: int) -> None:
    """Up or down as the learner meets it: in its lesson, in a prayer within its rak'ah."""
    sequence = _rakat_sequence(snapshot, node)
    position = [step.id for step in sequence].index(node.id)
    target = position + delta
    if not 0 <= target < len(sequence):
        where = "в ракаате" if node.rakat is not None else "в уроке"
        raise StructureError(
            f"Шаг и так первый {where}." if delta < 0 else f"Шаг и так последний {where}."
        )
    move_step_next_to(snapshot, node, sequence[target], after=delta > 0)


def move_step_next_to(
    snapshot: dict[str, Any], node: EditorNode, target: EditorNode, *, after: bool
) -> None:
    if node.id == target.id:
        return
    if node.lesson is None or target.lesson is None or node.lesson is not target.lesson:
        raise StructureError("Шаг переставляется только внутри своего урока.")
    if node.template_id is None:
        steps = node.lesson["steps"]
        index = next(i for i, item in enumerate(steps) if item is node.data)
        target_index = next(i for i, item in enumerate(steps) if item is target.data)
        _move(steps, index, target_index, after=after)
        return
    if target.template_id != node.template_id or target.rakat != node.rakat:
        raise StructureError("В молитве шаг переставляется только внутри своего ракаата.")
    template = _template(snapshot, node)
    _move(template["steps"], node.template_index or 0, target.template_index or 0, after=after)


# Describing ----------------------------------------------------------------


def deletion_notes(snapshot: dict[str, Any], node: EditorNode) -> list[str]:
    """What the owner should know before removing: what goes with it and where it shows."""
    describe = {"section": _section_notes, "lesson": _lesson_notes, "step": _step_notes}
    notes = describe[node.kind](snapshot, node) if node.kind in describe else []
    notes.append(
        "Ученики, которые остановились на удалённом месте, после публикации начнут урок "
        "с начала. Удаление касается только этого черновика."
    )
    return notes


def _section_notes(snapshot: dict[str, Any], node: EditorNode) -> list[str]:
    lessons = {lesson["slug"]: lesson for lesson in snapshot.get("lessons", [])}
    notes = []
    for slug in node.data.get("lessons", []):
        lesson = lessons.get(slug)
        if lesson is None:
            continue
        title = localized_title(lesson.get("title"), slug)
        if [s for s in _sections_of(snapshot, slug) if s is not node.data]:
            notes.append(f"Урок «{title}» останется: он есть и в другом разделе.")
        else:
            notes.append(f"Удалится урок «{title}» со всеми его шагами.")
    return notes or ["В разделе нет уроков."]


def _lesson_notes(snapshot: dict[str, Any], node: EditorNode) -> list[str]:
    steps = list(lesson_steps(snapshot, node.data))
    prayer = node.data.get("prayer")
    if prayer:
        notes = [
            f"Это урок-молитва. Его шаги ({len(steps)}) — из шаблона «"
            f"{template_label(snapshot, prayer.get('template', ''))}»: шаблон останется "
            "для других молитв."
        ]
    else:
        notes = [f"Удалятся шаги урока ({len(steps)}) с их заметками и записями."]
    sections = [
        localized_title(section.get("title"), section["slug"])
        for section in _sections_of(snapshot, node.data["slug"])
    ]
    if sections:
        notes.append(f"Урок пропадёт из раздела «{', '.join(sections)}».")
    return notes


def _step_notes(snapshot: dict[str, Any], node: EditorNode) -> list[str]:
    if node.template_id is not None:
        usage = template_step_usage(snapshot, node)
        places = "; ".join(f"{title} ({where})" if where else title for title, where in usage)
        notes = [f"Шаг общий: он удалится из шаблона и из всех этих мест — {places}."]
        variants = variant_descriptions(snapshot, node)
        if variants:
            notes.append(f"Другие варианты этого шага останутся: {'; '.join(variants)}.")
        return notes
    if node.lesson is not None:
        title = localized_title(node.lesson.get("title"), node.lesson["slug"])
        return [f"Шаг удалится из урока «{title}» с заметками и записями."]
    return []
