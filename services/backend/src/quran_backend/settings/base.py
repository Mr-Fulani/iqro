from __future__ import annotations

import os
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

from corsheaders.defaults import default_headers
from django.core.exceptions import ImproperlyConfigured

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
QURAN_PRAYER_THROTTLE_HASH_KEY = os.getenv("QURAN_PRAYER_THROTTLE_HASH_KEY", SECRET_KEY)
QURAN_AUTH_SESSION_RETENTION_DAYS = os.getenv("QURAN_AUTH_SESSION_RETENTION_DAYS", "90")
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
QURAN_QF_AUDIO_REFRESH_DAYS = positive_env_int("QF_AUDIO_REFRESH_DAYS", 5)
if QURAN_QF_AUDIO_REFRESH_DAYS > 6:
    raise ImproperlyConfigured("QF_AUDIO_REFRESH_DAYS must be between 1 and 6")
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
    "corsheaders.middleware.CorsMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.locale.LocaleMiddleware",
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

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "HOST": os.getenv("DATABASE_HOST", "localhost"),
        "PORT": int(os.getenv("DATABASE_PORT", "5432")),
        "NAME": os.getenv("DATABASE_NAME", "quran"),
        "USER": os.getenv("DATABASE_USER", "quran"),
        "PASSWORD": os.getenv("DATABASE_PASSWORD", "quran-local-only"),
        "CONN_MAX_AGE": int(os.getenv("DATABASE_CONN_MAX_AGE", "60")),
        "CONN_HEALTH_CHECKS": True,
        "OPTIONS": {"connect_timeout": 5},
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
DATA_UPLOAD_MAX_MEMORY_SIZE = positive_env_int("DJANGO_DATA_UPLOAD_MAX_MEMORY_SIZE", 1_048_576)
FILE_UPLOAD_MAX_MEMORY_SIZE = positive_env_int("DJANGO_FILE_UPLOAD_MAX_MEMORY_SIZE", 1_048_576)

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.redis.RedisCache",
        "LOCATION": REDIS_URL,
        "TIMEOUT": 300,
        "KEY_PREFIX": "quran-platform",
    }
}

SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = "Lax"
CSRF_COOKIE_SAMESITE = "Lax"
X_FRAME_OPTIONS = "DENY"
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = "strict-origin-when-cross-origin"

CSRF_TRUSTED_ORIGINS = env_list("DJANGO_CSRF_TRUSTED_ORIGINS")
CORS_ALLOWED_ORIGINS = env_list("DJANGO_CORS_ALLOWED_ORIGINS")
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

CELERY_BROKER_URL = REDIS_URL
CELERY_RESULT_BACKEND = REDIS_URL
CELERY_TASK_SERIALIZER = "json"
CELERY_ACCEPT_CONTENT = ["json"]
CELERY_RESULT_SERIALIZER = "json"
CELERY_TIMEZONE = "UTC"
CELERY_TASK_TRACK_STARTED = True
CELERY_TASK_ACKS_LATE = True
CELERY_TASK_REJECT_ON_WORKER_LOST = True
CELERY_BROKER_CONNECTION_RETRY_ON_STARTUP = True
CELERY_BEAT_SCHEDULE = {
    "sync-quran-foundation-audio-daily": {
        "task": "audio.sync_quran_foundation",
        "schedule": 86_400.0,
    },
    "prune-auth-sessions-hourly": {
        "task": "accounts.prune_auth_sessions",
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
