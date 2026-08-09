from __future__ import annotations

from django.apps import AppConfig


class AudioConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "quran_backend.modules.audio"
    label = "audio"
    verbose_name = "Quran audio"
