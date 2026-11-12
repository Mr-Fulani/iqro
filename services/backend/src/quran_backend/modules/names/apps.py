from __future__ import annotations

from django.apps import AppConfig


class NamesConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "quran_backend.modules.names"
    label = "names"
    verbose_name = "Имена Аллаха"
