from __future__ import annotations

from django.apps import AppConfig


class PrayerTimesConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "quran_backend.modules.prayer_times"
    label = "prayer_times"
    verbose_name = "Время намаза"
