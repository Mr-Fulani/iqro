from __future__ import annotations

from typing import cast

from quran_backend.settings.production import *  # noqa: F403
from quran_backend.settings.production import MAILERS

# Staging keeps production security/storage checks, but captures login codes locally.
# Production still requires a real SMTP provider and never imports this module.
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
