from __future__ import annotations

from quran_backend.settings.base import *  # noqa: F403
from quran_backend.settings.base import env_list

DEBUG = True
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
