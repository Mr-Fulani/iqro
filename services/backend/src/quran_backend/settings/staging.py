from __future__ import annotations

from quran_backend.settings.production import *  # noqa: F403
from quran_backend.settings.production import MAILERS

# Staging keeps production security/storage checks, but captures login codes locally.
# Production still requires a real SMTP provider and never imports this module.
MAILERS["default"]["OPTIONS"].update(
    {
        "host": "mailpit",
        "port": 1025,
        "username": "",
        "password": "",
        "use_tls": False,
    }
)
