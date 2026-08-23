from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Literal

from django.conf import settings
from django.utils import timezone

from quran_backend.modules.audio.models import QuranFoundationSyncState
from quran_backend.modules.audio.quran_foundation_sync import latest_complete_qf_recitations

QuranFoundationOperationalStatus = Literal["ok", "degraded", "disabled"]


@dataclass(frozen=True, slots=True)
class QuranFoundationOperationalSummary:
    status: QuranFoundationOperationalStatus
    enabled: bool
    environment: str
    tracked_recitations: int
    healthy: int
    stale: int
    failing: int
    never_synced: int
    stale_after_seconds: int
    oldest_success_at: datetime | None
    max_consecutive_failures: int

    def as_dict(self) -> dict[str, Any]:
        return {
            "enabled": self.enabled,
            "environment": self.environment,
            "tracked_recitations": self.tracked_recitations,
            "states": {
                "healthy": self.healthy,
                "stale": self.stale,
                "failing": self.failing,
                "never_synced": self.never_synced,
            },
            "stale_after_seconds": self.stale_after_seconds,
            "oldest_success_at": (
                self.oldest_success_at.isoformat() if self.oldest_success_at else None
            ),
            "max_consecutive_failures": self.max_consecutive_failures,
        }


def quran_foundation_operational_summary(
    *,
    now: datetime | None = None,
) -> QuranFoundationOperationalSummary:
    current_time = now or timezone.now()
    enabled = bool(settings.QURAN_QF_AUDIO_SYNC_ENABLED)
    environment = str(settings.QURAN_QF_ENV)
    stale_after_seconds = int(settings.QURAN_QF_AUDIO_STALE_AFTER_HOURS) * 3_600
    stale_cutoff = current_time - timedelta(seconds=stale_after_seconds)

    source_ids = {
        source_id for source_id, _recitation in latest_complete_qf_recitations(environment)
    }
    states = {
        state.source_reciter_id: state
        for state in QuranFoundationSyncState.objects.filter(
            environment=environment,
            source_reciter_id__in=source_ids,
        )
    }

    healthy = 0
    stale = 0
    failing = 0
    never_synced = 0
    successful_at: list[datetime] = []
    max_consecutive_failures = 0
    for source_id in source_ids:
        state = states.get(source_id)
        if state is None or state.last_success_at is None:
            if state is not None and state.consecutive_failures:
                failing += 1
                max_consecutive_failures = max(
                    max_consecutive_failures,
                    state.consecutive_failures,
                )
            else:
                never_synced += 1
            continue

        successful_at.append(state.last_success_at)
        max_consecutive_failures = max(
            max_consecutive_failures,
            state.consecutive_failures,
        )
        if state.consecutive_failures:
            failing += 1
        elif state.last_success_at <= stale_cutoff:
            stale += 1
        else:
            healthy += 1

    tracked_recitations = len(source_ids)
    status: QuranFoundationOperationalStatus
    if not enabled:
        status = "disabled"
    elif tracked_recitations == 0 or healthy != tracked_recitations:
        status = "degraded"
    else:
        status = "ok"

    return QuranFoundationOperationalSummary(
        status=status,
        enabled=enabled,
        environment=environment,
        tracked_recitations=tracked_recitations,
        healthy=healthy,
        stale=stale,
        failing=failing,
        never_synced=never_synced,
        stale_after_seconds=stale_after_seconds,
        oldest_success_at=min(successful_at) if successful_at else None,
        max_consecutive_failures=max_consecutive_failures,
    )
