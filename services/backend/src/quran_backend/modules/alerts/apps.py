from __future__ import annotations

import logging
from typing import Any

from django.apps import AppConfig


def _attach_alert_handler(logger: logging.Logger | None = None, **_kwargs: Any) -> None:
    """Celery replaces the root logger's handlers; this puts the alerts handler back."""
    from quran_backend.modules.alerts.logging import TelegramAlertHandler  # noqa: PLC0415

    target = logger or logging.getLogger()
    if not any(isinstance(handler, TelegramAlertHandler) for handler in target.handlers):
        target.addHandler(TelegramAlertHandler())


class AlertsConfig(AppConfig):
    name = "quran_backend.modules.alerts"
    verbose_name = "Уведомления в Telegram"

    def ready(self) -> None:
        from celery.signals import after_setup_logger, worker_ready  # noqa: PLC0415

        from quran_backend.modules.alerts.beat import start_watchdog  # noqa: PLC0415

        after_setup_logger.connect(_attach_alert_handler, weak=False)
        worker_ready.connect(_attach_alert_handler, weak=False)
        worker_ready.connect(start_watchdog, weak=False)
