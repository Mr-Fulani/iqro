from __future__ import annotations

from quran_backend.settings.base import *  # noqa: F403
from quran_backend.settings.base import env_list

DEBUG = True
LOCAL_DEVELOPMENT = True
MUSHAF_STAGING_PREVIEWS = True
# Local content is prepared explicitly by dev-data. Do not start production-size
# provider imports on every developer's machine after a day of running Celery.
CELERY_BEAT_SCHEDULE = {
    name: job
    for name, job in CELERY_BEAT_SCHEDULE.items()  # noqa: F405
    if not name.startswith("sync-quran-foundation-")
}
ALLOWED_HOSTS = env_list("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1")
MAILERS = {
    "default": {
        "BACKEND": "django.core.mail.backends.console.EmailBackend",
    }
}

REST_FRAMEWORK["DEFAULT_RENDERER_CLASSES"] = [  # noqa: F405
    *REST_FRAMEWORK["DEFAULT_RENDERER_CLASSES"],  # noqa: F405
    "rest_framework.renderers.BrowsableAPIRenderer",
]
