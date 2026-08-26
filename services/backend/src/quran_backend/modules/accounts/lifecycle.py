from __future__ import annotations

from datetime import datetime, timedelta
from typing import TypedDict
from uuid import UUID

from django.conf import settings
from django.core.exceptions import ImproperlyConfigured
from django.db import transaction
from django.db.models import Count, Max, Q
from django.utils import timezone

from quran_backend.modules.accounts.exceptions import (
    AccountLifecycleUnavailable,
    AccountReauthenticationRequired,
    CurrentDeviceRevokeConflict,
    DeviceNotFound,
)
from quran_backend.modules.accounts.models import (
    AuthIdentity,
    Consent,
    Device,
    EmailAuthChallenge,
    RefreshSession,
    RefreshToken,
    User,
    UserStatus,
)
from quran_backend.modules.accounts.services import AccessAuthContext

DEFAULT_DELETION_GRACE_DAYS = 7
DEFAULT_REAUTH_MAX_AGE_SECONDS = 10 * 60
DEFAULT_DELETION_BATCH_SIZE = 100


class AccountDeletionFinalizeResult(TypedDict):
    finalized: int
    has_more: bool
    batch_size: int


def list_user_devices(*, user: User, context: AccessAuthContext) -> list[dict[str, object]]:
    now = timezone.now()
    devices = (
        Device.objects.filter(user=user, revoked_at__isnull=True)
        .annotate(
            active_session_count=Count(
                "refresh_sessions",
                filter=Q(
                    refresh_sessions__revoked_at__isnull=True,
                    refresh_sessions__expires_at__gt=now,
                ),
            ),
            last_session_used_at=Max("refresh_sessions__last_used_at"),
        )
        .order_by("-last_seen_at", "-created_at", "id")
    )
    return [
        {
            "id": device.id,
            "platform": device.platform,
            "locale": device.locale,
            "app_version": device.app_version,
            "created_at": device.created_at,
            "last_seen_at": device.last_seen_at,
            "last_session_used_at": device.last_session_used_at,
            "active_session_count": device.active_session_count,
            "is_current": device.id == context.device.id,
        }
        for device in devices
    ]


def revoke_user_device(*, user: User, context: AccessAuthContext, device_id: UUID) -> None:
    from quran_backend.modules.reminders.models import (  # noqa: PLC0415
        WebPushSubscription,
    )

    if device_id == context.device.id:
        raise CurrentDeviceRevokeConflict
    now = timezone.now()
    with transaction.atomic():
        device = (
            Device.objects.select_for_update()
            .filter(id=device_id, user=user, revoked_at__isnull=True)
            .first()
        )
        if device is None:
            raise DeviceNotFound
        session_ids = list(
            RefreshSession.objects.select_for_update()
            .filter(device=device, user=user, revoked_at__isnull=True)
            .order_by("id")
            .values_list("id", flat=True)
        )
        if session_ids:
            RefreshSession.objects.filter(id__in=session_ids).update(revoked_at=now)
            RefreshToken.objects.filter(
                session_id__in=session_ids,
                revoked_at__isnull=True,
            ).update(revoked_at=now)
        device.revoked_at = now
        device.save(update_fields=["revoked_at", "updated_at"])
        WebPushSubscription.objects.filter(device=device).delete()


def request_account_deletion(
    *,
    user: User,
    context: AccessAuthContext,
    reauth_challenge_id: UUID,
) -> User:
    from quran_backend.modules.reminders.models import (  # noqa: PLC0415
        WebPushSubscription,
    )

    now = timezone.now()
    with transaction.atomic():
        locked_user = User.objects.select_for_update().get(id=user.id)
        if (
            locked_user.status != UserStatus.ACTIVE
            or not locked_user.is_active
            or locked_user.is_staff
            or not locked_user.email
        ):
            raise AccountLifecycleUnavailable
        _validate_recent_reauthentication(
            user=locked_user,
            context=context,
            challenge_id=reauth_challenge_id,
            now=now,
        )
        locked_user.status = UserStatus.PENDING_DELETION
        locked_user.deletion_requested_at = now
        locked_user.deletion_scheduled_for = now + timedelta(days=deletion_grace_days())
        locked_user.save(
            update_fields=[
                "status",
                "deletion_requested_at",
                "deletion_scheduled_for",
                "updated_at",
            ]
        )
        WebPushSubscription.objects.filter(device__user=locked_user).delete()
        return locked_user


def cancel_account_deletion(
    *,
    user: User,
    context: AccessAuthContext,
    reauth_challenge_id: UUID,
) -> User:
    now = timezone.now()
    with transaction.atomic():
        locked_user = User.objects.select_for_update().get(id=user.id)
        if (
            locked_user.status != UserStatus.PENDING_DELETION
            or not locked_user.is_active
            or locked_user.deletion_requested_at is None
            or locked_user.deletion_scheduled_for is None
            or locked_user.deletion_scheduled_for <= now
        ):
            raise AccountLifecycleUnavailable
        _validate_recent_reauthentication(
            user=locked_user,
            context=context,
            challenge_id=reauth_challenge_id,
            now=now,
            consumed_after=locked_user.deletion_requested_at,
        )
        locked_user.status = UserStatus.ACTIVE
        locked_user.deletion_requested_at = None
        locked_user.deletion_scheduled_for = None
        locked_user.save(
            update_fields=[
                "status",
                "deletion_requested_at",
                "deletion_scheduled_for",
                "updated_at",
            ]
        )
        return locked_user


def finalize_due_account_deletions(
    *,
    now: datetime | None = None,
) -> AccountDeletionFinalizeResult:
    effective_now = now or timezone.now()
    batch_size = _positive_setting(
        "QURAN_ACCOUNT_DELETION_BATCH_SIZE",
        DEFAULT_DELETION_BATCH_SIZE,
    )
    due_ids = list(
        User.objects.filter(
            status=UserStatus.PENDING_DELETION,
            deletion_scheduled_for__lte=effective_now,
        )
        .order_by("deletion_scheduled_for", "id")
        .values_list("id", flat=True)[:batch_size]
    )
    finalized = 0
    for user_id in due_ids:
        with transaction.atomic():
            user = User.objects.select_for_update().filter(id=user_id).first()
            if (
                user is None
                or user.status != UserStatus.PENDING_DELETION
                or user.deletion_scheduled_for is None
                or user.deletion_scheduled_for > effective_now
            ):
                continue
            _finalize_account(user=user, deleted_at=effective_now)
            finalized += 1
    has_more = User.objects.filter(
        status=UserStatus.PENDING_DELETION,
        deletion_scheduled_for__lte=effective_now,
    ).exists()
    return {"finalized": finalized, "has_more": has_more, "batch_size": batch_size}


def deletion_grace_days() -> int:
    return _positive_setting("QURAN_ACCOUNT_DELETION_GRACE_DAYS", DEFAULT_DELETION_GRACE_DAYS)


def _validate_recent_reauthentication(
    *,
    user: User,
    context: AccessAuthContext,
    challenge_id: UUID,
    now: datetime,
    consumed_after: datetime | None = None,
) -> None:
    cutoff = now - timedelta(
        seconds=_positive_setting(
            "QURAN_ACCOUNT_REAUTH_MAX_AGE_SECONDS",
            DEFAULT_REAUTH_MAX_AGE_SECONDS,
        )
    )
    challenge = (
        EmailAuthChallenge.objects.select_for_update()
        .filter(
            id=challenge_id,
            requester=user,
            result_user=user,
            device=context.device,
            email=user.email,
            consumed_at__gte=cutoff,
            invalidated_at__isnull=True,
        )
        .first()
    )
    if (
        challenge is None
        or challenge.consumed_at is None
        or (consumed_after is not None and challenge.consumed_at <= consumed_after)
    ):
        raise AccountReauthenticationRequired


def _finalize_account(*, user: User, deleted_at: datetime) -> None:
    from quran_backend.modules.feedback.models import (  # noqa: PLC0415
        FeedbackAudit,
        FeedbackMessage,
        FeedbackTicket,
    )
    from quran_backend.modules.prayer_times.models import PrayerProfile  # noqa: PLC0415
    from quran_backend.modules.reading.models import (  # noqa: PLC0415
        Bookmark,
        ReadingPosition,
        RetiredBookmarkId,
        SyncChange,
        SyncOperation,
        UserSyncCursor,
    )
    from quran_backend.modules.reminders.models import (  # noqa: PLC0415
        ReminderRule,
        RetiredReminderId,
    )

    FeedbackTicket.objects.filter(reporter=user).update(contact_email=None)
    FeedbackMessage.objects.filter(author=user).update(author=None)
    FeedbackAudit.objects.filter(actor=user).update(actor=None)

    ReminderRule.objects.filter(user=user).delete()
    RetiredReminderId.objects.filter(user=user).delete()
    PrayerProfile.objects.filter(user=user).delete()
    ReadingPosition.objects.filter(user=user).delete()
    Bookmark.objects.filter(user=user).delete()
    RetiredBookmarkId.objects.filter(user=user).delete()
    SyncChange.objects.filter(user=user).delete()
    SyncOperation.objects.filter(user=user).delete()
    UserSyncCursor.objects.filter(user=user).delete()
    Consent.objects.filter(user=user).delete()

    EmailAuthChallenge.objects.filter(Q(requester=user) | Q(result_user=user)).delete()
    Device.objects.filter(user=user).delete()
    for identity in AuthIdentity.objects.select_for_update().filter(user=user):
        identity.provider_subject = f"deleted:{identity.id}"
        identity.email_at_provider = None
        identity.email_verified = False
        identity.save(
            update_fields=[
                "provider_subject",
                "email_at_provider",
                "email_verified",
                "updated_at",
            ]
        )

    user.groups.clear()
    user.user_permissions.clear()
    user.email = None
    user.status = UserStatus.DELETED
    user.is_active = False
    user.is_staff = False
    user.is_superuser = False
    user.preferred_locale = "en"
    user.timezone = "UTC"
    user.deleted_at = deleted_at
    user.set_unusable_password()
    user.save(
        update_fields=[
            "email",
            "status",
            "is_active",
            "is_staff",
            "is_superuser",
            "preferred_locale",
            "timezone",
            "deleted_at",
            "password",
            "updated_at",
        ]
    )


def _positive_setting(name: str, default: int) -> int:
    try:
        value = int(getattr(settings, name, default))
    except (TypeError, ValueError) as exc:
        raise ImproperlyConfigured(f"{name} must be a positive integer.") from exc
    if value <= 0:
        raise ImproperlyConfigured(f"{name} must be a positive integer.")
    return value
