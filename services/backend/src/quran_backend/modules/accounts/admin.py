from __future__ import annotations

from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as DjangoUserAdmin

from quran_backend.modules.accounts.models import (
    AuthIdentity,
    Consent,
    Device,
    EmailAuthChallenge,
    GuestMergeAudit,
    RefreshSession,
    RefreshToken,
    User,
)


@admin.register(User)
class UserAdmin(DjangoUserAdmin):  # type: ignore[type-arg]
    ordering = ("-created_at",)
    list_display = ("id", "email", "status", "preferred_locale", "is_staff", "created_at")
    list_filter = ("status", "preferred_locale", "is_staff", "is_active")
    search_fields = ("=id", "email")
    readonly_fields = (
        "id",
        "created_at",
        "updated_at",
        "date_joined",
        "last_login",
        "deletion_requested_at",
        "deletion_scheduled_for",
        "deleted_at",
    )
    fieldsets = (
        (None, {"fields": ("id", "email", "password")}),
        ("Profile", {"fields": ("status", "preferred_locale", "timezone")}),
        (
            "Permissions",
            {"fields": ("is_active", "is_staff", "is_superuser", "groups", "user_permissions")},
        ),
        (
            "Dates",
            {
                "fields": (
                    "date_joined",
                    "last_login",
                    "deletion_requested_at",
                    "deletion_scheduled_for",
                    "deleted_at",
                    "created_at",
                    "updated_at",
                )
            },
        ),
    )
    add_fieldsets = (
        (
            None,
            {
                "classes": ("wide",),
                "fields": ("email", "password1", "password2", "is_staff", "is_superuser"),
            },
        ),
    )


@admin.register(AuthIdentity)
class AuthIdentityAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("id", "user", "provider", "email_verified", "linked_at")
    list_filter = ("provider", "email_verified")
    search_fields = ("=id", "=user__id", "provider_subject", "email_at_provider")
    readonly_fields = ("id", "created_at", "updated_at")


@admin.register(Device)
class DeviceAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("id", "user", "platform", "app_version", "last_seen_at", "revoked_at")
    list_filter = ("platform",)
    search_fields = ("=id", "=user__id", "installation_id_hash")
    readonly_fields = ("id", "installation_id_hash", "created_at", "updated_at")
    exclude = ("installation_credential_hash",)


class RefreshTokenInline(admin.TabularInline):  # type: ignore[type-arg]
    model = RefreshToken
    fields = ("id", "created_at", "expires_at", "used_at", "revoked_at", "replaced_by")
    readonly_fields = fields
    extra = 0
    can_delete = False
    show_change_link = False

    def has_add_permission(self, _request: object, _obj: object | None = None) -> bool:
        return False


@admin.register(RefreshSession)
class RefreshSessionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = (
        "id",
        "user",
        "device",
        "expires_at",
        "last_used_at",
        "revoked_at",
        "compromise_detected_at",
    )
    list_filter = ("revoked_at", "compromise_detected_at")
    search_fields = ("=id", "=user__id", "=device__id")
    readonly_fields = (
        "id",
        "user",
        "device",
        "expires_at",
        "last_used_at",
        "revoked_at",
        "compromise_detected_at",
        "created_at",
        "updated_at",
    )
    inlines = (RefreshTokenInline,)

    def has_add_permission(self, _request: object) -> bool:
        return False


@admin.register(RefreshToken)
class RefreshTokenAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("id", "session", "created_at", "expires_at", "used_at", "revoked_at")
    list_filter = ("used_at", "revoked_at")
    search_fields = ("=id", "=session__id", "=session__user__id", "=session__device__id")
    readonly_fields = (
        "id",
        "session",
        "expires_at",
        "used_at",
        "revoked_at",
        "replaced_by",
        "created_at",
        "updated_at",
    )
    exclude = ("secret_hash",)

    def has_add_permission(self, _request: object) -> bool:
        return False


@admin.register(Consent)
class ConsentAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("id", "user", "purpose", "policy_version", "granted_at", "withdrawn_at")
    list_filter = ("purpose", "policy_version")
    search_fields = ("=id", "=user__id")
    readonly_fields = ("id", "created_at", "updated_at")


@admin.register(EmailAuthChallenge)
class EmailAuthChallengeAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = (
        "id",
        "requester",
        "device",
        "email",
        "expires_at",
        "attempts_remaining",
        "consumed_at",
        "invalidated_at",
    )
    list_filter = ("consumed_at", "invalidated_at")
    search_fields = ("=id", "=requester__id", "=device__id", "email")
    readonly_fields = (
        "id",
        "requester",
        "device",
        "email",
        "expires_at",
        "attempts_remaining",
        "invalidated_at",
        "consumed_at",
        "verification_key",
        "result_user",
        "created_at",
        "updated_at",
    )
    exclude = ("code_hash",)

    def has_add_permission(self, _request: object) -> bool:
        return False

    def has_delete_permission(self, _request: object, _obj: object | None = None) -> bool:
        return False


@admin.register(GuestMergeAudit)
class GuestMergeAuditAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("id", "source_user", "target_user", "trigger_identity", "completed_at")
    search_fields = ("=id", "=source_user__id", "=target_user__id", "=idempotency_key")
    readonly_fields = (
        "id",
        "source_user",
        "target_user",
        "trigger_identity",
        "idempotency_key",
        "moved_counts",
        "completed_at",
        "created_at",
        "updated_at",
    )

    def has_add_permission(self, _request: object) -> bool:
        return False

    def has_delete_permission(self, _request: object, _obj: object | None = None) -> bool:
        return False
