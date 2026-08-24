from __future__ import annotations

from django.conf import settings
from django.core.checks import Error, register
from django.core.exceptions import ImproperlyConfigured

from quran_backend.modules.core.object_storage import object_storage_config


@register()
def check_media_object_storage(**_kwargs: object) -> list[Error]:
    enabled = bool(getattr(settings, "MEDIA_OBJECT_STORAGE_ENABLED", False))
    required = bool(getattr(settings, "MEDIA_OBJECT_STORAGE_REQUIRED", False))
    if required and not enabled:
        return [
            Error(
                "Production managed media requires S3-compatible object storage.",
                id="core.E001",
            )
        ]
    if not enabled:
        return []
    try:
        object_storage_config()
    except ImproperlyConfigured as exc:
        return [Error(str(exc), id="core.E002")]
    return []
