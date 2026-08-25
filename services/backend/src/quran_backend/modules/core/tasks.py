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


def _request_content_endpoint(
    request: Request,
    *,
    endpoint: str,
    content_type: str,
) -> int:
    try:
        with urlopen(  # noqa: S310 -- URLs are validated deployment configuration.
            request,
            timeout=settings.WEB_CONTENT_REVALIDATION_TIMEOUT_SECONDS,
        ) as response:
            status = int(response.status)
            response.read(64 * 1024)
    except HTTPError as exc:
        if exc.code >= 500:
            raise ContentRevalidationTransientError(
                f"{endpoint} returned HTTP {exc.code}."
            ) from exc
        logger.error(
            "Content cache endpoint rejected the request",
            extra={
                "event": "content_cache_endpoint_rejected",
                "content_type": content_type,
                "endpoint": endpoint,
                "status": exc.code,
            },
        )
        raise
    except (TimeoutError, URLError) as exc:
        raise ContentRevalidationTransientError(f"{endpoint} is unavailable.") from exc
    return status


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
    content_type = event.get("type", "unknown")
    status = _request_content_endpoint(
        request,
        endpoint="web content revalidation endpoint",
        content_type=content_type,
    )

    purge_status: int | None = None
    if settings.PUBLIC_API_CACHE_PURGE_URL:
        purge_request = Request(  # noqa: S310 -- URL is trusted deployment configuration.
            settings.PUBLIC_API_CACHE_PURGE_URL,
            method="PURGE",
            headers={
                "Accept": "application/json",
                "Authorization": f"Bearer {settings.QURAN_OPERATIONS_TOKEN}",
            },
        )
        purge_status = _request_content_endpoint(
            purge_request,
            endpoint="public API cache purge endpoint",
            content_type=content_type,
        )

    logger.info(
        "Web content cache invalidated",
        extra={
            "event": "web_content_revalidated",
            "content_type": content_type,
            "status": status,
            "purge_status": purge_status,
        },
    )
    return {
        "accepted": True,
        "status": status,
        "purge_status": purge_status,
        "type": content_type,
    }
