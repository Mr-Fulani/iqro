from __future__ import annotations

import base64
import binascii
from urllib.parse import urlsplit

from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
from django.core.exceptions import ImproperlyConfigured
from py_vapid import Vapid

from quran_backend.settings.base import *  # noqa: F403
from quran_backend.settings.base import (
    DATABASES,
    REST_FRAMEWORK,
    env_bool,
    env_list,
    required_env,
    validate_https_base_url,
)

if DATABASES["default"]["CONN_MAX_AGE"] != 0:
    raise ImproperlyConfigured(
        "DATABASE_CONN_MAX_AGE must be 0 because the production backend runs under ASGI"
    )

SECRET_KEY = required_env("DJANGO_SECRET_KEY")
QURAN_INSTALLATION_HASH_KEY = required_env("QURAN_INSTALLATION_HASH_KEY")
QURAN_GUEST_CREDENTIAL_HASH_KEY = required_env("QURAN_GUEST_CREDENTIAL_HASH_KEY")
QURAN_REFRESH_TOKEN_HASH_KEY = required_env("QURAN_REFRESH_TOKEN_HASH_KEY")
QURAN_EMAIL_CODE_HASH_KEY = required_env("QURAN_EMAIL_CODE_HASH_KEY")
QURAN_PRAYER_THROTTLE_HASH_KEY = required_env("QURAN_PRAYER_THROTTLE_HASH_KEY")
QURAN_OPERATIONS_TOKEN = required_env("QURAN_OPERATIONS_TOKEN")
WEB_CONTENT_REVALIDATION_SECRET = required_env("WEB_CONTENT_REVALIDATION_SECRET")
if len(WEB_CONTENT_REVALIDATION_SECRET) < 32:
    raise ImproperlyConfigured("WEB_CONTENT_REVALIDATION_SECRET must be at least 32 characters")
if WEB_PUSH_ENABLED:  # noqa: F405
    WEB_PUSH_VAPID_PUBLIC_KEY = required_env("WEB_PUSH_VAPID_PUBLIC_KEY")
    WEB_PUSH_VAPID_PRIVATE_KEY = required_env("WEB_PUSH_VAPID_PRIVATE_KEY")
    WEB_PUSH_VAPID_SUBJECT = required_env("WEB_PUSH_VAPID_SUBJECT")
    if not WEB_PUSH_VAPID_SUBJECT.startswith(("mailto:", "https://")):
        raise ImproperlyConfigured("WEB_PUSH_VAPID_SUBJECT must use mailto: or https://")
    try:
        public_padding = "=" * (-len(WEB_PUSH_VAPID_PUBLIC_KEY) % 4)
        configured_public_key = base64.urlsafe_b64decode(
            (WEB_PUSH_VAPID_PUBLIC_KEY + public_padding).encode("ascii")
        )
        vapid = Vapid.from_string(WEB_PUSH_VAPID_PRIVATE_KEY)
        derived_public_key = vapid.public_key.public_bytes(
            Encoding.X962,
            PublicFormat.UncompressedPoint,
        )
    except (UnicodeEncodeError, ValueError, TypeError, binascii.Error) as exc:
        raise ImproperlyConfigured("Web Push VAPID keys are invalid") from exc
    if configured_public_key != derived_public_key:
        raise ImproperlyConfigured("Web Push VAPID public/private keys do not match")
WEB_CONTENT_REVALIDATION_URL = required_env("WEB_CONTENT_REVALIDATION_URL")
revalidation_url = urlsplit(WEB_CONTENT_REVALIDATION_URL)
if (
    revalidation_url.scheme not in {"http", "https"}
    or revalidation_url.hostname is None
    or revalidation_url.username is not None
    or revalidation_url.password is not None
    or revalidation_url.query
    or revalidation_url.fragment
):
    raise ImproperlyConfigured(
        "WEB_CONTENT_REVALIDATION_URL must be an HTTP(S) URL without credentials, "
        "query, or fragment"
    )
PUBLIC_API_CACHE_PURGE_URL = required_env("PUBLIC_API_CACHE_PURGE_URL")
public_api_cache_purge_url = urlsplit(PUBLIC_API_CACHE_PURGE_URL)
if (
    public_api_cache_purge_url.scheme not in {"http", "https"}
    or public_api_cache_purge_url.hostname is None
    or public_api_cache_purge_url.username is not None
    or public_api_cache_purge_url.password is not None
    or public_api_cache_purge_url.query
    or public_api_cache_purge_url.fragment
):
    raise ImproperlyConfigured(
        "PUBLIC_API_CACHE_PURGE_URL must be an HTTP(S) URL without credentials, query, or fragment"
    )
for email_setting in (
    "DJANGO_EMAIL_HOST",
    "DJANGO_EMAIL_HOST_USER",
    "DJANGO_EMAIL_HOST_PASSWORD",
    "DJANGO_DEFAULT_FROM_EMAIL",
):
    required_env(email_setting)
PUBLIC_MEDIA_BASE_URL = validate_https_base_url(
    "PUBLIC_MEDIA_BASE_URL",
    required_env("PUBLIC_MEDIA_BASE_URL"),
)
PUBLIC_AUDIO_BASE_URL = validate_https_base_url(
    "PUBLIC_AUDIO_BASE_URL",
    required_env("PUBLIC_AUDIO_BASE_URL"),
)
MEDIA_OBJECT_STORAGE_ENABLED = True
MEDIA_OBJECT_STORAGE_REQUIRED = True
MEDIA_OBJECT_STORAGE_ALLOW_HTTP = False
MEDIA_OBJECT_STORAGE_ENDPOINT_URL = validate_https_base_url(
    "MEDIA_OBJECT_STORAGE_ENDPOINT_URL",
    required_env("MEDIA_OBJECT_STORAGE_ENDPOINT_URL"),
)
MEDIA_OBJECT_STORAGE_BUCKET = required_env("MEDIA_OBJECT_STORAGE_BUCKET")
MEDIA_OBJECT_STORAGE_ACCESS_KEY_ID = required_env("MEDIA_OBJECT_STORAGE_ACCESS_KEY_ID")
MEDIA_OBJECT_STORAGE_SECRET_ACCESS_KEY = required_env("MEDIA_OBJECT_STORAGE_SECRET_ACCESS_KEY")
MEDIA_CDN_REQUIRED_ORIGINS = env_list("MEDIA_CDN_REQUIRED_ORIGINS")
if not MEDIA_CDN_REQUIRED_ORIGINS:
    raise ImproperlyConfigured("MEDIA_CDN_REQUIRED_ORIGINS must contain production clients")
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

SECURE_SSL_REDIRECT = env_bool("DJANGO_SECURE_SSL_REDIRECT", True)
SECURE_HSTS_SECONDS = 31_536_000
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
