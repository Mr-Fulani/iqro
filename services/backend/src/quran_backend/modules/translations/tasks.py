from __future__ import annotations

import logging
from typing import Any

from celery import shared_task
from django.conf import settings

from quran_backend.modules.audio.quran_foundation import QuranFoundationError
from quran_backend.modules.translations.quran_foundation_sync import (
    sync_quran_foundation_translations,
)

logger = logging.getLogger(__name__)


@shared_task(
    name="translations.sync_quran_foundation_translations",
    autoretry_for=(QuranFoundationError,),
    retry_backoff=True,
    retry_jitter=True,
    max_retries=3,
)  # type: ignore[untyped-decorator]
def sync_quran_foundation_translations_task() -> dict[str, Any]:
    if not settings.QURAN_QF_TRANSLATION_SYNC_ENABLED:
        logger.info(
            "Quran.Foundation translation sync is disabled",
            extra={"event": "quran_foundation_translation_sync_disabled"},
        )
        return {"enabled": False}
    result = sync_quran_foundation_translations(
        resource_ids=settings.QURAN_QF_TRANSLATION_RESOURCE_IDS
    )
    logger.info(
        "Quran.Foundation translation sync completed",
        extra={
            "event": "quran_foundation_translation_sync_completed",
            "editions": result.editions,
            "versions_created": result.versions_created,
            "ayahs_imported": result.ayahs_imported,
            "removed": result.removed,
            "changed": result.changed,
            "sync_sequence": result.sync_sequence,
        },
    )
    return {
        "enabled": True,
        "editions": result.editions,
        "versions_created": result.versions_created,
        "ayahs_imported": result.ayahs_imported,
        "removed": result.removed,
        "changed": result.changed,
        "sync_sequence": result.sync_sequence,
    }
