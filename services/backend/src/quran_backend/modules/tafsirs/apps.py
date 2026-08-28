from __future__ import annotations

from django.apps import AppConfig


class TafsirsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "quran_backend.modules.tafsirs"
    label = "tafsirs"
    verbose_name = "Тафсиры Корана"
