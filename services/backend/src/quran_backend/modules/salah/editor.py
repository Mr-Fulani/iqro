"""The draft editor of the prayer-learning course: the snapshot as a tree of texts.

Pure functions over the snapshot JSON, like `snapshot.py`; the admin views in
`editor_admin.py` render and save them. A prayer's steps live in its template,
so a step of Fajr is edited in the template and changes every prayer that uses
it. A draft may miss translations: they are counted and highlighted, and the
sign-off requires every one (`validate_snapshot`).

Node ids: `course`, `section:<slug>`, `lesson:<slug>`, `step:<step slug of the
compiled document>` (`step:fajr.r1.ruku`, `step:wudu.face`) and `formula:<id>`.
"""

from __future__ import annotations

# Russian interface strings intentionally contain characters that resemble Latin glyphs.
# ruff: noqa: RUF001, RUF002
import copy
import hashlib
import json
import re
import secrets
from collections.abc import Iterable, Iterator, Mapping, Sequence
from dataclasses import dataclass, field
from typing import Any

from quran_backend.modules.salah.snapshot import (
    AUDIO_SUFFIXES,
    NOTE_KINDS,
    prayer_step_sources,
)

# The owner writes the course in Russian first; the other languages follow.
SOURCE_LANGUAGE = "ru"
AUDIO_ALL = "all"
NOTE_MAX_LENGTH = 1200
NOTE_KIND_LABELS = {"help": "Справка «?»", "warning": "Важно «!»"}


@dataclass(frozen=True)
class TextField:
    name: str
    label: str
    help: str
    max_length: int
    rows: int
    required: bool = True


COURSE_FIELDS = (
    TextField(
        "source_title",
        "Источник курса",
        "Показывается на главной курса под заголовком.",
        200,
        rows=2,
    ),
)
SECTION_FIELDS = (TextField("title", "Название раздела", "", 120, rows=1),)
LESSON_FIELDS = (
    TextField("title", "Название урока", "", 120, rows=1),
    TextField(
        "summary",
        "Краткое описание",
        "Одно-два предложения: видны в списке уроков и в поиске.",
        400,
        rows=2,
    ),
)
STEP_FIELDS = (
    TextField("title", "Название шага", "", 120, rows=1),
    TextField("instruction", "Инструкция", "Что сделать на этом шаге.", 1500, rows=4),
    TextField(
        "details",
        "Подробности",
        "Пояснение, хукм, источник. Можно оставить пустыми на всех языках.",
        3000,
        rows=5,
        required=False,
    ),
)

_WHEN_SITTINGS = {
    "none": "без сидения",
    "middle_tashahhud": "средний ташаххуд",
    "final_tashahhud": "последний ташаххуд",
}


class EditorNodeNotFoundError(KeyError):
    pass


@dataclass
class EditorNode:
    id: str
    kind: str
    title: str
    # The dict of the snapshot that holds this node's fields (edited in place).
    data: dict[str, Any]
    fields: tuple[TextField, ...] = ()
    lesson: Mapping[str, Any] | None = None
    template_id: str | None = None
    template_index: int | None = None
    rakat: int | None = None

    @property
    def has_notes(self) -> bool:
        return self.kind == "step"

    @property
    def audio_owner(self) -> dict[str, Any] | None:
        """The dict whose `audio_media` keys a recording: a step, or a formula's source."""
        if self.kind == "step":
            return self.data
        if self.kind == "formula":
            return self.data["source"]
        return None


@dataclass
class TreeEntry:
    id: str
    label: str
    missing: int = 0
    notes: int = 0
    audio: bool = False
    children: list[TreeEntry] = field(default_factory=list)


# Reading -------------------------------------------------------------------


def editor_languages(languages: Iterable[str]) -> list[str]:
    """The project's languages, the source language first."""
    ordered = list(languages)
    return sorted(ordered, key=lambda code: (code != SOURCE_LANGUAGE, ordered.index(code)))


def localized_title(value: Any, fallback: str) -> str:
    if isinstance(value, Mapping):
        for text in (value.get(SOURCE_LANGUAGE), *value.values()):
            if isinstance(text, str) and text.strip():
                return text.strip()
    return fallback


def _templates(snapshot: Mapping[str, Any]) -> dict[str, dict[str, Any]]:
    return {template["id"]: template for template in snapshot.get("templates", [])}


def lesson_steps(snapshot: Mapping[str, Any], lesson: Mapping[str, Any]) -> Iterator[EditorNode]:
    """The lesson's steps as the learner meets them; a prayer's come from its template."""
    slug = lesson["slug"]
    prayer = lesson.get("prayer")
    if not prayer:
        for step in lesson.get("steps", []):
            yield EditorNode(
                id=f"step:{slug}.{step['slug']}",
                kind="step",
                title=localized_title(step.get("title"), step["slug"]),
                data=step,
                fields=STEP_FIELDS,
                lesson=lesson,
            )
        return
    templates = _templates(snapshot)
    template = templates.get(prayer.get("template"))
    if template is None:
        return
    for index, rakat in prayer_step_sources(lesson, templates):
        step = template["steps"][index]
        middle = f"r{rakat}." if rakat is not None else ""
        yield EditorNode(
            id=f"step:{slug}.{middle}{step['slug']}",
            kind="step",
            title=localized_title(step.get("title"), step["slug"]),
            data=step,
            fields=STEP_FIELDS,
            lesson=lesson,
            template_id=template["id"],
            template_index=index,
            rakat=rakat,
        )


def find_node(snapshot: dict[str, Any], node_id: str) -> EditorNode:
    kind, _, rest = node_id.partition(":")
    finder = _FINDERS.get("course" if node_id == "course" else kind)
    node = finder(snapshot, node_id, rest) if finder else None
    if node is None:
        raise EditorNodeNotFoundError(node_id)
    return node


def _course_node(snapshot: dict[str, Any], _node_id: str, _rest: str) -> EditorNode:
    return EditorNode(
        id="course", kind="course", title="Курс", data=snapshot["course"], fields=COURSE_FIELDS
    )


def _section_node(snapshot: dict[str, Any], node_id: str, slug: str) -> EditorNode | None:
    for section in snapshot.get("sections", []):
        if section["slug"] == slug:
            return EditorNode(
                id=node_id,
                kind="section",
                title=localized_title(section.get("title"), slug),
                data=section,
                fields=SECTION_FIELDS,
            )
    return None


def _lesson_node(snapshot: dict[str, Any], node_id: str, slug: str) -> EditorNode | None:
    for lesson in snapshot.get("lessons", []):
        if lesson["slug"] == slug:
            return EditorNode(
                id=node_id,
                kind="lesson",
                title=localized_title(lesson.get("title"), slug),
                data=lesson,
                fields=LESSON_FIELDS,
                lesson=lesson,
            )
    return None


def _step_node(snapshot: dict[str, Any], node_id: str, slug: str) -> EditorNode | None:
    lesson_slug = slug.split(".", 1)[0]
    for lesson in snapshot.get("lessons", []):
        if lesson["slug"] == lesson_slug:
            return next(
                (node for node in lesson_steps(snapshot, lesson) if node.id == node_id), None
            )
    return None


def _formula_node(snapshot: dict[str, Any], node_id: str, formula_id: str) -> EditorNode | None:
    for formula in snapshot.get("formulas", []):
        if formula.get("id") == formula_id:
            return EditorNode(id=node_id, kind="formula", title=formula_id, data=formula)
    return None


_FINDERS = {
    "course": _course_node,
    "section": _section_node,
    "lesson": _lesson_node,
    "step": _step_node,
    "formula": _formula_node,
}


def node_revision(snapshot: Mapping[str, Any], node: EditorNode) -> str:
    """Changes whenever anything the node's form shows changes, so a stale form is not saved.

    A step's form also holds the recordings of its formulas.
    """
    shown: list[Any] = [node.data]
    if node.kind == "step":
        formulas = {formula.get("id"): formula for formula in snapshot.get("formulas", [])}
        shown += [formulas.get(formula_id) for formula_id in node.data.get("formulas", [])]
    canonical = json.dumps(shown, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode()).hexdigest()[:16]


def _filled(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def missing_in(value: Any, languages: Sequence[str], *, required: bool = True) -> list[str]:
    """Languages without a text. An optional text is complete when it is empty everywhere."""
    texts = value if isinstance(value, Mapping) else {}
    missing = [language for language in languages if not _filled(texts.get(language))]
    if not required and len(missing) == len(languages):
        return []
    return missing


def node_missing(node: EditorNode, languages: Sequence[str]) -> dict[str, int]:
    """Untranslated texts of the node, by language."""
    counts = dict.fromkeys(languages, 0)
    for text_field in node.fields:
        for language in missing_in(
            node.data.get(text_field.name), languages, required=text_field.required
        ):
            counts[language] += 1
    if node.has_notes:
        for note in node.data.get("notes", []):
            for language in missing_in(note.get("text"), languages):
                counts[language] += 1
    return counts


def _all_nodes(snapshot: dict[str, Any]) -> Iterator[EditorNode]:
    """Every node once, a template step once however many prayers show it."""
    yield find_node(snapshot, "course")
    for section in snapshot.get("sections", []):
        yield find_node(snapshot, f"section:{section['slug']}")
    seen_template_steps: set[tuple[str, int]] = set()
    for lesson in snapshot.get("lessons", []):
        yield find_node(snapshot, f"lesson:{lesson['slug']}")
        for step in lesson_steps(snapshot, lesson):
            if step.template_id is not None:
                source = (step.template_id, step.template_index or 0)
                if source in seen_template_steps:
                    continue
                seen_template_steps.add(source)
            yield step


def course_missing(snapshot: dict[str, Any], languages: Sequence[str]) -> dict[str, int]:
    totals = dict.fromkeys(languages, 0)
    for node in _all_nodes(snapshot):
        for language, count in node_missing(node, languages).items():
            totals[language] += count
    return totals


def _has_audio(owner: Mapping[str, Any]) -> bool:
    return bool(owner.get("audio_media") or owner.get("audio_media_languages"))


def editor_tree(snapshot: dict[str, Any], languages: Sequence[str]) -> list[TreeEntry]:
    """Sections → lessons → steps, then the formulas, with untranslated counts."""
    lessons = {lesson["slug"]: lesson for lesson in snapshot.get("lessons", [])}
    tree = [TreeEntry(id="course", label="Курс: описание и источник")]
    tree[0].missing = sum(node_missing(find_node(snapshot, "course"), languages).values())
    for section in snapshot.get("sections", []):
        section_node = find_node(snapshot, f"section:{section['slug']}")
        entry = TreeEntry(
            id=section_node.id,
            label=section_node.title,
            missing=sum(node_missing(section_node, languages).values()),
        )
        for lesson_slug in section.get("lessons", []):
            lesson = lessons.get(lesson_slug)
            if lesson is None:
                continue
            lesson_node = find_node(snapshot, f"lesson:{lesson_slug}")
            lesson_entry = TreeEntry(
                id=lesson_node.id,
                label=lesson_node.title,
                missing=sum(node_missing(lesson_node, languages).values()),
            )
            for number, step in enumerate(lesson_steps(snapshot, lesson), start=1):
                prefix = f"Р{step.rakat} · " if step.rakat is not None else ""
                lesson_entry.children.append(
                    TreeEntry(
                        id=step.id,
                        label=f"{number}. {prefix}{step.title}",
                        missing=sum(node_missing(step, languages).values()),
                        notes=len(step.data.get("notes", [])),
                        audio=_has_audio(step.data),
                    )
                )
            entry.children.append(lesson_entry)
        tree.append(entry)
    formulas = TreeEntry(id="", label="Формулы: записи")
    for formula in snapshot.get("formulas", []):
        formulas.children.append(
            TreeEntry(
                id=f"formula:{formula['id']}",
                label=formula["id"],
                audio=_has_audio(formula.get("source") or {}),
            )
        )
    tree.append(formulas)
    return tree


def flat_ids(tree: Sequence[TreeEntry]) -> list[str]:
    """Node ids in tree order, for «previous» and «next»."""
    ids: list[str] = []
    for entry in tree:
        if entry.id:
            ids.append(entry.id)
        ids.extend(flat_ids(entry.children))
    return ids


def missing_ids(tree: Sequence[TreeEntry]) -> list[str]:
    ids: list[str] = []
    for entry in tree:
        if entry.id and entry.missing:
            ids.append(entry.id)
        ids.extend(missing_ids(entry.children))
    return ids


def describe_when(when: Mapping[str, Any]) -> str:
    """A template step's condition in words: «ракааты 2, 3, 4 · чтение вслух»."""
    parts: list[str] = []
    for key, value in when.items():
        if key == "first_rakat" and value:
            parts.append("первый ракаат")
        elif key == "last_rakat" and value:
            parts.append("последний ракаат")
        elif key == "rakat":
            values = value if isinstance(value, list) else [value]
            label = "ракаат" if len(values) == 1 else "ракааты"
            parts.append(f"{label} {', '.join(str(item) for item in values)}")
        elif key == "recitation":
            parts.append("чтение вслух" if value == "jahr" else "чтение про себя")
        elif key == "surah_after_fatiha":
            parts.append("с сурой после Фатихи" if value else "без суры после Фатихи")
        elif key == "sitting":
            values = value if isinstance(value, list) else [value]
            parts.append(" или ".join(_WHEN_SITTINGS.get(item, item) for item in values))
        elif key == "qunut":
            parts.append("с кунутом" if value else "без кунута")
    return " · ".join(parts) or "во всех ракаатах"


def template_step_usage(snapshot: dict[str, Any], node: EditorNode) -> list[tuple[str, str]]:
    """Lessons that show this template step: (lesson title, «ракааты 1, 2»)."""
    usage: list[tuple[str, str]] = []
    for lesson in snapshot.get("lessons", []):
        rakats = [
            step.rakat
            for step in lesson_steps(snapshot, lesson)
            if step.template_id == node.template_id and step.template_index == node.template_index
        ]
        if not rakats:
            continue
        numbered = [str(rakat) for rakat in rakats if rakat is not None]
        where = f"ракааты {', '.join(numbered)}" if len(numbered) > 1 else ""
        if len(numbered) == 1:
            where = f"ракаат {numbered[0]}"
        usage.append((localized_title(lesson.get("title"), lesson["slug"]), where))
    return usage


def step_variants(snapshot: dict[str, Any], node: EditorNode) -> list[dict[str, Any]]:
    """Other template steps with the same slug: the same step in other rak'ahs or prayers."""
    if node.template_id is None:
        return []
    return [
        step
        for template in snapshot.get("templates", [])
        for step in template.get("steps", [])
        if step.get("slug") == node.data.get("slug") and step is not node.data
    ]


def template_label(snapshot: Mapping[str, Any], template_id: str) -> str:
    """A template has no title of its own: «fard: Фаджр, Зухр, Аср…»."""
    titles = [
        localized_title(lesson.get("title"), lesson["slug"])
        for lesson in snapshot.get("lessons", [])
        if (lesson.get("prayer") or {}).get("template") == template_id
    ]
    shown = ", ".join(titles[:3]) + ("…" if len(titles) > 3 else "")
    return f"{template_id}: {shown}" if shown else template_id


def variant_descriptions(snapshot: Mapping[str, Any], node: EditorNode) -> list[str]:
    """Where the other variants of a template step are: «fard: Фаджр… — ракааты 2, 3, 4»."""
    if node.template_id is None:
        return []
    return [
        f"{template_label(snapshot, template['id'])} — {describe_when(step.get('when', {}))}"
        for template in snapshot.get("templates", [])
        for step in template.get("steps", [])
        if step.get("slug") == node.data.get("slug") and step is not node.data
    ]


def audio_slots(owner: Mapping[str, Any], languages: Sequence[str]) -> dict[str, str | None]:
    """The recording for every language (`all`) and each language's own voice-over."""
    by_language = owner.get("audio_media_languages") or {}
    return {
        AUDIO_ALL: owner.get("audio_media"),
        **{language: by_language.get(language) for language in languages},
    }


def formula_steps(snapshot: dict[str, Any], formula_id: str) -> list[EditorNode]:
    """The steps that show a formula, a template step once."""
    seen: set[int] = set()
    nodes = []
    for lesson in snapshot.get("lessons", []):
        for step in lesson_steps(snapshot, lesson):
            if formula_id in step.data.get("formulas", []) and id(step.data) not in seen:
                seen.add(id(step.data))
                nodes.append(step)
    return nodes


# Editing -------------------------------------------------------------------


@dataclass
class NodeEdit:
    """A parsed form: texts by field and language, and the notes in their new order."""

    texts: dict[str, dict[str, str]]
    notes: list[dict[str, Any]] | None
    errors: dict[str, str]


def clean_text(value: str) -> str:
    return re.sub(r"[ \t]+\n", "\n", value.replace("\r\n", "\n").replace("\r", "\n")).strip()


def parse_node_form(
    node: EditorNode, data: Mapping[str, Any], languages: Sequence[str]
) -> NodeEdit:
    """Reads `text-<field>-<lang>` and the notes `note-<uid>-…` listed in `notes_order`.

    Untranslated texts are allowed in a draft; too long ones and unknown note
    kinds are errors keyed by the form field, so the form shows them in place.
    """
    errors: dict[str, str] = {}
    texts: dict[str, dict[str, str]] = {}
    for text_field in node.fields:
        values = {}
        for language in languages:
            name = f"text-{text_field.name}-{language}"
            text = clean_text(str(data.get(name, "")))
            if len(text) > text_field.max_length:
                errors[name] = (
                    f"Слишком длинно: {len(text)} знаков, допустимо до {text_field.max_length}."
                )
            values[language] = text
        texts[text_field.name] = values
    notes: list[dict[str, Any]] | None = None
    if node.has_notes:
        notes = []
        order = [uid for uid in str(data.get("notes_order", "")).split(",") if uid.strip()]
        for uid in order:
            prefix = f"note-{uid.strip()}"
            text = {
                language: clean_text(str(data.get(f"{prefix}-text-{language}", "")))
                for language in languages
            }
            if not any(text.values()):
                # An added note left empty is simply not kept.
                continue
            kind = data.get(f"{prefix}-kind")
            if kind not in NOTE_KINDS:
                errors[f"{prefix}-kind"] = "Выберите тип заметки: справка «?» или важно «!»."
            for language, value in text.items():
                if len(value) > NOTE_MAX_LENGTH:
                    errors[f"{prefix}-text-{language}"] = (
                        f"Слишком длинно: {len(value)} знаков, допустимо до {NOTE_MAX_LENGTH}."
                    )
            notes.append({"kind": kind, "text": text, "uid": uid.strip()})
    return NodeEdit(texts=texts, notes=notes, errors=errors)


def _merged(old: Any, new: Mapping[str, str]) -> dict[str, str]:
    """New texts over the old ones, keeping a language no longer listed in the settings."""
    merged = dict(old) if isinstance(old, Mapping) else {}
    merged.update(new)
    return merged


def _same_texts(left: Any, right: Any, languages: Sequence[str]) -> bool:
    def normalized(value: Any) -> list[str]:
        texts = value if isinstance(value, Mapping) else {}
        return [str(texts.get(language) or "").strip() for language in languages]

    return normalized(left) == normalized(right)


def _same_notes(left: Any, right: Any, languages: Sequence[str]) -> bool:
    left_notes = left if isinstance(left, list) else []
    right_notes = right if isinstance(right, list) else []
    return len(left_notes) == len(right_notes) and all(
        a.get("kind") == b.get("kind") and _same_texts(a.get("text"), b.get("text"), languages)
        for a, b in zip(left_notes, right_notes, strict=True)
    )


def _set_text(owner: dict[str, Any], text_field: TextField, value: dict[str, str]) -> None:
    if not text_field.required and not any(_filled(text) for text in value.values()):
        owner.pop(text_field.name, None)
    else:
        owner[text_field.name] = value


def _set_notes(owner: dict[str, Any], notes: list[dict[str, Any]]) -> None:
    if notes:
        owner["notes"] = notes
    else:
        owner.pop("notes", None)


def apply_node_edit(
    snapshot: dict[str, Any],
    node: EditorNode,
    edit: NodeEdit,
    languages: Sequence[str],
    *,
    sync_variants: bool,
) -> int:
    """Writes the edit into the snapshot; returns how many other variants changed too.

    With `sync_variants`, a text of the same step in another rak'ah or prayer
    follows when it was identical in every language before the edit, so a
    correction reaches every place that showed the same words and never
    overwrites a text that differed.
    """
    old = copy.deepcopy(node.data)
    variants = step_variants(snapshot, node) if sync_variants else []
    # Decided before any text changes: the variants that show the same words.
    same_step = {id(variant) for variant in variants if _same_words(variant, old, languages)}
    touched: set[int] = set()
    for text_field in node.fields:
        new_value = _merged(old.get(text_field.name), edit.texts[text_field.name])
        if _same_texts(old.get(text_field.name), new_value, languages):
            continue
        _set_text(node.data, text_field, new_value)
        for variant in variants:
            if _same_texts(variant.get(text_field.name), old.get(text_field.name), languages):
                _set_text(variant, text_field, _merged(variant.get(text_field.name), new_value))
                touched.add(id(variant))
    if edit.notes is not None:
        notes = [{"kind": note["kind"], "text": note["text"]} for note in edit.notes]
        if not _same_notes(old.get("notes"), notes, languages):
            _set_notes(node.data, notes)
            for variant in variants:
                if id(variant) in same_step and _same_notes(
                    variant.get("notes"), old.get("notes"), languages
                ):
                    _set_notes(variant, copy.deepcopy(notes))
                    touched.add(id(variant))
    return len(touched)


def _same_words(
    variant: Mapping[str, Any], old: Mapping[str, Any], languages: Sequence[str]
) -> bool:
    """The same step for the learner: notes and recordings follow only such a variant."""
    return all(
        _same_texts(variant.get(name), old.get(name), languages)
        for name in ("title", "instruction")
    )


def audio_variants(
    snapshot: dict[str, Any],
    node: EditorNode,
    slot: str,
    old_key: str | None,
    languages: Sequence[str],
) -> list[dict[str, Any]]:
    """Variants that take this step's new recording too: the same words, the same old one.

    A voice-over in one language needs the same words in that language; a
    recording for every language needs them in all of them.
    """
    compared = languages if slot == AUDIO_ALL else [slot]
    return [
        variant
        for variant in step_variants(snapshot, node)
        if _same_words(variant, node.data, compared) and audio_slot(variant, slot) == old_key
    ]


def audio_slot(owner: Mapping[str, Any], slot: str) -> str | None:
    if slot == AUDIO_ALL:
        return owner.get("audio_media")
    return (owner.get("audio_media_languages") or {}).get(slot)


def set_audio_slot(owner: dict[str, Any], slot: str, key: str | None) -> None:
    if slot == AUDIO_ALL:
        if key:
            owner["audio_media"] = key
        else:
            owner.pop("audio_media", None)
        return
    by_language = dict(owner.get("audio_media_languages") or {})
    if key:
        by_language[slot] = key
    else:
        by_language.pop(slot, None)
    if by_language:
        owner["audio_media_languages"] = by_language
    else:
        owner.pop("audio_media_languages", None)


def new_audio_key(node: EditorNode, slot: str) -> str:
    """A fresh media key: a replaced recording never changes a file other places still use."""
    base = re.sub(r"[^a-z0-9]+", "-", node.id.split(":", 1)[-1].lower()).strip("-")
    kind = "formula" if node.kind == "formula" else "step"
    suffix = secrets.token_hex(3)
    return f"audio-{kind}-{base}"[: 96 - len(slot) - len(suffix) - 2] + f"-{slot}-{suffix}"


def add_audio_media(snapshot: dict[str, Any], key: str, suffix: str) -> None:
    if suffix not in AUDIO_SUFFIXES:
        raise ValueError(suffix)
    snapshot.setdefault("media", []).append({"key": key, "file": f"media/{key}{suffix}"})


def _audio_references(snapshot: Mapping[str, Any]) -> set[str]:
    owners: list[Mapping[str, Any]] = [
        formula.get("source") or {} for formula in snapshot.get("formulas", [])
    ]
    owners += [step for lesson in snapshot.get("lessons", []) for step in lesson.get("steps", [])]
    owners += [
        step for template in snapshot.get("templates", []) for step in template.get("steps", [])
    ]
    keys: set[str] = set()
    for owner in owners:
        if owner.get("audio_media"):
            keys.add(owner["audio_media"])
        keys.update((owner.get("audio_media_languages") or {}).values())
    return keys


def drop_unused_audio(snapshot: dict[str, Any], candidates: Iterable[str]) -> list[str]:
    """Removes from `media[]` the recordings among `candidates` that nothing plays any more."""
    used = _audio_references(snapshot)
    dropped = [key for key in candidates if key not in used]
    if dropped:
        snapshot["media"] = [
            asset for asset in snapshot.get("media", []) if asset.get("key") not in dropped
        ]
    return dropped
