# ruff: noqa: RUF001
from __future__ import annotations

from typing import Any, ClassVar, cast

from django import forms
from django.contrib import admin, messages
from django.db.models import Count, Q
from django.http import HttpRequest
from django.urls import reverse
from django.utils import timezone
from django.utils.html import format_html

from quran_backend.modules.accounts.models import User, UserStatus
from quran_backend.modules.share_referrals.exceptions import ReferralConflict
from quran_backend.modules.share_referrals.models import (
    AttributionSource,
    ReferralAttribution,
    ReferralClick,
    ReferralLink,
    ReferralQualification,
    ReferralReward,
    ReferralRewardAudit,
    ShareCampaign,
    ShareCampaignCopy,
    ShareEvent,
)
from quran_backend.modules.share_referrals.services import (
    approve_reward,
    qualify_referral,
    record_referral_attribution,
    reject_referral,
    reverse_qualification,
    reverse_reward,
    revoke_referral_link,
    set_referral_link_enabled,
)


class ShareCampaignAdminForm(forms.ModelForm):  # type: ignore[type-arg]
    class Meta:
        model = ShareCampaign
        fields = (
            "key",
            "internal_name",
            "is_active",
            "starts_at",
            "ends_at",
            "canonical_download_url",
            "ios_url",
            "android_url",
            "short_link_base_url",
            "referral_enabled",
            "reward_points",
            "priority",
        )
        labels: ClassVar[dict[str, str]] = {
            "internal_name": "Название кампании в админке",
            "key": "Код кампании",
            "is_active": "Показывать пользователям",
            "starts_at": "Начать показ",
            "ends_at": "Закончить показ",
            "canonical_download_url": "Куда ведёт приглашение",
            "ios_url": "Ссылка на приложение в App Store",
            "android_url": "Ссылка на приложение в Google Play",
            "short_link_base_url": "Адрес коротких ссылок",
            "referral_enabled": "Выдавать персональные ссылки и промокоды",
            "reward_points": "Бонус пригласившему пользователю",
            "priority": "Приоритет кампании",
        }
        help_texts: ClassVar[dict[str, str]] = {
            "internal_name": "Видно только сотрудникам, например «Основная кампания IQRO».",
            "key": (
                "Короткий постоянный код латиницей, например app-invite. "
                "После запуска кампании его не меняют."
            ),
            "is_active": (
                "Включайте только после заполнения ссылки и текстов минимум "
                "на русском и английском."
            ),
            "starts_at": "Оставьте пустым, если кампания должна начать работать сразу.",
            "ends_at": "Оставьте пустым, если у кампании нет даты окончания.",
            "canonical_download_url": (
                "Безопасный HTTPS-адрес страницы скачивания или IQRO. "
                "Все короткие ссылки ведут сюда."
            ),
            "ios_url": "Можно оставить пустым, пока приложение не опубликовано в App Store.",
            "android_url": "Можно оставить пустым, пока приложение не опубликовано в Google Play.",
            "short_link_base_url": (
                "Например https://iqro.example/r. Если пусто, используется адрес текущего сайта."
            ),
            "referral_enabled": (
                "Разрешает подтверждённым пользователям получать свою ссылку в личном кабинете."
            ),
            "reward_points": (
                "Количество внутренних баллов после подтверждения приглашения. "
                "Укажите 0, если бонусов нет."
            ),
            "priority": (
                "Если одновременно работают несколько кампаний, показывается кампания "
                "с большим числом."
            ),
        }

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        self.fields["key"].widget.attrs["placeholder"] = "app-invite"
        self.fields["canonical_download_url"].widget.attrs["placeholder"] = (
            "https://iqro.example/download"
        )
        self.fields["short_link_base_url"].widget.attrs["placeholder"] = "https://iqro.example/r"


class ShareCampaignCopyAdminForm(forms.ModelForm):  # type: ignore[type-arg]
    locale = forms.ChoiceField(
        choices=(
            ("ru", "Русский"),
            ("en", "English"),
            ("ar", "العربية"),
            ("tr", "Türkçe"),
        ),
        label="Язык",
        help_text="Для запуска заполните минимум русский и английский варианты.",
    )

    class Meta:
        model = ShareCampaignCopy
        fields = ("locale", "title", "message", "cta_label")
        labels: ClassVar[dict[str, str]] = {
            "title": "Заголовок блока",
            "message": "Текст приглашения",
            "cta_label": "Текст кнопки",
        }
        help_texts: ClassVar[dict[str, str]] = {
            "title": "Например «Пригласить друзей в IQRO».",
            "message": "Этот текст попадёт в системное меню «Поделиться».",
            "cta_label": "Например «Поделиться». Можно оставить пустым.",
        }


class ShareCampaignCopyInline(admin.StackedInline):  # type: ignore[type-arg]
    model = ShareCampaignCopy
    form = ShareCampaignCopyAdminForm
    extra = 1
    fields = ("locale", "title", "message", "cta_label")
    verbose_name = "Текст для одного языка"
    verbose_name_plural = "Что увидят пользователи на разных языках"


@admin.register(ShareCampaign)
class ShareCampaignAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    form = ShareCampaignAdminForm
    list_display = (
        "internal_name",
        "key",
        "available_now",
        "referral_enabled",
        "reward_points",
        "priority",
        "config_version",
        "updated_at",
    )
    list_filter = ("is_active", "referral_enabled")
    search_fields = ("=key", "internal_name")
    ordering = ("-priority", "key")
    readonly_fields = ("id", "config_version", "created_at", "updated_at", "download_link")
    fieldsets = (
        (
            "1. Что это за кампания",
            {
                "description": (
                    "Создайте одну основную кампанию. Сначала заполните все поля и тексты ниже, "
                    "затем включите показ пользователям."
                ),
                "fields": (
                    "internal_name",
                    "key",
                    "is_active",
                    "starts_at",
                    "ends_at",
                    "priority",
                ),
            },
        ),
        (
            "2. Куда попадёт пользователь",
            {
                "description": (
                    "Основная ссылка обязательна. App Store и Google Play можно добавить позже "
                    "без выпуска новой версии приложения."
                ),
                "fields": (
                    "canonical_download_url",
                    "download_link",
                    "ios_url",
                    "android_url",
                    "short_link_base_url",
                ),
            },
        ),
        (
            "3. Персональные приглашения и бонусы",
            {
                "description": (
                    "После включения пользователь получит персональную ссылку в личном кабинете. "
                    "Само нажатие «Поделиться» бонус не начисляет: приглашение "
                    "сначала подтверждается."
                ),
                "fields": ("referral_enabled", "reward_points"),
            },
        ),
        (
            "Служебная информация",
            {
                "classes": ("collapse",),
                "fields": ("id", "config_version", "created_at", "updated_at"),
            },
        ),
    )
    inlines = (ShareCampaignCopyInline,)

    @admin.display(boolean=True, description="Доступна сейчас")
    def available_now(self, obj: ShareCampaign) -> bool:
        return obj.is_available_at()

    @admin.display(description="Проверить страницу")
    def download_link(self, obj: ShareCampaign) -> str:
        if not obj.canonical_download_url:
            return "—"
        return format_html(
            '<a href="{}" target="_blank" rel="noopener noreferrer">Открыть HTTPS-страницу</a>',
            obj.canonical_download_url,
        )


class ImmutableAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_change_permission(self, request: HttpRequest, _obj: object | None = None) -> bool:
        return bool(request.user.has_perm(f"{self.opts.app_label}.view_{self.opts.model_name}"))

    def has_delete_permission(self, _request: HttpRequest, _obj: object | None = None) -> bool:
        return False


@admin.register(ReferralLink)
class ReferralLinkAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = (
        "code",
        "campaign",
        "owner_account",
        "available_now",
        "click_count",
        "short_link",
        "created_at",
    )
    list_filter = ("campaign", "is_enabled", "revoked_at")
    search_fields = ("=code", "owner__email")
    ordering = ("-created_at",)
    readonly_fields = (
        "id",
        "campaign",
        "owner",
        "code",
        "is_enabled",
        "disabled_at",
        "disabled_by",
        "revoked_at",
        "revoked_by",
        "state_reason",
        "created_at",
        "updated_at",
        "short_link",
    )
    fieldsets = (
        ("Персональная ссылка", {"fields": ("campaign", "owner", "code", "short_link")}),
        (
            "Состояние — меняется только действиями ниже",
            {
                "fields": (
                    "is_enabled",
                    "disabled_at",
                    "disabled_by",
                    "revoked_at",
                    "revoked_by",
                    "state_reason",
                )
            },
        ),
        (
            "Служебная информация",
            {"classes": ("collapse",), "fields": ("id", "created_at", "updated_at")},
        ),
    )
    actions = ("enable_selected", "disable_selected", "revoke_selected")
    list_select_related = ("campaign", "owner")

    def get_queryset(self, request: HttpRequest) -> Any:
        return super().get_queryset(request).annotate(admin_click_count=Count("clicks"))

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_delete_permission(self, _request: HttpRequest, _obj: object | None = None) -> bool:
        return False

    @admin.display(description="Кто приглашает", ordering="owner__email")
    def owner_account(self, obj: ReferralLink) -> str:
        return obj.owner.email or "Подтверждённый пользователь"

    @admin.display(boolean=True, description="Работает сейчас")
    def available_now(self, obj: ReferralLink) -> bool:
        return obj.is_available_at()

    @admin.display(description="Переходы")
    def click_count(self, obj: ReferralLink) -> int:
        return int(getattr(obj, "admin_click_count", 0))

    @admin.display(description="Короткая ссылка")
    def short_link(self, obj: ReferralLink) -> str:
        if obj.campaign.short_link_base_url:
            url = f"{obj.campaign.short_link_base_url.rstrip('/')}/{obj.code}"
        else:
            url = reverse("share-referrals:referral-redirect", kwargs={"code": obj.code})
        return format_html(
            '<a href="{}" target="_blank" rel="noopener noreferrer">{}</a>',
            url,
            url,
        )

    @admin.action(description="Включить выбранные ссылки (отозванные не включатся)")
    def enable_selected(self, request: HttpRequest, queryset: Any) -> None:
        for link_id in queryset.values_list("id", flat=True):
            try:
                set_referral_link_enabled(
                    link_id,
                    enabled=True,
                    actor=request.user,  # type: ignore[arg-type]
                    reason="Включено оператором через Django Admin.",
                )
            except ReferralConflict as exc:
                self.message_user(request, str(exc.detail), level=messages.WARNING)

    @admin.action(description="Отключить выбранные ссылки (обратимо)")
    def disable_selected(self, request: HttpRequest, queryset: Any) -> None:
        for link_id in queryset.values_list("id", flat=True):
            set_referral_link_enabled(
                link_id,
                enabled=False,
                actor=request.user,  # type: ignore[arg-type]
                reason="Отключено оператором через Django Admin.",
            )

    @admin.action(description="ОТОЗВАТЬ выбранные ссылки без возможности включения")
    def revoke_selected(self, request: HttpRequest, queryset: Any) -> None:
        for link_id in queryset.values_list("id", flat=True):
            revoke_referral_link(
                link_id,
                actor=request.user,  # type: ignore[arg-type]
                reason="Безвозвратно отозвано оператором через Django Admin.",
            )


@admin.register(ShareEvent)
class ShareEventAdmin(ImmutableAdmin):
    list_display = (
        "client_event_id",
        "campaign",
        "action",
        "result",
        "channel",
        "account_mode",
        "occurred_at",
        "received_at",
    )
    list_filter = ("campaign", "action", "result", "channel", "account_mode")
    search_fields = ("=client_event_id", "=referral_link__code")
    date_hierarchy = "received_at"
    ordering = ("-received_at",)
    readonly_fields = tuple(field.name for field in ShareEvent._meta.fields)
    list_select_related = ("campaign", "referral_link")


@admin.register(ReferralClick)
class ReferralClickAdmin(ImmutableAdmin):
    list_display = ("id", "campaign", "referral_link", "channel", "received_at")
    list_filter = ("campaign", "channel")
    search_fields = ("=referral_link__code",)
    date_hierarchy = "received_at"
    ordering = ("-received_at",)
    readonly_fields = tuple(field.name for field in ReferralClick._meta.fields)
    list_select_related = ("campaign", "referral_link")


class ReferralLinkChoiceField(forms.ModelChoiceField):  # type: ignore[type-arg]
    def label_from_instance(self, obj: ReferralLink) -> str:
        owner = obj.owner.email or "Подтверждённый пользователь"
        return f"{owner} — {obj.campaign.internal_name} — промокод {obj.code}"


class VerifiedUserChoiceField(forms.ModelChoiceField):  # type: ignore[type-arg]
    def label_from_instance(self, obj: User) -> str:
        return obj.email or "Подтверждённый пользователь"


class ReferralAttributionAdminForm(forms.ModelForm):  # type: ignore[type-arg]
    referral_link = ReferralLinkChoiceField(
        queryset=ReferralLink.objects.none(),
        empty_label="Выберите, кто пригласил пользователя",
        label="Кто пригласил",
        help_text=(
            "Показываются только работающие персональные ссылки. Если список пуст, сначала "
            "включите кампанию, затем пользователь должен получить ссылку в личном кабинете."
        ),
    )
    invitee = VerifiedUserChoiceField(
        queryset=User.objects.none(),
        empty_label="Выберите приглашённого пользователя",
        label="Кого пригласили",
        help_text=(
            "Показываются только подтверждённые аккаунты с email. "
            "Гостевые профили здесь не используются."
        ),
    )
    approve_now = forms.BooleanField(
        required=False,
        initial=True,
        label="Условия приглашения уже выполнены",
        help_text=(
            "Оставьте включённым, если приглашение проверено. Будет создан ожидающий бонус, "
            "который затем можно одобрить в разделе «Бонусы за приглашения»."
        ),
    )

    class Meta:
        model = ReferralAttribution
        fields = ("referral_link", "invitee")

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        now = timezone.now()
        referral_link_field = cast(ReferralLinkChoiceField, self.fields["referral_link"])
        invitee_field = cast(VerifiedUserChoiceField, self.fields["invitee"])
        referral_link_field.queryset = (
            ReferralLink.objects.select_related("campaign", "owner")
            .filter(
                is_enabled=True,
                revoked_at__isnull=True,
                campaign__is_active=True,
                campaign__referral_enabled=True,
            )
            .filter(Q(campaign__starts_at__isnull=True) | Q(campaign__starts_at__lte=now))
            .filter(Q(campaign__ends_at__isnull=True) | Q(campaign__ends_at__gt=now))
            .order_by("owner__email", "campaign__internal_name")
        )
        invitee_field.queryset = User.objects.filter(
            status=UserStatus.ACTIVE,
            is_active=True,
            email__isnull=False,
        ).order_by("email")

    def clean(self) -> dict[str, Any]:
        cleaned = super().clean() or {}
        link = cleaned.get("referral_link")
        invitee = cleaned.get("invitee")
        if link is not None:
            self.instance.campaign = link.campaign
            self.instance.source = AttributionSource.MANUAL_ADMIN
        if invitee is not None and invitee.status != UserStatus.ACTIVE:
            self.add_error("invitee", "Нужен подтверждённый активный аккаунт.")
        if link is not None and invitee is not None and link.owner_id == invitee.id:
            self.add_error("invitee", "Нельзя пригласить самого себя.")
        return cleaned


@admin.register(ReferralAttribution)
class ReferralAttributionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    form = ReferralAttributionAdminForm
    list_display = (
        "campaign_name",
        "inviter_account",
        "invitee_account",
        "qualification_status",
        "attributed_at",
    )
    list_filter = ("campaign", "qualification__status")
    search_fields = ("=referral_link__code", "referral_link__owner__email", "invitee__email")
    ordering = ("-attributed_at",)
    date_hierarchy = "attributed_at"
    list_select_related = (
        "campaign",
        "referral_link__owner",
        "invitee",
        "created_by",
        "qualification",
    )

    def get_readonly_fields(
        self,
        _request: HttpRequest,
        obj: ReferralAttribution | None = None,
    ) -> tuple[str, ...]:
        if obj is None:
            return ()
        return (
            *tuple(field.name for field in ReferralAttribution._meta.fields),
            "qualification_status",
        )

    def get_fieldsets(
        self,
        _request: HttpRequest,
        obj: ReferralAttribution | None = None,
    ) -> tuple[Any, ...]:
        if obj is None:
            return (
                (
                    "Подтвердить приглашение вручную",
                    {
                        "description": (
                            "Используйте эту форму только после проверки регистрации. "
                            "Выберите пригласившего по его ссылке и подтверждённый "
                            "аккаунт нового пользователя. "
                            "Служебный ключ операции создастся автоматически."
                        ),
                        "fields": ("referral_link", "invitee", "approve_now"),
                    },
                ),
            )
        return (
            (
                "Приглашение",
                {
                    "fields": (
                        "campaign",
                        "referral_link",
                        "invitee",
                        "qualification_status",
                        "source",
                        "attributed_at",
                    )
                },
            ),
            (
                "Служебная информация",
                {
                    "classes": ("collapse",),
                    "fields": (
                        "id",
                        "idempotency_key",
                        "created_by",
                        "created_at",
                        "updated_at",
                    ),
                },
            ),
        )

    def has_delete_permission(self, _request: HttpRequest, _obj: object | None = None) -> bool:
        return False

    def save_model(
        self,
        request: HttpRequest,
        obj: ReferralAttribution,
        form: ReferralAttributionAdminForm,
        change: bool,
    ) -> None:
        if change:
            return
        attribution, _created = record_referral_attribution(
            link=obj.referral_link,
            invitee=obj.invitee,
            idempotency_key=obj.idempotency_key,
            source=AttributionSource.MANUAL_ADMIN,
            actor=request.user,  # type: ignore[arg-type]
        )
        obj.pk = attribution.pk
        obj.campaign = attribution.campaign
        obj.source = attribution.source
        obj.created_by = attribution.created_by
        obj.created_at = attribution.created_at
        obj.updated_at = attribution.updated_at
        obj._state.adding = False
        if form.cleaned_data.get("approve_now"):
            qualify_referral(
                attribution.qualification.id,
                actor=request.user,  # type: ignore[arg-type]
                reason="Приглашение проверено при ручном добавлении через Django Admin.",
            )
            self.message_user(
                request,
                "Приглашение подтверждено. Если для кампании задан бонус, "
                "он создан со статусом «Ожидает одобрения».",
                level=messages.SUCCESS,
            )

    @admin.display(description="Кампания", ordering="campaign__internal_name")
    def campaign_name(self, obj: ReferralAttribution) -> str:
        return obj.campaign.internal_name

    @admin.display(description="Кто пригласил", ordering="referral_link__owner__email")
    def inviter_account(self, obj: ReferralAttribution) -> str:
        return obj.referral_link.owner.email or "Подтверждённый пользователь"

    @admin.display(description="Кого пригласили", ordering="invitee__email")
    def invitee_account(self, obj: ReferralAttribution) -> str:
        return obj.invitee.email or "Подтверждённый пользователь"

    @admin.display(description="Статус проверки", ordering="qualification__status")
    def qualification_status(self, obj: ReferralAttribution) -> str:
        return str(obj.qualification.get_status_display())


@admin.register(ReferralQualification)
class ReferralQualificationAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = (
        "campaign_name",
        "inviter_account",
        "invitee_account",
        "status",
        "decided_at",
        "created_at",
    )
    list_filter = ("status", "attribution__campaign")
    search_fields = (
        "=attribution__referral_link__code",
        "attribution__referral_link__owner__email",
        "attribution__invitee__email",
    )
    ordering = ("-created_at",)
    readonly_fields = tuple(field.name for field in ReferralQualification._meta.fields)
    actions = ("qualify_selected", "reject_selected", "reverse_selected")
    list_select_related = (
        "attribution__campaign",
        "attribution__referral_link__owner",
        "attribution__invitee",
        "decided_by",
    )

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_delete_permission(self, _request: HttpRequest, _obj: object | None = None) -> bool:
        return False

    @admin.display(description="Кампания", ordering="attribution__campaign__internal_name")
    def campaign_name(self, obj: ReferralQualification) -> str:
        return obj.attribution.campaign.internal_name

    @admin.display(description="Кто пригласил", ordering="attribution__referral_link__owner__email")
    def inviter_account(self, obj: ReferralQualification) -> str:
        return obj.attribution.referral_link.owner.email or "Подтверждённый пользователь"

    @admin.display(description="Кого пригласили", ordering="attribution__invitee__email")
    def invitee_account(self, obj: ReferralQualification) -> str:
        return obj.attribution.invitee.email or "Подтверждённый пользователь"

    @admin.display(description="Промокод", ordering="attribution__referral_link__code")
    def referral_code(self, obj: ReferralQualification) -> str:
        return obj.attribution.referral_link.code

    @admin.action(description="Подтвердить приглашения и создать ожидающие начисления")
    def qualify_selected(self, request: HttpRequest, queryset: Any) -> None:
        for qualification_id in queryset.values_list("id", flat=True):
            try:
                qualify_referral(
                    qualification_id,
                    actor=request.user,  # type: ignore[arg-type]
                    reason="Подтверждено оператором через Django Admin.",
                )
            except ReferralConflict as exc:
                self.message_user(request, str(exc.detail), level=messages.WARNING)

    @admin.action(description="Отклонить ожидающие приглашения (без начисления)")
    def reject_selected(self, request: HttpRequest, queryset: Any) -> None:
        for qualification_id in queryset.values_list("id", flat=True):
            try:
                reject_referral(
                    qualification_id,
                    actor=request.user,  # type: ignore[arg-type]
                    reason="Отклонено оператором через Django Admin.",
                )
            except ReferralConflict as exc:
                self.message_user(request, str(exc.detail), level=messages.WARNING)

    @admin.action(description="Отменить подтверждённые приглашения и связанные начисления")
    def reverse_selected(self, request: HttpRequest, queryset: Any) -> None:
        for qualification_id in queryset.values_list("id", flat=True):
            try:
                reverse_qualification(
                    qualification_id,
                    actor=request.user,  # type: ignore[arg-type]
                    reason="Отменено оператором через Django Admin.",
                )
            except ReferralConflict as exc:
                self.message_user(request, str(exc.detail), level=messages.WARNING)


@admin.register(ReferralReward)
class ReferralRewardAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = (
        "campaign_name",
        "beneficiary_account",
        "invitee_account",
        "points",
        "status",
        "approved_at",
        "reversed_at",
        "created_at",
    )
    list_filter = ("campaign", "status")
    search_fields = (
        "beneficiary__email",
        "qualification__attribution__invitee__email",
        "=qualification__attribution__referral_link__code",
    )
    ordering = ("-created_at",)
    readonly_fields = tuple(field.name for field in ReferralReward._meta.fields)
    actions = ("approve_selected", "reverse_selected")
    list_select_related = (
        "campaign",
        "beneficiary",
        "qualification__attribution__invitee",
    )

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_delete_permission(self, _request: HttpRequest, _obj: object | None = None) -> bool:
        return False

    @admin.display(description="Кому начислить", ordering="beneficiary__email")
    def beneficiary_account(self, obj: ReferralReward) -> str:
        return obj.beneficiary.email or "Подтверждённый пользователь"

    @admin.display(
        description="За приглашение",
        ordering="qualification__attribution__invitee__email",
    )
    def invitee_account(self, obj: ReferralReward) -> str:
        return obj.qualification.attribution.invitee.email or "Подтверждённый пользователь"

    @admin.display(description="Кампания", ordering="campaign__internal_name")
    def campaign_name(self, obj: ReferralReward) -> str:
        return obj.campaign.internal_name

    @admin.action(description="Одобрить выбранные ожидающие начисления")
    def approve_selected(self, request: HttpRequest, queryset: Any) -> None:
        for reward_id in queryset.values_list("id", flat=True):
            try:
                approve_reward(
                    reward_id,
                    actor=request.user,  # type: ignore[arg-type]
                    reason="Одобрено оператором через Django Admin.",
                )
            except ReferralConflict as exc:
                self.message_user(request, str(exc.detail), level=messages.WARNING)

    @admin.action(description="ОТМЕНИТЬ выбранные начисления с записью в аудит")
    def reverse_selected(self, request: HttpRequest, queryset: Any) -> None:
        for reward_id in queryset.values_list("id", flat=True):
            reverse_reward(
                reward_id,
                actor=request.user,  # type: ignore[arg-type]
                reason="Отменено оператором через Django Admin.",
            )


@admin.register(ReferralRewardAudit)
class ReferralRewardAuditAdmin(ImmutableAdmin):
    list_display = (
        "id",
        "reward",
        "action",
        "previous_status",
        "new_status",
        "actor",
        "created_at",
    )
    list_filter = ("action", "new_status")
    search_fields = ("=reward__id", "=reward__beneficiary__id")
    ordering = ("-created_at",)
    readonly_fields = tuple(field.name for field in ReferralRewardAudit._meta.fields)
