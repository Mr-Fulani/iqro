from __future__ import annotations

from django.apps import AppConfig


class WebsiteConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "quran_backend.modules.website"
    verbose_name = "Настройки сайта"
