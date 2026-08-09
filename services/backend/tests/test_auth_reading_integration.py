from __future__ import annotations

from typing import Any
from uuid import uuid4

import pytest
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient


@pytest.mark.django_db
def test_guest_credentials_bind_reading_state_to_authenticated_device(
    api_client: APIClient,
    quran_dataset: dict[str, Any],
) -> None:
    bootstrap = api_client.post(
        reverse("accounts:guest-bootstrap"),
        {
            "installation_id": str(uuid4()),
            "installation_credential": "C" * 43,
            "platform": "android",
            "locale": "ru",
            "app_version": "1.0.0",
        },
        format="json",
    )
    assert bootstrap.status_code == 200
    credentials = bootstrap.json()
    api_client.credentials(HTTP_AUTHORIZATION=f"Bearer {credentials['access_token']}")

    now = timezone.now().isoformat()
    position_url = reverse(
        "reading:reading-position",
        kwargs={"edition": "madani-hafs"},
    )
    saved = api_client.put(
        position_url,
        {
            "base_revision": 0,
            "page_number": 1,
            "surah_number": 1,
            "ayah_number": 1,
            "progress_percent": "0.16",
            "last_read_at": now,
            "client_updated_at": now,
        },
        format="json",
    )

    assert saved.status_code == 200
    assert saved.json()["device_id"] == credentials["device"]["id"]
    assert saved["Cache-Control"] == "private, no-store, max-age=0"

    logout = api_client.post(reverse("accounts:logout"), format="json")
    rejected = api_client.get(position_url)

    assert logout.status_code == 204
    assert rejected.status_code == 401
    assert rejected.json()["code"] == "access_token_invalid"
