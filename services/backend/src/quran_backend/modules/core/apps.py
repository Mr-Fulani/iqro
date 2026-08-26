from __future__ import annotations

from django.apps import AppConfig


class CoreConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "quran_backend.modules.core"
    verbose_name = "Системное ядро"

    def ready(self) -> None:
        from quran_backend.modules.core import checks as _checks  # noqa: F401, PLC0415
