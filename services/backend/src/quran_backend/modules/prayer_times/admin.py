from __future__ import annotations

from typing import Any

from django.contrib import admin, messages
from django.core.exceptions import ValidationError
from django.db.models import QuerySet
from django.http import HttpRequest

from quran_backend.modules.prayer_times.models import (
    PrayerConfigRelease,
    PrayerConfigReleaseStatus,
    PrayerMethod,
    PrayerMethodConfig,
)


def _validation_message(error: ValidationError) -> str:
    if hasattr(error, "message_dict"):
        return "; ".join(
            f"{field}: {', '.join(values)}" for field, values in error.message_dict.items()
        )
    return "; ".join(error.messages)


@admin.register(PrayerMethod)
class PrayerMethodAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    actions = None
    list_display = (
        "code",
        "name_ar",
        "name_en",
        "name_ru",
        "authority_name",
        "is_active",
    )
    list_filter = ("is_active",)
    search_fields = ("=code", "name_ar", "name_en", "name_ru", "authority_name")
    readonly_fields = ("id", "created_at", "updated_at")

    def get_readonly_fields(
        self,
        request: HttpRequest,
        obj: PrayerMethod | None = None,
    ) -> tuple[str, ...]:
        fields = tuple(super().get_readonly_fields(request, obj))
        if (
            obj
            and obj.configurations.exclude(release__status=PrayerConfigReleaseStatus.DRAFT).exists()
        ):
            return tuple(dict.fromkeys((*fields, *obj.identity_fields)))
        return fields

    def has_delete_permission(
        self,
        request: HttpRequest,
        obj: PrayerMethod | None = None,
    ) -> bool:
        return bool(
            super().has_delete_permission(request, obj)
            and obj is not None
            and not obj.configurations.exists()
        )


@admin.register(PrayerConfigRelease)
class PrayerConfigReleaseAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    actions = ("publish_as_default", "publish_additional", "withdraw_release")
    list_display = (
        "version",
        "configuration_schema_version",
        "algorithm",
        "algorithm_version",
        "timezone_database_version",
        "status",
        "is_default",
        "published_at",
    )
    list_filter = ("status", "is_default", "algorithm")
    search_fields = ("=version", "algorithm", "algorithm_version", "manifest_checksum_sha256")
    readonly_fields = (
        "id",
        "status",
        "is_default",
        "manifest_checksum_sha256",
        "published_at",
        "withdrawn_at",
        "created_at",
        "updated_at",
    )

    def get_readonly_fields(
        self,
        request: HttpRequest,
        obj: PrayerConfigRelease | None = None,
    ) -> tuple[str, ...]:
        fields = tuple(super().get_readonly_fields(request, obj))
        if obj and obj.status != PrayerConfigReleaseStatus.DRAFT:
            immutable = tuple(field.name for field in obj._meta.fields)
            return tuple(dict.fromkeys((*fields, *immutable)))
        return fields

    def has_delete_permission(
        self,
        request: HttpRequest,
        obj: PrayerConfigRelease | None = None,
    ) -> bool:
        return bool(
            super().has_delete_permission(request, obj)
            and obj is not None
            and obj.status == PrayerConfigReleaseStatus.DRAFT
        )

    @admin.action(description="Publish selected draft as the default release")
    def publish_as_default(
        self,
        request: HttpRequest,
        queryset: QuerySet[PrayerConfigRelease],
    ) -> None:
        release = self._single_release(request, queryset)
        if release is None:
            return
        try:
            release.publish(make_default=True)
            release.save()
        except ValidationError as error:
            self.message_user(request, _validation_message(error), level=messages.ERROR)
            return
        self.message_user(request, f"Published {release} as the default.", level=messages.SUCCESS)

    @admin.action(description="Publish selected draft as an additional release")
    def publish_additional(
        self,
        request: HttpRequest,
        queryset: QuerySet[PrayerConfigRelease],
    ) -> None:
        release = self._single_release(request, queryset)
        if release is None:
            return
        try:
            release.publish(make_default=False)
            release.save()
        except ValidationError as error:
            self.message_user(request, _validation_message(error), level=messages.ERROR)
            return
        self.message_user(request, f"Published {release}.", level=messages.SUCCESS)

    @admin.action(description="Withdraw selected non-default release")
    def withdraw_release(
        self,
        request: HttpRequest,
        queryset: QuerySet[PrayerConfigRelease],
    ) -> None:
        release = self._single_release(request, queryset)
        if release is None:
            return
        try:
            release.withdraw()
            release.save()
        except ValidationError as error:
            self.message_user(request, _validation_message(error), level=messages.ERROR)
            return
        self.message_user(request, f"Withdrew {release}.", level=messages.SUCCESS)

    def _single_release(
        self,
        request: HttpRequest,
        queryset: QuerySet[PrayerConfigRelease],
    ) -> PrayerConfigRelease | None:
        if queryset.count() != 1:
            self.message_user(
                request,
                "Select exactly one release for this lifecycle operation.",
                level=messages.ERROR,
            )
            return None
        return queryset.first()


@admin.register(PrayerMethodConfig)
class PrayerMethodConfigAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    actions = None
    list_display = (
        "release",
        "method",
        "fajr_angle",
        "isha_mode",
        "default_high_latitude_rule",
        "default_polar_resolution",
    )
    list_filter = (
        "release__status",
        "release",
        "default_high_latitude_rule",
        "default_polar_resolution",
    )
    search_fields = (
        "release__version",
        "method__code",
        "method__name_ar",
        "method__name_en",
        "method__name_ru",
        "source_name",
        "source_checksum_sha256",
    )
    list_select_related = ("release", "method")
    readonly_fields = ("id", "checksum_sha256", "created_at", "updated_at")

    @admin.display(description="Isha rule")
    def isha_mode(self, obj: PrayerMethodConfig) -> str:
        if obj.isha_angle is not None:
            return f"{obj.isha_angle}°"
        interval = obj.isha_interval_minutes
        return f"{interval} min" if interval is not None else "Invalid"

    def get_readonly_fields(
        self,
        request: HttpRequest,
        obj: PrayerMethodConfig | None = None,
    ) -> tuple[str, ...]:
        fields = tuple(super().get_readonly_fields(request, obj))
        if obj and obj.release.status != PrayerConfigReleaseStatus.DRAFT:
            immutable = tuple(field.name for field in obj._meta.fields)
            return tuple(dict.fromkeys((*fields, *immutable)))
        return fields

    def has_delete_permission(
        self,
        request: HttpRequest,
        obj: PrayerMethodConfig | None = None,
    ) -> bool:
        return bool(
            super().has_delete_permission(request, obj)
            and obj is not None
            and obj.release.status == PrayerConfigReleaseStatus.DRAFT
        )

    def formfield_for_foreignkey(
        self,
        db_field: Any,
        request: HttpRequest,
        **kwargs: Any,
    ) -> Any:
        if db_field.name == "release":
            kwargs["queryset"] = PrayerConfigRelease.objects.filter(
                status=PrayerConfigReleaseStatus.DRAFT
            )
        return super().formfield_for_foreignkey(db_field, request, **kwargs)

    def get_queryset(self, request: HttpRequest) -> QuerySet[PrayerMethodConfig]:
        return super().get_queryset(request).select_related("release", "method")
