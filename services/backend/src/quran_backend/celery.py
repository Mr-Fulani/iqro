from __future__ import annotations

import os

from celery import Celery

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "quran_backend.settings.production")

app = Celery("quran_backend")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks()
