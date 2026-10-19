from __future__ import annotations

from django.apps import AppConfig


class SalahConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "quran_backend.modules.salah"
    label = "salah"
    verbose_name = "Обучение намазу"
