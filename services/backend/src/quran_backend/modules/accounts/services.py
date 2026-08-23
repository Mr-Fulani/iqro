from __future__ import annotations

import hashlib
import hmac
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any
from uuid import UUID

from django.conf import settings
from django.core import signing
from django.core.exceptions import ImproperlyConfigured
from django.db import IntegrityError, transaction
from django.utils import timezone

from quran_backend.modules.accounts.exceptions import (
    AccessTokenInvalid,
    GuestBootstrapUnavailable,
    RefreshTokenInvalid,
    RefreshTokenReused,
)
from quran_backend.modules.accounts.models import (
    Device,
    RefreshSession,
    RefreshToken,
    User,
    UserStatus,
)

ACCESS_TOKEN_PREFIX = "qat1."  # noqa: S105 - public format marker, not a credential
REFRESH_TOKEN_PREFIX = "qrt1"  # noqa: S105 - public format marker, not a credential
ACCESS_TOKEN_SALT = "quran-platform.accounts.access.v1"  # noqa: S105 - signing namespace
DEFAULT_ACCESS_TOKEN_TTL_SECONDS = 15 * 60
DEFAULT_REFRESH_TOKEN_TTL_SECONDS = 30 * 24 * 60 * 60
ACCESS_USER_STATUSES = frozenset({UserStatus.GUEST, UserStatus.ACTIVE})
REFRESH_USER_STATUSES = frozenset(
    {UserStatus.GUEST, UserStatus.ACTIVE, UserStatus.PENDING_DELETION}
)


@dataclass(frozen=True, slots=True)
class AccessClaims:
    user_id: UUID
    device_id: UUID
    session_id: UUID


@dataclass(frozen=True, slots=True)
class AccessAuthContext:
    device: Device
    session: RefreshSession


@dataclass(frozen=True, slots=True)
class IssuedCredentials:
    access_token: str
    refresh_token: str
    access_expires_at: datetime
    refresh_expires_at: datetime


@dataclass(frozen=True, slots=True)
class GuestBootstrapResult:
    user: User
    device: Device
    credentials: IssuedCredentials


def access_token_ttl_seconds() -> int:
    return _positive_int_setting(
        "QURAN_ACCESS_TOKEN_TTL_SECONDS",
        DEFAULT_ACCESS_TOKEN_TTL_SECONDS,
    )


def refresh_token_ttl_seconds() -> int:
    return _positive_int_setting(
        "QURAN_REFRESH_TOKEN_TTL_SECONDS",
        DEFAULT_REFRESH_TOKEN_TTL_SECONDS,
    )


def hash_installation_id(installation_id: UUID) -> str:
    canonical_identifier = str(installation_id).encode("ascii")
    return hmac.new(
        _derived_key("QURAN_INSTALLATION_HASH_KEY", b"installation-id-v1"),
        canonical_identifier,
        hashlib.sha256,
    ).hexdigest()


def hash_installation_credential(credential: str) -> str:
    return hmac.new(
        _derived_key("QURAN_GUEST_CREDENTIAL_HASH_KEY", b"guest-credential-v1"),
        credential.encode("ascii"),
        hashlib.sha256,
    ).hexdigest()


def bootstrap_guest(
    *,
    installation_id: UUID,
    installation_credential: str,
    platform: str,
    locale: str,
    app_version: str,
) -> GuestBootstrapResult:
    installation_id_hash = hash_installation_id(installation_id)
    credential_hash = hash_installation_credential(installation_credential)
    now = timezone.now()

    with transaction.atomic():
        device = (
            Device.objects.select_for_update()
            .select_related("user")
            .filter(installation_id_hash=installation_id_hash)
            .first()
        )
        if device is None:
            device = _create_guest_device(
                installation_id_hash=installation_id_hash,
                installation_credential_hash=credential_hash,
                platform=platform,
                locale=locale,
                app_version=app_version,
                now=now,
            )

        user = device.user
        if (
            not device.installation_credential_hash
            or not secrets.compare_digest(
                device.installation_credential_hash,
                credential_hash,
            )
            or device.revoked_at is not None
            or device.platform != platform
            or not user.is_active
            or user.status != UserStatus.GUEST
        ):
            raise GuestBootstrapUnavailable

        device.locale = locale
        device.app_version = app_version
        device.last_seen_at = now
        device.bootstrap_generation += 1
        device.save(
            update_fields=[
                "locale",
                "app_version",
                "last_seen_at",
                "bootstrap_generation",
                "updated_at",
            ]
        )
        if user.preferred_locale != locale:
            user.preferred_locale = locale
            user.save(update_fields=["preferred_locale", "updated_at"])

        _revoke_device_sessions(device=device, revoked_at=now)
        session = RefreshSession.objects.create(
            user=user,
            device=device,
            expires_at=now + timedelta(seconds=refresh_token_ttl_seconds()),
        )
        credentials = _issue_credentials(session=session, now=now)

    return GuestBootstrapResult(user=user, device=device, credentials=credentials)


def replace_device_credentials(*, user: User, device: Device) -> IssuedCredentials:
    """Revoke every credential for a device and issue one fresh token family."""

    now = timezone.now()
    with transaction.atomic():
        locked_device = Device.objects.select_for_update().get(id=device.id, user=user)
        _revoke_device_sessions(device=locked_device, revoked_at=now)
        session = RefreshSession.objects.create(
            user=user,
            device=locked_device,
            expires_at=now + timedelta(seconds=refresh_token_ttl_seconds()),
        )
        return _issue_credentials(session=session, now=now)


def rotate_refresh_token(raw_token: str) -> IssuedCredentials:
    token_id, supplied_secret = _parse_refresh_token(raw_token)
    locator = (
        RefreshToken.objects.filter(id=token_id).values("session_id", "session__device_id").first()
    )
    if locator is None:
        raise RefreshTokenInvalid

    session_id = _coerce_uuid(locator["session_id"])
    device_id = _coerce_uuid(locator["session__device_id"])
    now = timezone.now()
    replay_detected = False
    credentials: IssuedCredentials | None = None

    with transaction.atomic():
        try:
            device = Device.objects.select_for_update().select_related("user").get(id=device_id)
            session = RefreshSession.objects.select_for_update().get(
                id=session_id,
                device=device,
            )
            token = RefreshToken.objects.select_for_update().get(
                id=token_id,
                session=session,
            )
        except (Device.DoesNotExist, RefreshSession.DoesNotExist, RefreshToken.DoesNotExist) as exc:
            raise RefreshTokenInvalid from exc

        if not secrets.compare_digest(
            token.secret_hash,
            _hash_refresh_secret(supplied_secret),
        ):
            raise RefreshTokenInvalid

        if token.used_at is not None:
            _mark_session_compromised(session=session, detected_at=now)
            replay_detected = True
        elif not _refresh_context_is_active(
            user=device.user,
            device=device,
            session=session,
            token=token,
            now=now,
        ):
            raise RefreshTokenInvalid
        else:
            replacement, replacement_raw = _create_refresh_token(session=session)
            token.used_at = now
            token.replaced_by = replacement
            token.save(update_fields=["used_at", "replaced_by", "updated_at"])
            session.last_used_at = now
            session.save(update_fields=["last_used_at", "updated_at"])
            device.last_seen_at = now
            device.save(update_fields=["last_seen_at", "updated_at"])
            credentials = _credentials_for(
                session=session,
                raw_refresh_token=replacement_raw,
                now=now,
            )

    if replay_detected:
        raise RefreshTokenReused
    if credentials is None:  # pragma: no cover - defensive invariant
        raise RefreshTokenInvalid
    return credentials


def refresh_token_rate_limit_identity(raw_token: str) -> UUID | None:
    """Resolve a verified refresh token to its stable family without mutating it."""

    try:
        token_id, supplied_secret = _parse_refresh_token(raw_token)
    except RefreshTokenInvalid:
        return None
    locator = RefreshToken.objects.filter(id=token_id).values("session_id", "secret_hash").first()
    if locator is None or not secrets.compare_digest(
        str(locator["secret_hash"]),
        _hash_refresh_secret(supplied_secret),
    ):
        return None
    return _coerce_uuid(locator["session_id"])


def authenticate_access_token(
    raw_token: str,
    *,
    allow_pending_deletion: bool = False,
) -> tuple[User, AccessAuthContext]:
    claims = decode_access_token(raw_token)
    now = timezone.now()
    try:
        session = RefreshSession.objects.select_related("user", "device").get(id=claims.session_id)
    except RefreshSession.DoesNotExist as exc:
        raise AccessTokenInvalid from exc

    user = session.user
    device = session.device
    if (
        user.id != claims.user_id
        or device.id != claims.device_id
        or session.device_id != device.id
        or session.user_id != user.id
        or not _session_context_is_active(
            user=user,
            device=device,
            session=session,
            now=now,
            allowed_statuses=(
                REFRESH_USER_STATUSES if allow_pending_deletion else ACCESS_USER_STATUSES
            ),
        )
    ):
        raise AccessTokenInvalid
    return user, AccessAuthContext(device=device, session=session)


def revoke_access_session(*, user: User, context: AccessAuthContext) -> None:
    now = timezone.now()
    with transaction.atomic():
        try:
            device = Device.objects.select_for_update().get(id=context.device.id, user=user)
            session = RefreshSession.objects.select_for_update().get(
                id=context.session.id,
                user=user,
                device=device,
            )
        except (Device.DoesNotExist, RefreshSession.DoesNotExist) as exc:
            raise AccessTokenInvalid from exc
        _revoke_session(session=session, revoked_at=now)


def revoke_all_user_sessions(*, user: User) -> None:
    now = timezone.now()
    with transaction.atomic():
        # Lock devices in a stable order before sessions. Refresh and bootstrap flows
        # also take a device lock first, avoiding inverted lock ordering.
        list(
            Device.objects.select_for_update()
            .filter(user=user)
            .order_by("id")
            .values_list("id", flat=True)
        )
        session_ids = list(
            RefreshSession.objects.select_for_update()
            .filter(user=user, revoked_at__isnull=True)
            .order_by("id")
            .values_list("id", flat=True)
        )
        if not session_ids:
            return
        RefreshSession.objects.filter(id__in=session_ids).update(revoked_at=now)
        RefreshToken.objects.filter(
            session_id__in=session_ids,
            revoked_at__isnull=True,
        ).update(revoked_at=now)


def decode_access_token(raw_token: str) -> AccessClaims:
    if not raw_token.startswith(ACCESS_TOKEN_PREFIX):
        raise AccessTokenInvalid
    signed_value = raw_token.removeprefix(ACCESS_TOKEN_PREFIX)
    try:
        payload = signing.loads(
            signed_value,
            salt=ACCESS_TOKEN_SALT,
            max_age=access_token_ttl_seconds(),
        )
    except (signing.BadSignature, signing.SignatureExpired) as exc:
        raise AccessTokenInvalid from exc

    if (
        not isinstance(payload, dict)
        or payload.get("typ") != "access"
        or payload.get("v") != 1
        or not isinstance(payload.get("jti"), str)
        or not payload["jti"]
    ):
        raise AccessTokenInvalid
    try:
        return AccessClaims(
            user_id=UUID(str(payload["uid"])),
            device_id=UUID(str(payload["did"])),
            session_id=UUID(str(payload["sid"])),
        )
    except (KeyError, TypeError, ValueError) as exc:
        raise AccessTokenInvalid from exc


def _create_guest_device(  # noqa: PLR0913
    *,
    installation_id_hash: str,
    installation_credential_hash: str,
    platform: str,
    locale: str,
    app_version: str,
    now: datetime,
) -> Device:
    user = User.objects.create_user(preferred_locale=locale)
    try:
        # The savepoint keeps the outer transaction usable if a concurrent bootstrap
        # wins the global installation digest constraint.
        with transaction.atomic():
            return Device.objects.create(
                user=user,
                platform=platform,
                installation_id_hash=installation_id_hash,
                installation_credential_hash=installation_credential_hash,
                app_version=app_version,
                locale=locale,
                last_seen_at=now,
            )
    except IntegrityError:
        user.delete()
        try:
            return (
                Device.objects.select_for_update()
                .select_related("user")
                .get(installation_id_hash=installation_id_hash)
            )
        except Device.DoesNotExist as exc:  # pragma: no cover - abnormal database failure
            raise GuestBootstrapUnavailable from exc


def _issue_credentials(*, session: RefreshSession, now: datetime) -> IssuedCredentials:
    _, raw_refresh_token = _create_refresh_token(session=session)
    return _credentials_for(session=session, raw_refresh_token=raw_refresh_token, now=now)


def _credentials_for(
    *,
    session: RefreshSession,
    raw_refresh_token: str,
    now: datetime,
) -> IssuedCredentials:
    access_expires_at = now + timedelta(seconds=access_token_ttl_seconds())
    payload = {
        "v": 1,
        "typ": "access",
        "jti": secrets.token_urlsafe(12),
        "uid": str(session.user_id),
        "did": str(session.device_id),
        "sid": str(session.id),
    }
    signed = signing.dumps(payload, salt=ACCESS_TOKEN_SALT, compress=False)
    return IssuedCredentials(
        access_token=f"{ACCESS_TOKEN_PREFIX}{signed}",
        refresh_token=raw_refresh_token,
        access_expires_at=access_expires_at,
        refresh_expires_at=session.expires_at,
    )


def _create_refresh_token(*, session: RefreshSession) -> tuple[RefreshToken, str]:
    secret = secrets.token_urlsafe(48)
    token = RefreshToken(
        session=session,
        secret_hash=_hash_refresh_secret(secret),
        expires_at=session.expires_at,
    )
    token.save(force_insert=True)
    raw_token = f"{REFRESH_TOKEN_PREFIX}.{token.id.hex}.{secret}"
    return token, raw_token


def _parse_refresh_token(raw_token: str) -> tuple[UUID, str]:
    if not isinstance(raw_token, str) or len(raw_token) > 256:
        raise RefreshTokenInvalid
    parts = raw_token.split(".")
    if len(parts) != 3 or parts[0] != REFRESH_TOKEN_PREFIX or not parts[2]:
        raise RefreshTokenInvalid
    try:
        token_id = UUID(hex=parts[1])
    except (ValueError, AttributeError) as exc:
        raise RefreshTokenInvalid from exc
    return token_id, parts[2]


def _hash_refresh_secret(secret: str) -> str:
    return hmac.new(
        _derived_key("QURAN_REFRESH_TOKEN_HASH_KEY", b"refresh-token-v1"),
        secret.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def _derived_key(setting_name: str, purpose: bytes) -> bytes:
    configured = getattr(settings, setting_name, None)
    raw_key = configured if configured is not None else settings.SECRET_KEY
    if not isinstance(raw_key, str) or not raw_key:
        msg = f"{setting_name} must be a non-empty string."
        raise ImproperlyConfigured(msg)
    return hmac.new(raw_key.encode("utf-8"), purpose, hashlib.sha256).digest()


def _positive_int_setting(name: str, default: int) -> int:
    value = getattr(settings, name, default)
    try:
        parsed = int(value)
    except (TypeError, ValueError) as exc:
        msg = f"{name} must be a positive integer."
        raise ImproperlyConfigured(msg) from exc
    if parsed <= 0:
        msg = f"{name} must be a positive integer."
        raise ImproperlyConfigured(msg)
    return parsed


def _refresh_context_is_active(
    *,
    user: User,
    device: Device,
    session: RefreshSession,
    token: RefreshToken,
    now: datetime,
) -> bool:
    return (
        _session_context_is_active(
            user=user,
            device=device,
            session=session,
            now=now,
            allowed_statuses=REFRESH_USER_STATUSES,
        )
        and token.revoked_at is None
        and token.expires_at > now
    )


def _session_context_is_active(
    *,
    user: User,
    device: Device,
    session: RefreshSession,
    now: datetime,
    allowed_statuses: frozenset[str],
) -> bool:
    return (
        user.is_active
        and user.status in allowed_statuses
        and device.revoked_at is None
        and device.user_id == user.id
        and session.user_id == user.id
        and session.device_id == device.id
        and session.revoked_at is None
        and session.expires_at > now
    )


def _revoke_device_sessions(*, device: Device, revoked_at: datetime) -> None:
    sessions = list(
        RefreshSession.objects.select_for_update()
        .filter(device=device, revoked_at__isnull=True)
        .values_list("id", flat=True)
    )
    if not sessions:
        return
    RefreshSession.objects.filter(id__in=sessions).update(revoked_at=revoked_at)
    RefreshToken.objects.filter(session_id__in=sessions, revoked_at__isnull=True).update(
        revoked_at=revoked_at
    )


def _revoke_session(*, session: RefreshSession, revoked_at: datetime) -> None:
    if session.revoked_at is None:
        session.revoked_at = revoked_at
        session.save(update_fields=["revoked_at", "updated_at"])
    RefreshToken.objects.filter(session=session, revoked_at__isnull=True).update(
        revoked_at=revoked_at
    )


def _mark_session_compromised(*, session: RefreshSession, detected_at: datetime) -> None:
    if session.compromise_detected_at is None:
        session.compromise_detected_at = detected_at
    if session.revoked_at is None:
        session.revoked_at = detected_at
    session.save(update_fields=["compromise_detected_at", "revoked_at", "updated_at"])
    RefreshToken.objects.filter(session=session, revoked_at__isnull=True).update(
        revoked_at=detected_at
    )


def _coerce_uuid(value: Any) -> UUID:
    if isinstance(value, UUID):
        return value
    try:
        return UUID(str(value))
    except (TypeError, ValueError) as exc:  # pragma: no cover - database invariant
        raise RefreshTokenInvalid from exc
