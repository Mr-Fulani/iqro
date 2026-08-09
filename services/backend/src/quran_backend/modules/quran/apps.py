from __future__ import annotations

from django.apps import AppConfig


class QuranConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "quran_backend.modules.quran"
    label = "quran"
    verbose_name = "Quran"
