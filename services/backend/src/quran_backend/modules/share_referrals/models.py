# ruff: noqa: RUF001
from __future__ import annotations

import secrets
import uuid
from typing import Any
from urllib.parse import urlsplit

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models, transaction
from django.utils import timezone

from quran_backend.modules.core.models import BaseModel

SUPPORTED_LOCALES = ("ar", "en", "ru", "tr")


def generate_referral_code() -> str:
    """Return a URL-safe opaque code containing no account information."""
    return secrets.token_urlsafe(12)


def validate_https_url(value: str, *, field: str, allow_query: bool = True) -> None:
    if not value:
        return
    parsed = urlsplit(value)
    try:
        port = parsed.port
    except ValueError as exc:
        raise ValidationError({field: "Некорректный порт в адресе."}) from exc
    if (
        parsed.scheme != "https"
        or parsed.hostname is None
        or parsed.username is not None
        or parsed.password is not None
        or port not in {None, 443}
        or (not allow_query and parsed.query)
        or parsed.fragment
    ):
        raise ValidationError(
            {field: "Нужен HTTPS-адрес без логина, пароля, нестандартного порта и #fragment."}
        )


class ShareCampaign(BaseModel):
    key = models.SlugField(
        max_length=64,
        unique=True,
        verbose_name="Стабильный ключ",
        help_text="Не меняйте после выпуска клиента, например app-invite.",
    )
    internal_name = models.CharField(max_length=120, verbose_name="Название для команды")
    is_active = models.BooleanField(
        default=False,
        verbose_name="Включена",
        help_text="Кампания доступна только внутри указанного временного окна.",
    )
    starts_at = models.DateTimeField(null=True, blank=True, verbose_name="Начало")
    ends_at = models.DateTimeField(null=True, blank=True, verbose_name="Окончание")
    canonical_download_url = models.URLField(
        max_length=500,
        verbose_name="Основная страница загрузки",
        help_text="Доверенный HTTPS-адрес. Публичный referral redirect ведёт только сюда.",
    )
    ios_url = models.URLField(max_length=500, blank=True, verbose_name="App Store URL")
    android_url = models.URLField(max_length=500, blank=True, verbose_name="Google Play URL")
    short_link_base_url = models.URLField(
        max_length=500,
        blank=True,
        verbose_name="База коротких ссылок",
        help_text="Например https://iqro.app/r. Если пусто, API использует свой /r/ путь.",
    )
    referral_enabled = models.BooleanField(default=True, verbose_name="Рефералы включены")
    reward_points = models.PositiveIntegerField(
        default=0,
        verbose_name="Баллов за подтверждённое приглашение",
        help_text="Начисление создаётся сервером после квалификации; 0 отключает бонус.",
    )
    priority = models.SmallIntegerField(
        default=100,
        verbose_name="Приоритет",
        help_text="При запросе без ключа выбирается активная кампания с большим приоритетом.",
    )
    config_version = models.PositiveBigIntegerField(
        default=1,
        editable=False,
        verbose_name="Версия конфигурации",
    )

    class Meta:
        db_table = "share_campaign"
        ordering = ("-priority", "key")
        verbose_name = "Кампания «Поделиться»"
        verbose_name_plural = "Кампании «Поделиться»"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(ends_at__isnull=True)
                | models.Q(starts_at__isnull=True)
                | models.Q(ends_at__gt=models.F("starts_at")),
                name="share_campaign_valid_window",
            )
        ]
        indexes = [
            models.Index(
                fields=("is_active", "priority", "starts_at", "ends_at"),
                name="share_campaign_active_idx",
            )
        ]

    def __str__(self) -> str:
        return f"{self.internal_name} ({self.key})"

    def clean(self) -> None:
        super().clean()
        self.key = self.key.strip().lower()
        self.internal_name = self.internal_name.strip()
        validate_https_url(self.canonical_download_url, field="canonical_download_url")
        validate_https_url(self.ios_url, field="ios_url")
        validate_https_url(self.android_url, field="android_url")
        validate_https_url(
            self.short_link_base_url,
            field="short_link_base_url",
            allow_query=False,
        )

    def save(self, *args: Any, **kwargs: Any) -> None:
        self.full_clean()
        if self.pk and type(self).objects.filter(pk=self.pk).exists():
            with transaction.atomic():
                current = (
                    type(self).objects.select_for_update().only("config_version").get(pk=self.pk)
                )
                self.config_version = current.config_version + 1
                update_fields = kwargs.get("update_fields")
                if update_fields is not None:
                    kwargs["update_fields"] = (*update_fields, "config_version")
                super().save(*args, **kwargs)
        else:
            super().save(*args, **kwargs)

    def is_available_at(self, moment: Any | None = None) -> bool:
        at = moment or timezone.now()
        return bool(
            self.is_active
            and (self.starts_at is None or self.starts_at <= at)
            and (self.ends_at is None or self.ends_at > at)
        )


class ShareCampaignCopy(BaseModel):
    campaign = models.ForeignKey(
        ShareCampaign,
        on_delete=models.CASCADE,
        related_name="localized_copies",
        verbose_name="Кампания",
    )
    locale = models.CharField(max_length=8, verbose_name="Язык")
    title = models.CharField(max_length=160, verbose_name="Заголовок")
    message = models.TextField(max_length=1200, verbose_name="Текст для отправки")
    cta_label = models.CharField(max_length=80, blank=True, verbose_name="Текст кнопки")

    class Meta:
        db_table = "share_campaign_copy"
        ordering = ("campaign", "locale")
        verbose_name = "Перевод кампании"
        verbose_name_plural = "Переводы кампаний"
        constraints = [
            models.UniqueConstraint(
                fields=("campaign", "locale"),
                name="share_campaign_copy_locale_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(locale__in=SUPPORTED_LOCALES),
                name="share_campaign_copy_locale_supported",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.campaign.key}: {self.locale}"

    def clean(self) -> None:
        super().clean()
        self.locale = self.locale.strip().lower()
        self.title = self.title.strip()
        self.message = self.message.strip()
        self.cta_label = self.cta_label.strip()

    def save(self, *args: Any, **kwargs: Any) -> None:
        self.full_clean()
        is_new = self._state.adding
        super().save(*args, **kwargs)
        ShareCampaign.objects.filter(pk=self.campaign_id).update(
            config_version=models.F("config_version") + 1,
            updated_at=timezone.now(),
        )
        if is_new:
            self.campaign.refresh_from_db(fields=("config_version", "updated_at"))

    def delete(self, *args: Any, **kwargs: Any) -> tuple[int, dict[str, int]]:
        campaign_id = self.campaign_id
        result = super().delete(*args, **kwargs)
        ShareCampaign.objects.filter(pk=campaign_id).update(
            config_version=models.F("config_version") + 1,
            updated_at=timezone.now(),
        )
        return result


class ReferralLink(BaseModel):
    campaign = models.ForeignKey(
        ShareCampaign,
        on_delete=models.PROTECT,
        related_name="referral_links",
        verbose_name="Кампания",
    )
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="referral_links",
        verbose_name="Владелец",
    )
    code = models.CharField(
        max_length=32,
        unique=True,
        default=generate_referral_code,
        editable=False,
        verbose_name="Промокод",
    )
    is_enabled = models.BooleanField(default=True, verbose_name="Включена")
    disabled_at = models.DateTimeField(null=True, blank=True, verbose_name="Отключена")
    disabled_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="disabled_referral_links",
        null=True,
        blank=True,
        limit_choices_to={"is_staff": True},
        verbose_name="Отключил",
    )
    revoked_at = models.DateTimeField(null=True, blank=True, verbose_name="Отозвана")
    revoked_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="revoked_referral_links",
        null=True,
        blank=True,
        limit_choices_to={"is_staff": True},
        verbose_name="Отозвал",
    )
    state_reason = models.CharField(max_length=500, blank=True, verbose_name="Причина")

    class Meta:
        db_table = "share_referral_link"
        ordering = ("-created_at",)
        verbose_name = "Реферальная ссылка / промокод"
        verbose_name_plural = "Реферальные ссылки / промокоды"
        constraints = [
            models.UniqueConstraint(
                fields=("campaign", "owner"),
                name="share_referral_campaign_owner_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(revoked_at__isnull=True, revoked_by__isnull=True)
                | models.Q(revoked_at__isnull=False, revoked_by__isnull=False),
                name="share_referral_revocation_shape",
            ),
        ]
        indexes = [
            models.Index(
                fields=("campaign", "is_enabled", "revoked_at"),
                name="share_referral_state_idx",
            )
        ]

    def __str__(self) -> str:
        return f"{self.campaign.key}: {self.code}"

    def is_available_at(self, moment: Any | None = None) -> bool:
        return bool(
            self.is_enabled
            and self.revoked_at is None
            and self.campaign.referral_enabled
            and self.campaign.is_available_at(moment)
        )


class ShareEventAction(models.TextChoices):
    OPENED = "opened", "Opened"
    SHARE_SHEET_OPENED = "share_sheet_opened", "Share sheet opened"
    LINK_COPIED = "link_copied", "Link copied"
    REFERRAL_CODE_COPIED = "referral_code_copied", "Referral code copied"
    SHARE_COMPLETED = "share_completed", "Share completed"
    REFERRAL_CODE_ENTERED = "referral_code_entered", "Referral code entered"


class ShareEventResult(models.TextChoices):
    STARTED = "started", "Started"
    SUCCEEDED = "succeeded", "Succeeded"
    CANCELLED = "cancelled", "Cancelled"
    FAILED = "failed", "Failed"


class ShareEventChannel(models.TextChoices):
    SYSTEM = "system", "System share sheet"
    COPY = "copy", "Copy"
    WHATSAPP = "whatsapp", "WhatsApp"
    TELEGRAM = "telegram", "Telegram"
    EMAIL = "email", "Email"
    SMS = "sms", "SMS"
    OTHER = "other", "Other"


class AccountMode(models.TextChoices):
    GUEST = "guest", "Guest"
    VERIFIED = "verified", "Verified account"


class ShareEvent(BaseModel):
    client_event_id = models.UUIDField(unique=True, verbose_name="ID события на клиенте")
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="share_events",
        verbose_name="Аккаунт",
    )
    account_mode = models.CharField(max_length=16, choices=AccountMode, verbose_name="Тип аккаунта")
    campaign = models.ForeignKey(
        ShareCampaign,
        on_delete=models.PROTECT,
        related_name="share_events",
        verbose_name="Кампания",
    )
    referral_link = models.ForeignKey(
        ReferralLink,
        on_delete=models.PROTECT,
        related_name="share_events",
        null=True,
        blank=True,
        verbose_name="Реферальный код",
    )
    action = models.CharField(max_length=32, choices=ShareEventAction, verbose_name="Действие")
    result = models.CharField(max_length=16, choices=ShareEventResult, verbose_name="Результат")
    channel = models.CharField(max_length=16, choices=ShareEventChannel, verbose_name="Канал")
    occurred_at = models.DateTimeField(verbose_name="Произошло на клиенте")
    received_at = models.DateTimeField(auto_now_add=True, db_index=True, verbose_name="Получено")
    metadata = models.JSONField(default=dict, blank=True, verbose_name="Безопасные метаданные")

    class Meta:
        db_table = "share_event"
        ordering = ("-received_at", "-id")
        verbose_name = "Событие «Поделиться»"
        verbose_name_plural = "События «Поделиться»"
        indexes = [
            models.Index(
                fields=("campaign", "action", "received_at"),
                name="share_event_analytics_idx",
            ),
            models.Index(fields=("actor", "received_at"), name="share_event_actor_idx"),
        ]

    def __str__(self) -> str:
        return f"{self.campaign.key}: {self.action} ({self.client_event_id})"

    def save(self, *args: Any, **kwargs: Any) -> None:
        if self.pk and type(self).objects.filter(pk=self.pk).exists():
            raise ValidationError("Share events are immutable.")
        super().save(*args, **kwargs)

    def delete(self, *_args: Any, **_kwargs: Any) -> tuple[int, dict[str, int]]:
        raise ValidationError("Share events are immutable.")


class ReferralClick(BaseModel):
    referral_link = models.ForeignKey(
        ReferralLink,
        on_delete=models.PROTECT,
        related_name="clicks",
        verbose_name="Реферальный код",
    )
    campaign = models.ForeignKey(
        ShareCampaign,
        on_delete=models.PROTECT,
        related_name="referral_clicks",
        verbose_name="Кампания",
    )
    channel = models.CharField(
        max_length=16,
        choices=ShareEventChannel,
        default=ShareEventChannel.OTHER,
        verbose_name="Канал",
    )
    received_at = models.DateTimeField(auto_now_add=True, db_index=True, verbose_name="Получено")

    class Meta:
        db_table = "share_referral_click"
        ordering = ("-received_at", "-id")
        verbose_name = "Переход по короткой ссылке"
        verbose_name_plural = "Переходы по коротким ссылкам"
        indexes = [
            models.Index(
                fields=("campaign", "received_at"),
                name="share_click_campaign_idx",
            )
        ]

    def save(self, *args: Any, **kwargs: Any) -> None:
        if self.pk and type(self).objects.filter(pk=self.pk).exists():
            raise ValidationError("Referral clicks are immutable.")
        super().save(*args, **kwargs)

    def delete(self, *_args: Any, **_kwargs: Any) -> tuple[int, dict[str, int]]:
        raise ValidationError("Referral clicks are immutable.")


class AttributionSource(models.TextChoices):
    MANUAL_ADMIN = "manual_admin", "Manual admin review"
    SIGNUP_HOOK = "signup_hook", "Verified signup hook"


class ReferralAttribution(BaseModel):
    campaign = models.ForeignKey(
        ShareCampaign,
        on_delete=models.PROTECT,
        related_name="attributions",
        verbose_name="Кампания",
    )
    referral_link = models.ForeignKey(
        ReferralLink,
        on_delete=models.PROTECT,
        related_name="attributions",
        verbose_name="Реферальный код",
    )
    invitee = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="referral_attributions",
        verbose_name="Приглашённый аккаунт",
    )
    source = models.CharField(max_length=20, choices=AttributionSource, verbose_name="Источник")
    idempotency_key = models.UUIDField(
        unique=True,
        default=uuid.uuid7,
        verbose_name="Ключ идемпотентности",
    )
    attributed_at = models.DateTimeField(default=timezone.now, verbose_name="Атрибуция")
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="created_referral_attributions",
        null=True,
        blank=True,
        limit_choices_to={"is_staff": True},
        verbose_name="Создал",
    )

    class Meta:
        db_table = "share_referral_attribution"
        ordering = ("-attributed_at", "-id")
        verbose_name = "Атрибуция приглашения"
        verbose_name_plural = "Атрибуции приглашений"
        constraints = [
            models.UniqueConstraint(
                fields=("campaign", "invitee"),
                name="share_attribution_campaign_invitee_unique",
            ),
        ]
        indexes = [
            models.Index(
                fields=("referral_link", "attributed_at"),
                name="share_attribution_link_idx",
            )
        ]

    def __str__(self) -> str:
        return f"{self.referral_link.code}: invitee {self.invitee_id}"

    def clean(self) -> None:
        super().clean()
        if self.referral_link_id and self.campaign_id != self.referral_link.campaign_id:
            raise ValidationError({"campaign": "Кампания должна совпадать с реферальной ссылкой."})
        if self.referral_link_id and self.invitee_id == self.referral_link.owner_id:
            raise ValidationError({"invitee": "Нельзя пригласить самого себя."})


class QualificationStatus(models.TextChoices):
    PENDING = "pending", "Pending review"
    QUALIFIED = "qualified", "Qualified"
    REJECTED = "rejected", "Rejected"
    REVERSED = "reversed", "Reversed"


class ReferralQualification(BaseModel):
    attribution = models.OneToOneField(
        ReferralAttribution,
        on_delete=models.PROTECT,
        related_name="qualification",
        verbose_name="Атрибуция",
    )
    status = models.CharField(
        max_length=16,
        choices=QualificationStatus,
        default=QualificationStatus.PENDING,
        verbose_name="Статус",
    )
    decided_at = models.DateTimeField(null=True, blank=True, verbose_name="Решение принято")
    decided_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="decided_referral_qualifications",
        null=True,
        blank=True,
        limit_choices_to={"is_staff": True},
        verbose_name="Решение принял",
    )
    decision_reason = models.CharField(max_length=500, blank=True, verbose_name="Основание")

    class Meta:
        db_table = "share_referral_qualification"
        ordering = ("-created_at",)
        verbose_name = "Квалификация приглашения"
        verbose_name_plural = "Квалификации приглашений"

    def __str__(self) -> str:
        return f"{self.attribution.referral_link.code}: {self.status}"


class RewardStatus(models.TextChoices):
    PENDING = "pending", "Pending approval"
    APPROVED = "approved", "Approved"
    REVERSED = "reversed", "Reversed"


class ReferralReward(BaseModel):
    qualification = models.OneToOneField(
        ReferralQualification,
        on_delete=models.PROTECT,
        related_name="reward",
        verbose_name="Квалификация",
    )
    campaign = models.ForeignKey(
        ShareCampaign,
        on_delete=models.PROTECT,
        related_name="rewards",
        verbose_name="Кампания",
    )
    beneficiary = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="referral_rewards",
        verbose_name="Получатель",
    )
    points = models.PositiveIntegerField(verbose_name="Баллы")
    status = models.CharField(
        max_length=16,
        choices=RewardStatus,
        default=RewardStatus.PENDING,
        verbose_name="Статус",
    )
    idempotency_key = models.CharField(
        max_length=160,
        unique=True,
        editable=False,
        verbose_name="Ключ идемпотентности",
    )
    approved_at = models.DateTimeField(null=True, blank=True, verbose_name="Одобрено")
    approved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="approved_referral_rewards",
        null=True,
        blank=True,
        limit_choices_to={"is_staff": True},
        verbose_name="Одобрил",
    )
    reversed_at = models.DateTimeField(null=True, blank=True, verbose_name="Отменено")
    reversed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="reversed_referral_rewards",
        null=True,
        blank=True,
        limit_choices_to={"is_staff": True},
        verbose_name="Отменил",
    )
    reversal_reason = models.CharField(max_length=500, blank=True, verbose_name="Причина отмены")

    class Meta:
        db_table = "share_referral_reward"
        ordering = ("-created_at",)
        verbose_name = "Начисление за приглашение"
        verbose_name_plural = "Начисления за приглашения"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(points__gt=0),
                name="share_reward_points_positive",
            ),
            models.CheckConstraint(
                condition=~models.Q(status=RewardStatus.APPROVED)
                | models.Q(approved_at__isnull=False, approved_by__isnull=False),
                name="share_reward_approved_audit",
            ),
            models.CheckConstraint(
                condition=~models.Q(status=RewardStatus.REVERSED)
                | models.Q(
                    reversed_at__isnull=False,
                    reversed_by__isnull=False,
                ),
                name="share_reward_reversed_audit",
            ),
        ]
        indexes = [
            models.Index(
                fields=("beneficiary", "status", "created_at"),
                name="share_reward_balance_idx",
            )
        ]

    def __str__(self) -> str:
        return f"{self.points} points: {self.status}"


class RewardAuditAction(models.TextChoices):
    CREATED = "created", "Created pending"
    APPROVED = "approved", "Approved"
    REVERSED = "reversed", "Reversed"


class ReferralRewardAudit(BaseModel):
    reward = models.ForeignKey(
        ReferralReward,
        on_delete=models.PROTECT,
        related_name="audit_events",
        verbose_name="Начисление",
    )
    action = models.CharField(max_length=16, choices=RewardAuditAction, verbose_name="Операция")
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="referral_reward_audits",
        null=True,
        blank=True,
        limit_choices_to={"is_staff": True},
        verbose_name="Оператор",
    )
    previous_status = models.CharField(max_length=16, blank=True, verbose_name="Было")
    new_status = models.CharField(max_length=16, choices=RewardStatus, verbose_name="Стало")
    reason = models.CharField(max_length=500, blank=True, verbose_name="Причина")

    class Meta:
        db_table = "share_referral_reward_audit"
        ordering = ("-created_at",)
        verbose_name = "Аудит начисления"
        verbose_name_plural = "Аудит начислений"

    def save(self, *args: Any, **kwargs: Any) -> None:
        if self.pk and type(self).objects.filter(pk=self.pk).exists():
            raise ValidationError("Reward audit is immutable.")
        super().save(*args, **kwargs)

    def delete(self, *_args: Any, **_kwargs: Any) -> tuple[int, dict[str, int]]:
        raise ValidationError("Reward audit is immutable.")
