# Russian operator-facing strings intentionally contain Cyrillic glyphs.
# ruff: noqa: RUF001
from __future__ import annotations

from typing import Any

from django.contrib import admin
from django.http import HttpRequest
from django.utils.html import format_html

from quran_backend.modules.core.content_revalidation import enqueue_social_profiles_change
from quran_backend.modules.website.models import SocialProfile


@admin.register(SocialProfile)
class SocialProfileAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = (
        "platform_name",
        "profile_link",
        "display_name",
        "is_active",
        "include_in_seo",
        "sort_order",
        "updated_at",
    )
    list_display_links = ("platform_name", "profile_link")
    list_editable = ("is_active", "include_in_seo", "sort_order")
    list_filter = ("is_active", "include_in_seo", "platform")
    search_fields = ("profile_url", "display_name")
    ordering = ("sort_order", "platform")
    readonly_fields = ("id", "created_at", "updated_at")
    fieldsets = (
        (
            "Профиль",
            {"fields": ("platform", "profile_url", "display_name")},
        ),
        (
            "Публикация",
            {"fields": ("is_active", "include_in_seo", "sort_order")},
        ),
        (
            "Служебные данные",
            {"fields": ("id", "created_at", "updated_at"), "classes": ("collapse",)},
        ),
    )

    @admin.display(description="Платформа", ordering="platform")
    def platform_name(self, obj: SocialProfile) -> str:
        return str(obj.get_platform_display())

    @admin.display(description="Ссылка", ordering="profile_url")
    def profile_link(self, obj: SocialProfile) -> str:
        if not obj.profile_url:
            return "Не заполнена"
        return format_html(
            '<a href="{}" target="_blank" rel="noopener noreferrer">Открыть профиль ↗</a>',
            obj.profile_url,
        )

    def save_model(
        self,
        request: HttpRequest,
        obj: SocialProfile,
        form: Any,
        change: bool,
    ) -> None:
        super().save_model(request, obj, form, change)
        enqueue_social_profiles_change(action="updated" if change else "created")

    def delete_model(self, request: HttpRequest, obj: SocialProfile) -> None:
        super().delete_model(request, obj)
        enqueue_social_profiles_change(action="deleted")

    def delete_queryset(self, request: HttpRequest, queryset: Any) -> None:
        super().delete_queryset(request, queryset)
        enqueue_social_profiles_change(action="deleted")
