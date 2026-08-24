from __future__ import annotations

import json
import logging
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from celery import shared_task
from django.conf import settings

logger = logging.getLogger(__name__)


class ContentRevalidationTransientError(RuntimeError):
    pass


@shared_task(
    name="core.notify_web_content_change",
    autoretry_for=(ContentRevalidationTransientError,),
    retry_backoff=True,
    retry_jitter=True,
    max_retries=5,
)  # type: ignore[untyped-decorator]
def notify_web_content_change_task(event: dict[str, str]) -> dict[str, Any]:
    payload = json.dumps(event, separators=(",", ":")).encode()
    request = Request(  # noqa: S310 -- URL is trusted deployment configuration.
        settings.WEB_CONTENT_REVALIDATION_URL,
        data=payload,
        method="POST",
        headers={
            "Accept": "application/json",
            "Authorization": f"Bearer {settings.WEB_CONTENT_REVALIDATION_SECRET}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urlopen(  # noqa: S310 -- Request URL is validated deployment configuration.
            request,
            timeout=settings.WEB_CONTENT_REVALIDATION_TIMEOUT_SECONDS,
        ) as response:
            status = response.status
            response.read(64 * 1024)
    except HTTPError as exc:
        if exc.code >= 500:
            raise ContentRevalidationTransientError(
                f"Web content revalidation returned HTTP {exc.code}."
            ) from exc
        logger.error(
            "Web content revalidation was rejected",
            extra={
                "event": "web_content_revalidation_rejected",
                "content_type": event.get("type", "unknown"),
                "status": exc.code,
            },
        )
        raise
    except (TimeoutError, URLError) as exc:
        raise ContentRevalidationTransientError(
            "Web content revalidation endpoint is unavailable."
        ) from exc

    logger.info(
        "Web content cache invalidated",
        extra={
            "event": "web_content_revalidated",
            "content_type": event.get("type", "unknown"),
            "status": status,
        },
    )
    return {"accepted": True, "status": status, "type": event.get("type", "unknown")}
