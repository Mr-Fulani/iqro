from __future__ import annotations

from django.core.exceptions import ImproperlyConfigured

from quran_backend.settings.base import *  # noqa: F403
from quran_backend.settings.base import REST_FRAMEWORK, env_list, required_env

SECRET_KEY = required_env("DJANGO_SECRET_KEY")
QURAN_INSTALLATION_HASH_KEY = required_env("QURAN_INSTALLATION_HASH_KEY")
QURAN_GUEST_CREDENTIAL_HASH_KEY = required_env("QURAN_GUEST_CREDENTIAL_HASH_KEY")
QURAN_REFRESH_TOKEN_HASH_KEY = required_env("QURAN_REFRESH_TOKEN_HASH_KEY")
try:
    TRUSTED_PROXY_COUNT = int(required_env("DJANGO_NUM_PROXIES"))
except ValueError as exc:
    msg = "DJANGO_NUM_PROXIES must be a non-negative integer"
    raise ImproperlyConfigured(msg) from exc
if TRUSTED_PROXY_COUNT < 0:
    msg = "DJANGO_NUM_PROXIES must be a non-negative integer"
    raise ImproperlyConfigured(msg)
REST_FRAMEWORK["NUM_PROXIES"] = TRUSTED_PROXY_COUNT
ALLOWED_HOSTS = env_list("DJANGO_ALLOWED_HOSTS")
if not ALLOWED_HOSTS:
    msg = "DJANGO_ALLOWED_HOSTS must contain at least one production host"
    raise ImproperlyConfigured(msg)

CSRF_TRUSTED_ORIGINS = env_list("DJANGO_CSRF_TRUSTED_ORIGINS")

SECURE_SSL_REDIRECT = True
SECURE_HSTS_SECONDS = 31_536_000
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
