from __future__ import annotations

import logging
from typing import Any

from celery import shared_task
from django.conf import settings

from quran_backend.modules.audio.quran_foundation import QuranFoundationError
from quran_backend.modules.quran.quran_foundation_sync import sync_quran_foundation_mushafs

logger = logging.getLogger(__name__)


@shared_task(
    name="quran.sync_quran_foundation_mushafs",
    autoretry_for=(QuranFoundationError,),
    retry_backoff=True,
    retry_jitter=True,
    max_retries=3,
)  # type: ignore[untyped-decorator]
def sync_quran_foundation_mushafs_task() -> dict[str, Any]:
    if not settings.QURAN_QF_MUSHAF_SYNC_ENABLED:
        logger.info(
            "Quran.Foundation Mushaf sync is disabled",
            extra={"event": "quran_foundation_mushaf_sync_disabled"},
        )
        return {"enabled": False}
    result = sync_quran_foundation_mushafs()
    logger.info(
        "Quran.Foundation Mushaf sync completed",
        extra={
            "event": "quran_foundation_mushaf_sync_completed",
            "resources": result.resources,
            "pages": result.pages,
            "words": result.words,
            "removed": result.removed,
            "changed": result.changed,
            "sync_sequence": result.sync_sequence,
        },
    )
    return {
        "enabled": True,
        "resources": result.resources,
        "pages": result.pages,
        "words": result.words,
        "removed": result.removed,
        "changed": result.changed,
        "sync_sequence": result.sync_sequence,
    }
