from __future__ import annotations

from django.apps import AppConfig


class FeedbackConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "quran_backend.modules.feedback"
    verbose_name = "Обратная связь"
