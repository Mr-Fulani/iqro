from __future__ import annotations

import os
from typing import cast

from django.core.exceptions import ImproperlyConfigured

from quran_backend.settings.production import *  # noqa: F403
from quran_backend.settings.production import MAILERS

STAGING_EMAIL_DELIVERY_MODE = os.getenv("STAGING_EMAIL_DELIVERY_MODE", "mailpit").strip().lower()
if STAGING_EMAIL_DELIVERY_MODE not in {"mailpit", "smtp"}:
    raise ImproperlyConfigured("STAGING_EMAIL_DELIVERY_MODE must be either 'mailpit' or 'smtp'")

# Staging keeps production security/storage checks. Mailpit remains the safe default,
# while an explicit smtp mode reuses the provider settings already loaded by production.py.
if STAGING_EMAIL_DELIVERY_MODE == "mailpit":
    staging_mailer_options = cast(dict[str, object], MAILERS["default"]["OPTIONS"])
    staging_mailer_options.update(
        {
            "host": "mailpit",
            "port": 1025,
            "username": "",
            "password": "",
            "use_tls": False,
        }
    )
