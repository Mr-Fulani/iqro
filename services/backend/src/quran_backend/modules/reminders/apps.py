from __future__ import annotations

from django.apps import AppConfig


class RemindersConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "quran_backend.modules.reminders"
    label = "reminders"
    verbose_name = "Reminder rules"

    def ready(self) -> None:
        from quran_backend.modules.reminders import checks as _checks  # noqa: F401, PLC0415
