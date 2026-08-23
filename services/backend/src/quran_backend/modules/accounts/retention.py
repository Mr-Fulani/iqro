from __future__ import annotations

from datetime import datetime, timedelta
from typing import TypedDict

from django.conf import settings
from django.core.exceptions import ImproperlyConfigured
from django.db.models import Q, QuerySet
from django.utils import timezone

from quran_backend.modules.accounts.models import EmailAuthChallenge, RefreshSession, RefreshToken


class AuthPruneResult(TypedDict):
    dry_run: bool
    sessions: int
    tokens: int
    has_more: bool
    retention_days: int


class EmailChallengePruneResult(TypedDict):
    dry_run: bool
    challenges: int
    has_more: bool
    retention_hours: int


def prune_auth_sessions(
    *,
    now: datetime | None = None,
    dry_run: bool = False,
) -> AuthPruneResult:
    """Delete one bounded batch of long-expired or long-revoked token families."""

    effective_now = now or timezone.now()
    retention_days = _positive_setting("QURAN_AUTH_SESSION_RETENTION_DAYS", 90)
    session_batch_size = _positive_setting("QURAN_AUTH_PRUNE_BATCH_SIZE", 5_000)
    token_batch_size = _positive_setting("QURAN_AUTH_PRUNE_TOKEN_BATCH_SIZE", 50_000)
    cutoff = effective_now - timedelta(days=retention_days)
    stale = _stale_sessions(cutoff)
    token_ids = list(
        RefreshToken.objects.filter(session__in=stale)
        .order_by("session_id", "created_at", "id")
        .values_list("id", flat=True)[:token_batch_size]
    )
    if token_ids and not dry_run:
        RefreshToken.objects.filter(id__in=token_ids).delete()

    session_ids = list(
        _stale_sessions(cutoff)
        .filter(tokens__isnull=True)
        .order_by("expires_at", "id")
        .values_list("id", flat=True)[:session_batch_size]
    )
    if session_ids and not dry_run:
        RefreshSession.objects.filter(id__in=session_ids).delete()

    return {
        "dry_run": dry_run,
        "sessions": len(session_ids),
        "tokens": len(token_ids),
        "has_more": _stale_sessions(cutoff).exists(),
        "retention_days": retention_days,
    }


def prune_email_challenges(
    *,
    now: datetime | None = None,
    dry_run: bool = False,
) -> EmailChallengePruneResult:
    """Delete one bounded batch of expired passwordless-login challenges."""

    effective_now = now or timezone.now()
    retention_hours = _positive_setting("QURAN_EMAIL_CHALLENGE_RETENTION_HOURS", 24)
    batch_size = _positive_setting("QURAN_EMAIL_CHALLENGE_PRUNE_BATCH_SIZE", 5_000)
    cutoff = effective_now - timedelta(hours=retention_hours)
    stale = EmailAuthChallenge.objects.filter(
        Q(expires_at__lt=cutoff) | Q(invalidated_at__lt=cutoff) | Q(consumed_at__lt=cutoff)
    )
    challenge_ids = list(
        stale.order_by("expires_at", "id").values_list("id", flat=True)[:batch_size]
    )
    if challenge_ids and not dry_run:
        EmailAuthChallenge.objects.filter(id__in=challenge_ids).delete()
    return {
        "dry_run": dry_run,
        "challenges": len(challenge_ids),
        "has_more": stale.exclude(id__in=challenge_ids).exists(),
        "retention_hours": retention_hours,
    }


def _stale_sessions(cutoff: datetime) -> QuerySet[RefreshSession]:
    return RefreshSession.objects.filter(Q(expires_at__lt=cutoff) | Q(revoked_at__lt=cutoff))


def _positive_setting(name: str, default: int) -> int:
    try:
        value = int(getattr(settings, name, default))
    except (TypeError, ValueError) as exc:
        raise ImproperlyConfigured(f"{name} must be a positive integer.") from exc
    if value <= 0:
        raise ImproperlyConfigured(f"{name} must be a positive integer.")
    return value
