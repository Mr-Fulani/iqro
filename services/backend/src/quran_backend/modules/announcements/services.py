# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""Moderation of announcements and what the audience sends back about them."""

from __future__ import annotations

import logging
import uuid
from collections import Counter
from collections.abc import Callable, Iterable
from dataclasses import dataclass, field
from datetime import date
from typing import Any

from django.core.exceptions import PermissionDenied
from django.db import IntegrityError, transaction
from django.db.models import F
from django.utils import timezone

from quran_backend.modules.accounts.models import User
from quran_backend.modules.announcements.media import AnnouncementMediaError, portrait_thumbnail
from quran_backend.modules.announcements.models import (
    LANGUAGE_NAMES,
    LANGUAGES,
    PRIORITY_RANK,
    ActionType,
    Announcement,
    AnnouncementDailyStat,
    AnnouncementKind,
    AnnouncementPriority,
    AnnouncementReceipt,
    AnnouncementSettings,
    AnnouncementStatus,
    AnnouncementTranslation,
)
from quran_backend.modules.announcements.routes import SCREENS, external_url_allowed
from quran_backend.modules.core.content_revalidation import enqueue_announcements_change
from quran_backend.modules.core.object_storage import ObjectStorageError

logger = logging.getLogger(__name__)

PUBLISH_PERMISSION = "announcements.publish_announcement"
SENSITIVE_PERMISSION = "announcements.publish_sensitive_announcement"
RELIGIOUS_PERMISSION = "announcements.review_religious_content"


class AnnouncementNotReadyError(ValueError):
    def __init__(self, problems: list[str]) -> None:
        super().__init__("; ".join(problems))
        self.problems = problems


@dataclass(slots=True)
class Readiness:
    languages: list[str] = field(default_factory=list)
    problems: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    @property
    def ready(self) -> bool:
        return not self.problems


def translations_by_language(announcement: Announcement) -> dict[str, AnnouncementTranslation]:
    return {item.language: item for item in announcement.translations.all()}


def is_sensitive(announcement: Announcement) -> bool:
    """What only the owner signs: money, interruptions and forced updates."""
    return (
        announcement.kind == AnnouncementKind.FUNDRAISING
        or announcement.priority == AnnouncementPriority.CRITICAL
        or announcement.channel_modal
        or announcement.channel_web_push
    )


def uses_image(announcement: Announcement) -> bool:
    reciter = announcement.reciter
    return bool(announcement.image_object_key or (reciter and reciter.portrait_object_key))


RELIGIOUS_REVIEW_NEEDED = (
    "Отмечено «Есть аят, хадис или фетва»: перед публикацией текст проверяет человек "
    "из группы «Проверяющий религиозные тексты» — кнопка «Религиозный текст проверен»."
)


def readiness(announcement: Announcement, *, publisher_checks_religion: bool = False) -> Readiness:
    """Everything that must hold before the announcement may be published.

    `publisher_checks_religion`: the person about to publish may confirm the religious
    text themselves, so publishing records that check instead of waiting for it.
    """
    result = Readiness()
    translations = translations_by_language(announcement)
    _check_languages(announcement, translations, result)
    steps = _check_texts(announcement, translations, result)
    result.problems.extend(_action_problems(announcement))
    result.problems.extend(_channel_problems(announcement, steps))
    if announcement.needs_religious_review and announcement.religious_reviewed_at is None:
        if publisher_checks_religion:
            result.notes.append(
                "Есть аят, хадис или фетва: публикуя, вы подтверждаете, что текст проверен."
            )
        else:
            result.problems.append(RELIGIOUS_REVIEW_NEEDED)
    if announcement.ends_at and announcement.ends_at <= announcement.starts_at:
        result.problems.append("Окончание показа должно быть позже начала.")
    return result


def _check_languages(
    announcement: Announcement,
    translations: dict[str, AnnouncementTranslation],
    result: Readiness,
) -> None:
    filled = [code for code in LANGUAGES if code in translations and translations[code].is_filled]
    requested = list(announcement.audience_languages or [])
    if requested:
        result.problems.extend(
            f"{LANGUAGE_NAMES[code]}: заполните заголовок и «Кратко»."
            for code in requested
            if code not in filled
        )
        result.languages = [code for code in requested if code in filled]
    else:
        result.languages = filled
        result.notes.extend(
            f"{LANGUAGE_NAMES[code]} не заполнен — эта аудитория объявление не увидит."
            for code in LANGUAGES
            if code not in filled
        )
    if not result.languages:
        result.problems.append("Заполните текст хотя бы на одном языке.")


def _check_texts(
    announcement: Announcement,
    translations: dict[str, AnnouncementTranslation],
    result: Readiness,
) -> int:
    """Button, picture description and steps in every audience language; returns steps."""
    has_image = uses_image(announcement)
    step_counts = set()
    for code in result.languages:
        translation = translations[code]
        name = LANGUAGE_NAMES[code]
        if announcement.action_type != ActionType.NONE and not translation.cta_label.strip():
            result.problems.append(f"{name}: заполните текст кнопки.")
        if has_image and not translation.image_alt.strip():
            result.problems.append(f"{name}: опишите картинку для экранного диктора.")
        step_counts.add(len(translation.steps or []))
    if len(step_counts) > 1:
        result.problems.append("Число шагов должно совпадать на всех языках.")
    steps = max(step_counts, default=0)
    if any(step.order > steps for step in announcement.step_images.all()):
        result.problems.append("Есть иллюстрация для шага, которого нет в текстах.")
    return steps


def _action_problems(announcement: Announcement) -> list[str]:
    action = announcement.action_type
    reciter = announcement.reciter
    problem = None
    if action == ActionType.RECITER and reciter is None:
        problem = "Выберите чтеца для кнопки."
    elif action == ActionType.RECITER and reciter is not None and not reciter.is_active:
        problem = "Чтец скрыт в каталоге — кнопка никуда не приведёт."
    elif action == ActionType.SURAH and not announcement.action_surah:
        problem = "Укажите номер суры."
    elif action == ActionType.SALAH_LESSON and not announcement.action_slug:
        problem = "Укажите slug урока курса намаза."
    elif action == ActionType.SCREEN and announcement.action_slug not in SCREENS:
        problem = f"Раздел должен быть одним из: {', '.join(SCREENS)}."
    elif action == ActionType.EXTERNAL and not external_url_allowed(announcement.action_url):
        problem = "Внешняя ссылка: только HTTPS и только разрешённые сайты."
    return [problem] if problem else []


def _channel_problems(announcement: Announcement, steps: int) -> list[str]:
    problems = []
    rank = PRIORITY_RANK[AnnouncementPriority(announcement.priority)]
    if announcement.kind == AnnouncementKind.FUNDRAISING:
        if announcement.channel_bubble or announcement.channel_modal:
            problems.append("Сбор средств не показывается пузырём и окном.")
        if announcement.channel_web_push:
            problems.append("Сбор средств не рассылается push.")
    if announcement.channel_modal and rank < PRIORITY_RANK[AnnouncementPriority.HIGH]:
        problems.append("Окно с шагами — только для высокого приоритета.")
    if announcement.channel_modal and steps == 0:
        problems.append("Для окна с шагами добавьте шаги.")
    if announcement.channel_web_push and rank < PRIORITY_RANK[AnnouncementPriority.HIGH]:
        problems.append("Push — только для высокого приоритета.")
    if (
        announcement.priority == AnnouncementPriority.CRITICAL
        and announcement.kind != AnnouncementKind.APP_RELEASE
    ):
        problems.append("Критический приоритет — только для обязательного обновления.")
    return problems


def _require(user: User, permission: str) -> None:
    if not user.has_perm(permission):
        raise PermissionDenied


@transaction.atomic
def submit_for_review(announcement: Announcement) -> None:
    locked = Announcement.objects.select_for_update().get(pk=announcement.pk)
    if locked.status != AnnouncementStatus.DRAFT:
        raise AnnouncementNotReadyError(["На проверку отправляется только черновик."])
    locked.status = AnnouncementStatus.IN_REVIEW
    locked.save(update_fields=["status", "updated_at"])
    announcement.status = locked.status


@transaction.atomic
def sign_religious_review(announcement: Announcement, user: User) -> None:
    _require(user, RELIGIOUS_PERMISSION)
    locked = Announcement.objects.select_for_update().get(pk=announcement.pk)
    if not locked.is_editable:
        raise AnnouncementNotReadyError(["Объявление уже опубликовано."])
    locked.religious_reviewed_by = user
    locked.religious_reviewed_at = timezone.now()
    locked.save(update_fields=["religious_reviewed_by", "religious_reviewed_at", "updated_at"])


@transaction.atomic
def publish(
    announcement: Announcement,
    user: User,
    *,
    thumbnail: Callable[[str], str] = portrait_thumbnail,
) -> Announcement:
    _require(user, PUBLISH_PERMISSION)
    locked = Announcement.objects.select_for_update().get(pk=announcement.pk)
    if not locked.is_editable:
        raise AnnouncementNotReadyError(["Объявление уже опубликовано или снято."])
    if is_sensitive(locked):
        _require(user, SENSITIVE_PERMISSION)
    checks_religion = user.has_perm(RELIGIOUS_PERMISSION)
    result = readiness(locked, publisher_checks_religion=checks_religion)
    if not result.ready:
        raise AnnouncementNotReadyError(result.problems)

    if not locked.audience_languages:
        locked.audience_languages = result.languages
    if locked.ends_at is None:
        locked.ends_at = locked.display_until
    reciter = locked.reciter
    if (
        not locked.thumb_object_key
        and not locked.image_object_key
        and reciter is not None
        and reciter.portrait_object_key
    ):
        try:
            locked.thumb_object_key = thumbnail(reciter.portrait_object_key)
        except AnnouncementMediaError, ObjectStorageError, OSError:
            # The bubble falls back to an icon; publishing must not wait for the CDN.
            logger.warning("Reciter portrait thumbnail failed", extra={"announcement": locked.pk})
    now = timezone.now()
    if locked.needs_religious_review and locked.religious_reviewed_at is None:
        locked.religious_reviewed_by = user
        locked.religious_reviewed_at = now
    locked.status = AnnouncementStatus.PUBLISHED
    locked.reviewed_by = user
    locked.reviewed_at = now
    locked.published_at = now
    locked.save()
    enqueue_announcements_change(action="published")
    return locked


@transaction.atomic
def withdraw(announcement: Announcement, user: User) -> None:
    _require(user, PUBLISH_PERMISSION)
    locked = Announcement.objects.select_for_update().get(pk=announcement.pk)
    if locked.status != AnnouncementStatus.PUBLISHED:
        raise AnnouncementNotReadyError(["Снять можно только опубликованное объявление."])
    locked.status = AnnouncementStatus.WITHDRAWN
    locked.withdrawn_at = timezone.now()
    locked.save(update_fields=["status", "withdrawn_at", "updated_at"])
    enqueue_announcements_change(action="withdrawn")


@transaction.atomic
def archive(announcement: Announcement, user: User) -> None:
    _require(user, PUBLISH_PERMISSION)
    locked = Announcement.objects.select_for_update().get(pk=announcement.pk)
    if locked.status not in {AnnouncementStatus.PUBLISHED, AnnouncementStatus.WITHDRAWN}:
        raise AnnouncementNotReadyError(["В архив уходит опубликованное или снятое объявление."])
    was_public = locked.status == AnnouncementStatus.PUBLISHED
    locked.status = AnnouncementStatus.ARCHIVED
    locked.save(update_fields=["status", "updated_at"])
    if was_public:
        enqueue_announcements_change(action="archived")


@transaction.atomic
def duplicate(announcement: Announcement, user: User) -> Announcement:
    """A fresh draft with the same content; read receipts stay with the original."""
    source = Announcement.objects.get(pk=announcement.pk)
    copy = Announcement.objects.get(pk=announcement.pk)
    copy.pk = uuid.uuid7()
    copy._state.adding = True
    copy.status = AnnouncementStatus.DRAFT
    copy.source = "manual"
    copy.auto_key = None
    copy.starts_at = max(source.starts_at, timezone.now())
    copy.ends_at = None
    copy.created_by = user
    for name in (
        "religious_reviewed_by",
        "religious_reviewed_at",
        "reviewed_by",
        "reviewed_at",
        "published_at",
        "withdrawn_at",
    ):
        setattr(copy, name, None)
    copy.review_note = ""
    copy.save()
    for translation in source.translations.all():
        translation.pk = uuid.uuid7()
        translation._state.adding = True
        translation.announcement = copy
        translation.save()
    for step in source.step_images.all():
        step.pk = uuid.uuid7()
        step._state.adding = True
        step.announcement = copy
        step.save()
    return copy


def announcements_enabled() -> bool:
    settings_row = AnnouncementSettings.objects.first()
    return settings_row is None or settings_row.is_enabled


@transaction.atomic
def set_receipt(
    *,
    user: User,
    announcement: Announcement,
    read: bool,
    dismissed: bool,
) -> AnnouncementReceipt:
    """Marks only move forward, so two devices can never un-read an announcement."""
    receipt, _ = AnnouncementReceipt.objects.select_for_update().get_or_create(
        user=user,
        announcement=announcement,
    )
    now = timezone.now()
    changed = []
    if read and receipt.read_at is None:
        receipt.read_at = now
        changed.append("read_at")
    if dismissed and receipt.dismissed_at is None:
        receipt.dismissed_at = now
        changed.append("dismissed_at")
    if changed:
        receipt.save(update_fields=[*changed, "updated_at"])
    return receipt


def receipt_snapshot(receipt: AnnouncementReceipt) -> dict[str, Any]:
    return {
        "announcement_id": str(receipt.announcement_id),
        "read_at": receipt.read_at,
        "dismissed_at": receipt.dismissed_at,
    }


def record_events(
    *,
    platform: str,
    events: Iterable[tuple[uuid.UUID, str, str]],
    published_ids: set[uuid.UUID],
    today: date | None = None,
) -> int:
    """Add the batch to the daily sums of published announcements; return accepted events."""
    day = today or timezone.localdate()
    totals = Counter(
        (announcement_id, surface, event)
        for announcement_id, surface, event in events
        if announcement_id in published_ids
    )
    for (announcement_id, surface, event), count in totals.items():
        lookup = {
            "date": day,
            "announcement_id": announcement_id,
            "platform": platform,
            "surface": surface,
            "event": event,
        }
        updated = AnnouncementDailyStat.objects.filter(**lookup).update(count=F("count") + count)
        if updated:
            continue
        try:
            with transaction.atomic():
                AnnouncementDailyStat.objects.create(**lookup, count=count)
        except IntegrityError:
            AnnouncementDailyStat.objects.filter(**lookup).update(count=F("count") + count)
    return sum(totals.values())
