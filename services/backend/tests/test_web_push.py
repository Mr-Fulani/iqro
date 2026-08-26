from __future__ import annotations

import base64
import json
import uuid
from datetime import UTC, datetime, time, timedelta
from decimal import Decimal
from typing import Any
from unittest.mock import Mock

import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
from django.conf import settings
from django.test import override_settings
from django.urls import reverse
from django.utils import timezone
from pywebpush import WebPushException
from rest_framework.test import APIClient

from quran_backend.modules.accounts.models import (
    Device,
    DevicePlatform,
    RefreshSession,
    User,
)
from quran_backend.modules.accounts.services import AccessAuthContext
from quran_backend.modules.core.privacy import PRIVATE_NO_STORE_CACHE_CONTROL
from quran_backend.modules.prayer_times.models import PrayerMethodConfig, PrayerProfile
from quran_backend.modules.reminders.models import (
    ReminderRule,
    ReminderType,
    WebPushSchedule,
    WebPushSubscription,
)
from quran_backend.modules.reminders.push import (
    claim_due_web_push_schedules,
    deliver_claimed_web_push_schedule,
    next_local_occurrence,
    refresh_subscription_schedules,
)

PUSH_SETTINGS = {
    "WEB_PUSH_ENABLED": True,
    "WEB_PUSH_VAPID_PUBLIC_KEY": "public-test-key",
    "WEB_PUSH_VAPID_PRIVATE_KEY": "private-test-key",
    "WEB_PUSH_VAPID_SUBJECT": "mailto:test@example.com",
    "WEB_PUSH_ALLOWED_ENDPOINT_HOST_SUFFIXES": ["push.example.test"],
}


def _b64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


TEST_P256DH = _b64url(
    ec.derive_private_key(1, ec.SECP256R1())
    .public_key()
    .public_bytes(Encoding.X962, PublicFormat.UncompressedPoint)
)


def _subscription_payload(**overrides: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "endpoint": "https://push.example.test/subscriptions/secret-capability",
        "keys": {
            "p256dh": TEST_P256DH,
            "auth": _b64url(b"a" * 16),
        },
        "expiration_time": None,
        "timezone_name": "Europe/Istanbul",
        "locale": "ru",
    }
    payload.update(overrides)
    return payload


def _authenticated_web_client(user: User) -> tuple[APIClient, Device]:
    device = Device.objects.create(
        user=user,
        platform=DevicePlatform.WEB,
        installation_id_hash=uuid.uuid4().hex * 2,
    )
    session = RefreshSession.objects.create(
        user=user,
        device=device,
        expires_at=timezone.now() + timedelta(days=1),
    )
    client = APIClient()
    client.force_authenticate(
        user=user,
        token=AccessAuthContext(device=device, session=session),  # type: ignore[arg-type]
    )
    return client, device


def _subscription(device: Device, **overrides: Any) -> WebPushSubscription:
    values: dict[str, Any] = {
        "device": device,
        "endpoint": "https://push.example.test/subscriptions/secret-capability",
        "p256dh": TEST_P256DH,
        "auth": _b64url(b"a" * 16),
        "timezone_name": "Europe/Istanbul",
        "locale": "ru",
    }
    values.update(overrides)
    return WebPushSubscription.objects.create(**values)


def _reading_rule(user: User, **overrides: Any) -> ReminderRule:
    values: dict[str, Any] = {
        "user": user,
        "reminder_type": ReminderType.QURAN_READING,
        "local_time": time(7, 30),
        "client_updated_at": timezone.now(),
    }
    values.update(overrides)
    return ReminderRule.objects.create(**values)


def _prayer_profile(user: User) -> PrayerProfile:
    configuration = PrayerMethodConfig.objects.select_related("release", "method").get(
        method__code="muslim-world-league",
        release__version="2026.1",
    )
    return PrayerProfile.objects.create(
        user=user,
        method_config=configuration,
        asr_method="standard",
        high_latitude_rule="middle_of_night",
        polar_resolution="unresolved",
        timezone_mode="device_local",
        client_updated_at=timezone.now(),
    )


@pytest.mark.django_db
@override_settings(**PUSH_SETTINGS)
def test_web_push_api_upserts_reports_and_deletes_device_subscription() -> None:
    user = User.objects.create_user()
    client, device = _authenticated_web_client(user)
    url = reverse("reminders:web-push")

    unavailable_client = APIClient()
    assert unavailable_client.get(url).status_code in {401, 403}
    created = client.put(
        url,
        _subscription_payload(prayer_location={"latitude": "41.008200", "longitude": "28.978400"}),
        format="json",
    )
    status_response = client.get(url)

    assert created.status_code == 200
    assert created.json() == {
        "available": True,
        "enabled": True,
        "vapid_public_key": "public-test-key",
        "timezone_name": "Europe/Istanbul",
        "locale": "ru",
        "prayer_location_configured": True,
        "prayer_profile_configured": False,
        "supported_reminder_types": ["prayer", "quran_reading", "quran_review"],
    }
    assert "endpoint" not in created.json()
    assert status_response.json() == created.json()
    assert created.headers["Cache-Control"] == PRIVATE_NO_STORE_CACHE_CONTROL
    subscription = WebPushSubscription.objects.get(device=device)
    assert subscription.locale == "ru"
    assert subscription.endpoint.endswith("secret-capability")
    assert subscription.prayer_latitude == Decimal("41.008200")
    assert subscription.prayer_longitude == Decimal("28.978400")

    deleted = client.delete(url)

    assert deleted.status_code == 204
    assert not WebPushSubscription.objects.filter(device=device).exists()


@pytest.mark.django_db
@override_settings(**PUSH_SETTINGS)
def test_web_push_api_rejects_untrusted_endpoint_and_malformed_keys() -> None:
    user = User.objects.create_user()
    client, _device = _authenticated_web_client(user)
    url = reverse("reminders:web-push")

    endpoint_response = client.put(
        url,
        _subscription_payload(endpoint="https://127.0.0.1/internal"),
        format="json",
    )
    key_response = client.put(
        url,
        _subscription_payload(keys={"p256dh": "invalid", "auth": "invalid"}),
        format="json",
    )

    assert endpoint_response.status_code == 400
    assert "endpoint" in endpoint_response.json()["field_errors"]
    assert key_response.status_code == 400
    assert WebPushSubscription.objects.count() == 0


@pytest.mark.django_db
def test_logout_removes_the_device_push_capability() -> None:
    user = User.objects.create_user()
    client, device = _authenticated_web_client(user)
    _subscription(device)

    response = client.post(reverse("accounts:logout"), format="json")

    assert response.status_code == 204
    assert not WebPushSubscription.objects.filter(device=device).exists()


@pytest.mark.django_db
def test_next_occurrence_resolves_dst_gap_and_fold_once() -> None:
    user = User.objects.create_user()
    _client, device = _authenticated_web_client(user)
    subscription = _subscription(device, timezone_name="Europe/Berlin")
    rule = _reading_rule(
        user,
        local_time=time(2, 30),
        timezone_mode="fixed",
        timezone_name="Europe/Berlin",
        weekdays_mask=1 << 6,
    )

    gap = next_local_occurrence(
        rule,
        subscription,
        after=datetime(2026, 3, 28, 12, tzinfo=UTC),
    )
    fold = next_local_occurrence(
        rule,
        subscription,
        after=datetime(2026, 10, 24, 12, tzinfo=UTC),
    )

    assert gap == datetime(2026, 3, 29, 1, 0, tzinfo=UTC)
    assert fold == datetime(2026, 10, 25, 0, 30, tzinfo=UTC)


@pytest.mark.django_db
def test_refresh_builds_indexed_schedules_for_quran_and_prayer_rules() -> None:
    user = User.objects.create_user()
    _client, device = _authenticated_web_client(user)
    _prayer_profile(user)
    subscription = _subscription(
        device,
        timezone_name="Europe/Istanbul",
        prayer_latitude=Decimal("41.008200"),
        prayer_longitude=Decimal("28.978400"),
    )
    reading = _reading_rule(user, local_time=time(8, 0))
    prayer = ReminderRule.objects.create(
        user=user,
        reminder_type=ReminderType.PRAYER,
        prayer_event="fajr",
        prayer_offset_minutes=0,
        client_updated_at=timezone.now(),
    )

    refresh_subscription_schedules(
        subscription.id,
        now=datetime(2026, 8, 26, 0, 0, tzinfo=UTC),
    )

    schedules = {schedule.reminder_id: schedule for schedule in WebPushSchedule.objects.all()}
    assert set(schedules) == {reading.id, prayer.id}
    assert schedules[reading.id].occurrence_at == datetime(2026, 8, 26, 5, 0, tzinfo=UTC)
    assert datetime(2026, 8, 26, 0, 0, tzinfo=UTC) < schedules[prayer.id].occurrence_at
    assert schedules[prayer.id].occurrence_at < datetime(2026, 8, 27, 0, 0, tzinfo=UTC)
    assert all(
        schedule.next_attempt_at == schedule.occurrence_at for schedule in schedules.values()
    )


@pytest.mark.django_db
@override_settings(**PUSH_SETTINGS)
def test_claim_and_successful_delivery_advance_schedule(monkeypatch: pytest.MonkeyPatch) -> None:
    user = User.objects.create_user()
    _client, device = _authenticated_web_client(user)
    subscription = _subscription(device, timezone_name="UTC")
    current_time = timezone.now()
    occurrence = current_time - timedelta(seconds=1)
    rule = _reading_rule(
        user,
        local_time=occurrence.time().replace(microsecond=0, tzinfo=None),
    )
    schedule = WebPushSchedule.objects.create(
        subscription=subscription,
        reminder=rule,
        occurrence_at=occurrence,
        next_attempt_at=occurrence,
    )
    captured: dict[str, Any] = {}

    def fake_webpush(**kwargs: Any) -> Mock:
        captured.update(kwargs)
        return Mock(status_code=201)

    monkeypatch.setattr("quran_backend.modules.reminders.push.webpush", fake_webpush)
    claimed = claim_due_web_push_schedules(now=occurrence + timedelta(seconds=1))
    result = deliver_claimed_web_push_schedule(
        schedule_id=claimed[0].schedule_id,
        claim_token=claimed[0].claim_token,
    )

    assert result == "delivered"
    payload = json.loads(captured["data"])
    assert payload["title"] == "Время читать Коран"
    assert payload["url"] == "/ru/quran"
    assert "secret-capability" in captured["subscription_info"]["endpoint"]
    schedule.refresh_from_db()
    subscription.refresh_from_db()
    assert current_time + timedelta(hours=23) < schedule.occurrence_at
    assert schedule.occurrence_at < current_time + timedelta(hours=25)
    assert schedule.claim_token is None
    assert subscription.consecutive_failures == 0
    assert subscription.last_success_at is not None


@pytest.mark.django_db
@override_settings(**PUSH_SETTINGS)
def test_review_notification_links_to_the_first_ayah(
    monkeypatch: pytest.MonkeyPatch,
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    _client, device = _authenticated_web_client(user)
    subscription = _subscription(device, timezone_name="UTC")
    occurrence = timezone.now() - timedelta(seconds=1)
    rule = ReminderRule.objects.create(
        user=user,
        reminder_type=ReminderType.QURAN_REVIEW,
        local_time=occurrence.time().replace(microsecond=0, tzinfo=None),
        start_ayah=quran_dataset["first_ayah"],
        end_ayah=quran_dataset["second_ayah"],
        client_updated_at=timezone.now(),
    )
    WebPushSchedule.objects.create(
        subscription=subscription,
        reminder=rule,
        occurrence_at=occurrence,
        next_attempt_at=occurrence,
    )
    captured: dict[str, Any] = {}

    def fake_webpush(**kwargs: Any) -> Mock:
        captured.update(kwargs)
        return Mock(status_code=201)

    monkeypatch.setattr("quran_backend.modules.reminders.push.webpush", fake_webpush)
    claimed = claim_due_web_push_schedules(now=occurrence + timedelta(seconds=1))

    result = deliver_claimed_web_push_schedule(
        schedule_id=claimed[0].schedule_id,
        claim_token=claimed[0].claim_token,
    )

    assert result == "delivered"
    payload = json.loads(captured["data"])
    assert payload["url"] == "/ru/quran?surah=1&ayah=1"


@pytest.mark.django_db
@override_settings(**PUSH_SETTINGS)
def test_gone_push_endpoint_is_deleted(monkeypatch: pytest.MonkeyPatch) -> None:
    user = User.objects.create_user()
    _client, device = _authenticated_web_client(user)
    subscription = _subscription(device, timezone_name="UTC")
    rule = _reading_rule(user, local_time=time(8, 0))
    occurrence = timezone.now() - timedelta(seconds=1)
    schedule = WebPushSchedule.objects.create(
        subscription=subscription,
        reminder=rule,
        occurrence_at=occurrence,
        next_attempt_at=occurrence,
    )
    response = Mock(status_code=410)

    def gone(**_kwargs: Any) -> None:
        raise WebPushException("gone", response=response)

    monkeypatch.setattr("quran_backend.modules.reminders.push.webpush", gone)
    claimed = claim_due_web_push_schedules()
    result = deliver_claimed_web_push_schedule(
        schedule_id=claimed[0].schedule_id,
        claim_token=claimed[0].claim_token,
    )

    assert result == "subscription_expired"
    assert not WebPushSubscription.objects.filter(id=subscription.id).exists()
    assert not WebPushSchedule.objects.filter(id=schedule.id).exists()


@pytest.mark.django_db
@override_settings(**PUSH_SETTINGS, WEB_PUSH_RETRY_WINDOW_SECONDS=900)
def test_stale_occurrence_is_skipped_instead_of_burst_delivered(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    user = User.objects.create_user()
    _client, device = _authenticated_web_client(user)
    subscription = _subscription(device, timezone_name="UTC")
    rule = _reading_rule(user, local_time=time(8, 0))
    occurrence = timezone.now() - timedelta(days=2)
    schedule = WebPushSchedule.objects.create(
        subscription=subscription,
        reminder=rule,
        occurrence_at=occurrence,
        next_attempt_at=occurrence,
    )
    sender = Mock()
    monkeypatch.setattr("quran_backend.modules.reminders.push.webpush", sender)

    claimed = claim_due_web_push_schedules()
    result = deliver_claimed_web_push_schedule(
        schedule_id=claimed[0].schedule_id,
        claim_token=claimed[0].claim_token,
    )

    assert result == "expired"
    sender.assert_not_called()
    schedule.refresh_from_db()
    assert schedule.occurrence_at > timezone.now()
    assert schedule.last_error_code == "expired"


@pytest.mark.django_db
@override_settings(**PUSH_SETTINGS)
def test_transport_error_is_bounded_for_database_retry(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    user = User.objects.create_user()
    _client, device = _authenticated_web_client(user)
    subscription = _subscription(device, timezone_name="UTC")
    current_time = timezone.now()
    occurrence = current_time - timedelta(seconds=1)
    rule = _reading_rule(
        user,
        local_time=occurrence.time().replace(microsecond=0, tzinfo=None),
    )
    schedule = WebPushSchedule.objects.create(
        subscription=subscription,
        reminder=rule,
        occurrence_at=occurrence,
        next_attempt_at=occurrence,
    )

    def fail_transport(**_kwargs: Any) -> None:
        raise OSError("network unavailable")

    monkeypatch.setattr("quran_backend.modules.reminders.push.webpush", fail_transport)
    claimed = claim_due_web_push_schedules()
    result = deliver_claimed_web_push_schedule(
        schedule_id=claimed[0].schedule_id,
        claim_token=claimed[0].claim_token,
    )

    assert result == "retry"
    schedule.refresh_from_db()
    subscription.refresh_from_db()
    assert schedule.claim_token is None
    assert schedule.attempt_count == 1
    assert schedule.last_error_code == "transport"
    assert subscription.consecutive_failures == 1


def test_celery_beat_dispatches_web_push_frequently() -> None:
    assert settings.CELERY_BEAT_SCHEDULE["dispatch-web-push-reminders-every-30-seconds"] == {
        "task": "reminders.dispatch_web_push_due",
        "schedule": 30.0,
    }
