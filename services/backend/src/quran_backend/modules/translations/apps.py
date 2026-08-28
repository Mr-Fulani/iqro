from __future__ import annotations

from django.apps import AppConfig


class TranslationsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "quran_backend.modules.translations"
    label = "translations"
    verbose_name = "Смысловые переводы Корана"
