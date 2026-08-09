from __future__ import annotations

from datetime import timedelta
from unittest.mock import patch

import pytest
from django.test import override_settings
from django.utils import timezone

from quran_backend.modules.accounts.models import Device, RefreshSession, RefreshToken, User
from quran_backend.modules.accounts.retention import prune_auth_sessions
from quran_backend.modules.accounts.tasks import prune_auth_sessions_task

pytestmark = pytest.mark.django_db


def _session(*, expires_delta: timedelta, revoked_delta: timedelta | None = None) -> RefreshSession:
    now = timezone.now()
    user = User.objects.create_user(preferred_locale="en")
    device = Device.objects.create(
        user=user,
        platform="android",
        installation_id_hash=f"{user.id.hex:0<64}"[:64],
        installation_credential_hash="a" * 64,
        locale="en",
    )
    session = RefreshSession.objects.create(
        user=user,
        device=device,
        expires_at=now + expires_delta,
        revoked_at=now + revoked_delta if revoked_delta is not None else None,
    )
    RefreshToken.objects.create(
        session=session,
        secret_hash="b" * 64,
        expires_at=session.expires_at,
    )
    return session


@override_settings(QURAN_AUTH_SESSION_RETENTION_DAYS=90)
def test_auth_retention_deletes_only_long_dead_families() -> None:
    now = timezone.now()
    expired = _session(expires_delta=timedelta(days=-100))
    revoked = _session(
        expires_delta=timedelta(days=10),
        revoked_delta=timedelta(days=-100),
    )
    recent_revocation = _session(
        expires_delta=timedelta(days=10),
        revoked_delta=timedelta(days=-10),
    )
    active = _session(expires_delta=timedelta(days=10))

    result = prune_auth_sessions(now=now)

    assert result == {
        "dry_run": False,
        "sessions": 2,
        "tokens": 2,
        "has_more": False,
        "retention_days": 90,
    }
    assert not RefreshSession.objects.filter(id__in=[expired.id, revoked.id]).exists()
    assert RefreshSession.objects.filter(id__in=[recent_revocation.id, active.id]).count() == 2
    assert RefreshToken.objects.count() == 2


@override_settings(
    QURAN_AUTH_SESSION_RETENTION_DAYS=30,
    QURAN_AUTH_PRUNE_BATCH_SIZE=1,
    QURAN_AUTH_PRUNE_TOKEN_BATCH_SIZE=1,
)
def test_auth_retention_is_bounded_and_supports_dry_run() -> None:
    now = timezone.now()
    _session(expires_delta=timedelta(days=-60))
    _session(expires_delta=timedelta(days=-61))

    preview = prune_auth_sessions(now=now, dry_run=True)
    first = prune_auth_sessions(now=now)
    second = prune_auth_sessions(now=now)

    assert preview["sessions"] == 0
    assert preview["tokens"] == 1
    assert preview["has_more"] is True
    assert RefreshSession.objects.count() == 0
    assert first["sessions"] == 1
    assert first["has_more"] is True
    assert second["sessions"] == 1
    assert second["has_more"] is False


@override_settings(QURAN_RETENTION_TASK_MAX_BATCHES=3)
def test_auth_retention_task_drains_multiple_bounded_batches() -> None:
    results = [
        {
            "dry_run": False,
            "sessions": 1,
            "tokens": 3,
            "has_more": True,
            "retention_days": 90,
        },
        {
            "dry_run": False,
            "sessions": 2,
            "tokens": 4,
            "has_more": False,
            "retention_days": 90,
        },
    ]

    with patch(
        "quran_backend.modules.accounts.tasks.prune_auth_sessions",
        side_effect=results,
    ) as prune:
        result = prune_auth_sessions_task()

    assert prune.call_count == 2
    assert result == {
        "dry_run": False,
        "sessions": 3,
        "tokens": 7,
        "batches": 2,
        "has_more": False,
        "retention_days": 90,
    }


@override_settings(QURAN_RETENTION_TASK_MAX_BATCHES=5)
def test_auth_retention_task_stops_when_batch_cannot_make_progress() -> None:
    stalled = {
        "dry_run": False,
        "sessions": 0,
        "tokens": 0,
        "has_more": True,
        "retention_days": 90,
    }

    with patch(
        "quran_backend.modules.accounts.tasks.prune_auth_sessions",
        return_value=stalled,
    ) as prune:
        result = prune_auth_sessions_task()

    assert prune.call_count == 1
    assert result["batches"] == 1
    assert result["has_more"] is True
