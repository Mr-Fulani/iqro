from __future__ import annotations

from typing import Any

from django.contrib import admin
from django.http import HttpRequest

from quran_backend.modules.reminders.models import ReminderRule, RetiredReminderId


@admin.register(ReminderRule)
class ReminderRuleAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    actions = None
    list_display = (
        "id",
        "user",
        "device",
        "reminder_type",
        "schedule",
        "timezone_mode",
        "signal",
        "is_enabled",
        "revision",
        "deleted_at",
        "updated_at",
    )
    list_filter = (
        "reminder_type",
        "prayer_event",
        "timezone_mode",
        "signal",
        "is_enabled",
        "deleted_at",
    )
    search_fields = ("=id", "=user__id", "=user__email")
    list_select_related = ("user", "device")
    readonly_fields = tuple(field.name for field in ReminderRule._meta.fields)

    @admin.display(description="Schedule")
    def schedule(self, obj: ReminderRule) -> str:
        if obj.deleted_at is not None:
            return "Deleted"
        if obj.prayer_event:
            offset = obj.prayer_offset_minutes or 0
            return f"{obj.prayer_event} {offset:+d} min"
        return obj.local_time.isoformat(timespec="minutes") if obj.local_time else "Invalid"

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_change_permission(
        self,
        _request: HttpRequest,
        _obj: ReminderRule | None = None,
    ) -> bool:
        return False

    def has_delete_permission(
        self,
        _request: HttpRequest,
        _obj: ReminderRule | None = None,
    ) -> bool:
        return False

    def get_queryset(self, request: HttpRequest) -> Any:
        return super().get_queryset(request).select_related("user", "device")


@admin.register(RetiredReminderId)
class RetiredReminderIdAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    actions = None
    list_display = ("reminder_id", "user", "last_revision", "retired_at")
    search_fields = ("=reminder_id", "=user__id")
    list_select_related = ("user",)
    readonly_fields = tuple(field.name for field in RetiredReminderId._meta.fields)

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_change_permission(
        self,
        _request: HttpRequest,
        _obj: RetiredReminderId | None = None,
    ) -> bool:
        return False

    def has_delete_permission(
        self,
        _request: HttpRequest,
        _obj: RetiredReminderId | None = None,
    ) -> bool:
        return False
