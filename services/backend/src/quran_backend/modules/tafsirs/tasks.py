from __future__ import annotations

import logging
from typing import Any

from celery import shared_task
from django.conf import settings

from quran_backend.modules.audio.quran_foundation import QuranFoundationError
from quran_backend.modules.tafsirs.quran_foundation_sync import sync_quran_foundation_tafsirs

logger = logging.getLogger(__name__)


@shared_task(
    name="tafsirs.sync_quran_foundation_tafsirs",
    autoretry_for=(QuranFoundationError,),
    retry_backoff=True,
    retry_jitter=True,
    max_retries=3,
)  # type: ignore[untyped-decorator]
def sync_quran_foundation_tafsirs_task() -> dict[str, Any]:
    if not settings.QURAN_QF_TAFSIR_SYNC_ENABLED:
        logger.info(
            "Quran.Foundation Tafsir sync is disabled",
            extra={"event": "quran_foundation_tafsir_sync_disabled"},
        )
        return {"enabled": False}
    result = sync_quran_foundation_tafsirs(resource_ids=settings.QURAN_QF_TAFSIR_RESOURCE_IDS)
    logger.info(
        "Quran.Foundation Tafsir sync completed",
        extra={
            "event": "quran_foundation_tafsir_sync_completed",
            "editions": result.editions,
            "versions_created": result.versions_created,
            "records_imported": result.records_imported,
            "removed": result.removed,
            "changed": result.changed,
            "sync_sequence": result.sync_sequence,
        },
    )
    return {
        "enabled": True,
        "editions": result.editions,
        "versions_created": result.versions_created,
        "records_imported": result.records_imported,
        "removed": result.removed,
        "changed": result.changed,
        "sync_sequence": result.sync_sequence,
    }
