# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""Moderation of announcements and what the audience sends back about them."""

from __future__ import annotations

import logging
import uuid
from collections import Counter
from collections.abc import Callable, Iterable
from dataclasses import dataclass, field
from datetime import date, timedelta
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
    AnnouncementWave,
    WaveReason,
)
from quran_backend.modules.announcements.routes import SCREENS, external_url_allowed
from quran_backend.modules.core.content_revalidation import enqueue_announcements_change
from quran_backend.modules.core.object_storage import ObjectStorageError

logger = logging.getLogger(__name__)

PUBLISH_PERMISSION = "announcements.publish_announcement"
SENSITIVE_PERMISSION = "announcements.publish_sensitive_announcement"
RELIGIOUS_PERMISSION = "announcements.review_religious_content"
CHANGE_PERMISSION = "announcements.change_announcement"


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
    reshow: bool = False,
) -> Announcement:
    """Publish a draft, or an edit of a published announcement.

    `reshow` (edits only): bring it back to the home screen of those who closed it.
    """
    _require(user, PUBLISH_PERMISSION)
    locked = Announcement.objects.select_for_update().get(pk=announcement.pk)
    if not locked.is_editable:
        raise AnnouncementNotReadyError([NOT_A_DRAFT[AnnouncementStatus(locked.status)]])
    original = None
    if locked.edit_of_id is not None:
        original = Announcement.objects.select_for_update().get(pk=locked.edit_of_id)
        if original.status != AnnouncementStatus.PUBLISHED:
            raise AnnouncementNotReadyError([EDIT_OF_UNPUBLISHED])
    # Taking push or a window off an owner-only announcement is the owner's call too.
    if is_sensitive(locked) or (original is not None and is_sensitive(original)):
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
    if original is not None:
        return _apply_edit(locked, original, user, now, reshow=reshow)
    locked.status = AnnouncementStatus.PUBLISHED
    locked.reviewed_by = user
    locked.reviewed_at = now
    locked.published_at = now
    locked.wave = 1
    locked.save()
    _record_wave(locked, user, WaveReason.PUBLISHED)
    enqueue_announcements_change(action="published")
    return locked


NOT_A_DRAFT = {
    AnnouncementStatus.PUBLISHED: "Уже опубликовано.",
    AnnouncementStatus.WITHDRAWN: "Снято с публикации: нажмите «Опубликовать снова».",
    AnnouncementStatus.ARCHIVED: "В архиве: сделайте копию-черновик и опубликуйте её.",
}


@transaction.atomic
def republish(announcement: Announcement, user: User) -> Announcement:
    """Bring a withdrawn announcement back: a new wave, so earlier closes do not hide it."""
    _require(user, PUBLISH_PERMISSION)
    locked = Announcement.objects.select_for_update().get(pk=announcement.pk)
    if locked.status != AnnouncementStatus.WITHDRAWN:
        raise AnnouncementNotReadyError(["Опубликовать снова можно только снятое объявление."])
    if is_sensitive(locked):
        _require(user, SENSITIVE_PERMISSION)
    result = readiness(locked, publisher_checks_religion=user.has_perm(RELIGIOUS_PERMISSION))
    if not result.ready:
        raise AnnouncementNotReadyError(result.problems)
    now = timezone.now()
    locked.status = AnnouncementStatus.PUBLISHED
    locked.withdrawn_at = None
    locked.reviewed_by = user
    locked.reviewed_at = now
    if locked.needs_religious_review and locked.religious_reviewed_at is None:
        locked.religious_reviewed_by = user
        locked.religious_reviewed_at = now
    locked.wave += 1
    locked.save()
    _record_wave(locked, user, WaveReason.REPUBLISHED)
    enqueue_announcements_change(action="published")
    return locked


EXTEND_DAYS = 7


@transaction.atomic
def extend_display(announcement: Announcement, user: User) -> Announcement:
    """Keep a published announcement on the home screen a week longer than now or planned."""
    _require(user, PUBLISH_PERMISSION)
    locked = Announcement.objects.select_for_update().get(pk=announcement.pk)
    if locked.status != AnnouncementStatus.PUBLISHED:
        raise AnnouncementNotReadyError(["Продлить можно только опубликованное объявление."])
    if is_sensitive(locked):
        _require(user, SENSITIVE_PERMISSION)
    locked.ends_at = max(locked.display_until, timezone.now()) + timedelta(days=EXTEND_DAYS)
    locked.save(update_fields=["ends_at", "updated_at"])
    enqueue_announcements_change(action="published")
    return locked


def _record_wave(announcement: Announcement, user: User, reason: WaveReason) -> None:
    AnnouncementWave.objects.create(
        announcement=announcement,
        number=announcement.wave,
        reason=reason,
        revision=announcement.revision,
        started_by=user,
    )


@transaction.atomic
def reshow(announcement: Announcement, user: User) -> Announcement:
    """Put it back on the home screen of everyone who already read or closed it."""
    _require(user, PUBLISH_PERMISSION)
    locked = Announcement.objects.select_for_update().get(pk=announcement.pk)
    if is_sensitive(locked):
        _require(user, SENSITIVE_PERMISSION)
    now = timezone.now()
    problem = None
    if locked.status != AnnouncementStatus.PUBLISHED:
        problem = "Показать снова можно только опубликованное объявление."
    elif not (locked.channel_bubble or locked.channel_home_card):
        problem = "Нет ни пузыря, ни карточки: на главной его не показать."
    elif locked.starts_at > now:
        problem = "Объявление ещё не началось: его и так увидят все."
    elif locked.display_until <= now:
        problem = (
            f"Срок показа на главной закончился "
            f"{timezone.localtime(locked.display_until):%d.%m.%Y}. Продлите его правкой и "
            "опубликуйте снова с отметкой «Показать снова»."
        )
    if problem:
        raise AnnouncementNotReadyError([problem])
    locked.wave += 1
    locked.save(update_fields=["wave", "updated_at"])
    _record_wave(locked, user, WaveReason.RESHOW)
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


# What an edit of a published announcement may change. Status, signatures and the
# date of the first publication stay with the original.
EDITABLE_FIELDS = (
    "kind",
    "priority",
    "starts_at",
    "ends_at",
    "pinned",
    "channel_bubble",
    "channel_home_card",
    "channel_modal",
    "channel_web_push",
    "bubble_frequency",
    "bubble_max_impressions",
    "bubble_icon",
    "action_type",
    "action_reciter",
    "action_surah",
    "action_ayah",
    "action_slug",
    "action_url",
    "image_object_key",
    "image_width",
    "image_height",
    "thumb_object_key",
    "audience_languages",
    "audience_platforms",
    "app_version_min",
    "app_version_max",
    "audience_auth",
    "needs_religious_review",
    "religious_reviewed_by",
    "religious_reviewed_at",
    "review_note",
)

EDIT_OF_UNPUBLISHED = (
    "Исходное объявление уже снято или в архиве. Сделайте копию-черновик и опубликуйте её."
)


def _copy(source: Announcement, user: User, **values: Any) -> Announcement:
    """A new draft with the content of `source`, its texts and step pictures."""
    copy = Announcement.objects.get(pk=source.pk)
    copy.pk = uuid.uuid7()
    copy._state.adding = True
    copy.status = AnnouncementStatus.DRAFT
    copy.source = "manual"
    copy.auto_key = None
    copy.created_by = user
    copy.edit_of = None
    copy.revision = 1
    copy.wave = 1
    for name in (
        "religious_reviewed_by",
        "religious_reviewed_at",
        "reviewed_by",
        "reviewed_at",
        "published_at",
        "withdrawn_at",
        "revised_at",
        "revised_by",
    ):
        setattr(copy, name, None)
    copy.review_note = ""
    for name, value in values.items():
        setattr(copy, name, value)
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


@transaction.atomic
def duplicate(announcement: Announcement, user: User) -> Announcement:
    """A fresh draft with the same content; read receipts stay with the original."""
    source = Announcement.objects.get(pk=announcement.pk)
    return _copy(source, user, starts_at=max(source.starts_at, timezone.now()), ends_at=None)


@transaction.atomic
def start_edit(announcement: Announcement, user: User) -> Announcement:
    """The draft of changes to a published announcement; the audience keeps the old one.

    One edit at a time: a second call returns the edit already started.
    """
    _require(user, CHANGE_PERMISSION)
    locked = Announcement.objects.select_for_update().get(pk=announcement.pk)
    if locked.status != AnnouncementStatus.PUBLISHED:
        raise AnnouncementNotReadyError(["Изменить можно только опубликованное объявление."])
    existing = Announcement.objects.filter(edit_of=locked).first()
    if existing is not None:
        return existing
    return _copy(locked, user, edit_of=locked)


@transaction.atomic
def cancel_edit(announcement: Announcement, user: User) -> Announcement:
    """Throw an unpublished edit away; returns the published announcement it belonged to."""
    _require(user, CHANGE_PERMISSION)
    locked = Announcement.objects.select_for_update().get(pk=announcement.pk)
    original = locked.edit_of
    if original is None or not locked.is_editable:
        raise AnnouncementNotReadyError(["Это не правка опубликованного объявления."])
    locked.delete()
    return original


def _apply_edit(
    edit: Announcement,
    original: Announcement,
    user: User,
    now: Any,
    *,
    reshow: bool,
) -> Announcement:
    """Swap the published content for the edit in the caller's transaction."""
    for name in EDITABLE_FIELDS:
        setattr(original, name, getattr(edit, name))
    original.reviewed_by = user
    original.reviewed_at = now
    original.revision += 1
    original.revised_at = now
    original.revised_by = user
    if reshow:
        original.wave += 1
    original.translations.all().delete()
    original.step_images.all().delete()
    edit.translations.update(announcement=original)
    edit.step_images.update(announcement=original)
    edit.delete()
    original.save()
    if reshow:
        _record_wave(original, user, WaveReason.EDIT)
    enqueue_announcements_change(action="published")
    return original


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
    wave: int | None = None,
) -> AnnouncementReceipt:
    """Marks only move forward, so two devices can never un-read an announcement.

    `wave` is the wave the device showed it in (the current one if not sent): the
    mark hides the announcement on the home screen until the next wave.
    """
    receipt, _ = AnnouncementReceipt.objects.select_for_update().get_or_create(
        user=user,
        announcement=announcement,
    )
    now = timezone.now()
    changed = []
    seen_wave = min(wave or announcement.wave, announcement.wave)
    if (read or dismissed) and seen_wave > receipt.wave:
        receipt.wave = seen_wave
        changed.append("wave")
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
        "wave": receipt.wave,
    }


def record_events(
    *,
    platform: str,
    events: Iterable[tuple[uuid.UUID, str, str, int | None]],
    published_waves: dict[uuid.UUID, int],
    today: date | None = None,
) -> int:
    """Add the batch to the daily sums of published announcements; return accepted events.

    Each event counts in the wave the device reported, or the current one.
    """
    day = today or timezone.localdate()
    totals = Counter(
        (announcement_id, _event_wave(wave, published_waves[announcement_id]), surface, event)
        for announcement_id, surface, event, wave in events
        if announcement_id in published_waves
    )
    for (announcement_id, wave, surface, event), count in totals.items():
        lookup = {
            "date": day,
            "announcement_id": announcement_id,
            "wave": wave,
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


def _event_wave(reported: int | None, current: int) -> int:
    return reported if reported is not None and 1 <= reported <= current else current
