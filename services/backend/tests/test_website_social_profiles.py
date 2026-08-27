from __future__ import annotations

from typing import Any

import pytest
from django.contrib import admin
from django.core.exceptions import ValidationError
from django.test import RequestFactory

from quran_backend.modules.website.admin import SocialProfileAdmin
from quran_backend.modules.website.models import SocialPlatform, SocialProfile


@pytest.mark.django_db
def test_social_profile_normalizes_text_and_requires_the_platform_domain() -> None:
    profile = SocialProfile.objects.create(
        platform=SocialPlatform.TELEGRAM,
        profile_url="  https://t.me/iqro_forum  ",
        display_name="  @iqro_forum  ",
        sort_order=10,
    )

    assert profile.profile_url == "https://t.me/iqro_forum"
    assert profile.display_name == "@iqro_forum"

    invalid_urls = (
        "http://t.me/iqro_forum",
        "https://example.com/iqro_forum",
        "https://user:password@t.me/iqro_forum",
        "https://t.me:8443/iqro_forum",
    )
    for url in invalid_urls:
        with pytest.raises(ValidationError, match="profile_url"):
            SocialProfile(
                platform=SocialPlatform.TELEGRAM,
                profile_url=url,
            ).save()


@pytest.mark.django_db
def test_empty_social_profile_is_automatically_hidden() -> None:
    profile = SocialProfile.objects.create(
        platform=SocialPlatform.YOUTUBE,
        profile_url="",
        is_active=True,
    )

    assert profile.is_active is False


@pytest.mark.django_db
def test_social_profile_platform_is_unique() -> None:
    SocialProfile.objects.create(
        platform=SocialPlatform.INSTAGRAM,
        profile_url="https://www.instagram.com/iqro",
    )

    with pytest.raises(ValidationError, match="platform"):
        SocialProfile(
            platform=SocialPlatform.INSTAGRAM,
            profile_url="https://instagram.com/another",
        ).save()


@pytest.mark.django_db
def test_public_social_profile_api_returns_only_active_rows_in_display_order(
    api_client: Any,
) -> None:
    SocialProfile.objects.create(
        platform=SocialPlatform.TELEGRAM,
        profile_url="https://t.me/iqro_forum",
        display_name="@iqro_forum",
        sort_order=20,
    )
    SocialProfile.objects.create(
        platform=SocialPlatform.YOUTUBE,
        profile_url="https://www.youtube.com/@iqro",
        display_name="IQRO",
        sort_order=10,
        include_in_seo=False,
    )
    SocialProfile.objects.create(
        platform=SocialPlatform.FACEBOOK,
        profile_url="https://facebook.com/iqro",
        sort_order=1,
        is_active=False,
    )

    response = api_client.get("/api/v1/site/social-profiles")

    assert response.status_code == 200
    assert response.headers["Cache-Control"] == "public, max-age=300, stale-while-revalidate=86400"
    assert response.headers["ETag"].startswith('W/"')
    assert response.json() == [
        {
            "platform": "youtube",
            "platform_name": "YouTube",
            "display_name": "IQRO",
            "url": "https://www.youtube.com/@iqro",
            "sort_order": 10,
            "include_in_seo": False,
        },
        {
            "platform": "telegram",
            "platform_name": "Telegram",
            "display_name": "@iqro_forum",
            "url": "https://t.me/iqro_forum",
            "sort_order": 20,
            "include_in_seo": True,
        },
    ]

    cached = api_client.get(
        "/api/v1/site/social-profiles",
        HTTP_IF_NONE_MATCH=response.headers["ETag"],
    )
    assert cached.status_code == 304


@pytest.mark.django_db
def test_social_profile_admin_revalidates_public_clients(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    events: list[str] = []
    monkeypatch.setattr(
        "quran_backend.modules.website.admin.enqueue_social_profiles_change",
        lambda *, action: events.append(action),
    )
    model_admin = SocialProfileAdmin(SocialProfile, admin.site)
    request = RequestFactory().post("/admin/website/socialprofile/add/")
    profile = SocialProfile(
        platform=SocialPlatform.VK,
        profile_url="https://vk.com/iqro",
    )

    model_admin.save_model(request, profile, form=None, change=False)
    profile.display_name = "IQRO"
    model_admin.save_model(request, profile, form=None, change=True)
    model_admin.delete_model(request, profile)

    assert events == ["created", "updated", "deleted"]


def test_social_profile_admin_is_registered_with_operator_controls() -> None:
    model_admin = admin.site._registry[SocialProfile]

    assert isinstance(model_admin, SocialProfileAdmin)
    assert model_admin.list_editable == ("is_active", "include_in_seo", "sort_order")
