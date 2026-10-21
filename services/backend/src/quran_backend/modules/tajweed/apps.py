from __future__ import annotations

from django.apps import AppConfig


class TajweedConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "quran_backend.modules.tajweed"
    label = "tajweed"
    verbose_name = "Таджвид"
