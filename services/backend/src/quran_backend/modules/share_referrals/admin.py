# ruff: noqa: RUF001
from __future__ import annotations

from typing import Any

from django import forms
from django.contrib import admin, messages
from django.db.models import Count
from django.http import HttpRequest
from django.urls import reverse
from django.utils.html import format_html

from quran_backend.modules.accounts.models import UserStatus
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


class ShareCampaignCopyInline(admin.StackedInline):  # type: ignore[type-arg]
    model = ShareCampaignCopy
    extra = 1
    fields = ("locale", "title", "message", "cta_label")
    verbose_name = "Перевод текста"
    verbose_name_plural = "Тексты для языков RU / EN / AR / TR"


@admin.register(ShareCampaign)
class ShareCampaignAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
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
            "Основное",
            {
                "fields": (
                    "id",
                    "internal_name",
                    "key",
                    "is_active",
                    "starts_at",
                    "ends_at",
                    "priority",
                )
            },
        ),
        (
            "Ссылки",
            {
                "fields": (
                    "canonical_download_url",
                    "download_link",
                    "ios_url",
                    "android_url",
                    "short_link_base_url",
                )
            },
        ),
        (
            "Реферальная программа",
            {"fields": ("referral_enabled", "reward_points")},
        ),
        (
            "Версионирование",
            {"fields": ("config_version", "created_at", "updated_at")},
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
        "owner_id_safe",
        "available_now",
        "click_count",
        "short_link",
        "created_at",
    )
    list_filter = ("campaign", "is_enabled", "revoked_at")
    search_fields = ("=code", "=owner__id")
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
        ("Ссылка", {"fields": ("id", "campaign", "owner", "code", "short_link")}),
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
        ("Аудит", {"fields": ("created_at", "updated_at")}),
    )
    actions = ("enable_selected", "disable_selected", "revoke_selected")
    list_select_related = ("campaign", "owner")

    def get_queryset(self, request: HttpRequest) -> Any:
        return super().get_queryset(request).annotate(admin_click_count=Count("clicks"))

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_delete_permission(self, _request: HttpRequest, _obj: object | None = None) -> bool:
        return False

    @admin.display(description="ID владельца", ordering="owner__id")
    def owner_id_safe(self, obj: ReferralLink) -> str:
        return str(obj.owner_id)

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


class ReferralAttributionAdminForm(forms.ModelForm):  # type: ignore[type-arg]
    class Meta:
        model = ReferralAttribution
        fields = ("referral_link", "invitee", "idempotency_key")

    def clean(self) -> dict[str, Any]:
        cleaned = super().clean() or {}
        link = cleaned.get("referral_link")
        invitee = cleaned.get("invitee")
        if invitee is not None and invitee.status != UserStatus.ACTIVE:
            self.add_error("invitee", "Нужен подтверждённый активный аккаунт.")
        if link is not None and invitee is not None and link.owner_id == invitee.id:
            self.add_error("invitee", "Нельзя пригласить самого себя.")
        return cleaned


@admin.register(ReferralAttribution)
class ReferralAttributionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    form = ReferralAttributionAdminForm
    list_display = (
        "id",
        "campaign",
        "referral_link",
        "invitee_id_safe",
        "source",
        "qualification_status",
        "attributed_at",
    )
    list_filter = ("campaign", "source", "qualification__status")
    search_fields = ("=id", "=referral_link__code", "=invitee__id", "=idempotency_key")
    ordering = ("-attributed_at",)
    date_hierarchy = "attributed_at"
    list_select_related = (
        "campaign",
        "referral_link",
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
            return ("id", "campaign", "source", "created_by", "created_at", "updated_at")
        return tuple(field.name for field in ReferralAttribution._meta.fields)

    def has_delete_permission(self, _request: HttpRequest, _obj: object | None = None) -> bool:
        return False

    def save_model(
        self,
        request: HttpRequest,
        obj: ReferralAttribution,
        _form: ReferralAttributionAdminForm,
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

    @admin.display(description="ID приглашённого", ordering="invitee__id")
    def invitee_id_safe(self, obj: ReferralAttribution) -> str:
        return str(obj.invitee_id)

    @admin.display(description="Квалификация", ordering="qualification__status")
    def qualification_status(self, obj: ReferralAttribution) -> str:
        return str(obj.qualification.get_status_display())


@admin.register(ReferralQualification)
class ReferralQualificationAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("id", "referral_code", "status", "decided_at", "decided_by", "created_at")
    list_filter = ("status", "attribution__campaign")
    search_fields = ("=id", "=attribution__referral_link__code", "=attribution__invitee__id")
    ordering = ("-created_at",)
    readonly_fields = tuple(field.name for field in ReferralQualification._meta.fields)
    actions = ("qualify_selected", "reject_selected", "reverse_selected")
    list_select_related = ("attribution__referral_link", "decided_by")

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_delete_permission(self, _request: HttpRequest, _obj: object | None = None) -> bool:
        return False

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
        "id",
        "campaign",
        "beneficiary_id_safe",
        "points",
        "status",
        "approved_at",
        "reversed_at",
        "created_at",
    )
    list_filter = ("campaign", "status")
    search_fields = ("=id", "=beneficiary__id", "=qualification__attribution__referral_link__code")
    ordering = ("-created_at",)
    readonly_fields = tuple(field.name for field in ReferralReward._meta.fields)
    actions = ("approve_selected", "reverse_selected")
    list_select_related = ("campaign", "beneficiary", "qualification")

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_delete_permission(self, _request: HttpRequest, _obj: object | None = None) -> bool:
        return False

    @admin.display(description="ID получателя", ordering="beneficiary__id")
    def beneficiary_id_safe(self, obj: ReferralReward) -> str:
        return str(obj.beneficiary_id)

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
