from __future__ import annotations

from django.apps import AppConfig


class DuaConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "quran_backend.modules.dua"
    label = "dua"
    verbose_name = "Ду’а и азкары"  # noqa: RUF001
