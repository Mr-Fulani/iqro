from __future__ import annotations

import logging
from collections.abc import Mapping
from functools import partial

from django.conf import settings
from django.db import transaction

from quran_backend.modules.core.tasks import notify_web_content_change_task

logger = logging.getLogger(__name__)


def enqueue_content_revalidation(event: Mapping[str, str]) -> None:
    """Publish an idempotent cache event only after the database transaction commits."""

    if not settings.WEB_CONTENT_REVALIDATION_URL:
        logger.info(
            "Web content revalidation is disabled",
            extra={"event": "web_content_revalidation_disabled", "content_type": event["type"]},
        )
        return
    payload = dict(event)
    transaction.on_commit(partial(notify_web_content_change_task.delay, payload))


def enqueue_quran_content_change(
    *,
    action: str,
    edition: str,
    version: str,
) -> None:
    enqueue_content_revalidation(
        {
            "type": "quran.edition.changed",
            "action": action,
            "edition": edition,
            "version": version,
        }
    )


def enqueue_audio_content_change(
    *,
    action: str,
    recitation_id: object,
    reciter_id: object,
    version: str,
) -> None:
    enqueue_content_revalidation(
        {
            "type": "audio.recitation.changed",
            "action": action,
            "recitation_id": str(recitation_id),
            "reciter_id": str(reciter_id),
            "version": version,
        }
    )


def enqueue_social_profiles_change(*, action: str) -> None:
    enqueue_content_revalidation(
        {
            "type": "site.social_profiles.changed",
            "action": action,
        }
    )
