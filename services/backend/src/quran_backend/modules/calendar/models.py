# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
from __future__ import annotations

import uuid
from urllib.parse import urlsplit

from django.core.exceptions import ValidationError
from django.core.validators import MaxValueValidator, MinValueValidator, RegexValidator
from django.db import models

from quran_backend.modules.core.models import BaseModel

LOCALES = ("ru", "en", "ar", "tr")
MONTHS = (
    (0, "Каждый месяц"),
    (1, "Мухаррам"),
    (2, "Сафар"),
    (3, "Раби аль-авваль"),
    (4, "Раби ас-сани"),
    (5, "Джумада аль-уля"),
    (6, "Джумада ас-сания"),
    (7, "Раджаб"),
    (8, "Шаабан"),
    (9, "Рамадан"),
    (10, "Шавваль"),
    (11, "Зуль-каада"),
    (12, "Зуль-хиджа"),
)


def event_code() -> str:
    return f"event_{uuid.uuid7().hex}"


class CalendarEvent(BaseModel):
    class Kind(models.TextChoices):
        OCCASION = "occasion", "Значимая дата или период"
        VOLUNTARY_FAST = "voluntary_fast", "Напоминание о добровольном посте"
        NO_FAST = "no_fast", "Праздник / дни без добровольного поста"

    code = models.SlugField(
        "Код события",
        unique=True,
        max_length=64,
        default=event_code,
        editable=False,
        validators=[RegexValidator(r"^[a-z][a-z0-9_]*$", "Латинские буквы, цифры и _.")],
        help_text="Создаётся автоматически и связывает событие с сайтом и приложением.",
    )
    kind = models.CharField("Тип отметки", choices=Kind, default=Kind.OCCASION, max_length=24)
    month = models.PositiveSmallIntegerField("Месяц по Хиджре", choices=MONTHS, default=0)
    day_start = models.PositiveSmallIntegerField(
        "С какого числа",
        validators=[MinValueValidator(1), MaxValueValidator(30)],
        default=1,
    )
    day_end = models.PositiveSmallIntegerField(
        "По какое число включительно",
        validators=[MinValueValidator(1), MaxValueValidator(30)],
        default=1,
        help_text="Для одного дня укажите то же число. В коротком месяце 30-й день пропускается.",
    )
    exclude_ramadan = models.BooleanField(
        "Не показывать в Рамадан",
        default=False,
        help_text="Для ежемесячных напоминаний, например белых дней.",
    )
    title_ru = models.CharField("Название на русском", max_length=180, blank=True)
    title_en = models.CharField("Название на английском", max_length=180, blank=True)
    title_ar = models.CharField("Название на арабском", max_length=180, blank=True)
    title_tr = models.CharField("Название на турецком", max_length=180, blank=True)
    description_ru = models.TextField("Пояснение на русском", blank=True, max_length=3000)
    description_en = models.TextField("Пояснение на английском", blank=True, max_length=3000)
    description_ar = models.TextField("Пояснение на арабском", blank=True, max_length=3000)
    description_tr = models.TextField("Пояснение на турецком", blank=True, max_length=3000)
    source_label = models.CharField("Название источника", max_length=180, blank=True)
    source_url = models.URLField(
        "Ссылка на источник",
        blank=True,
        help_text="HTTPS-ссылка на подтверждение даты и пояснения. Обязательна для публикации.",
    )
    is_published = models.BooleanField(
        "Показывать на сайте и в приложении",
        default=False,
        help_text=(
            "Для публикации заполните все четыре перевода и источник. "
            "Обновление каталога — до 5 минут онлайн."
        ),
    )
    sort_order = models.PositiveSmallIntegerField("Порядок в списке", default=100)

    class Meta:
        verbose_name = "событие календаря"
        verbose_name_plural = "События календаря"
        ordering = ("sort_order", "code")
        constraints = [
            models.CheckConstraint(condition=models.Q(month__lte=12), name="calendar_month_range"),
            models.CheckConstraint(
                condition=models.Q(
                    day_start__gte=1, day_end__lte=30, day_end__gte=models.F("day_start")
                ),
                name="calendar_day_range",
            ),
        ]

    def __str__(self) -> str:
        return self.title_ru or self.code

    def clean(self) -> None:
        super().clean()
        errors = {}
        if self.day_end < self.day_start:
            errors["day_end"] = "Последний день не может быть раньше первого."
        if self.source_url:
            parsed = urlsplit(self.source_url)
            if (
                parsed.scheme != "https"
                or not parsed.hostname
                or parsed.username
                or parsed.password
            ):
                errors["source_url"] = "Нужна HTTPS-ссылка без логина и пароля."
        if self.is_published:
            for field in (
                *(f"title_{locale}" for locale in LOCALES),
                *(f"description_{locale}" for locale in LOCALES),
                "source_label",
                "source_url",
            ):
                if not getattr(self, field).strip():
                    errors[field] = "Заполните перед публикацией."
        if errors:
            raise ValidationError(errors)
