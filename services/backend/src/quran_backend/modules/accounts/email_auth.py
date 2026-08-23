from __future__ import annotations

import hashlib
import hmac
import secrets
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta

from django.conf import settings
from django.core.mail import send_mail
from django.db import transaction
from django.utils import timezone
from django.views.decorators.debug import sensitive_variables

from quran_backend.modules.accounts.exceptions import (
    AccountLinkUnavailable,
    EmailChallengeDeliveryFailed,
    EmailChallengeExpired,
    EmailChallengeInvalid,
    IdentityAlreadyLinked,
)
from quran_backend.modules.accounts.merge import merge_guest_into_account
from quran_backend.modules.accounts.models import (
    AuthIdentity,
    Device,
    EmailAuthChallenge,
    IdentityProvider,
    User,
    UserStatus,
)
from quran_backend.modules.accounts.services import (
    IssuedCredentials,
    hash_installation_credential,
    replace_device_credentials,
)

DEFAULT_EMAIL_CODE_TTL_SECONDS = 10 * 60
DEFAULT_EMAIL_CODE_ATTEMPTS = 5


@dataclass(frozen=True, slots=True)
class EmailChallengeStartResult:
    challenge: EmailAuthChallenge
    expires_in: int


@dataclass(frozen=True, slots=True)
class EmailVerificationResult:
    user: User
    device: Device
    credentials: IssuedCredentials
    merged_guest: bool
    replayed: bool


@sensitive_variables("code")
def start_email_challenge(*, user: User, device: Device, email: str) -> EmailChallengeStartResult:
    normalized_email = email.strip().lower()
    now = timezone.now()
    expires_in = _positive_int_setting(
        "QURAN_EMAIL_CODE_TTL_SECONDS",
        DEFAULT_EMAIL_CODE_TTL_SECONDS,
    )
    attempts = _positive_int_setting(
        "QURAN_EMAIL_CODE_ATTEMPTS",
        DEFAULT_EMAIL_CODE_ATTEMPTS,
    )
    if attempts > 10:
        raise AccountLinkUnavailable
    challenge_id = uuid.uuid7()
    code = f"{secrets.randbelow(1_000_000):06d}"

    with transaction.atomic():
        locked_user = User.objects.select_for_update().get(id=user.id)
        locked_device = Device.objects.select_for_update().get(id=device.id)
        if (
            not locked_user.is_active
            or locked_user.status not in (UserStatus.GUEST, UserStatus.ACTIVE)
            or locked_device.user_id != locked_user.id
            or locked_device.revoked_at is not None
        ):
            raise AccountLinkUnavailable
        EmailAuthChallenge.objects.filter(
            requester=locked_user,
            device=locked_device,
            email=normalized_email,
            consumed_at__isnull=True,
            invalidated_at__isnull=True,
        ).update(invalidated_at=now)
        challenge = EmailAuthChallenge.objects.create(
            id=challenge_id,
            requester=locked_user,
            device=locked_device,
            email=normalized_email,
            code_hash=_hash_email_code(challenge_id, normalized_email, code),
            expires_at=now + timedelta(seconds=expires_in),
            attempts_remaining=attempts,
        )

    try:
        delivered = send_mail(
            subject="Код входа в Quran Platform",
            message=(
                f"Ваш одноразовый код: {code}\n\n"
                f"Он действует {max(1, expires_in // 60)} мин. "
                "Если вы не запрашивали вход, проигнорируйте письмо."
            ),
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[normalized_email],
        )
    except Exception as exc:
        EmailAuthChallenge.objects.filter(id=challenge.id).update(invalidated_at=timezone.now())
        raise EmailChallengeDeliveryFailed from exc
    if delivered != 1:
        EmailAuthChallenge.objects.filter(id=challenge.id).update(invalidated_at=timezone.now())
        raise EmailChallengeDeliveryFailed
    return EmailChallengeStartResult(challenge=challenge, expires_in=expires_in)


@sensitive_variables("code", "installation_credential")
def verify_email_challenge(
    *,
    challenge_id: uuid.UUID,
    code: str,
    installation_credential: str,
    idempotency_key: uuid.UUID,
) -> EmailVerificationResult:
    failure: type[Exception] | None = None
    result: EmailVerificationResult | None = None
    now = timezone.now()

    with transaction.atomic():
        challenge = (
            EmailAuthChallenge.objects.select_for_update()
            # PostgreSQL cannot lock the nullable side of the OUTER JOIN that
            # select_related("result_user") would add here. The replay path
            # locks and loads the result user explicitly below.
            .select_related("requester", "device")
            .filter(id=challenge_id)
            .first()
        )
        credential_matches = challenge is not None and secrets.compare_digest(
            challenge.device.installation_credential_hash,
            hash_installation_credential(installation_credential),
        )
        if challenge is None or not credential_matches:
            failure = EmailChallengeInvalid
        elif challenge.consumed_at is not None:
            result = _replay_consumed_challenge(
                challenge=challenge,
                idempotency_key=idempotency_key,
            )
        elif challenge.invalidated_at is not None or challenge.expires_at <= now:
            failure = EmailChallengeExpired
        elif challenge.attempts_remaining <= 0:
            failure = EmailChallengeInvalid
        elif not secrets.compare_digest(
            challenge.code_hash,
            _hash_email_code(challenge.id, challenge.email, code),
        ):
            challenge.attempts_remaining -= 1
            challenge.save(update_fields=["attempts_remaining", "updated_at"])
            failure = EmailChallengeInvalid
        else:
            result = _complete_email_challenge(
                challenge=challenge,
                idempotency_key=idempotency_key,
                now=now,
            )

    if failure is not None:
        raise failure
    if result is None:  # pragma: no cover - defensive invariant
        raise EmailChallengeInvalid
    return result


def _complete_email_challenge(
    *,
    challenge: EmailAuthChallenge,
    idempotency_key: uuid.UUID,
    now: datetime,
) -> EmailVerificationResult:
    requester = User.objects.select_for_update().get(id=challenge.requester_id)
    device = Device.objects.select_for_update().get(id=challenge.device_id)
    if requester.id != device.user_id or requester.status not in (
        UserStatus.GUEST,
        UserStatus.ACTIVE,
    ):
        raise AccountLinkUnavailable

    identity = (
        AuthIdentity.objects.select_for_update()
        .select_related("user")
        .filter(provider=IdentityProvider.EMAIL, provider_subject=challenge.email)
        .first()
    )
    if identity is None:
        legacy_owner = (
            User.objects.select_for_update().filter(email__iexact=challenge.email).first()
        )
        if legacy_owner is not None and (
            legacy_owner.status != UserStatus.ACTIVE or not legacy_owner.is_active
        ):
            raise AccountLinkUnavailable
        identity_user = legacy_owner or requester
        identity = AuthIdentity.objects.create(
            user=identity_user,
            provider=IdentityProvider.EMAIL,
            provider_subject=challenge.email,
            email_at_provider=challenge.email,
            email_verified=True,
            last_used_at=timezone.now(),
        )
    else:
        identity.email_at_provider = challenge.email
        identity.email_verified = True
        identity.last_used_at = timezone.now()
        identity.save(
            update_fields=["email_at_provider", "email_verified", "last_used_at", "updated_at"]
        )

    target = identity.user
    merged_guest = False
    if target.id == requester.id:
        if requester.status == UserStatus.GUEST:
            requester.email = challenge.email
            requester.status = UserStatus.ACTIVE
            requester.save(update_fields=["email", "status", "updated_at"])
            target = requester
    elif requester.status == UserStatus.GUEST:
        merge_guest_into_account(
            source_user=requester,
            target_user=target,
            trigger_identity=identity,
            idempotency_key=idempotency_key,
        )
        merged_guest = True
        device.refresh_from_db(fields=["user", "revoked_at"])
    else:
        raise IdentityAlreadyLinked

    if target.status != UserStatus.ACTIVE or not target.is_active or device.user_id != target.id:
        raise AccountLinkUnavailable
    credentials = replace_device_credentials(user=target, device=device)
    challenge.consumed_at = now
    challenge.verification_key = idempotency_key
    challenge.result_user = target
    challenge.save(
        update_fields=[
            "consumed_at",
            "verification_key",
            "result_user",
            "updated_at",
        ]
    )
    return EmailVerificationResult(
        user=target,
        device=device,
        credentials=credentials,
        merged_guest=merged_guest,
        replayed=False,
    )


def _replay_consumed_challenge(
    *,
    challenge: EmailAuthChallenge,
    idempotency_key: uuid.UUID,
) -> EmailVerificationResult:
    if challenge.verification_key != idempotency_key or challenge.result_user_id is None:
        raise EmailChallengeInvalid
    user = User.objects.select_for_update().get(id=challenge.result_user_id)
    device = Device.objects.select_for_update().get(id=challenge.device_id)
    if user.status != UserStatus.ACTIVE or not user.is_active or device.user_id != user.id:
        raise AccountLinkUnavailable
    credentials = replace_device_credentials(user=user, device=device)
    return EmailVerificationResult(
        user=user,
        device=device,
        credentials=credentials,
        merged_guest=challenge.requester_id != user.id,
        replayed=True,
    )


def _hash_email_code(challenge_id: uuid.UUID, email: str, code: str) -> str:
    configured_key = getattr(settings, "QURAN_EMAIL_CODE_HASH_KEY", settings.SECRET_KEY)
    material = f"email-code-v1\x00{challenge_id}\x00{email}\x00{code}".encode()
    return hmac.new(str(configured_key).encode(), material, hashlib.sha256).hexdigest()


def _positive_int_setting(name: str, default: int) -> int:
    try:
        value = int(getattr(settings, name, default))
    except (TypeError, ValueError) as exc:
        raise AccountLinkUnavailable from exc
    if value <= 0:
        raise AccountLinkUnavailable
    return value
