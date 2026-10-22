# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""Announcements shown to the audience of the site and the app.

One announcement carries its texts in every interface language, an optional
image or step-by-step illustrations, one action, a display window, an audience
and the surfaces it may use. A published announcement is not edited in place:
an edit is a draft of its own (`edit_of`) that replaces the published content in
one transaction and raises `revision`, so the audience never sees half an edit.

Closing or reading an announcement takes it off the home screen for good, unless
the admin brings it back: each «Показать снова» starts a new `wave`, and a mark
only hides the announcement in the wave it was made in. The feed keeps it always.
"""

from __future__ import annotations

import re
from datetime import timedelta
from typing import Any

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models

from quran_backend.modules.audio.models import Reciter
from quran_backend.modules.audio.validators import validate_relative_object_key
from quran_backend.modules.core.models import BaseModel

LANGUAGES = ("ru", "en", "ar", "tr")
LANGUAGE_NAMES = {"ru": "Русский", "en": "English", "ar": "العربية", "tr": "Türkçe"}
PLATFORMS = ("web", "android", "ios")
# A card or bubble without an explicit end stays on the home screen this long.
DEFAULT_DISPLAY_DAYS = 14
MAX_STEPS = 5
APP_VERSION_PATTERN = re.compile(r"^\d{1,4}(\.\d{1,4}){0,2}$")


class AnnouncementKind(models.TextChoices):
    RECITER = "reciter", "Новый чтец"
    FEATURE = "feature", "Что нового"
    APP_RELEASE = "app_release", "Новая версия приложения"
    CONTENT = "content", "Новое содержание"
    FUNDRAISING = "fundraising", "Сбор средств"
    GENERAL = "general", "Общее объявление"


class AnnouncementPriority(models.TextChoices):
    LOW = "low", "Низкий: только лента"
    NORMAL = "normal", "Обычный: лента, пузырь и карточка"
    HIGH = "high", "Высокий: плюс окно с шагами и push"
    CRITICAL = "critical", "Критический: обязательное обновление"


PRIORITY_RANK = {
    AnnouncementPriority.LOW: 0,
    AnnouncementPriority.NORMAL: 1,
    AnnouncementPriority.HIGH: 2,
    AnnouncementPriority.CRITICAL: 3,
}


class AnnouncementStatus(models.TextChoices):
    DRAFT = "draft", "Черновик"
    IN_REVIEW = "in_review", "На проверке"
    PUBLISHED = "published", "Опубликовано"
    WITHDRAWN = "withdrawn", "Снято"
    ARCHIVED = "archived", "В архиве"


class BubbleFrequency(models.TextChoices):
    EACH_VISIT = "each_visit", "Каждое открытие главной"
    DAILY = "daily", "Раз в день"
    EVERY_3_DAYS = "every_3_days", "Раз в 3 дня"
    WEEKLY = "weekly", "Раз в неделю"


class BubbleIcon(models.TextChoices):
    AUTO = "auto", "По типу объявления"
    PORTRAIT = "portrait", "Портрет чтеца"
    HEADPHONES = "headphones", "Наушники"
    SPARKLE = "sparkle", "Искра"
    ARROW_UP = "arrow_up", "Стрелка вверх"
    BOOK = "book", "Книга"
    MEGAPHONE = "megaphone", "Рупор"
    COMPASS = "compass", "Компас"
    MOSQUE = "mosque", "Мечеть"


KIND_BUBBLE_ICONS = {
    AnnouncementKind.RECITER: BubbleIcon.PORTRAIT,
    AnnouncementKind.FEATURE: BubbleIcon.SPARKLE,
    AnnouncementKind.APP_RELEASE: BubbleIcon.ARROW_UP,
    AnnouncementKind.CONTENT: BubbleIcon.BOOK,
    AnnouncementKind.FUNDRAISING: BubbleIcon.MEGAPHONE,
    AnnouncementKind.GENERAL: BubbleIcon.MEGAPHONE,
}


class ActionType(models.TextChoices):
    NONE = "none", "Без кнопки"
    RECITER = "reciter", "Открыть чтеца в плеере"
    SURAH = "surah", "Открыть суру или аят"
    SALAH_LESSON = "salah_lesson", "Открыть урок курса намаза"
    SCREEN = "screen", "Открыть раздел"
    EXTERNAL = "external", "Внешняя ссылка"


class AudienceAuth(models.TextChoices):
    ALL = "all", "Все"
    GUESTS = "guests", "Только гости"
    SIGNED_IN = "signed_in", "Только вошедшие"


class AnnouncementSource(models.TextChoices):
    MANUAL = "manual", "Вручную"
    AUTO = "auto", "Автоматически"


def validate_app_version(value: str) -> None:
    if value and APP_VERSION_PATTERN.fullmatch(value) is None:
        raise ValidationError("Версия в формате 1, 1.2 или 1.2.3.")


def default_platforms() -> list[str]:
    return list(PLATFORMS)


def default_languages() -> list[str]:
    return []


class Announcement(BaseModel):
    kind = models.CharField(
        "Тип объявления",
        max_length=24,
        choices=AnnouncementKind,
        default=AnnouncementKind.GENERAL,
    )
    priority = models.CharField(
        "Приоритет",
        max_length=16,
        choices=AnnouncementPriority,
        default=AnnouncementPriority.NORMAL,
    )
    status = models.CharField(
        "Статус",
        max_length=16,
        choices=AnnouncementStatus,
        default=AnnouncementStatus.DRAFT,
        editable=False,
    )
    starts_at = models.DateTimeField(
        "Показывать с",
        help_text="До этого времени объявления нет ни в ленте, ни на главной.",
    )
    ends_at = models.DateTimeField(
        "Убрать с главной после",
        null=True,
        blank=True,
        help_text=(
            f"Пузырь, карточка и окно исчезают после этой даты; в ленте объявление остаётся. "
            f"Если не заполнено — {DEFAULT_DISPLAY_DAYS} дней с начала."
        ),
    )
    pinned = models.BooleanField(
        "Закрепить в ленте",
        default=False,
        help_text="Закреплённые объявления стоят в ленте первыми.",
    )

    channel_bubble = models.BooleanField(
        "Пузырь на телефоне",
        default=True,
        help_text=(
            "Сайт на телефоне и приложение: пузырь в правом верхнем углу главной. "
            "Нажатие лопает его и раскрывает окно."
        ),
    )
    channel_home_card = models.BooleanField(
        "Карточка на главной (компьютер)",
        default=True,
        help_text="Под большим блоком главной. Одна карточка за раз.",
    )
    channel_modal = models.BooleanField(
        "Окно с шагами (компьютер)",
        default=False,
        help_text="Открывается само один раз в 7 дней. Нужен высокий приоритет и шаги.",
    )
    channel_web_push = models.BooleanField(
        "Push «Новости» на сайте",
        default=False,
        help_text="Только подписчикам, включившим «Новости». Нужен высокий приоритет.",
    )
    bubble_frequency = models.CharField(
        "Как часто показывать пузырь",
        max_length=16,
        choices=BubbleFrequency,
        default=BubbleFrequency.DAILY,
    )
    bubble_max_impressions = models.PositiveSmallIntegerField(
        "Максимум показов пузыря на устройство",
        default=5,
        validators=[MinValueValidator(1), MaxValueValidator(50)],
        help_text="После этого числа показов без нажатия объявление остаётся только в ленте.",
    )
    bubble_icon = models.CharField(
        "Иконка в пузыре",
        max_length=16,
        choices=BubbleIcon,
        default=BubbleIcon.AUTO,
        help_text="«По типу»: для чтеца — его портрет, для функции — искра и так далее.",
    )

    action_type = models.CharField(
        "Кнопка-действие",
        max_length=16,
        choices=ActionType,
        default=ActionType.NONE,
    )
    action_reciter = models.UUIDField(
        "Чтец",
        null=True,
        blank=True,
        help_text="Кнопка «Послушать» откроет этого чтеца в плеере.",
    )
    action_surah = models.PositiveSmallIntegerField(
        "Сура",
        null=True,
        blank=True,
        validators=[MinValueValidator(1), MaxValueValidator(114)],
    )
    action_ayah = models.PositiveSmallIntegerField(
        "Аят",
        null=True,
        blank=True,
        validators=[MinValueValidator(1), MaxValueValidator(286)],
    )
    action_slug = models.SlugField(
        "Урок или раздел",
        max_length=64,
        blank=True,
        help_text="Slug урока курса намаза или код раздела из списка.",
    )
    action_url = models.URLField(
        "Внешняя ссылка",
        max_length=500,
        blank=True,
        help_text="Только HTTPS и только разрешённые сайты. Открывается через переадресацию IQRO.",
    )

    image_object_key = models.CharField(
        "Картинка",
        max_length=512,
        blank=True,
        validators=[validate_relative_object_key],
        help_text="Пусто у объявления о чтеце — берётся его портрет.",
    )
    image_width = models.PositiveIntegerField("Ширина картинки", null=True, blank=True)
    image_height = models.PositiveIntegerField("Высота картинки", null=True, blank=True)
    thumb_object_key = models.CharField(
        "Миниатюра для пузыря",
        max_length=512,
        blank=True,
        validators=[validate_relative_object_key],
        editable=False,
    )

    audience_languages = models.JSONField(
        "Языки аудитории",
        default=default_languages,
        blank=True,
        help_text="Пусто — все языки, на которых заполнен текст.",
    )
    audience_platforms = models.JSONField("Платформы", default=default_platforms)
    app_version_min = models.CharField(
        "Версия приложения от",
        max_length=16,
        blank=True,
        validators=[validate_app_version],
    )
    app_version_max = models.CharField(
        "Версия приложения до",
        max_length=16,
        blank=True,
        validators=[validate_app_version],
    )
    audience_auth = models.CharField(
        "Кто увидит",
        max_length=16,
        choices=AudienceAuth,
        default=AudienceAuth.ALL,
    )

    source = models.CharField(
        "Как создано",
        max_length=8,
        choices=AnnouncementSource,
        default=AnnouncementSource.MANUAL,
        editable=False,
    )
    auto_key = models.CharField(
        "Ключ автоматического объявления",
        max_length=160,
        null=True,
        blank=True,
        unique=True,
        editable=False,
    )
    needs_religious_review = models.BooleanField(
        "Есть аят, хадис или фетва",
        default=False,
        help_text="Тогда до публикации нужна подпись проверяющего религиозные тексты.",
    )
    religious_reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        verbose_name="Религиозную проверку подписал",
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="+",
        editable=False,
    )
    religious_reviewed_at = models.DateTimeField(
        "Религиозная проверка",
        null=True,
        blank=True,
        editable=False,
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        verbose_name="Создал",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
        editable=False,
    )
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        verbose_name="Подписал",
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="+",
        editable=False,
    )
    reviewed_at = models.DateTimeField("Подписано", null=True, blank=True, editable=False)
    review_note = models.TextField("Примечание проверяющего", blank=True, max_length=2000)
    published_at = models.DateTimeField("Опубликовано", null=True, blank=True, editable=False)
    withdrawn_at = models.DateTimeField("Снято", null=True, blank=True, editable=False)
    edit_of = models.OneToOneField(
        "self",
        verbose_name="Правка объявления",
        null=True,
        blank=True,
        on_delete=models.CASCADE,
        related_name="pending_edit",
        editable=False,
    )
    # Raised by every published edit: clients can tell a changed announcement from
    # the one a person has already read.
    revision = models.PositiveIntegerField("Редакция", default=1, editable=False)
    # Raised by every «Показать снова»: marks made in an earlier wave stop hiding it.
    wave = models.PositiveIntegerField("Волна показа", default=1, editable=False)
    revised_at = models.DateTimeField(
        "Изменено после публикации", null=True, blank=True, editable=False
    )
    revised_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        verbose_name="Изменил",
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="+",
        editable=False,
    )

    class Meta:
        db_table = "announcement"
        verbose_name = "объявление"
        verbose_name_plural = "Объявления"
        ordering = ("-starts_at", "-created_at")
        permissions = [
            ("publish_announcement", "Может подписывать и публиковать объявления"),
            (
                "publish_sensitive_announcement",
                "Может публиковать сбор средств, push, окна и обязательные обновления",
            ),
            ("review_religious_content", "Может подписывать религиозную проверку"),
        ]
        constraints = [
            models.CheckConstraint(
                condition=~models.Q(status="published")
                | (models.Q(reviewed_by__isnull=False) & models.Q(reviewed_at__isnull=False)),
                name="announcement_published_is_signed",
            ),
            models.CheckConstraint(
                condition=models.Q(ends_at__isnull=True)
                | models.Q(ends_at__gt=models.F("starts_at")),
                name="announcement_window_order",
            ),
        ]
        indexes = [
            models.Index(fields=("status", "starts_at"), name="announcement_public_idx"),
        ]

    def __str__(self) -> str:
        translation = (
            None
            if self._state.adding
            else next((item for item in self.translations.all() if item.language == "ru"), None)
        )
        if translation is not None and translation.title:
            return translation.title
        return f"{self.get_kind_display()} · {self.starts_at:%d.%m.%Y}"

    @property
    def display_until(self) -> Any:
        return self.ends_at or self.starts_at + timedelta(days=DEFAULT_DISPLAY_DAYS)

    @property
    def is_editable(self) -> bool:
        return self.status in {AnnouncementStatus.DRAFT, AnnouncementStatus.IN_REVIEW}

    @property
    def is_edit(self) -> bool:
        return self.edit_of_id is not None

    @property
    def reciter(self) -> Reciter | None:
        """The reciter of a «listen» button: a reference by id, not a link between modules."""
        if self.action_type != ActionType.RECITER or self.action_reciter is None:
            return None
        cached = getattr(self, "_reciter_cache", None)
        if cached is None or cached[0] != self.action_reciter:
            cached = (self.action_reciter, Reciter.objects.filter(pk=self.action_reciter).first())
            self._reciter_cache = cached
        return cached[1]

    @property
    def effective_bubble_icon(self) -> str:
        if self.bubble_icon != BubbleIcon.AUTO:
            return str(self.bubble_icon)
        return str(KIND_BUBBLE_ICONS[AnnouncementKind(self.kind)])

    def clean(self) -> None:
        super().clean()
        errors: dict[str, str] = {}
        if self.ends_at and self.starts_at and self.ends_at <= self.starts_at:
            errors["ends_at"] = "Окончание должно быть позже начала."
        unknown_languages = set(self.audience_languages or ()) - set(LANGUAGES)
        if not isinstance(self.audience_languages, list) or unknown_languages:
            errors["audience_languages"] = "Только ru, en, ar, tr."
        if (
            not isinstance(self.audience_platforms, list)
            or not self.audience_platforms
            or set(self.audience_platforms) - set(PLATFORMS)
        ):
            errors["audience_platforms"] = "Выберите хотя бы одну платформу: web, android, ios."
        if errors:
            raise ValidationError(errors)


class AnnouncementTranslation(BaseModel):
    announcement = models.ForeignKey(
        Announcement,
        on_delete=models.CASCADE,
        related_name="translations",
    )
    language = models.CharField(
        "Язык",
        max_length=2,
        choices=[(code, LANGUAGE_NAMES[code]) for code in LANGUAGES],
    )
    title = models.CharField("Заголовок", max_length=70, blank=True)
    summary = models.CharField(
        "Кратко",
        max_length=160,
        blank=True,
        help_text="Карточка, подпись пузыря для экранного диктора и текст push.",
    )
    body = models.TextField(
        "Текст",
        max_length=4000,
        blank=True,
        help_text="Абзацы, списки, **жирный**, ссылки внутрь сайта.",
    )
    cta_label = models.CharField("Текст кнопки", max_length=24, blank=True)
    image_alt = models.CharField("Описание картинки", max_length=160, blank=True)
    push_title = models.CharField("Заголовок push", max_length=50, blank=True)
    steps = models.JSONField(
        "Шаги",
        default=list,
        blank=True,
        help_text='Список шагов: [{"title": "…", "text": "…"}], не больше 5.',
    )

    class Meta:
        db_table = "announcement_translation"
        verbose_name = "текст объявления"
        verbose_name_plural = "Тексты объявления"
        ordering = ("announcement", "language")
        constraints = [
            models.UniqueConstraint(
                fields=("announcement", "language"),
                name="announcement_translation_language_unique",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.language}: {self.title}"

    @property
    def is_filled(self) -> bool:
        return bool(self.title.strip() and self.summary.strip())

    def clean(self) -> None:
        super().clean()
        steps = self.steps
        if not isinstance(steps, list) or len(steps) > MAX_STEPS:
            raise ValidationError({"steps": f"Список не больше {MAX_STEPS} шагов."})
        for index, step in enumerate(steps, start=1):
            if (
                not isinstance(step, dict)
                or set(step) != {"title", "text"}
                or not isinstance(step["title"], str)
                or not isinstance(step["text"], str)
                or not step["title"].strip()
                or len(step["title"]) > 50
                or len(step["text"]) > 200
            ):
                raise ValidationError(
                    {"steps": f"Шаг {index}: нужны title до 50 и text до 200 символов."}
                )


class AnnouncementStep(BaseModel):
    announcement = models.ForeignKey(
        Announcement,
        on_delete=models.CASCADE,
        related_name="step_images",
    )
    order = models.PositiveSmallIntegerField(
        "Номер шага",
        validators=[MinValueValidator(1), MaxValueValidator(MAX_STEPS)],
    )
    image_object_key = models.CharField(
        "Иллюстрация",
        max_length=512,
        validators=[validate_relative_object_key],
    )
    image_width = models.PositiveIntegerField("Ширина", null=True, blank=True)
    image_height = models.PositiveIntegerField("Высота", null=True, blank=True)

    class Meta:
        db_table = "announcement_step"
        verbose_name = "иллюстрация шага"
        verbose_name_plural = "Иллюстрации шагов"
        ordering = ("announcement", "order")
        constraints = [
            models.UniqueConstraint(
                fields=("announcement", "order"),
                name="announcement_step_order_unique",
            ),
        ]

    def __str__(self) -> str:
        return f"Шаг {self.order}"


class WaveReason(models.TextChoices):
    PUBLISHED = "published", "Первая публикация"
    EDIT = "edit", "Правка с повторным показом"
    RESHOW = "reshow", "Показать снова"
    REPUBLISHED = "republished", "Опубликовано снова после снятия"


class AnnouncementWave(BaseModel):
    """One time the announcement was put on the home screen of the whole audience."""

    announcement = models.ForeignKey(
        Announcement,
        on_delete=models.CASCADE,
        related_name="waves",
    )
    number = models.PositiveIntegerField("Номер волны")
    reason = models.CharField("Повод", max_length=16, choices=WaveReason)
    revision = models.PositiveIntegerField("Редакция")
    started_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        verbose_name="Запустил",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="+",
    )

    class Meta:
        db_table = "announcement_wave"
        ordering = ("announcement", "number")
        constraints = [
            models.UniqueConstraint(
                fields=("announcement", "number"),
                name="announcement_wave_number_unique",
            ),
        ]

    def __str__(self) -> str:
        return f"Волна {self.number}"


class AnnouncementReceipt(BaseModel):
    """What a signed-in person has read or closed; synced between their devices."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="announcement_receipts",
    )
    announcement = models.ForeignKey(
        Announcement,
        on_delete=models.CASCADE,
        related_name="receipts",
    )
    read_at = models.DateTimeField(null=True, blank=True)
    dismissed_at = models.DateTimeField(null=True, blank=True)
    # The latest wave in which the person read or closed it: hidden until the next one.
    wave = models.PositiveIntegerField(default=1)

    class Meta:
        db_table = "announcement_receipt"
        ordering = ("-updated_at", "-id")
        constraints = [
            models.UniqueConstraint(
                fields=("user", "announcement"),
                name="announcement_receipt_user_unique",
            ),
        ]


class StatSurface(models.TextChoices):
    BUBBLE = "bubble", "Пузырь"
    CARD = "card", "Карточка"
    FEED = "feed", "Лента"
    MODAL = "modal", "Окно"
    PUSH = "push", "Push"


class StatEvent(models.TextChoices):
    IMPRESSION = "impression", "Показ"
    OPEN = "open", "Открытие"
    CLICK = "click", "Нажатие кнопки"
    DISMISS = "dismiss", "Закрытие"


class AnnouncementDailyStat(models.Model):
    """Daily sums only: no person, device, address or cookie is ever stored."""

    date = models.DateField()
    announcement = models.ForeignKey(
        Announcement,
        on_delete=models.CASCADE,
        related_name="daily_stats",
    )
    platform = models.CharField(max_length=8, choices=[(code, code) for code in PLATFORMS])
    surface = models.CharField(max_length=8, choices=StatSurface)
    event = models.CharField(max_length=12, choices=StatEvent)
    wave = models.PositiveIntegerField(default=1)
    count = models.PositiveIntegerField(default=0)

    class Meta:
        db_table = "announcement_daily_stat"
        constraints = [
            models.UniqueConstraint(
                fields=("date", "announcement", "wave", "platform", "surface", "event"),
                name="announcement_daily_stat_wave_unique",
            ),
        ]

    def __str__(self) -> str:
        return (
            f"{self.date} волна {self.wave} {self.platform} {self.surface} {self.event}: "
            f"{self.count}"
        )


class AnnouncementSettings(BaseModel):
    """Site-wide switch: hides every announcement at once without editing them."""

    singleton = models.BooleanField(default=True, unique=True, editable=False)
    window_checked_at = models.DateTimeField(null=True, blank=True, editable=False)
    is_enabled = models.BooleanField(
        "Показывать объявления",
        default=True,
        help_text=(
            "Выключите, чтобы сразу скрыть все объявления на сайте и в приложении. "
            "Сами объявления не меняются."
        ),
    )

    class Meta:
        db_table = "announcement_settings"
        verbose_name = "настройка объявлений"
        verbose_name_plural = "Показ объявлений"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(singleton=True),
                name="announcement_settings_singleton",
            ),
        ]

    def __str__(self) -> str:
        return "Показ объявлений: включён" if self.is_enabled else "Показ объявлений: выключен"
