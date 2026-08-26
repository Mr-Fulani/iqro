from __future__ import annotations

import os
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

from corsheaders.defaults import default_headers
from django.core.exceptions import ImproperlyConfigured

from quran_backend.database_budget import DatabaseBudgetError, DatabaseConnectionBudget
from quran_backend.redis_roles import RedisRoleConfig, RedisRoleConfigError

BASE_DIR = Path(__file__).resolve().parents[3]


def env_list(name: str, default: str = "") -> list[str]:
    return [item.strip() for item in os.getenv(name, default).split(",") if item.strip()]


def required_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        msg = f"Required environment variable is missing: {name}"
        raise ImproperlyConfigured(msg)
    return value


def positive_env_int(name: str, default: int) -> int:
    try:
        value = int(os.getenv(name, str(default)))
    except ValueError as exc:
        raise ImproperlyConfigured(f"{name} must be a positive integer") from exc
    if value <= 0:
        raise ImproperlyConfigured(f"{name} must be a positive integer")
    return value


def non_negative_env_int(name: str, default: int) -> int:
    try:
        value = int(os.getenv(name, str(default)))
    except ValueError as exc:
        raise ImproperlyConfigured(f"{name} must be a non-negative integer") from exc
    if value < 0:
        raise ImproperlyConfigured(f"{name} must be a non-negative integer")
    return value


def env_bool(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    normalized = raw.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise ImproperlyConfigured(f"{name} must be a boolean")


def validate_https_base_url(name: str, value: str) -> str:
    parsed = urlsplit(value)
    valid = (
        parsed.scheme == "https"
        and parsed.hostname is not None
        and parsed.username is None
        and parsed.password is None
        and not parsed.query
        and not parsed.fragment
    )
    if not valid:
        raise ImproperlyConfigured(
            f"{name} must be an HTTPS base URL without credentials, query, or fragment"
        )
    return value


APP_VERSION = os.getenv("APP_VERSION", "0.1.0")
SECRET_KEY = os.getenv("DJANGO_SECRET_KEY", "unsafe-local-development-key")
QURAN_ACCESS_TOKEN_TTL_SECONDS = os.getenv("QURAN_ACCESS_TOKEN_TTL_SECONDS", "900")
QURAN_REFRESH_TOKEN_TTL_SECONDS = os.getenv("QURAN_REFRESH_TOKEN_TTL_SECONDS", "2592000")
QURAN_INSTALLATION_HASH_KEY = os.getenv("QURAN_INSTALLATION_HASH_KEY", SECRET_KEY)
QURAN_GUEST_CREDENTIAL_HASH_KEY = os.getenv("QURAN_GUEST_CREDENTIAL_HASH_KEY", SECRET_KEY)
QURAN_REFRESH_TOKEN_HASH_KEY = os.getenv("QURAN_REFRESH_TOKEN_HASH_KEY", SECRET_KEY)
QURAN_EMAIL_CODE_HASH_KEY = os.getenv("QURAN_EMAIL_CODE_HASH_KEY", SECRET_KEY)
QURAN_EMAIL_CODE_TTL_SECONDS = os.getenv("QURAN_EMAIL_CODE_TTL_SECONDS", "600")
QURAN_EMAIL_CODE_ATTEMPTS = os.getenv("QURAN_EMAIL_CODE_ATTEMPTS", "5")
QURAN_EMAIL_CHALLENGE_RETENTION_HOURS = os.getenv(
    "QURAN_EMAIL_CHALLENGE_RETENTION_HOURS",
    "24",
)
QURAN_EMAIL_CHALLENGE_PRUNE_BATCH_SIZE = os.getenv(
    "QURAN_EMAIL_CHALLENGE_PRUNE_BATCH_SIZE",
    "5000",
)
QURAN_PRAYER_THROTTLE_HASH_KEY = os.getenv("QURAN_PRAYER_THROTTLE_HASH_KEY", SECRET_KEY)
QURAN_AUTH_SESSION_RETENTION_DAYS = os.getenv("QURAN_AUTH_SESSION_RETENTION_DAYS", "90")
QURAN_ACCOUNT_DELETION_GRACE_DAYS = os.getenv("QURAN_ACCOUNT_DELETION_GRACE_DAYS", "7")
QURAN_ACCOUNT_REAUTH_MAX_AGE_SECONDS = os.getenv(
    "QURAN_ACCOUNT_REAUTH_MAX_AGE_SECONDS",
    "600",
)
QURAN_ACCOUNT_DELETION_BATCH_SIZE = os.getenv("QURAN_ACCOUNT_DELETION_BATCH_SIZE", "100")
QURAN_AUTH_PRUNE_BATCH_SIZE = os.getenv("QURAN_AUTH_PRUNE_BATCH_SIZE", "5000")
QURAN_AUTH_PRUNE_TOKEN_BATCH_SIZE = os.getenv("QURAN_AUTH_PRUNE_TOKEN_BATCH_SIZE", "50000")
QURAN_RETENTION_TASK_MAX_BATCHES = os.getenv("QURAN_RETENTION_TASK_MAX_BATCHES", "10")
QURAN_SYNC_CHANGE_RETENTION_DAYS = os.getenv("QURAN_SYNC_CHANGE_RETENTION_DAYS", "180")
QURAN_SYNC_OPERATION_RETENTION_DAYS = os.getenv(
    "QURAN_SYNC_OPERATION_RETENTION_DAYS",
    "180",
)
QURAN_SYNC_PRUNE_BATCH_SIZE = os.getenv("QURAN_SYNC_PRUNE_BATCH_SIZE", "5000")
QURAN_SYNC_PRUNE_USER_BATCH_SIZE = os.getenv(
    "QURAN_SYNC_PRUNE_USER_BATCH_SIZE",
    "1000",
)
QURAN_BOOKMARK_TOMBSTONE_RETENTION_DAYS = os.getenv(
    "QURAN_BOOKMARK_TOMBSTONE_RETENTION_DAYS",
    "365",
)
QURAN_BOOKMARK_NEW_ID_MAX_AGE_DAYS = os.getenv(
    "QURAN_BOOKMARK_NEW_ID_MAX_AGE_DAYS",
    "360",
)
QURAN_BOOKMARK_ID_FUTURE_SKEW_SECONDS = os.getenv(
    "QURAN_BOOKMARK_ID_FUTURE_SKEW_SECONDS",
    "86400",
)
QURAN_BOOKMARK_MAX_PER_USER = os.getenv("QURAN_BOOKMARK_MAX_PER_USER", "5000")
QURAN_REMINDER_MAX_ACTIVE_PER_USER = os.getenv(
    "QURAN_REMINDER_MAX_ACTIVE_PER_USER",
    "64",
)
QURAN_REMINDER_MAX_TOTAL_PER_USER = os.getenv(
    "QURAN_REMINDER_MAX_TOTAL_PER_USER",
    "256",
)
WEB_PUSH_ENABLED = env_bool("WEB_PUSH_ENABLED", False)
WEB_PUSH_VAPID_PUBLIC_KEY = os.getenv("WEB_PUSH_VAPID_PUBLIC_KEY", "")
WEB_PUSH_VAPID_PRIVATE_KEY = os.getenv("WEB_PUSH_VAPID_PRIVATE_KEY", "")
WEB_PUSH_VAPID_SUBJECT = os.getenv("WEB_PUSH_VAPID_SUBJECT", "mailto:privacy@iqro.forum")
WEB_PUSH_ALLOWED_ENDPOINT_HOST_SUFFIXES = env_list(
    "WEB_PUSH_ALLOWED_ENDPOINT_HOST_SUFFIXES",
    "fcm.googleapis.com,push.services.mozilla.com,web.push.apple.com,notify.windows.com",
)
WEB_PUSH_DISPATCH_BATCH_SIZE = positive_env_int("WEB_PUSH_DISPATCH_BATCH_SIZE", 200)
WEB_PUSH_DISPATCH_MAX_BATCHES = positive_env_int("WEB_PUSH_DISPATCH_MAX_BATCHES", 10)
WEB_PUSH_CLAIM_TTL_SECONDS = positive_env_int("WEB_PUSH_CLAIM_TTL_SECONDS", 120)
WEB_PUSH_RETRY_WINDOW_SECONDS = positive_env_int("WEB_PUSH_RETRY_WINDOW_SECONDS", 900)
WEB_PUSH_REQUEST_TIMEOUT_SECONDS = positive_env_int("WEB_PUSH_REQUEST_TIMEOUT_SECONDS", 10)
WEB_PUSH_MESSAGE_TTL_SECONDS = positive_env_int("WEB_PUSH_MESSAGE_TTL_SECONDS", 3600)
QURAN_REMINDER_TOMBSTONE_RETENTION_DAYS = os.getenv(
    "QURAN_REMINDER_TOMBSTONE_RETENTION_DAYS",
    "365",
)
QURAN_REMINDER_NEW_ID_MAX_AGE_DAYS = os.getenv(
    "QURAN_REMINDER_NEW_ID_MAX_AGE_DAYS",
    "360",
)
QURAN_REMINDER_ID_FUTURE_SKEW_SECONDS = os.getenv(
    "QURAN_REMINDER_ID_FUTURE_SKEW_SECONDS",
    "86400",
)
QURAN_RETIRED_REMINDER_ID_MAX_PER_USER = os.getenv(
    "QURAN_RETIRED_REMINDER_ID_MAX_PER_USER",
    "50000",
)
QURAN_REMINDER_PRUNE_BATCH_SIZE = os.getenv(
    "QURAN_REMINDER_PRUNE_BATCH_SIZE",
    "5000",
)
QURAN_RETIRED_BOOKMARK_ID_MAX_PER_USER = os.getenv(
    "QURAN_RETIRED_BOOKMARK_ID_MAX_PER_USER",
    "50000",
)
QURAN_SYNC_FULL_RESYNC_TOKEN_MAX_AGE_SECONDS = os.getenv(
    "QURAN_SYNC_FULL_RESYNC_TOKEN_MAX_AGE_SECONDS",
    "86400",
)
QURAN_QF_AUDIO_SYNC_ENABLED = env_bool("QF_AUDIO_SYNC_ENABLED", False)
QURAN_QF_AYAH_AUDIO_SYNC_ENABLED = env_bool("QF_AYAH_AUDIO_SYNC_ENABLED", False)
QURAN_QF_AYAH_AUDIO_EDITION = os.getenv("QF_AYAH_AUDIO_EDITION", "madani-hafs")
QURAN_QF_MUSHAF_SYNC_ENABLED = env_bool("QF_MUSHAF_SYNC_ENABLED", False)
QURAN_QF_AUDIO_REFRESH_DAYS = positive_env_int("QF_AUDIO_REFRESH_DAYS", 5)
if QURAN_QF_AUDIO_REFRESH_DAYS > 6:
    raise ImproperlyConfigured("QF_AUDIO_REFRESH_DAYS must be between 1 and 6")
QURAN_QF_ENV = os.getenv("QF_ENV", "prelive")
if QURAN_QF_ENV not in {"prelive", "production"}:
    raise ImproperlyConfigured("QF_ENV must be 'prelive' or 'production'")
QURAN_QF_AUDIO_STALE_AFTER_HOURS = positive_env_int("QF_AUDIO_STALE_AFTER_HOURS", 168)
if QURAN_QF_AUDIO_STALE_AFTER_HOURS < QURAN_QF_AUDIO_REFRESH_DAYS * 24:
    raise ImproperlyConfigured(
        "QF_AUDIO_STALE_AFTER_HOURS must not be shorter than QF_AUDIO_REFRESH_DAYS"
    )
QURAN_OPERATIONS_TOKEN = os.getenv("QURAN_OPERATIONS_TOKEN", "")
WEB_CONTENT_REVALIDATION_URL = os.getenv("WEB_CONTENT_REVALIDATION_URL", "")
WEB_CONTENT_REVALIDATION_SECRET = os.getenv("WEB_CONTENT_REVALIDATION_SECRET", "")
PUBLIC_API_CACHE_PURGE_URL = os.getenv("PUBLIC_API_CACHE_PURGE_URL", "")
WEB_CONTENT_REVALIDATION_TIMEOUT_SECONDS = positive_env_int(
    "WEB_CONTENT_REVALIDATION_TIMEOUT_SECONDS",
    5,
)
DEBUG = False
ALLOWED_HOSTS: list[str] = []

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "corsheaders",
    "rest_framework",
    "drf_spectacular",
    "quran_backend.modules.core.apps.CoreConfig",
    "quran_backend.modules.accounts.apps.AccountsConfig",
    "quran_backend.modules.quran.apps.QuranConfig",
    "quran_backend.modules.audio.apps.AudioConfig",
    "quran_backend.modules.prayer_times.apps.PrayerTimesConfig",
    "quran_backend.modules.reading.apps.ReadingConfig",
    "quran_backend.modules.reminders.apps.RemindersConfig",
    "quran_backend.modules.feedback.apps.FeedbackConfig",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "quran_backend.modules.core.middleware.RequestIdMiddleware",
    "quran_backend.modules.core.middleware.RequestMetricsMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.locale.LocaleMiddleware",
    "quran_backend.modules.core.middleware.AdminRussianLocaleMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "quran_backend.urls"
WSGI_APPLICATION = "quran_backend.wsgi.application"
ASGI_APPLICATION = "quran_backend.asgi.application"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

try:
    DATABASE_CONNECTION_BUDGET = DatabaseConnectionBudget.from_environ(os.environ)
except DatabaseBudgetError as exc:
    raise ImproperlyConfigured(str(exc)) from exc

DATABASE_POOL_MODE = DATABASE_CONNECTION_BUDGET.pool_mode
DATABASE_CONN_MAX_AGE = non_negative_env_int("DATABASE_CONN_MAX_AGE", 0)
if DATABASE_POOL_MODE == "transaction" and DATABASE_CONN_MAX_AGE != 0:
    raise ImproperlyConfigured("DATABASE_CONN_MAX_AGE must be 0 with transaction pooling")
DATABASE_OPTIONS: dict[str, object] = {
    "connect_timeout": positive_env_int("DATABASE_CONNECT_TIMEOUT_SECONDS", 5),
}
if DATABASE_POOL_MODE == "transaction":
    DATABASE_OPTIONS["prepare_threshold"] = None

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "HOST": os.getenv("DATABASE_HOST", "localhost"),
        "PORT": int(os.getenv("DATABASE_PORT", "5432")),
        "NAME": os.getenv("DATABASE_NAME", "quran"),
        "USER": os.getenv("DATABASE_USER", "quran"),
        "PASSWORD": os.getenv("DATABASE_PASSWORD", "quran-local-only"),
        "CONN_MAX_AGE": DATABASE_CONN_MAX_AGE,
        "CONN_HEALTH_CHECKS": True,
        "DISABLE_SERVER_SIDE_CURSORS": DATABASE_POOL_MODE == "transaction",
        "OPTIONS": DATABASE_OPTIONS,
    }
}

AUTH_USER_MODEL = "accounts.User"
AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en"
LANGUAGES = [
    ("ar", "العربية"),
    ("en", "English"),
    ("ru", "Русский"),
]
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "media"
PUBLIC_MEDIA_BASE_URL = os.getenv("PUBLIC_MEDIA_BASE_URL", "http://localhost:8000/media/")
PUBLIC_AUDIO_BASE_URL = os.getenv("PUBLIC_AUDIO_BASE_URL", PUBLIC_MEDIA_BASE_URL)
MEDIA_OBJECT_STORAGE_ENABLED = env_bool("MEDIA_OBJECT_STORAGE_ENABLED", False)
MEDIA_OBJECT_STORAGE_REQUIRED = False
MEDIA_OBJECT_STORAGE_ALLOW_HTTP = env_bool("MEDIA_OBJECT_STORAGE_ALLOW_HTTP", DEBUG)
MEDIA_OBJECT_STORAGE_ENDPOINT_URL = os.getenv("MEDIA_OBJECT_STORAGE_ENDPOINT_URL", "")
MEDIA_OBJECT_STORAGE_BUCKET = os.getenv("MEDIA_OBJECT_STORAGE_BUCKET", "")
MEDIA_OBJECT_STORAGE_ACCESS_KEY_ID = os.getenv("MEDIA_OBJECT_STORAGE_ACCESS_KEY_ID", "")
MEDIA_OBJECT_STORAGE_SECRET_ACCESS_KEY = os.getenv(
    "MEDIA_OBJECT_STORAGE_SECRET_ACCESS_KEY",
    "",
)
MEDIA_OBJECT_STORAGE_REGION = os.getenv("MEDIA_OBJECT_STORAGE_REGION", "auto")
MEDIA_OBJECT_STORAGE_ADDRESSING_STYLE = os.getenv(
    "MEDIA_OBJECT_STORAGE_ADDRESSING_STYLE",
    "path",
)
MEDIA_OBJECT_STORAGE_CONNECT_TIMEOUT_SECONDS = positive_env_int(
    "MEDIA_OBJECT_STORAGE_CONNECT_TIMEOUT_SECONDS",
    5,
)
MEDIA_OBJECT_STORAGE_READ_TIMEOUT_SECONDS = positive_env_int(
    "MEDIA_OBJECT_STORAGE_READ_TIMEOUT_SECONDS",
    60,
)
MEDIA_OBJECT_STORAGE_MAX_ATTEMPTS = positive_env_int(
    "MEDIA_OBJECT_STORAGE_MAX_ATTEMPTS",
    3,
)
MEDIA_OBJECT_STORAGE_MAX_UPLOAD_BYTES = positive_env_int(
    "MEDIA_OBJECT_STORAGE_MAX_UPLOAD_BYTES",
    1_073_741_824,
)
DATA_UPLOAD_MAX_MEMORY_SIZE = positive_env_int("DJANGO_DATA_UPLOAD_MAX_MEMORY_SIZE", 1_048_576)
FILE_UPLOAD_MAX_MEMORY_SIZE = positive_env_int("DJANGO_FILE_UPLOAD_MAX_MEMORY_SIZE", 1_048_576)

MAILERS = {
    "default": {
        "BACKEND": os.getenv(
            "DJANGO_EMAIL_BACKEND",
            "django.core.mail.backends.smtp.EmailBackend",
        ),
        "OPTIONS": {
            "host": os.getenv("DJANGO_EMAIL_HOST", "localhost"),
            "port": positive_env_int("DJANGO_EMAIL_PORT", 587),
            "username": os.getenv("DJANGO_EMAIL_HOST_USER", ""),
            "password": os.getenv("DJANGO_EMAIL_HOST_PASSWORD", ""),
            "use_tls": env_bool("DJANGO_EMAIL_USE_TLS", True),
        },
    }
}
DEFAULT_FROM_EMAIL = os.getenv("DJANGO_DEFAULT_FROM_EMAIL", "Quran Platform <noreply@localhost>")

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

try:
    REDIS_ROLE_CONFIG = RedisRoleConfig.from_environ(os.environ)
except RedisRoleConfigError as exc:
    raise ImproperlyConfigured(str(exc)) from exc

REDIS_URL = REDIS_ROLE_CONFIG.legacy_url
REDIS_CACHE_URL = REDIS_ROLE_CONFIG.cache_url
REDIS_THROTTLE_URL = REDIS_ROLE_CONFIG.throttle_url
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.redis.RedisCache",
        "LOCATION": REDIS_CACHE_URL,
        "TIMEOUT": 300,
        "KEY_PREFIX": "quran-platform",
    },
    "throttling": {
        "BACKEND": "django.core.cache.backends.redis.RedisCache",
        "LOCATION": REDIS_THROTTLE_URL,
        "TIMEOUT": None,
        "KEY_PREFIX": "quran-platform-throttling",
    },
}

SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = "Lax"
CSRF_COOKIE_SAMESITE = "Lax"
X_FRAME_OPTIONS = "DENY"
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = "strict-origin-when-cross-origin"

CSRF_TRUSTED_ORIGINS = env_list("DJANGO_CSRF_TRUSTED_ORIGINS")
CORS_ALLOWED_ORIGINS = env_list("DJANGO_CORS_ALLOWED_ORIGINS")
MEDIA_CDN_REQUIRED_ORIGINS = env_list("MEDIA_CDN_REQUIRED_ORIGINS")
CORS_ALLOW_CREDENTIALS = False
CORS_URLS_REGEX = r"^/api/.*$"
CORS_ALLOW_HEADERS = (*default_headers, "idempotency-key", "x-request-id")
CORS_EXPOSE_HEADERS = ("ETag", "Retry-After", "X-Request-ID")

REST_FRAMEWORK: dict[str, Any] = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "quran_backend.modules.accounts.authentication.SignedAccessTokenAuthentication",
        "rest_framework.authentication.SessionAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticated",
    ],
    "DEFAULT_RENDERER_CLASSES": [
        "rest_framework.renderers.JSONRenderer",
    ],
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    "EXCEPTION_HANDLER": "quran_backend.modules.core.exceptions.problem_details_handler",
    "NON_FIELD_ERRORS_KEY": "non_field_errors",
    "NUM_PROXIES": int(os.getenv("DJANGO_NUM_PROXIES", "0")),
    "DEFAULT_THROTTLE_RATES": {
        "guest_bootstrap_installation": os.getenv(
            "QURAN_GUEST_BOOTSTRAP_INSTALLATION_RATE",
            "12/minute",
        ),
        "guest_bootstrap_ip_burst": os.getenv(
            "QURAN_GUEST_BOOTSTRAP_IP_BURST_RATE",
            "1200/minute",
        ),
        "token_refresh_session": os.getenv(
            "QURAN_TOKEN_REFRESH_SESSION_RATE",
            "60/minute",
        ),
        "token_refresh_ip_burst": os.getenv(
            "QURAN_TOKEN_REFRESH_IP_BURST_RATE",
            "6000/minute",
        ),
        "email_start_identity": os.getenv(
            "QURAN_EMAIL_START_IDENTITY_RATE",
            "5/hour",
        ),
        "email_start_ip_burst": os.getenv(
            "QURAN_EMAIL_START_IP_BURST_RATE",
            "100/hour",
        ),
        "email_verify_challenge": os.getenv(
            "QURAN_EMAIL_VERIFY_CHALLENGE_RATE",
            "10/hour",
        ),
        "email_verify_ip_burst": os.getenv(
            "QURAN_EMAIL_VERIFY_IP_BURST_RATE",
            "300/hour",
        ),
        "feedback_write": os.getenv("QURAN_FEEDBACK_WRITE_RATE", "20/hour"),
        "prayer_calculate": os.getenv("QURAN_PRAYER_CALCULATE_RATE", "60/minute"),
        "prayer_profile_mutation": os.getenv(
            "QURAN_PRAYER_PROFILE_MUTATION_RATE",
            "60/minute",
        ),
        "reading_mutation": os.getenv(
            "QURAN_READING_MUTATION_RATE",
            "120/minute",
        ),
        "reminder_mutation": os.getenv(
            "QURAN_REMINDER_MUTATION_RATE",
            "120/minute",
        ),
        "sync_push": os.getenv("QURAN_SYNC_PUSH_RATE", "300/minute"),
        "sync_push_daily": os.getenv("QURAN_SYNC_PUSH_DAILY_RATE", "5000/day"),
    },
}

FEEDBACK_MAX_OPEN_TICKETS_PER_USER = int(
    os.getenv("QURAN_FEEDBACK_MAX_OPEN_TICKETS_PER_USER", "20")
)
FEEDBACK_MAX_MESSAGES_PER_TICKET = int(os.getenv("QURAN_FEEDBACK_MAX_MESSAGES_PER_TICKET", "100"))

SPECTACULAR_SETTINGS = {
    "TITLE": "Quran Platform API",
    "DESCRIPTION": "Backend API for Quran Platform clients.",
    "VERSION": APP_VERSION,
    "SERVE_INCLUDE_SCHEMA": False,
    "OAS_VERSION": "3.1.0",
    "COMPONENT_SPLIT_REQUEST": True,
    "COMPONENT_SPLIT_PATCH": False,
    "SCHEMA_PATH_PREFIX": r"/api/v1",
    "ENUM_NAME_OVERRIDES": {
        "InterfaceLocaleEnum": ["ar", "en", "ru", "tr"],
        "ReadingPositionEntityTypeEnum": ["reading_position"],
        "BookmarkEntityTypeEnum": ["bookmark"],
        "ReminderEntityTypeEnum": ["reminder"],
        "SyncUpsertActionEnum": ["upsert"],
        "SyncDeleteActionEnum": ["delete"],
        "SyncEntityTypeEnum": [
            ("reading_position", "Reading position"),
            ("bookmark", "Bookmark"),
            ("reminder", "Reminder"),
        ],
    },
    "POSTPROCESSING_HOOKS": [
        "drf_spectacular.hooks.postprocess_schema_enums",
        "quran_backend.modules.core.openapi.add_public_cache_contract",
    ],
}

CELERY_BROKER_URL = REDIS_ROLE_CONFIG.broker_url
CELERY_RESULT_BACKEND = REDIS_ROLE_CONFIG.result_url
CELERY_TASK_SERIALIZER = "json"
CELERY_ACCEPT_CONTENT = ["json"]
CELERY_RESULT_SERIALIZER = "json"
CELERY_TIMEZONE = "UTC"
CELERY_TASK_TRACK_STARTED = True
CELERY_TASK_ACKS_LATE = True
CELERY_TASK_REJECT_ON_WORKER_LOST = True
CELERY_BROKER_CONNECTION_RETRY_ON_STARTUP = True
CELERY_WORKER_PREFETCH_MULTIPLIER = positive_env_int("CELERY_WORKER_PREFETCH_MULTIPLIER", 1)
CELERY_WORKER_SEND_TASK_EVENTS = env_bool("CELERY_WORKER_SEND_TASK_EVENTS", False)
CELERY_TASK_SEND_SENT_EVENT = env_bool("CELERY_TASK_SEND_SENT_EVENT", False)
CELERY_BEAT_LOCK_KEY = os.getenv("CELERY_BEAT_LOCK_KEY", "quran-platform:celery-beat:lease").strip()
if not CELERY_BEAT_LOCK_KEY:
    raise ImproperlyConfigured("CELERY_BEAT_LOCK_KEY must not be empty")
CELERY_BEAT_LOCK_TTL_SECONDS = positive_env_int("CELERY_BEAT_LOCK_TTL_SECONDS", 60)
CELERY_BEAT_LOCK_RENEW_INTERVAL_SECONDS = positive_env_int(
    "CELERY_BEAT_LOCK_RENEW_INTERVAL_SECONDS",
    20,
)
if CELERY_BEAT_LOCK_RENEW_INTERVAL_SECONDS >= CELERY_BEAT_LOCK_TTL_SECONDS:
    raise ImproperlyConfigured(
        "CELERY_BEAT_LOCK_RENEW_INTERVAL_SECONDS must be shorter than CELERY_BEAT_LOCK_TTL_SECONDS"
    )
CELERY_BEAT_MAX_LOOP_INTERVAL = positive_env_int("CELERY_BEAT_MAX_LOOP_INTERVAL_SECONDS", 5)
CELERY_BEAT_SCHEDULE = {
    "sync-quran-foundation-audio-daily": {
        "task": "audio.sync_quran_foundation",
        "schedule": 86_400.0,
    },
    "sync-quran-foundation-ayah-audio-weekly": {
        "task": "audio.sync_quran_foundation_ayah_catalog",
        "schedule": 604_800.0,
    },
    "sync-quran-foundation-mushafs-daily": {
        "task": "quran.sync_quran_foundation_mushafs",
        "schedule": 86_400.0,
    },
    "prune-auth-sessions-hourly": {
        "task": "accounts.prune_auth_sessions",
        "schedule": 3_600.0,
    },
    "prune-email-challenges-hourly": {
        "task": "accounts.prune_email_challenges",
        "schedule": 3_600.0,
    },
    "finalize-account-deletions-hourly": {
        "task": "accounts.finalize_due_deletions",
        "schedule": 3_600.0,
    },
    "prune-sync-history-hourly": {
        "task": "reading.prune_sync_history",
        "schedule": 3_600.0,
    },
    "prune-reminder-tombstones-hourly": {
        "task": "reminders.prune_tombstones",
        "schedule": 3_600.0,
    },
    "dispatch-web-push-reminders-every-30-seconds": {
        "task": "reminders.dispatch_web_push_due",
        "schedule": 30.0,
    },
}

LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "filters": {
        "request_id": {
            "()": "quran_backend.modules.core.logging.RequestIdFilter",
        }
    },
    "formatters": {
        "json": {
            "()": "quran_backend.modules.core.logging.JsonFormatter",
        }
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "filters": ["request_id"],
            "formatter": "json",
        }
    },
    "root": {"handlers": ["console"], "level": LOG_LEVEL},
    "loggers": {
        "django": {"handlers": ["console"], "level": LOG_LEVEL, "propagate": False},
        "quran_backend": {"handlers": ["console"], "level": LOG_LEVEL, "propagate": False},
    },
}
