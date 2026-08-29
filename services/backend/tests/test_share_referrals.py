# ruff: noqa: RUF001
from __future__ import annotations

import uuid
from datetime import timedelta
from urllib.parse import parse_qs, urlsplit

import pytest
from django.contrib import admin
from django.core.exceptions import ValidationError
from django.test import RequestFactory
from django.urls import reverse
from django.utils import timezone
from drf_spectacular.generators import SchemaGenerator
from rest_framework.test import APIClient

from quran_backend.modules.accounts.models import User, UserStatus
from quran_backend.modules.share_referrals.admin import (
    ReferralClickAdmin,
    ReferralQualificationAdmin,
    ReferralRewardAdmin,
    ReferralRewardAuditAdmin,
    ShareEventAdmin,
)
from quran_backend.modules.share_referrals.exceptions import ReferralConflict
from quran_backend.modules.share_referrals.models import (
    AttributionSource,
    ReferralClick,
    ReferralLink,
    ReferralQualification,
    ReferralReward,
    ReferralRewardAudit,
    ShareCampaign,
    ShareCampaignCopy,
    ShareEvent,
)
from quran_backend.modules.share_referrals.services import (
    approve_reward,
    qualify_referral,
    record_referral_attribution,
    reverse_qualification,
    revoke_referral_link,
)


def _verified(email: str) -> User:
    return User.objects.create_user(email=email, status=UserStatus.ACTIVE)


def _client(user: User) -> APIClient:
    client = APIClient()
    client.force_authenticate(user=user)
    return client


@pytest.fixture
def share_campaign(db: None) -> ShareCampaign:
    campaign = ShareCampaign.objects.create(
        key="app-invite",
        internal_name="Основная кампания",
        is_active=True,
        canonical_download_url="https://iqro.example/download?source=app",
        ios_url="https://apps.apple.com/app/iqro/id123",
        android_url="https://play.google.com/store/apps/details?id=example.iqro",
        short_link_base_url="https://iqro.example/r",
        referral_enabled=True,
        reward_points=25,
    )
    ShareCampaignCopy.objects.create(
        campaign=campaign,
        locale="en",
        title="Read Quran with IQRO",
        message="Join me in IQRO.",
        cta_label="Share",
    )
    ShareCampaignCopy.objects.create(
        campaign=campaign,
        locale="ru",
        title="Читайте Коран вместе с IQRO",
        message="Присоединяйтесь ко мне в IQRO.",
        cta_label="Поделиться",
    )
    campaign.refresh_from_db()
    return campaign


@pytest.mark.django_db
def test_public_config_localizes_and_signals_bundled_fallback(
    api_client: APIClient,
    share_campaign: ShareCampaign,
) -> None:
    ru = api_client.get(reverse("share-referrals:share-config"), {"locale": "ru"})
    tr = api_client.get(reverse("share-referrals:share-config"), {"locale": "tr"})
    unknown = api_client.get(reverse("share-referrals:share-config"), {"locale": "de"})

    assert ru.status_code == 200
    assert ru.json()["campaign"]["title"] == "Читайте Коран вместе с IQRO"
    assert ru.json()["used_fallback"] is False
    assert tr.json()["campaign"]["locale"] == "en"
    assert tr.json()["used_fallback"] is True
    assert unknown.json()["requested_locale"] == "de"
    assert unknown.json()["campaign"]["locale"] == "en"
    assert unknown["Cache-Control"].startswith("public")
    assert "ETag" in unknown

    share_campaign.is_active = False
    share_campaign.save()
    unavailable = api_client.get(reverse("share-referrals:share-config"), {"locale": "ru"})
    assert unavailable.status_code == 200
    assert unavailable.json() == {
        "available": False,
        "fallback_reason": "no_active_localized_campaign",
        "requested_locale": "ru",
        "used_fallback": True,
        "campaign": None,
    }


@pytest.mark.django_db
def test_copy_update_increments_remote_config_version(share_campaign: ShareCampaign) -> None:
    before = share_campaign.config_version
    copy = share_campaign.localized_copies.get(locale="ru")
    copy.message = "Новый текст без релиза клиента."
    copy.save()
    share_campaign.refresh_from_db()
    assert share_campaign.config_version == before + 1


@pytest.mark.django_db
def test_referral_link_requires_verified_account_and_is_idempotent(
    share_campaign: ShareCampaign,
) -> None:
    guest = User.objects.create_user()
    guest_response = _client(guest).post(
        reverse("share-referrals:my-referral-link"),
        {"campaign_key": share_campaign.key},
        format="json",
    )
    assert guest_response.status_code == 403
    assert guest_response.json()["code"] == "verified_account_required"

    owner = _verified("owner@example.com")
    client = _client(owner)
    first = client.post(
        reverse("share-referrals:my-referral-link"),
        {"campaign_key": share_campaign.key},
        format="json",
    )
    retry = client.post(
        reverse("share-referrals:my-referral-link"),
        {"campaign_key": share_campaign.key},
        format="json",
    )

    assert first.status_code == 201
    assert retry.status_code == 200
    assert retry.json() == first.json()
    assert owner.email not in first.json()["code"]
    assert first.json()["short_url"].startswith("https://iqro.example/r/")
    assert ReferralLink.objects.filter(owner=owner, campaign=share_campaign).count() == 1


@pytest.mark.django_db
def test_event_ingestion_is_allowlisted_idempotent_and_never_creates_rewards(
    share_campaign: ShareCampaign,
) -> None:
    guest = User.objects.create_user()
    client = _client(guest)
    event_id = uuid.uuid7()
    payload = {
        "client_event_id": str(event_id),
        "campaign_key": share_campaign.key,
        "action": "share_completed",
        "result": "succeeded",
        "channel": "system",
        "occurred_at": timezone.now().isoformat(),
        "metadata": {"app_version": "1.2.0", "platform": "android"},
    }
    url = reverse("share-referrals:share-event-create")
    first = client.post(url, payload, format="json")
    retry = client.post(url, payload, format="json")
    conflict = client.post(url, {**payload, "result": "failed"}, format="json")
    bad_metadata = client.post(
        url,
        {**payload, "client_event_id": str(uuid.uuid7()), "metadata": {"email": "x@y.z"}},
        format="json",
    )

    assert first.status_code == 201
    assert retry.status_code == 200
    assert retry.json()["replayed"] is True
    assert conflict.status_code == 409
    assert conflict.json()["code"] == "share_event_conflict"
    assert bad_metadata.status_code == 400
    assert ShareEvent.objects.count() == 1
    assert ReferralReward.objects.count() == 0


@pytest.mark.django_db
@pytest.mark.parametrize(
    "case",
    [
        ("open-system-share", "shared", "share_sheet_opened", "succeeded", "system"),
        ("copy-link", "copied", "link_copied", "succeeded", "copy"),
        ("copy-code", "unavailable", "referral_code_copied", "failed", "copy"),
    ],
)
def test_event_api_accepts_mobile_gateway_envelope_and_maps_canonical_values(
    share_campaign: ShareCampaign,
    case: tuple[str, str, str, str, str],
) -> None:
    action, result, stored_action, stored_result, stored_channel = case
    guest = User.objects.create_user()
    event_id = uuid.uuid7()
    response = _client(guest).post(
        reverse("share-referrals:share-event-create"),
        {
            "eventId": str(event_id),
            "campaignId": share_campaign.key,
            "action": action,
            "result": result,
            "occurredAt": timezone.now().isoformat(),
            "accountMode": "verified",  # Deliberate lie: auth remains authoritative.
        },
        format="json",
    )

    assert response.status_code == 201
    event = ShareEvent.objects.get(client_event_id=event_id)
    assert event.action == stored_action
    assert event.result == stored_result
    assert event.channel == stored_channel
    assert event.account_mode == "guest"


@pytest.mark.django_db
def test_redirect_uses_only_server_url_and_rejects_revoked_link(
    share_campaign: ShareCampaign,
) -> None:
    owner = _verified("owner@example.com")
    operator = User.objects.create_superuser("ops@example.com")
    link = ReferralLink.objects.create(campaign=share_campaign, owner=owner)
    url = reverse("share-referrals:referral-redirect", kwargs={"code": link.code})

    response = APIClient().get(
        url,
        {"channel": "telegram", "next": "https://evil.example/steal"},
    )
    assert response.status_code == 302
    parsed = urlsplit(response["Location"])
    assert parsed.hostname == "iqro.example"
    assert parsed.path == "/download"
    assert parse_qs(parsed.query) == {
        "source": ["app"],
        "referral_code": [link.code],
        "campaign": [share_campaign.key],
    }
    assert ReferralClick.objects.get().channel == "telegram"

    revoke_referral_link(link.id, actor=operator, reason="Abuse review")
    revoked = APIClient().get(url)
    assert revoked.status_code == 404
    assert ReferralClick.objects.count() == 1


@pytest.mark.django_db
def test_expired_campaign_redirect_is_unavailable(share_campaign: ShareCampaign) -> None:
    owner = _verified("owner@example.com")
    link = ReferralLink.objects.create(campaign=share_campaign, owner=owner)
    share_campaign.ends_at = timezone.now() - timedelta(seconds=1)
    share_campaign.save()

    response = APIClient().get(
        reverse("share-referrals:referral-redirect", kwargs={"code": link.code})
    )
    assert response.status_code == 404
    assert ReferralClick.objects.count() == 0


@pytest.mark.django_db
def test_attribution_qualification_reward_and_summary_are_idempotent_and_private(
    share_campaign: ShareCampaign,
) -> None:
    owner = _verified("owner@example.com")
    invitee = _verified("invitee@example.com")
    operator = User.objects.create_superuser("ops@example.com")
    link = ReferralLink.objects.create(campaign=share_campaign, owner=owner)
    key = uuid.uuid7()

    attribution, created = record_referral_attribution(
        link=link,
        invitee=invitee,
        idempotency_key=key,
        source=AttributionSource.SIGNUP_HOOK,
    )
    replay, replay_created = record_referral_attribution(
        link=link,
        invitee=invitee,
        idempotency_key=key,
        source=AttributionSource.SIGNUP_HOOK,
    )
    qualification = attribution.qualification
    qualification, reward = qualify_referral(
        qualification.id,
        actor=operator,
        reason="Verified account age and anti-abuse review passed.",
    )
    _qualification_retry, reward_retry = qualify_referral(
        qualification.id,
        actor=operator,
        reason="Retry",
    )
    assert created is True
    assert replay_created is False
    assert replay.id == attribution.id
    assert reward is not None
    assert reward_retry is not None
    assert reward_retry.id == reward.id
    assert ReferralReward.objects.count() == 1
    assert ReferralRewardAudit.objects.count() == 1

    approve_reward(reward.id, actor=operator, reason="Approved after qualification")
    approve_reward(reward.id, actor=operator, reason="Retry")
    summary = _client(owner).get(
        reverse("share-referrals:my-referral-summary"),
        {"campaign": share_campaign.key},
    )
    assert summary.status_code == 200
    assert summary.json() == {
        "campaign_key": share_campaign.key,
        "invited": 1,
        "qualified": 1,
        "reward_balance": 25,
        "pending_reward": 0,
    }
    assert invitee.email not in summary.content.decode()
    assert ReferralRewardAudit.objects.count() == 2

    reversed_qualification = reverse_qualification(
        qualification.id,
        actor=operator,
        reason="Confirmed abuse case",
    )
    reverse_qualification(
        qualification.id,
        actor=operator,
        reason="Retry",
    )
    reward.refresh_from_db()
    assert reversed_qualification.status == "reversed"
    assert reward.status == "reversed"
    assert ReferralRewardAudit.objects.count() == 3
    reversed_summary = _client(owner).get(
        reverse("share-referrals:my-referral-summary"),
        {"campaign": share_campaign.key},
    )
    assert reversed_summary.json()["qualified"] == 0
    assert reversed_summary.json()["reward_balance"] == 0


@pytest.mark.django_db
def test_self_referral_and_untrusted_campaign_urls_are_rejected(
    share_campaign: ShareCampaign,
) -> None:
    owner = _verified("owner@example.com")
    link = ReferralLink.objects.create(campaign=share_campaign, owner=owner)
    with pytest.raises(ReferralConflict) as self_referral:
        record_referral_attribution(
            link=link,
            invitee=owner,
            idempotency_key=uuid.uuid7(),
            source=AttributionSource.SIGNUP_HOOK,
        )
    assert "Self-referrals" in str(self_referral.value)

    invalid = ShareCampaign(
        key="unsafe",
        internal_name="Unsafe",
        canonical_download_url="https://user:password@evil.example/download#fragment",
    )
    with pytest.raises(ValidationError):
        invalid.full_clean()

    invalid_short_base = ShareCampaign(
        key="unsafe-short",
        internal_name="Unsafe short base",
        canonical_download_url="https://iqro.example/download",
        short_link_base_url="https://iqro.example/r?next=https://evil.example",
    )
    with pytest.raises(ValidationError):
        invalid_short_base.full_clean()


@pytest.mark.django_db
def test_admin_registers_operational_models_and_keeps_history_read_only() -> None:
    request = RequestFactory().get("/admin/")
    request.user = User.objects.create_superuser("admin@example.com")

    immutable_models = {
        ShareEvent: ShareEventAdmin,
        ReferralClick: ReferralClickAdmin,
        ReferralRewardAudit: ReferralRewardAuditAdmin,
    }
    for model, model_admin_type in immutable_models.items():
        model_admin = admin.site._registry[model]
        assert isinstance(model_admin, model_admin_type)
        assert model_admin.has_add_permission(request) is False
        assert model_admin.has_delete_permission(request) is False
        assert {field.name for field in model._meta.fields} <= set(model_admin.readonly_fields)

    qualification_admin = admin.site._registry[ReferralQualification]
    reward_admin = admin.site._registry[ReferralReward]
    assert isinstance(qualification_admin, ReferralQualificationAdmin)
    assert isinstance(reward_admin, ReferralRewardAdmin)
    assert qualification_admin.has_add_permission(request) is False
    assert reward_admin.has_add_permission(request) is False
    assert "qualify_selected" in qualification_admin.actions
    assert "reverse_selected" in qualification_admin.actions
    assert "approve_selected" in reward_admin.actions
    assert "reverse_selected" in reward_admin.actions


def test_openapi_includes_share_referral_contracts() -> None:
    schema = SchemaGenerator().get_schema(public=True)  # type: ignore[no-untyped-call]
    assert schema is not None
    assert set(schema["paths"]["/api/v1/share/config"]) == {"get"}
    assert set(schema["paths"]["/api/v1/share/events"]) == {"post"}
    assert set(schema["paths"]["/api/v1/me/referrals/links"]) == {"post"}
    assert set(schema["paths"]["/api/v1/me/referrals/summary"]) == {"get"}
    assert set(schema["paths"]["/r/{code}"]) == {"get"}
    assert "302" in schema["paths"]["/r/{code}"]["get"]["responses"]
    event_request = schema["paths"]["/api/v1/share/events"]["post"]["requestBody"]
    assert "application/json" in event_request["content"]
