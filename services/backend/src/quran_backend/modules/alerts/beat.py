# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""Is Celery beat alive? The worker watches the singleton lease beat renews in Redis.

Beat renews the lease (celery_beat.py) every 20 seconds with a 60-second TTL,
so a missing lease means no beat. Nothing scheduled runs without beat, so the
check runs in a thread of each worker, not as a scheduled task.
"""

from __future__ import annotations

import logging
import threading
import time

from django.conf import settings
from django.core.cache import cache
from redis import Redis
from redis.exceptions import RedisError

from quran_backend.modules.alerts.services import notify_now

logger = logging.getLogger(__name__)

CHECK_INTERVAL_SECONDS = 60
SILENCE_ALERT_SECONDS = 5 * 60
SILENT_SINCE_KEY = "alerts:beat:silent-since"
ALERTED_KEY = "alerts:beat:alerted"

_started = threading.Event()


def beat_alive() -> bool | None:
    """True or False, or None when Redis cannot be asked."""
    client = Redis.from_url(settings.CELERY_BROKER_URL, socket_connect_timeout=2, socket_timeout=2)
    try:
        return bool(client.exists(settings.CELERY_BEAT_LOCK_KEY))
    except RedisError:
        return None
    finally:
        client.close()


def check_beat(now: float | None = None) -> None:
    """One round: one alert after 5 silent minutes, one more when beat is back."""
    alive = beat_alive()
    if alive is None:
        return
    current = time.time() if now is None else now
    if alive:
        cache.delete(SILENT_SINCE_KEY)
        if cache.delete(ALERTED_KEY):
            notify_now("<b>✅ Celery beat снова работает</b>\nПлановые задачи выполняются.")
        return
    cache.add(SILENT_SINCE_KEY, current, timeout=None)
    since = float(cache.get(SILENT_SINCE_KEY) or current)
    silent_for = current - since
    if silent_for >= SILENCE_ALERT_SECONDS and cache.add(ALERTED_KEY, 1, timeout=None):
        notify_now(
            f"<b>🔴 Celery beat не отвечает {int(silent_for // 60)} мин</b>\n"
            "Плановые задачи не запускаются: синхронизации, напоминания, объявления.\n"
            "Проверьте контейнер beat: docker compose ps beat, docker compose logs beat."
        )


def _watch() -> None:
    while True:
        time.sleep(CHECK_INTERVAL_SECONDS)
        try:
            check_beat()
        except Exception:
            logger.warning("Celery beat check failed", exc_info=True)


def start_watchdog(**_kwargs: object) -> None:
    """Celery worker_ready: one daemon thread per worker process."""
    if _started.is_set():
        return
    _started.set()
    threading.Thread(target=_watch, name="beat-watchdog", daemon=True).start()
