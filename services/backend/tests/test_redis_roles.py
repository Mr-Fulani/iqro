from __future__ import annotations

import json

import pytest
from django.conf import settings
from django.core.cache import caches
from django.core.management import call_command

from quran_backend.modules.core.throttling import AtomicFixedWindowRateThrottle
from quran_backend.redis_roles import RedisRoleConfig, RedisRoleConfigError


def test_legacy_redis_url_is_the_backward_compatible_default() -> None:
    config = RedisRoleConfig.from_environ({"REDIS_URL": "redis://legacy.example:6379/4"})

    assert set(config.role_urls().values()) == {"redis://legacy.example:6379/4"}
    assert config.report()["single_redis_instance"] is True


def test_role_urls_can_move_independently_without_exposing_credentials() -> None:
    config = RedisRoleConfig.from_environ(
        {
            "REDIS_CACHE_URL": "rediss://cache-user:cache-secret@cache.example:6380/0",
            "REDIS_THROTTLE_URL": "rediss://throttle-user:secret@security.example:6380/1",
            "CELERY_BROKER_URL": "rediss://worker:secret@queue.example:6380/2",
            "CELERY_RESULT_BACKEND": "rediss://worker:secret@queue.example:6380/3",
        }
    )

    report = config.report()
    serialized = json.dumps(report)
    assert report["unique_role_urls"] == 4
    assert report["unique_redis_instances"] == 3
    assert report["single_redis_instance"] is False
    assert "secret" not in serialized
    assert "cache-user" not in serialized


@pytest.mark.parametrize(
    ("name", "value"),
    [
        ("REDIS_CACHE_URL", "http://cache.example/0"),
        ("REDIS_THROTTLE_URL", "redis:///0"),
        ("CELERY_BROKER_URL", "redis://queue.example/not-a-database"),
        ("CELERY_RESULT_BACKEND", "redis://queue.example/0#fragment"),
        ("REDIS_URL", "redis://queue.example:invalid/0"),
    ],
)
def test_invalid_role_url_is_rejected(name: str, value: str) -> None:
    with pytest.raises(RedisRoleConfigError, match=name):
        RedisRoleConfig.from_environ({name: value})


def test_runtime_uses_throttling_alias_and_role_specific_celery_urls() -> None:
    assert AtomicFixedWindowRateThrottle.cache is caches["throttling"]
    assert settings.REDIS_ROLE_CONFIG.broker_url == settings.CELERY_BROKER_URL
    assert settings.REDIS_ROLE_CONFIG.result_url == settings.CELERY_RESULT_BACKEND


def test_redis_role_config_command_prints_redacted_report(
    capsys: pytest.CaptureFixture[str],
) -> None:
    call_command("redis_role_config")

    report = json.loads(capsys.readouterr().out)
    assert set(report["roles"]) == {
        "cache",
        "throttling",
        "celery_broker",
        "celery_results",
    }
