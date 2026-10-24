# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
from __future__ import annotations

from typing import Any

from django.core.management.base import BaseCommand, CommandError

from quran_backend.modules.alerts import telegram
from quran_backend.modules.alerts.logging import process_role


class Command(BaseCommand):
    help = "Отправляет пробное уведомление в Telegram-группу владельца (docs/alerts.md)."

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        if not telegram.is_configured():
            raise CommandError(
                "Уведомления выключены: в окружении нет TELEGRAM_BOT_TOKEN "
                "или TELEGRAM_ALERT_CHAT_ID. Впишите их в services/backend/.env.production "
                "и перезапустите контейнеры."
            )
        try:
            # Directly, not through Celery: the answer is visible right here.
            telegram.send_message(
                "<b>✅ Проверка уведомлений IQRO</b>\n"
                f"Бот настроен, сообщение отправлено из {process_role()}."
            )
        except telegram.TelegramSendError as error:
            raise CommandError(f"Не отправлено: {error}") from None
        self.stdout.write(self.style.SUCCESS("Отправлено. Проверьте группу в Telegram."))
