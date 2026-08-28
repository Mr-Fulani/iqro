from __future__ import annotations

import uuid
from datetime import timedelta

import pytest
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from quran_backend.modules.accounts.merge import merge_guest_into_account
from quran_backend.modules.accounts.models import (
    AuthIdentity,
    Device,
    DevicePlatform,
    IdentityProvider,
    User,
    UserStatus,
)
from quran_backend.modules.reading.models import QuranReaderPreference

pytestmark = pytest.mark.django_db


def _authenticated_client(user: User) -> APIClient:
    client = APIClient()
    client.force_authenticate(user=user)
    return client


def _url(locale: str = "ru") -> str:
    return reverse("reading:quran-reader-preference", kwargs={"locale": locale})


def _payload(*, base_revision: int, translation_id: int = 45) -> dict[str, object]:
    return {
        "base_revision": base_revision,
        "translation_enabled": True,
        "translation_source_id": translation_id,
        "tafsir_enabled": True,
        "tafsir_source_id": 170,
        "client_updated_at": timezone.now().isoformat(),
    }


def test_reader_preference_default_create_update_and_locale_isolation() -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)

    default = client.get(_url("ru"))
    created = client.put(_url("ru"), _payload(base_revision=0), format="json")
    idempotent = client.put(_url("ru"), _payload(base_revision=0), format="json")
    updated = client.put(
        _url("ru"),
        {**_payload(base_revision=1), "tafsir_enabled": False},
        format="json",
    )
    english = client.get(_url("en"))

    assert default.status_code == 200
    assert default.json()["revision"] == 0
    assert default.json()["id"] is None
    assert default["Cache-Control"] == "private, no-store, max-age=0"
    assert created.status_code == 200
    assert created.json()["revision"] == 1
    assert created.json()["translation_source_id"] == 45
    assert idempotent.status_code == 200
    assert idempotent.json()["revision"] == 1
    assert updated.status_code == 200
    assert updated.json()["revision"] == 2
    assert updated.json()["tafsir_enabled"] is False
    assert english.json()["revision"] == 0


def test_reader_preference_rejects_stale_revision_and_enabled_without_source() -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    client.put(_url(), _payload(base_revision=0), format="json")

    stale = client.put(
        _url(),
        {**_payload(base_revision=0), "translation_source_id": 20},
        format="json",
    )
    invalid = client.put(
        _url("tr"),
        {
            **_payload(base_revision=0),
            "translation_enabled": False,
            "translation_source_id": None,
            "tafsir_source_id": None,
        },
        format="json",
    )

    assert stale.status_code == 409
    assert stale.json()["code"] == "quran_reader_preference_revision_conflict"
    assert invalid.status_code == 400
    assert "tafsir_source_id" in invalid.json()["field_errors"]


def test_guest_merge_keeps_newest_reader_preference_per_locale() -> None:
    now = timezone.now()
    guest = User.objects.create_user(status=UserStatus.GUEST)
    target = User.objects.create_user(email="reader@example.com", status=UserStatus.ACTIVE)
    identity = AuthIdentity.objects.create(
        user=target,
        provider=IdentityProvider.EMAIL,
        provider_subject="reader@example.com",
        email_at_provider="reader@example.com",
        email_verified=True,
    )
    guest_device = Device.objects.create(
        user=guest,
        platform=DevicePlatform.WEB,
        installation_id_hash="a" * 64,
        locale="ru",
    )
    QuranReaderPreference.objects.create(
        user=target,
        locale="ru",
        translation_enabled=True,
        translation_source_id=20,
        tafsir_enabled=False,
        tafsir_source_id=169,
        client_updated_at=now - timedelta(hours=1),
        revision=3,
    )
    QuranReaderPreference.objects.create(
        user=guest,
        locale="ru",
        translation_enabled=True,
        translation_source_id=45,
        tafsir_enabled=True,
        tafsir_source_id=170,
        client_updated_at=now,
        revision=2,
        device=guest_device,
    )

    result = merge_guest_into_account(
        source_user=guest,
        target_user=target,
        trigger_identity=identity,
        idempotency_key=uuid.uuid4(),
    )

    preference = QuranReaderPreference.objects.get(user=target, locale="ru")
    assert result.moved_counts["quran_reader_preferences"] == 1
    assert preference.translation_source_id == 45
    assert preference.tafsir_enabled is True
    assert preference.tafsir_source_id == 170
    assert preference.revision == 4
    assert preference.device_id == guest_device.id
    assert not QuranReaderPreference.objects.filter(user=guest).exists()
