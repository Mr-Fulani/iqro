from __future__ import annotations

from django.apps import AppConfig


class ReadingConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "quran_backend.modules.reading"
    label = "reading"
    verbose_name = "Reading and synchronization"

    def ready(self) -> None:
        from quran_backend.modules.reading import checks as _checks  # noqa: F401, PLC0415
