from __future__ import annotations

import logging
from typing import Any

from celery import shared_task
from django.conf import settings

from quran_backend.modules.audio.quran_foundation import QuranFoundationError
from quran_backend.modules.audio.quran_foundation_sync import refresh_quran_foundation_audio

logger = logging.getLogger(__name__)


@shared_task(
    name="audio.sync_quran_foundation",
    autoretry_for=(QuranFoundationError,),
    retry_backoff=True,
    retry_jitter=True,
    max_retries=3,
)  # type: ignore[untyped-decorator]
def sync_quran_foundation_task() -> dict[str, Any]:
    if not settings.QURAN_QF_AUDIO_SYNC_ENABLED:
        logger.info(
            "Quran.Foundation audio sync is disabled",
            extra={"event": "quran_foundation_sync_disabled"},
        )
        return {"enabled": False}
    try:
        result = refresh_quran_foundation_audio()
    except QuranFoundationError:
        logger.exception(
            "Quran.Foundation audio sync failed",
            extra={"event": "quran_foundation_sync_failed"},
        )
        raise
    logger.info(
        "Quran.Foundation audio sync completed",
        extra={
            "event": "quran_foundation_sync_completed",
            "checked": result.checked,
            "changed": result.changed,
            "withdrawn": result.withdrawn,
            "skipped_fresh": result.skipped_fresh,
        },
    )
    return {
        "enabled": True,
        "checked": result.checked,
        "changed": result.changed,
        "withdrawn": result.withdrawn,
        "skipped_fresh": result.skipped_fresh,
        "failures": result.failures,
    }
