from __future__ import annotations

from typing import ClassVar

from django.conf import settings
from django.contrib.auth.models import AbstractBaseUser, PermissionsMixin
from django.db import models
from django.db.models.functions import Lower
from django.utils import timezone as django_timezone

from quran_backend.modules.accounts.managers import UserManager
from quran_backend.modules.core.models import BaseModel


class UserStatus(models.TextChoices):
    GUEST = "guest", "Guest"
    ACTIVE = "active", "Active"
    PENDING_DELETION = "pending_deletion", "Pending deletion"
    SUSPENDED = "suspended", "Suspended"
    DELETED = "deleted", "Deleted"


class User(BaseModel, AbstractBaseUser, PermissionsMixin):
    email = models.EmailField(null=True, blank=True, unique=True)
    status = models.CharField(max_length=24, choices=UserStatus, default=UserStatus.GUEST)
    preferred_locale = models.CharField(max_length=8, default="en")
    timezone = models.CharField(max_length=64, default="UTC")
    is_staff = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)
    date_joined = models.DateTimeField(default=django_timezone.now)

    objects = UserManager()

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS: ClassVar[list[str]] = []

    class Meta:
        db_table = "accounts_user"
        constraints = [
            models.UniqueConstraint(
                Lower("email"),
                condition=models.Q(email__isnull=False),
                name="accounts_user_email_ci_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(preferred_locale__in=["ar", "en", "ru"]),
                name="accounts_user_supported_locale",
            ),
            models.CheckConstraint(
                condition=~models.Q(status=UserStatus.ACTIVE) | models.Q(email__isnull=False),
                name="accounts_active_user_has_email",
            ),
        ]
        indexes = [
            models.Index(fields=["status", "created_at"], name="accounts_user_status_idx"),
        ]

    def __str__(self) -> str:
        return self.email or f"guest:{self.id}"

    def clean(self) -> None:
        super().clean()
        if self.email:
            self.email = self.email.strip().lower()

    def get_full_name(self) -> str:
        return self.email or str(self.id)

    def get_short_name(self) -> str:
        return self.email.split("@", maxsplit=1)[0] if self.email else "Guest"


class IdentityProvider(models.TextChoices):
    EMAIL = "email", "Email"
    GOOGLE = "google", "Google"
    APPLE = "apple", "Apple"
    TELEGRAM = "telegram", "Telegram"


class AuthIdentity(BaseModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="identities",
    )
    provider = models.CharField(max_length=16, choices=IdentityProvider)
    provider_subject = models.CharField(max_length=255)
    email_at_provider = models.EmailField(null=True, blank=True)
    email_verified = models.BooleanField(default=False)
    linked_at = models.DateTimeField(default=django_timezone.now)
    last_used_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "accounts_auth_identity"
        constraints = [
            models.UniqueConstraint(
                fields=["provider", "provider_subject"],
                name="accounts_identity_provider_subject_unique",
            )
        ]
        indexes = [
            models.Index(fields=["user", "provider"], name="accounts_identity_user_idx"),
        ]


class DevicePlatform(models.TextChoices):
    IOS = "ios", "iOS"
    ANDROID = "android", "Android"
    WEB = "web", "Web"
    TELEGRAM = "telegram", "Telegram"


class Device(BaseModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="devices",
    )
    platform = models.CharField(max_length=16, choices=DevicePlatform)
    # This value is a keyed digest, never the client installation identifier itself.
    # An installation is globally bound to exactly one device/user pair.
    installation_id_hash = models.CharField(max_length=64, unique=True)
    # A separate high-entropy client credential proves possession on bootstrap retry.
    # Empty values are reserved for legacy/non-guest devices and can never bootstrap.
    installation_credential_hash = models.CharField(max_length=64, blank=True, default="")
    # Monotonic response generation lets clients reject reordered bootstrap responses.
    bootstrap_generation = models.PositiveBigIntegerField(default=0)
    app_version = models.CharField(max_length=32, blank=True)
    locale = models.CharField(max_length=8, default="en")
    last_seen_at = models.DateTimeField(default=django_timezone.now)
    revoked_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "accounts_device"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(locale__in=["ar", "en", "ru"]),
                name="accounts_device_supported_locale",
            )
        ]
        indexes = [
            models.Index(fields=["user", "last_seen_at"], name="accounts_device_seen_idx"),
        ]


class RefreshSession(BaseModel):
    """A revocable refresh-token family bound to one user installation."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="refresh_sessions",
    )
    device = models.ForeignKey(
        Device,
        on_delete=models.CASCADE,
        related_name="refresh_sessions",
    )
    expires_at = models.DateTimeField()
    last_used_at = models.DateTimeField(null=True, blank=True)
    revoked_at = models.DateTimeField(null=True, blank=True)
    compromise_detected_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "accounts_refresh_session"
        indexes = [
            models.Index(
                fields=["device", "revoked_at", "expires_at"],
                name="accounts_session_active_idx",
            ),
            models.Index(
                fields=["user", "created_at"],
                name="accounts_session_user_idx",
            ),
            models.Index(fields=["expires_at"], name="accounts_session_expiry_idx"),
            models.Index(fields=["revoked_at"], name="accounts_session_revoked_idx"),
        ]


class RefreshToken(BaseModel):
    """One-use refresh token; only a keyed digest of its secret is persisted."""

    session = models.ForeignKey(
        RefreshSession,
        on_delete=models.CASCADE,
        related_name="tokens",
    )
    secret_hash = models.CharField(max_length=64)
    expires_at = models.DateTimeField()
    used_at = models.DateTimeField(null=True, blank=True)
    revoked_at = models.DateTimeField(null=True, blank=True)
    replaced_by = models.OneToOneField(
        "self",
        on_delete=models.SET_NULL,
        related_name="replaces",
        null=True,
        blank=True,
    )

    class Meta:
        db_table = "accounts_refresh_token"
        indexes = [
            models.Index(
                fields=["session", "created_at"],
                name="accounts_token_session_idx",
            ),
            models.Index(
                fields=["expires_at", "revoked_at"],
                name="accounts_token_expiry_idx",
            ),
        ]


class ConsentPurpose(models.TextChoices):
    PRODUCT_ANALYTICS = "product_analytics", "Product analytics"
    NOTIFICATIONS = "notifications", "Notifications"
    DIAGNOSTICS = "diagnostics", "Diagnostics"
    LOCATION_STORAGE = "location_storage", "Location storage"


class Consent(BaseModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="consents",
    )
    purpose = models.CharField(max_length=32, choices=ConsentPurpose)
    policy_version = models.CharField(max_length=32)
    granted_at = models.DateTimeField(null=True, blank=True)
    withdrawn_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "accounts_consent"
        constraints = [
            models.UniqueConstraint(
                fields=["user", "purpose", "policy_version"],
                name="accounts_consent_user_purpose_policy_unique",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(granted_at__isnull=False, withdrawn_at__isnull=True)
                    | models.Q(granted_at__isnull=False, withdrawn_at__isnull=False)
                ),
                name="accounts_consent_has_grant",
            ),
        ]
