"""Tajweed practice (docs/tajweed/practice.md): tasks from the markup of the whole
Quran for the targets of passed lessons, and the score, streak and review list
computed from the learner's sessions.

`apply_session` is the same function in the web (`lib/tajweed-practice.ts`)
and the app (`tajweed_practice.dart`): the state is never stored, only
recomputed from sessions in order, so devices that send sessions in any order
end with the same state.
"""

from __future__ import annotations

import random
import re
import uuid
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from typing import Any

from django.db import transaction
from django.db.models import QuerySet
from django.db.models.functions import Length

from quran_backend.modules.tajweed.course_examples import course_example, target_filter
from quran_backend.modules.tajweed.course_markers import (
    TARGETS,
    Occurrence,
    occurrences,
    parse_course_words,
)
from quran_backend.modules.tajweed.models import AyahTajweed, TajweedPracticeSession
from quran_backend.modules.tajweed.progress import LESSON_SLUG, iso_millis

TASK_TYPES = ("find", "identify", "listen")
MAX_TASKS = 12
DEFAULT_TASKS = 8
MAX_REVIEW = 6
MAX_OPTIONS = 4
# Short ayahs fit a phone screen; the markup text of 20 words is about 400 characters.
MAX_WORDS = 20
MAX_SOURCE_LENGTH = 600
PICK_ATTEMPTS = 12
# Days until a task in a box is asked again after a right answer; box 1 waits for nothing.
REVIEW_DAYS = {2: 1, 3: 3}
LAST_BOX = 3
_FIELDS = ("verse_key", "surah_number", "ayah_number", "page_number", "source_text", "words")


def task_key(task_type: str, verse_key: str, target: str) -> str:
    return f"{task_type}~{verse_key}~{target}"


def parse_task_key(key: str) -> tuple[str, str, str] | None:
    parts = key.split("~")
    if len(parts) != 3 or parts[0] not in TASK_TYPES:
        return None
    return parts[0], parts[1], parts[2]


# State -----------------------------------------------------------------------


@dataclass
class PracticeState:
    sessions: int = 0
    answers: int = 0
    correct: int = 0
    current_streak: int = 0
    best_streak: int = 0
    last_date: date | None = None
    review: dict[str, dict[str, Any]] = field(default_factory=dict)

    def as_dict(self, course: str) -> dict[str, Any]:
        return {
            "course": course,
            "sessions": self.sessions,
            "answers": self.answers,
            "correct": self.correct,
            "score": self.correct,
            "streak": {
                "current": self.current_streak,
                "best": self.best_streak,
                "last_date": self.last_date.isoformat() if self.last_date else None,
            },
            "review": sorted(self.review.values(), key=lambda item: (item["due_at"], item["key"])),
        }


def _moment(value: str) -> datetime:
    return datetime.fromisoformat(value)


def apply_session(state: PracticeState, session: Mapping[str, Any]) -> PracticeState:
    """The state after one more session: score, day streak and the Leitner boxes."""
    day = date.fromisoformat(session["local_date"])
    state.sessions += 1
    if state.last_date is None or day > state.last_date:
        if state.last_date is not None and day == state.last_date + timedelta(days=1):
            state.current_streak += 1
        else:
            state.current_streak = 1
        state.best_streak = max(state.best_streak, state.current_streak)
        state.last_date = day
    for answer in session["answers"]:
        state.answers += 1
        key = answer["key"]
        if not answer["correct"]:
            state.review[key] = {
                "key": key,
                "target": answer["target"],
                "type": answer["type"],
                "box": 1,
                "due_at": iso_millis(_moment(answer["at"])),
            }
            continue
        state.correct += 1
        item = state.review.get(key)
        if item is None:
            continue
        if item["box"] >= LAST_BOX:
            del state.review[key]
            continue
        box = item["box"] + 1
        due = _moment(answer["at"]) + timedelta(days=REVIEW_DAYS[box])
        state.review[key] = {**item, "box": box, "due_at": iso_millis(due)}
    return state


def practice_state(sessions: Iterable[Mapping[str, Any]]) -> PracticeState:
    state = PracticeState()
    for session in sorted(sessions, key=lambda item: (item["finished_at"], str(item["id"]))):
        apply_session(state, session)
    return state


# Tasks -----------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class _Ayah:
    row: Mapping[str, Any]
    words: Sequence[Any]


def _overlaps(left: Occurrence, right: Occurrence) -> bool:
    return any(
        a.position == b.position and a.start < b.end and b.start < a.end
        for a in left.parts
        for b in right.parts
    )


class TaskBuilder:
    """Builds the tasks of one practice session from the published markup."""

    def __init__(self, ayahs: QuerySet[AyahTajweed], targets: Sequence[str], seed: int) -> None:
        self.ayahs = ayahs
        self.targets = list(dict.fromkeys(targets))
        self.rng = random.Random(seed)  # noqa: S311 - a lesson exercise, not a secret
        self.used: set[tuple[str, str]] = set()
        self.candidates: dict[str, list[str]] = {}

    def _ayah(self, verse_key: str) -> _Ayah | None:
        row = (
            self.ayahs.filter(verse_key=verse_key)
            .values(
                "verse_key", "surah_number", "ayah_number", "page_number", "source_text", "words"
            )
            .first()
        )
        if row is None:
            return None
        words = parse_course_words(row["verse_key"], row["source_text"], row["words"])
        return _Ayah(row, words) if words is not None else None

    def _candidates(self, target: str) -> list[str]:
        if target not in self.candidates:
            self.candidates[target] = list(
                self.ayahs.filter(target_filter(target))
                .annotate(length=Length("source_text"))
                .filter(length__lte=MAX_SOURCE_LENGTH)
                .order_by("surah_number", "ayah_number")
                .values_list("verse_key", flat=True)
            )
        return self.candidates[target]

    def _options(self, ayah: _Ayah, target: str, focus: Occurrence) -> list[str]:
        """The right target and up to three others whose places miss the asked letters."""
        others = [
            other
            for other in self.targets
            if other != target
            and not any(_overlaps(focus, place) for place in occurrences(ayah.words, other))
        ]
        options = [target, *self.rng.sample(others, min(len(others), MAX_OPTIONS - 1))]
        self.rng.shuffle(options)
        return options

    def task(
        self, ayah: _Ayah, task_type: str, target: str, *, review: bool
    ) -> dict[str, Any] | None:
        places = occurrences(ayah.words, target)
        if not places:
            return None
        focus = 0 if task_type == "find" else self.rng.randrange(len(places))
        example = course_example(ayah.row, target)
        if example is None:
            return None
        task: dict[str, Any] = {
            "key": task_key(task_type, ayah.row["verse_key"], target),
            "type": task_type,
            "target": target,
            "review": review,
            "example": example,
            "focus": focus,
        }
        if task_type != "find":
            task["options"] = self._options(ayah, target, places[focus])
        self.used.add((ayah.row["verse_key"], target))
        return task

    def review_task(self, key: str) -> dict[str, Any] | None:
        parsed = parse_task_key(key)
        if parsed is None:
            return None
        task_type, verse_key, target = parsed
        if target not in self.targets or (verse_key, target) in self.used:
            return None
        if task_type != "find" and len(self.targets) < 2:
            task_type = "find"
        ayah = self._ayah(verse_key)
        return self.task(ayah, task_type, target, review=True) if ayah else None

    def random_task(self) -> dict[str, Any] | None:
        target = self.rng.choice(self.targets)
        task_type = "find" if len(self.targets) < 2 else self.rng.choice(TASK_TYPES)
        candidates = self._candidates(target)
        for _ in range(PICK_ATTEMPTS if candidates else 0):
            verse_key = self.rng.choice(candidates)
            if (verse_key, target) in self.used:
                continue
            ayah = self._ayah(verse_key)
            if ayah is None or len(ayah.words) > MAX_WORDS:
                continue
            task = self.task(ayah, task_type, target, review=False)
            if task is not None:
                return task
        return None


def practice_tasks(
    ayahs: QuerySet[AyahTajweed],
    *,
    targets: Sequence[str],
    count: int,
    seed: int,
    review: Sequence[str],
) -> list[dict[str, Any]]:
    """Review tasks first, then random ones; fewer than `count` only when the markup runs out."""
    builder = TaskBuilder(ayahs, targets, seed)
    tasks = [task for key in review[:MAX_REVIEW] if (task := builder.review_task(key))]
    attempts = 0
    while len(tasks) < count and attempts < count * 3:
        attempts += 1
        task = builder.random_task()
        if task is not None:
            tasks.append(task)
    return tasks[:count]


# Sessions --------------------------------------------------------------------

MAX_ANSWERS = 50
VERSE_KEY = re.compile(r"^\d{1,3}:\d{1,3}$")


class PracticeSessionError(ValueError):
    """The session does not fit the contract."""


class PracticeSessionConflictError(Exception):
    """The session id is already stored with other content."""


def _aware(value: object, where: str) -> datetime:
    if not isinstance(value, str):
        raise PracticeSessionError(f"{where} must be an ISO date and time.")
    try:
        moment = datetime.fromisoformat(value)
    except ValueError as error:
        raise PracticeSessionError(f"{where} must be an ISO date and time.") from error
    if moment.tzinfo is None:
        raise PracticeSessionError(f"{where} needs a time zone.")
    return moment


def clean_session(value: object) -> dict[str, Any]:
    """The session of a request in the stored form, or PracticeSessionError."""
    if not isinstance(value, Mapping):
        raise PracticeSessionError("The session must be an object.")
    try:
        session_id = str(uuid.UUID(str(value.get("id"))))
    except ValueError as error:
        raise PracticeSessionError("id must be a UUID.") from error
    course = value.get("course")
    if not isinstance(course, str) or not LESSON_SLUG.match(course) or len(course) > 64:
        raise PracticeSessionError("course must be a course slug.")
    try:
        local_date = date.fromisoformat(str(value.get("local_date")))
    except ValueError as error:
        raise PracticeSessionError("local_date must be YYYY-MM-DD.") from error
    answers = value.get("answers")
    if not isinstance(answers, list) or len(answers) > MAX_ANSWERS:
        raise PracticeSessionError(f"answers must be a list of at most {MAX_ANSWERS}.")
    cleaned: list[dict[str, Any]] = []
    for index, answer in enumerate(answers):
        where = f"answers[{index}]"
        parsed = parse_task_key(answer.get("key", "")) if isinstance(answer, Mapping) else None
        if (
            not isinstance(answer, Mapping)
            or parsed is None
            or not VERSE_KEY.match(parsed[1])
            or parsed[2] not in TARGETS
            or answer.get("type") != parsed[0]
            or answer.get("target") != parsed[2]
            or not isinstance(answer.get("correct"), bool)
        ):
            raise PracticeSessionError(f"{where} does not fit the contract.")
        cleaned.append(
            {
                "key": answer["key"],
                "target": parsed[2],
                "type": parsed[0],
                "correct": answer["correct"],
                "at": iso_millis(_aware(answer.get("at"), f"{where}.at")),
            }
        )
    return {
        "id": session_id,
        "course": course,
        "local_date": local_date.isoformat(),
        "finished_at": iso_millis(_aware(value.get("finished_at"), "finished_at")),
        "answers": cleaned,
    }


def _stored(row: TajweedPracticeSession) -> dict[str, Any]:
    return {
        "id": str(row.id),
        "course": row.course,
        "local_date": row.local_date.isoformat(),
        "finished_at": iso_millis(row.finished_at),
        "answers": row.answers,
    }


def user_practice_state(user: Any, course: str) -> dict[str, Any]:
    rows = TajweedPracticeSession.objects.filter(user=user, course=course)
    return practice_state(_stored(row) for row in rows).as_dict(course)


@transaction.atomic
def record_practice_session(user: Any, value: object) -> tuple[dict[str, Any], bool]:
    """Stores a session once; the same session again is a no-op, other content a conflict."""
    session = clean_session(value)
    existing = TajweedPracticeSession.objects.select_for_update().filter(id=session["id"]).first()
    if existing is not None:
        if existing.user_id != user.id or _stored(existing) != session:
            raise PracticeSessionConflictError
        return user_practice_state(user, session["course"]), False
    TajweedPracticeSession.objects.create(
        id=session["id"],
        user=user,
        course=session["course"],
        local_date=date.fromisoformat(session["local_date"]),
        finished_at=_aware(session["finished_at"], "finished_at"),
        answers=session["answers"],
    )
    return user_practice_state(user, session["course"]), True
