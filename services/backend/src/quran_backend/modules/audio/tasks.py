from __future__ import annotations

import logging
from typing import Any

from celery import shared_task
from django.conf import settings

from quran_backend.modules.audio.quran_foundation import QuranFoundationError
from quran_backend.modules.audio.quran_foundation_ayah_sync import (
    sync_quran_foundation_ayah_recitations,
)
from quran_backend.modules.audio.quran_foundation_sync import refresh_quran_foundation_audio
from quran_backend.modules.quran.models import QuranEdition

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


@shared_task(
    name="audio.sync_quran_foundation_ayah_catalog",
    autoretry_for=(QuranFoundationError,),
    retry_backoff=True,
    retry_jitter=True,
    max_retries=3,
)  # type: ignore[untyped-decorator]
def sync_quran_foundation_ayah_catalog_task() -> dict[str, Any]:
    if not settings.QURAN_QF_AYAH_AUDIO_SYNC_ENABLED:
        logger.info(
            "Quran.Foundation ayah audio sync is disabled",
            extra={"event": "quran_foundation_ayah_sync_disabled"},
        )
        return {"enabled": False}
    try:
        edition = QuranEdition.objects.select_related("active_version").get(
            code=settings.QURAN_QF_AYAH_AUDIO_EDITION
        )
        if edition.active_version is None:
            raise QuranFoundationError("The ayah audio Quran edition has no active version.")
        result = sync_quran_foundation_ayah_recitations(
            quran_version=edition.active_version,
        )
        if result.failures:
            failed_ids = ", ".join(str(source_id) for source_id, _error in result.failures)
            raise QuranFoundationError(f"Ayah audio sync failed for source IDs: {failed_ids}")
    except QuranEdition.DoesNotExist as exc:
        raise QuranFoundationError("The ayah audio Quran edition does not exist.") from exc
    logger.info(
        "Quran.Foundation ayah audio sync completed",
        extra={
            "event": "quran_foundation_ayah_sync_completed",
            "available": result.available,
            "chapters": result.chapters,
            "audio_files": result.audio_files,
        },
    )
    return {
        "enabled": True,
        "available": result.available,
        "created": result.created,
        "updated": result.updated,
        "unchanged": result.unchanged,
        "chapters": result.chapters,
        "audio_files": result.audio_files,
        "delivery_samples": result.delivery_samples,
    }
