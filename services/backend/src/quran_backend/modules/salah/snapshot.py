"""The course source snapshot: validation and expansion of prayer templates.

Pure functions over plain JSON, no database: the importer, the compiler and
the sequence snapshot tests share them.
"""

from __future__ import annotations

import hashlib
import json
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from quran_backend.modules.courses.snapshot_media import MEDIA_PROBLEM, media_valid
from quran_backend.modules.salah.models import SALAH_LANGUAGES

SNAPSHOT_SCHEMA_VERSION = 1

LESSON_KINDS = frozenset({"article", "steps", "prayer"})
STEP_KINDS = frozenset({"action", "recitation", "info"})
RULINGS = frozenset({"shart", "rukn", "wajib", "sunnah"})
RECITATIONS = frozenset({"jahr", "sirr"})
SITTINGS = frozenset({"none", "middle_tashahhud", "final_tashahhud"})
FORMULA_KINDS = frozenset({"dua", "quran", "inline"})
WHEN_KEYS = frozenset(
    {"first_rakat", "last_rakat", "surah_after_fatiha", "sitting", "qunut", "recitation", "rakat"}
)
# Poses and views of the schematic 3D scene (docs/salah/salah-3d.md). An illustration with
# `scene` is a still of that pose; clients that can run the scene show it instead.
SCENE_POSES = frozenset(
    {"qiyam", "takbir", "ruku", "itidal", "sujud", "sujud2", "jalsa", "tashahhud", "salam"}
)
SCENE_VIEWS = frozenset({"full", "hand", "back"})
# A step's notes open from small icons: «?» for a help note, «!» for a warning.
NOTE_KINDS = frozenset({"help", "warning"})
AUDIO_SUFFIXES = (".m4a", ".mp3")


@dataclass(frozen=True)
class _Known:
    """What a step may refer to: formula ids, media keys and, among them, recordings."""

    formulas: set[str]
    media: set[str]
    audio: set[str]


class SalahSnapshotError(ValueError):
    """Every problem found in a snapshot, so an editor fixes them in one pass."""

    def __init__(self, problems: Sequence[str]) -> None:
        self.problems = list(problems)
        super().__init__("\n".join(self.problems))


def load_snapshot(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as file:
        data = json.load(file)
    if not isinstance(data, dict):
        raise SalahSnapshotError(["Снимок должен быть JSON-объектом."])
    return data


def snapshot_checksum(snapshot: Mapping[str, Any]) -> str:
    canonical = json.dumps(snapshot, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode()).hexdigest()


def _rule_matches(when: Mapping[str, Any], rule: Mapping[str, Any], *, rakats: int) -> bool:
    rakat = int(rule["rakat"])
    for key, expected in when.items():
        if key == "first_rakat":
            actual: Any = rakat == 1
        elif key == "last_rakat":
            actual = rakat == rakats
        elif key == "rakat":
            values = expected if isinstance(expected, list) else [expected]
            if rakat not in values:
                return False
            continue
        else:
            actual = rule.get(key)
        if isinstance(expected, list):
            if actual not in expected:
                return False
        elif actual != expected:
            return False
    return True


def expand_lesson_steps(
    lesson: Mapping[str, Any],
    templates: Mapping[str, Mapping[str, Any]],
) -> list[dict[str, Any]]:
    """The lesson's linear steps; a prayer's template is unrolled per rakat.

    Step slugs are stable ids: `<lesson>.<step>` or `<lesson>.r<n>.<step>`.
    """
    slug = lesson["slug"]
    prayer = lesson.get("prayer")
    if not prayer:
        return [{**step, "slug": f"{slug}.{step['slug']}"} for step in lesson.get("steps", [])]
    template = templates[prayer["template"]]
    steps: list[dict[str, Any]] = []
    for index, rakat in prayer_step_sources(lesson, templates):
        step = template["steps"][index]
        expanded = {key: value for key, value in step.items() if key != "when"}
        if rakat is not None:
            expanded["slug"] = f"{slug}.r{rakat}.{step['slug']}"
            expanded["rakat"] = rakat
        else:
            expanded["slug"] = f"{slug}.{step['slug']}"
        steps.append(expanded)
    return steps


def prayer_step_sources(
    lesson: Mapping[str, Any], templates: Mapping[str, Mapping[str, Any]]
) -> list[tuple[int, int | None]]:
    """Each step of a prayer lesson as (index of its template step, rak'ah or None)."""
    prayer = lesson["prayer"]
    template = templates[prayer["template"]]
    rules = prayer["rakat_rules"]
    counts_rakats = template_counts_rakats(template)
    return [
        (index, int(rule["rakat"]) if counts_rakats else None)
        for rule in rules
        for index, step in enumerate(template["steps"])
        if _rule_matches(step.get("when", {}), rule, rakats=len(rules))
    ]


def audio_media_key(owner: Mapping[str, Any], language: str) -> str | None:
    """The recording of a step or a formula source in `language`.

    `audio_media_languages[language]` is a voice-over in that language; without
    it the step or formula sounds `audio_media` in every language.
    """
    by_language = owner.get("audio_media_languages") or {}
    return by_language.get(language) or owner.get("audio_media")


def template_counts_rakats(template: Mapping[str, Any]) -> bool:
    """False for a prayer without rak'ahs (the funeral prayer): one pass, no rak'ah counter."""
    return template.get("counts_rakats", True) is not False


# What a draft may still lack while it is written: the sign-off asks for it, a save does not.
_MISSING_TEXT = "нет текста на «"
_NO_STEPS = ": нет шагов."
_NO_ARABIC = ": нет арабского текста."
_NO_LESSONS = ": нет уроков."
_COMPLETENESS_MARKERS = (_MISSING_TEXT, _NO_STEPS, _NO_ARABIC, _NO_LESSONS)


def _localized(
    value: Any, where: str, problems: list[str], *, languages: Iterable[str] = SALAH_LANGUAGES
) -> None:
    if not isinstance(value, Mapping):
        problems.append(f"{where}: ожидаются тексты по языкам.")
        return
    for language in languages:
        text = value.get(language)
        if not isinstance(text, str) or not text.strip():
            problems.append(f"{where}: {_MISSING_TEXT}{language}».")


def _optional_localized(value: Any, where: str, problems: list[str]) -> None:
    """Empty in every language is fine; once written, every language is due."""
    if isinstance(value, Mapping) and not any(
        isinstance(text, str) and text.strip() for text in value.values()
    ):
        return
    _localized(value, where, problems)


def _check_course(snapshot: Mapping[str, Any], problems: list[str]) -> None:
    if snapshot.get("schema_version") != SNAPSHOT_SCHEMA_VERSION:
        problems.append(f"schema_version должен быть {SNAPSHOT_SCHEMA_VERSION}.")
    course = snapshot.get("course") or {}
    problems.extend(
        f"course.{field} обязателен."
        for field in ("slug", "version", "methodology")
        if not isinstance(course.get(field), str) or not course[field].strip()
    )
    _localized(course.get("source_title"), "course.source_title", problems)


def _check_formula_source(formula_id: str, source: Mapping[str, Any], problems: list[str]) -> None:
    kind = source.get("kind")
    where = f"Формула «{formula_id}»"
    if kind not in FORMULA_KINDS:
        problems.append(f"{where}: неизвестный источник «{kind}».")
    elif kind == "dua":
        if not (source.get("collection") and isinstance(source.get("source_number"), int)):
            problems.append(f"{where}: для дуа нужны collection и source_number.")
    elif kind == "quran":
        if not all(
            isinstance(source.get(field), int) for field in ("surah", "ayah_from", "ayah_to")
        ):
            problems.append(f"{where}: для Корана нужны surah, ayah_from, ayah_to.")
    else:
        if not isinstance(source.get("arabic"), str) or not source["arabic"].strip():
            problems.append(f"{where}{_NO_ARABIC}")
        translations = source.get("translations") or {}
        meanings = {
            language: translations.get(language, {}).get("meaning") for language in SALAH_LANGUAGES
        }
        _localized(meanings, f"{where}.translations", problems)
    if source.get("caption") is not None:
        _optional_localized(source["caption"], f"{where}.caption", problems)


def _check_formulas(snapshot: Mapping[str, Any], audio: set[str], problems: list[str]) -> set[str]:
    ids: set[str] = set()
    for formula in snapshot.get("formulas", []):
        formula_id = formula.get("id")
        if not formula_id or formula_id in ids:
            problems.append(f"Формула «{formula_id}»: пустой или повторяющийся id.")
            continue
        ids.add(formula_id)
        source = formula.get("source") or {}
        _check_formula_source(formula_id, source, problems)
        _check_audio(f"Формула «{formula_id}»", source, audio, problems)
    return ids


def _check_audio(
    where: str, owner: Mapping[str, Any], audio: set[str], problems: list[str]
) -> None:
    """`audio_media` and `audio_media_languages` name recordings of `media[]`."""
    keys = [owner["audio_media"]] if owner.get("audio_media") is not None else []
    by_language = owner.get("audio_media_languages")
    if by_language is not None:
        if not isinstance(by_language, Mapping):
            problems.append(f"{where}.audio_media_languages: ожидаются записи по языкам.")
            by_language = {}
        problems.extend(
            f"{where}: запись на неизвестном языке «{language}»."
            for language in by_language
            if language not in SALAH_LANGUAGES
        )
        keys.extend(by_language.values())
    problems.extend(f"{where}: нет записи «{key}» в media." for key in keys if key not in audio)


def _check_notes(where: str, notes: Any, problems: list[str]) -> None:
    if not isinstance(notes, list):
        problems.append(f"{where}.notes: ожидается список заметок.")
        return
    for number, note in enumerate(notes, start=1):
        if not isinstance(note, Mapping) or note.get("kind") not in NOTE_KINDS:
            problems.append(f"{where}, заметка {number}: тип должен быть help или warning.")
            continue
        _localized(note.get("text"), f"{where}, заметка {number}", problems)


def _check_media(snapshot: Mapping[str, Any], problems: list[str]) -> set[str]:
    """Every media key; recordings are the ones whose file is .m4a or .mp3."""
    keys: set[str] = set()
    for asset in snapshot.get("media", []):
        key = asset.get("key")
        if not key or key in keys:
            problems.append(f"Медиа «{key}»: пустой или повторяющийся key.")
            continue
        keys.add(key)
        if not asset.get("file"):
            problems.append(f"Медиа «{key}»: не указан файл.")
        if str(asset.get("file", "")).endswith(".webp"):
            _localized(asset.get("alt"), f"Медиа «{key}».alt", problems)
        if "scene" in asset:
            _check_scene(key, asset, problems)
    return keys


def _check_scene(key: str, asset: Mapping[str, Any], problems: list[str]) -> None:
    scene = asset["scene"]
    if not str(asset.get("file", "")).endswith(".webp"):
        problems.append(f"Медиа «{key}».scene: сцену задают только картинке — её кадру.")
    if not isinstance(scene, Mapping) or set(scene) != {"pose", "view"}:
        problems.append(f"Медиа «{key}».scene: ожидается {{pose, view}}.")
        return
    if scene["pose"] not in SCENE_POSES:
        problems.append(f"Медиа «{key}».scene: в сцене нет позы «{scene['pose']}».")
    if scene["view"] not in SCENE_VIEWS:
        problems.append(f"Медиа «{key}».scene: в сцене нет вида «{scene['view']}».")


def _check_prayer_kinds(snapshot: Mapping[str, Any], problems: list[str]) -> set[str]:
    """Kinds of prayer come from the course, so a new one needs no client release."""
    codes: set[str] = set()
    for kind in snapshot.get("prayer_kinds", []):
        code = kind.get("code")
        if not isinstance(code, str) or not code.strip() or code in codes:
            problems.append(f"Вид молитвы «{code}»: пустой или повторяющийся code.")
            continue
        codes.add(code)
        _localized(kind.get("title"), f"Вид молитвы «{code}».title", problems)
    if not codes:
        problems.append("prayer_kinds: нужен хотя бы один вид молитвы.")
    return codes


def _check_prayer(
    where: str,
    prayer: Mapping[str, Any],
    templates: Mapping[str, Any],
    kinds: set[str],
    problems: list[str],
) -> bool:
    """Whether the prayer block can be unrolled."""
    if prayer.get("kind") not in kinds:
        problems.append(f"{where}: неизвестный вид молитвы «{prayer.get('kind')}».")
    if prayer.get("template") not in templates:
        problems.append(f"{where}: нет шаблона «{prayer.get('template')}».")
        return False
    rules = prayer.get("rakat_rules") or []
    if not template_counts_rakats(templates[prayer["template"]]) and len(rules) != 1:
        problems.append(f"{where}: в молитве без ракаатов нужно ровно одно правило.")
        return False
    if [rule.get("rakat") for rule in rules] != list(range(1, len(rules) + 1)):
        problems.append(f"{where}: ракааты в rakat_rules должны идти 1..N.")
        return False
    for rule in rules:
        if rule.get("recitation") not in RECITATIONS:
            problems.append(f"{where}, ракаат {rule.get('rakat')}: recitation jahr|sirr.")
        if rule.get("sitting") not in SITTINGS:
            problems.append(f"{where}, ракаат {rule.get('rakat')}: неизвестное сидение.")
    return True


def _check_steps(steps: Sequence[Mapping[str, Any]], known: _Known, problems: list[str]) -> None:
    seen: set[str] = set()
    for step in steps:
        where = f"Шаг «{step['slug']}»"
        if step["slug"] in seen:
            problems.append(f"{where}: повторяется в уроке.")
        seen.add(step["slug"])
        if step.get("kind") not in STEP_KINDS:
            problems.append(f"{where}: неизвестный вид «{step.get('kind')}».")
        if step.get("ruling") is not None and step["ruling"] not in RULINGS:
            problems.append(f"{where}: неизвестный хукм «{step['ruling']}».")
        _localized(step.get("title"), f"{where}.title", problems)
        _localized(step.get("instruction"), f"{where}.instruction", problems)
        if step.get("details") is not None:
            _localized(step["details"], f"{where}.details", problems)
        problems.extend(
            f"{where}: нет формулы «{formula_id}»."
            for formula_id in step.get("formulas", [])
            if formula_id not in known.formulas
        )
        if step.get("media") is not None and step["media"] not in known.media:
            problems.append(f"{where}: нет медиа «{step['media']}».")
        if step.get("notes") is not None:
            _check_notes(where, step["notes"], problems)
        _check_audio(where, step, known.audio, problems)


def _check_lessons(
    snapshot: Mapping[str, Any], known: _Known, kinds: set[str], problems: list[str]
) -> set[str]:
    templates = {template.get("id"): template for template in snapshot.get("templates", [])}
    for template_id, template in templates.items():
        for step in template.get("steps", []):
            unknown = set(step.get("when", {})) - WHEN_KEYS
            if unknown:
                problems.append(
                    f"Шаблон «{template_id}», шаг «{step.get('slug')}»: условия {sorted(unknown)}."
                )
    slugs: set[str] = set()
    for lesson in snapshot.get("lessons", []):
        slug = lesson.get("slug")
        where = f"Урок «{slug}»"
        if not slug or slug in slugs:
            problems.append(f"{where}: пустой или повторяющийся slug.")
            continue
        slugs.add(slug)
        if lesson.get("kind") not in LESSON_KINDS:
            problems.append(f"{where}: неизвестный вид «{lesson.get('kind')}».")
        _localized(lesson.get("title"), f"{where}.title", problems)
        _localized(lesson.get("summary"), f"{where}.summary", problems)
        # Video, slides and banners of the lesson (docs/salah/lesson-media.md).
        if not media_valid(lesson.get("media", [])):
            problems.append(f"{where}: {MEDIA_PROBLEM}")
        prayer = lesson.get("prayer")
        if lesson.get("kind") == "prayer":
            if not prayer:
                problems.append(f"{where}: молитве не хватает блока prayer.")
                continue
            if not _check_prayer(where, prayer, templates, kinds, problems):
                continue
        elif prayer:
            problems.append(f"{where}: блок prayer допустим лишь в уроках-молитвах.")
        steps = expand_lesson_steps(lesson, templates)
        if not steps:
            problems.append(f"{where}{_NO_STEPS}")
        _check_steps(steps, known, problems)
    return slugs


def _check_sections(snapshot: Mapping[str, Any], lessons: set[str], problems: list[str]) -> None:
    listed: set[str] = set()
    for section in snapshot.get("sections", []):
        where = f"Раздел «{section.get('slug')}»"
        _localized(section.get("title"), f"{where}.title", problems)
        if not section.get("lessons"):
            problems.append(f"{where}{_NO_LESSONS}")
        for lesson_slug in section.get("lessons", []):
            if lesson_slug not in lessons:
                problems.append(f"{where}: нет урока «{lesson_slug}».")
            listed.add(lesson_slug)
    problems.extend(
        f"Урок «{slug}» не входит ни в один раздел." for slug in sorted(lessons - listed)
    )


def integrity_problems(snapshot: Mapping[str, Any]) -> list[str]:
    """What even a draft being written may not have: a broken reference, a duplicate, an
    unknown kind. Untranslated texts and an empty lesson wait for the sign-off."""
    try:
        validate_snapshot(snapshot)
    except SalahSnapshotError as error:
        return [
            problem
            for problem in error.problems
            if not any(marker in problem for marker in _COMPLETENESS_MARKERS)
        ]
    return []


def validate_snapshot(snapshot: Mapping[str, Any]) -> None:
    """Raises SalahSnapshotError listing every problem; returns when valid."""
    problems: list[str] = []
    _check_course(snapshot, problems)
    media = _check_media(snapshot, problems)
    audio = {
        asset["key"]
        for asset in snapshot.get("media", [])
        if asset.get("key") in media and str(asset.get("file", "")).lower().endswith(AUDIO_SUFFIXES)
    }
    formulas = _check_formulas(snapshot, audio, problems)
    kinds = _check_prayer_kinds(snapshot, problems)
    lessons = _check_lessons(snapshot, _Known(formulas, media, audio), kinds, problems)
    _check_sections(snapshot, lessons, problems)
    if problems:
        raise SalahSnapshotError(problems)
