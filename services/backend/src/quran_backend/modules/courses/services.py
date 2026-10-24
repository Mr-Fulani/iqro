# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""Release cycle of a course: prepare → (return) → sign → publish → hide / roll back.

Every operation checks the user's right here, not only in the admin buttons
(docs/courses/plan.md, 6.4), locks the course row and, after commit, tells the
site which course changed.
"""

from __future__ import annotations

from typing import Any

from django.conf import settings
from django.contrib.admin.models import ADDITION, CHANGE, LogEntry
from django.contrib.contenttypes.models import ContentType
from django.core.exceptions import PermissionDenied
from django.db import transaction
from django.db.models import Max
from django.utils import timezone

from quran_backend.modules.core.content_revalidation import enqueue_course_change
from quran_backend.modules.courses.document import (
    MAX_DOCUMENT_BYTES,
    build_document,
    build_snapshot,
    canonical_json,
    catalog_card,
    checksum,
    readiness,
)
from quran_backend.modules.courses.models import (
    COURSE_LANGUAGES,
    Course,
    CourseDocument,
    CourseLesson,
    CourseRelease,
    CourseReleaseStatus,
)

MAX_REVIEW_NOTE = 2000
MAX_REASON = 300


class CourseReleaseError(Exception):
    def __init__(self, problems: list[str]) -> None:
        super().__init__("; ".join(problems))
        self.problems = problems


def can_sign(user: Any) -> bool:
    return bool(user.has_perm("courses.sign_course"))


def can_publish(user: Any) -> bool:
    return bool(user.has_perm("courses.publish_course"))


def _require(allowed: bool) -> None:
    if not allowed:
        raise PermissionDenied


def _locked_course(course_id: Any) -> Course:
    return Course.objects.select_for_update().get(pk=course_id)


def _locked_release(release: CourseRelease) -> CourseRelease:
    return CourseRelease.objects.select_for_update().select_related("course").get(pk=release.pk)


@transaction.atomic
def prepare_release(
    course: Course, user: Any, *, languages: list[str], change_note: str
) -> CourseRelease:
    """Freezes the course as release N «на проверке» with a document per language."""
    _require(user.has_perm("courses.change_course"))
    course = _locked_course(course.pk)
    problems: list[str] = []
    in_review = course.releases.filter(status=CourseReleaseStatus.IN_REVIEW).first()
    if in_review is not None:
        problems.append(
            f"Выпуск {in_review.number} уже на проверке. Отзовите его или дождитесь подписи."
        )
    change_note = change_note.strip()
    if not change_note:
        problems.append("Напишите, что изменилось.")
    elif len(change_note) > 500:
        problems.append("«Что изменилось» — не больше 500 знаков.")
    chosen = [language for language in COURSE_LANGUAGES if language in set(languages)]
    if not chosen:
        problems.append("Отметьте хотя бы один язык.")
    snapshot = build_snapshot(course)
    missing = readiness(snapshot)
    problems += [
        f"{language}: {problem.text}" for language in chosen for problem in missing[language]
    ]
    digest = checksum(snapshot)
    live = course.live_release
    if live is not None and live.checksum_sha256 == digest and sorted(live.languages) == chosen:
        problems.append(f"Нет изменений с выпуска {live.number}, который на сайте.")
    if problems:
        raise CourseReleaseError(problems)
    number = (course.releases.aggregate(last=Max("number"))["last"] or 0) + 1
    release = CourseRelease.objects.create(
        course=course,
        number=number,
        based_on=live,
        languages=chosen,
        snapshot=snapshot,
        checksum_sha256=digest,
        change_note=change_note,
        submitted_by=user,
        submitted_at=timezone.now(),
    )
    for language in chosen:
        payload = build_document(
            snapshot, language=language, version=release.version, languages=chosen
        )
        encoded = canonical_json(payload)
        if len(encoded) > MAX_DOCUMENT_BYTES:
            raise CourseReleaseError(
                [f"{language}: документ больше 2 МиБ. Сократите конспекты или разделите курс."]
            )
        CourseDocument.objects.create(
            release=release,
            language=language,
            payload=payload,
            card=catalog_card(payload),
            checksum_sha256=checksum(payload),
            bytes=len(encoded),
        )
    return release


@transaction.atomic
def withdraw_from_review(release: CourseRelease, user: Any) -> CourseRelease:
    """The author (or a reviewer) takes the release back to fix something."""
    release = _locked_release(release)
    _require(release.submitted_by_id == user.pk or can_sign(user))
    _expect(release, CourseReleaseStatus.IN_REVIEW, "Отозвать можно только выпуск на проверке.")
    release.status = CourseReleaseStatus.RETURNED
    release.save(update_fields=["status", "updated_at"])
    return release


@transaction.atomic
def return_for_rework(release: CourseRelease, user: Any, *, comment: str) -> CourseRelease:
    """The reviewer's remark; the owner sees it on the course page."""
    _require(can_sign(user))
    release = _locked_release(release)
    _expect(release, CourseReleaseStatus.IN_REVIEW, "Вернуть можно только выпуск на проверке.")
    comment = comment.strip()
    if not comment:
        raise CourseReleaseError(["Напишите, что исправить."])
    if len(comment) > MAX_REVIEW_NOTE:
        raise CourseReleaseError([f"Комментарий — не больше {MAX_REVIEW_NOTE} знаков."])
    release.status = CourseReleaseStatus.RETURNED
    release.review_note = comment
    release.save(update_fields=["status", "review_note", "updated_at"])
    return release


@transaction.atomic
def sign_release(release: CourseRelease, user: Any, *, note: str = "") -> CourseRelease:
    _require(can_sign(user))
    release = _locked_release(release)
    _expect(release, CourseReleaseStatus.IN_REVIEW, "Подписать можно только выпуск на проверке.")
    unwatched = new_videos(release) - set(release.watched_videos)
    if unwatched:
        raise CourseReleaseError(["Отметьте «Просмотрено» у каждого нового видео."])
    if settings.COURSES_STRICT_REVIEW and user.pk in release_authors(release):
        raise CourseReleaseError(
            ["Строгий режим: подписывает не тот, кто готовил выпуск или правил его темы."]
        )
    if len(note.strip()) > MAX_REVIEW_NOTE:
        raise CourseReleaseError([f"Примечание — не больше {MAX_REVIEW_NOTE} знаков."])
    release.status = CourseReleaseStatus.SIGNED
    release.reviewed_by = user
    release.reviewed_at = timezone.now()
    release.review_note = note.strip()
    release.save(
        update_fields=["status", "reviewed_by", "reviewed_at", "review_note", "updated_at"]
    )
    return release


@transaction.atomic
def publish_release(release: CourseRelease, user: Any) -> CourseRelease:
    """Signed → on the site; the previous live release is superseded."""
    _require(can_publish(user))
    release = _locked_release(release)
    course = _locked_course(release.course_id)
    _expect(release, CourseReleaseStatus.SIGNED, "Опубликовать можно только подписанный выпуск.")
    live = course.live_release
    if live is not None and live.number > release.number:
        raise CourseReleaseError(
            [f"На сайте более новый выпуск {live.number}. Подготовьте новый выпуск."]
        )
    now = timezone.now()
    if live is not None:
        _end(live, CourseReleaseStatus.SUPERSEDED, user, now, f"Заменён выпуском {release.number}.")
    release.status = CourseReleaseStatus.PUBLISHED
    release.published_by = user
    release.published_at = now
    release.save(update_fields=["status", "published_by", "published_at", "updated_at"])
    _go_live(course, release)
    return release


@transaction.atomic
def hide_course(course: Course, user: Any, *, reason: str) -> Course:
    _require(can_publish(user))
    course = _locked_course(course.pk)
    if course.live_release is None:
        raise CourseReleaseError(["Курса ещё нет на сайте."])
    if course.hidden_at is not None:
        raise CourseReleaseError(["Курс уже скрыт."])
    course.hidden_reason = _reason(reason)
    course.hidden_at = timezone.now()
    course.save(update_fields=["hidden_at", "hidden_reason", "updated_at"])
    enqueue_course_change(
        action="withdrawn", course=course.slug, version=course.live_release.version
    )
    return course


@transaction.atomic
def show_course(course: Course, user: Any) -> Course:
    _require(can_publish(user))
    course = _locked_course(course.pk)
    if course.live_release is None or course.hidden_at is None:
        raise CourseReleaseError(["Курс не скрыт."])
    course.hidden_at = None
    course.hidden_reason = ""
    course.save(update_fields=["hidden_at", "hidden_reason", "updated_at"])
    enqueue_course_change(
        action="activated", course=course.slug, version=course.live_release.version
    )
    return course


@transaction.atomic
def roll_back(
    course: Course, target: CourseRelease, user: Any, *, reason: str, faulty: bool = False
) -> CourseRelease:
    """Puts a superseded release back; the current one is superseded or withdrawn for good."""
    _require(can_publish(user))
    course = _locked_course(course.pk)
    target = _locked_release(target)
    if target.course_id != course.pk:
        raise CourseReleaseError(["Это выпуск другого курса."])
    if target.status != CourseReleaseStatus.SUPERSEDED:
        raise CourseReleaseError(
            ["Вернуть можно только заменённый выпуск. Ошибочный выпуск не возвращается никогда."]
        )
    reason = _reason(reason)
    live = course.live_release
    if live is None:
        raise CourseReleaseError(["Курса нет на сайте."])
    status = CourseReleaseStatus.WITHDRAWN if faulty else CourseReleaseStatus.SUPERSEDED
    _end(live, status, user, timezone.now(), reason)
    target.status = CourseReleaseStatus.PUBLISHED
    target.ended_by = None
    target.ended_at = None
    target.end_reason = ""
    target.save(update_fields=["status", "ended_by", "ended_at", "end_reason", "updated_at"])
    _go_live(course, target)
    return target


def new_videos(release: CourseRelease) -> set[str]:
    """SHA-256 of the videos this release adds or replaces; none before stage 2."""
    old = release.based_on.snapshot["lessons"] if release.based_on else []
    before = {lesson["video"]["sha256"] for lesson in old if lesson.get("video")}
    return {
        lesson["video"]["sha256"]
        for lesson in release.snapshot["lessons"]
        if lesson.get("video") and lesson["video"]["sha256"] not in before
    }


def release_authors(release: CourseRelease) -> set[Any]:
    """Who prepared the release or edited it in the admin since the previous one."""
    authors = {release.submitted_by_id}
    previous = {lesson["id"]: lesson["checksum"] for lesson in _based_on_lessons(release)}
    changed = [
        lesson["id"]
        for lesson in release.snapshot["lessons"]
        if previous.get(lesson["id"]) != lesson["checksum"]
    ]
    edits = LogEntry.objects.filter(
        action_flag__in=(ADDITION, CHANGE),
        action_time__lte=release.submitted_at,
        # Form saves; release actions are logged as plain sentences.
        change_message__startswith="[",
    )
    if release.based_on is not None:
        edits = edits.filter(action_time__gt=release.based_on.submitted_at)
    course_type = ContentType.objects.get_for_model(Course)
    lesson_type = ContentType.objects.get_for_model(CourseLesson)
    authors |= set(
        edits.filter(content_type=course_type, object_id=str(release.course_id)).values_list(
            "user_id", flat=True
        )
    )
    authors |= set(
        edits.filter(content_type=lesson_type, object_id__in=changed).values_list(
            "user_id", flat=True
        )
    )
    return authors


def _based_on_lessons(release: CourseRelease) -> list[dict[str, Any]]:
    return release.based_on.snapshot["lessons"] if release.based_on else []


def _expect(release: CourseRelease, status: str, message: str) -> None:
    if release.status != status:
        raise CourseReleaseError([message])


def _reason(reason: str) -> str:
    reason = reason.strip()
    if not reason:
        raise CourseReleaseError(["Укажите причину."])
    if len(reason) > MAX_REASON:
        raise CourseReleaseError([f"Причина — не больше {MAX_REASON} знаков."])
    return reason


def _end(release: CourseRelease, status: str, user: Any, when: Any, reason: str) -> None:
    release.status = status
    release.ended_by = user
    release.ended_at = when
    release.end_reason = reason
    release.save(update_fields=["status", "ended_by", "ended_at", "end_reason", "updated_at"])


def _go_live(course: Course, release: CourseRelease) -> None:
    course.live_release = release
    course.hidden_at = None
    course.hidden_reason = ""
    course.save(update_fields=["live_release", "hidden_at", "hidden_reason", "updated_at"])
    enqueue_course_change(action="activated", course=course.slug, version=release.version)
