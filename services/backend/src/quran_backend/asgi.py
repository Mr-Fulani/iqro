from __future__ import annotations

import os

from django.conf import settings
from django.contrib.staticfiles.handlers import ASGIStaticFilesHandler
from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "quran_backend.settings.production")

application = get_asgi_application()

if settings.DEBUG:
    application = ASGIStaticFilesHandler(application)
