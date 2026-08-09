from __future__ import annotations

import os

from quran_backend.settings.base import *  # noqa: F403

DEBUG = False
SECRET_KEY = "test-only-secret-key"
ALLOWED_HOSTS = ["testserver"]

if os.getenv("QURAN_TEST_DATABASE") != "postgresql":
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": ":memory:",
        }
    }
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
        "LOCATION": "quran-platform-tests",
    }
}
PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]
CELERY_TASK_ALWAYS_EAGER = True
CELERY_TASK_EAGER_PROPAGATES = True
REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"] = {  # noqa: F405
    "guest_bootstrap_installation": "10000/minute",
    "guest_bootstrap_ip_burst": "10000/minute",
    "token_refresh_session": "10000/minute",
    "token_refresh_ip_burst": "10000/minute",
    "feedback_write": "10000/minute",
    "prayer_calculate": "10000/minute",
    "reading_mutation": "10000/minute",
    "sync_push": "10000/minute",
    "sync_push_daily": "100000/day",
}
