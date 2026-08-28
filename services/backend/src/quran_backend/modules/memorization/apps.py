from __future__ import annotations

from django.apps import AppConfig


class MemorizationConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "quran_backend.modules.memorization"
    label = "memorization"
    verbose_name = "Заучивание Корана"
