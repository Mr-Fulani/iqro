from __future__ import annotations

from typing import Any

import pytest
from celery import Celery

from quran_backend.celery_beat import (
    BeatLeaseLostError,
    BeatLeaseUnavailableError,
    RedisLease,
    SingletonRedisScheduler,
)


class FakeRedis:
    def __init__(self) -> None:
        self.values: dict[str, str] = {}
        self.renewals = 0
        self.closed = False

    def set(self, key: str, value: str, *, ex: int, nx: bool) -> bool | None:
        assert ex > 0
        assert nx is True
        if key in self.values:
            return None
        self.values[key] = value
        return True

    def eval(self, script: str, key_count: int, *args: object) -> int:
        assert key_count == 1
        key = str(args[0])
        token = str(args[1])
        if self.values.get(key) != token:
            return 0
        if "expire" in script:
            assert int(str(args[2])) > 0
            self.renewals += 1
            return 1
        del self.values[key]
        return 1

    def close(self) -> None:
        self.closed = True


def make_lease(client: FakeRedis, *, token: str) -> RedisLease:
    return RedisLease(
        client=client,
        key="quran-platform:test-beat",
        ttl_seconds=60,
        token=token,
    )


def make_app() -> Celery:
    app = Celery("beat-tests")
    app.conf.beat_schedule = {}
    return app


def test_redis_lease_acquire_renew_and_release_are_token_safe() -> None:
    client = FakeRedis()
    owner = make_lease(client, token="owner")
    contender = make_lease(client, token="contender")

    assert owner.acquire() is True
    assert contender.acquire() is False
    assert contender.renew() is False
    assert contender.release() is False
    assert owner.renew() is True
    assert client.renewals == 1
    assert owner.release() is True
    assert client.values == {}


def test_lazy_scheduler_does_not_claim_a_lease(monkeypatch: pytest.MonkeyPatch) -> None:
    def unexpected_factory(**kwargs: Any) -> RedisLease:
        raise AssertionError("lazy scheduler must not connect to Redis")

    monkeypatch.setattr(RedisLease, "from_url", unexpected_factory)

    scheduler = SingletonRedisScheduler(app=make_app(), lazy=True)
    scheduler.close()


def test_second_scheduler_fails_while_lease_is_owned(monkeypatch: pytest.MonkeyPatch) -> None:
    client = FakeRedis()

    def lease_factory(**kwargs: Any) -> RedisLease:
        return make_lease(client, token=f"owner-{len(client.values)}")

    monkeypatch.setattr(RedisLease, "from_url", lease_factory)
    scheduler = SingletonRedisScheduler(app=make_app())

    with pytest.raises(BeatLeaseUnavailableError, match="already owned"):
        SingletonRedisScheduler(app=make_app())

    scheduler.close()
    assert client.closed is True


def test_scheduler_renews_lease_and_caps_sleep(monkeypatch: pytest.MonkeyPatch) -> None:
    client = FakeRedis()
    lease = make_lease(client, token="owner")
    clock = [0.0]

    def lease_factory(**_kwargs: Any) -> RedisLease:
        return lease

    monkeypatch.setattr(RedisLease, "from_url", lease_factory)

    scheduler = SingletonRedisScheduler(app=make_app(), monotonic=lambda: clock[0])
    clock[0] = 20.0

    delay = scheduler.tick()

    assert client.renewals == 1
    assert 0 <= delay <= 20
    scheduler.close()


def test_scheduler_exits_fail_closed_after_lease_loss(monkeypatch: pytest.MonkeyPatch) -> None:
    client = FakeRedis()
    lease = make_lease(client, token="owner")
    clock = [0.0]

    def lease_factory(**_kwargs: Any) -> RedisLease:
        return lease

    monkeypatch.setattr(RedisLease, "from_url", lease_factory)
    scheduler = SingletonRedisScheduler(app=make_app(), monotonic=lambda: clock[0])
    client.values.clear()
    clock[0] = 20.0

    with pytest.raises(BeatLeaseLostError, match="was lost"):
        scheduler.tick()

    scheduler.close()
