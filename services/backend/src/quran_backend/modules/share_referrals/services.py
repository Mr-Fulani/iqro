from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import timedelta
from typing import Any
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from django.db import IntegrityError, transaction
from django.db.models import Q, Sum
from django.utils import timezone

from quran_backend.modules.accounts.models import User, UserStatus
from quran_backend.modules.share_referrals.exceptions import (
    ReferralConflict,
    ReferralLinkUnavailable,
    ShareCampaignUnavailable,
    ShareEventConflict,
    VerifiedAccountRequired,
)
from quran_backend.modules.share_referrals.models import (
    AccountMode,
    AttributionSource,
    QualificationStatus,
    ReferralAttribution,
    ReferralClick,
    ReferralLink,
    ReferralQualification,
    ReferralReward,
    ReferralRewardAudit,
    RewardAuditAction,
    RewardStatus,
    ShareCampaign,
    ShareCampaignCopy,
    ShareEvent,
)
from quran_backend.modules.share_referrals.selectors import select_available_campaign

EVENT_METADATA_KEYS = frozenset(
    {"app_version", "app_build", "platform", "os_major", "source_screen"}
)


@dataclass(frozen=True)
class LocalizedCampaign:
    campaign: ShareCampaign
    copy: ShareCampaignCopy
    requested_locale: str
    used_fallback: bool


def localized_campaign(key: str | None, locale: str) -> LocalizedCampaign | None:
    campaign = select_available_campaign(key)
    if campaign is None:
        return None
    requested = locale
    lookup_locale = locale if locale in {"ar", "en", "ru", "tr"} else "en"
    copies = {copy.locale: copy for copy in campaign.localized_copies.all()}
    selected = copies.get(lookup_locale) or copies.get("en")
    if selected is None and copies:
        selected = copies[sorted(copies)[0]]
    if selected is None:
        return None
    return LocalizedCampaign(
        campaign=campaign,
        copy=selected,
        requested_locale=requested,
        used_fallback=selected.locale != requested,
    )


def require_verified_account(user: User) -> None:
    if not user.is_active or user.status != UserStatus.ACTIVE:
        raise VerifiedAccountRequired


def _require_staff_actor(actor: User) -> None:
    if not actor.is_active or not actor.is_staff:
        raise ReferralConflict("A staff operator is required for this transition.")


@transaction.atomic
def get_or_create_referral_link(user: User, campaign_key: str) -> tuple[ReferralLink, bool]:
    require_verified_account(user)
    campaign = ShareCampaign.objects.filter(key=campaign_key.strip().lower()).first()
    if campaign is None or not campaign.referral_enabled or not campaign.is_available_at():
        raise ShareCampaignUnavailable

    existing = (
        ReferralLink.objects.select_for_update()
        .filter(
            campaign=campaign,
            owner=user,
        )
        .first()
    )
    if existing is not None:
        if not existing.is_available_at():
            raise ReferralLinkUnavailable
        return existing, False

    for _attempt in range(4):
        try:
            with transaction.atomic():
                return ReferralLink.objects.create(campaign=campaign, owner=user), True
        except IntegrityError:
            existing = ReferralLink.objects.filter(campaign=campaign, owner=user).first()
            if existing is not None:
                return existing, False
    raise ReferralConflict("Could not allocate a unique referral code.")


@transaction.atomic
def set_referral_link_enabled(
    link_id: uuid.UUID,
    *,
    enabled: bool,
    actor: User,
    reason: str,
) -> ReferralLink:
    _require_staff_actor(actor)
    link = ReferralLink.objects.select_for_update().get(pk=link_id)
    if link.revoked_at is not None:
        raise ReferralConflict("A revoked referral link cannot be re-enabled.")
    if link.is_enabled == enabled:
        return link
    link.is_enabled = enabled
    link.disabled_at = None if enabled else timezone.now()
    link.disabled_by = None if enabled else actor
    link.state_reason = reason.strip()
    link.save(
        update_fields=("is_enabled", "disabled_at", "disabled_by", "state_reason", "updated_at")
    )
    return link


@transaction.atomic
def revoke_referral_link(link_id: uuid.UUID, *, actor: User, reason: str) -> ReferralLink:
    _require_staff_actor(actor)
    link = ReferralLink.objects.select_for_update().get(pk=link_id)
    if link.revoked_at is not None:
        return link
    link.is_enabled = False
    link.revoked_at = timezone.now()
    link.revoked_by = actor
    link.disabled_at = link.disabled_at or link.revoked_at
    link.disabled_by = link.disabled_by or actor
    link.state_reason = reason.strip()
    link.save(
        update_fields=(
            "is_enabled",
            "disabled_at",
            "disabled_by",
            "revoked_at",
            "revoked_by",
            "state_reason",
            "updated_at",
        )
    )
    return link


def referral_link_url(link: ReferralLink, *, fallback_base: str) -> str:
    if link.campaign.short_link_base_url:
        return f"{link.campaign.short_link_base_url.rstrip('/')}/{link.code}"
    return f"{fallback_base.rstrip('/')}/{link.code}"


def referral_redirect_target(link: ReferralLink) -> str:
    """Build a redirect exclusively from a validated server-owned campaign URL."""
    if not link.is_available_at():
        raise ReferralLinkUnavailable
    parsed = urlsplit(link.campaign.canonical_download_url)
    # Models reject non-HTTPS data, but re-check at the security boundary.
    if parsed.scheme != "https" or parsed.hostname is None or parsed.username or parsed.password:
        raise ReferralLinkUnavailable
    query = dict(parse_qsl(parsed.query, keep_blank_values=True))
    query.update({"referral_code": link.code, "campaign": link.campaign.key})
    return urlunsplit((parsed.scheme, parsed.netloc, parsed.path, urlencode(query), ""))


@transaction.atomic
def record_click(code: str, *, channel: str) -> tuple[ReferralClick, str]:
    link = ReferralLink.objects.select_related("campaign").filter(code=code).first()
    if link is None or not link.is_available_at():
        raise ReferralLinkUnavailable
    target = referral_redirect_target(link)
    click = ReferralClick.objects.create(
        referral_link=link,
        campaign=link.campaign,
        channel=channel,
    )
    return click, target


def _event_fingerprint(event: ShareEvent) -> tuple[Any, ...]:
    return (
        event.actor_id,
        event.campaign_id,
        event.referral_link_id,
        event.action,
        event.result,
        event.channel,
        event.occurred_at,
        event.metadata,
    )


@transaction.atomic
def ingest_share_event(user: User, data: dict[str, Any]) -> tuple[ShareEvent, bool]:
    client_event_id = data["client_event_id"]
    existing = (
        ShareEvent.objects.select_for_update().filter(client_event_id=client_event_id).first()
    )
    campaign = ShareCampaign.objects.filter(key=data["campaign_key"]).first()
    if campaign is None:
        raise ShareCampaignUnavailable

    occurred_at = data["occurred_at"]
    now = timezone.now()
    referral = None
    code = data.get("referral_code", "")
    if code:
        referral = ReferralLink.objects.filter(code=code, campaign=campaign).first()
        if referral is None:
            raise ReferralLinkUnavailable

    account_mode = AccountMode.VERIFIED if user.status == UserStatus.ACTIVE else AccountMode.GUEST
    candidate = ShareEvent(
        client_event_id=client_event_id,
        actor=user,
        account_mode=account_mode,
        campaign=campaign,
        referral_link=referral,
        action=data["action"],
        result=data["result"],
        channel=data["channel"],
        occurred_at=occurred_at,
        metadata=data.get("metadata", {}),
    )
    if existing is not None:
        if _event_fingerprint(existing) != _event_fingerprint(candidate):
            raise ShareEventConflict
        return existing, False
    if referral is not None and not referral.is_available_at(occurred_at):
        raise ReferralLinkUnavailable
    if occurred_at > now + timedelta(minutes=5) or occurred_at < now - timedelta(days=30):
        raise ReferralConflict("occurred_at must be within the accepted 30-day ingestion window.")
    if not campaign.is_available_at(occurred_at):
        raise ShareCampaignUnavailable
    try:
        with transaction.atomic():
            candidate.save()
    except IntegrityError as exc:
        existing = ShareEvent.objects.filter(client_event_id=client_event_id).first()
        if existing is None or _event_fingerprint(existing) != _event_fingerprint(candidate):
            raise ShareEventConflict from exc
        return existing, False
    return candidate, True


@transaction.atomic
def record_referral_attribution(
    *,
    link: ReferralLink,
    invitee: User,
    idempotency_key: uuid.UUID,
    source: str,
    actor: User | None = None,
) -> tuple[ReferralAttribution, bool]:
    require_verified_account(invitee)
    if source not in AttributionSource.values:
        raise ReferralConflict("Unsupported attribution source.")
    if source == AttributionSource.MANUAL_ADMIN:
        if actor is None:
            raise ReferralConflict("Manual attribution requires a staff operator.")
        _require_staff_actor(actor)
    if link.owner_id == invitee.id:
        raise ReferralConflict("Self-referrals are not allowed.")
    existing = (
        ReferralAttribution.objects.select_for_update()
        .filter(idempotency_key=idempotency_key)
        .first()
    )
    if existing is not None:
        if existing.referral_link_id != link.id or existing.invitee_id != invitee.id:
            raise ReferralConflict("The attribution idempotency key was reused.")
        return existing, False
    try:
        with transaction.atomic():
            attribution = ReferralAttribution.objects.create(
                campaign=link.campaign,
                referral_link=link,
                invitee=invitee,
                source=source,
                idempotency_key=idempotency_key,
                created_by=actor,
            )
            ReferralQualification.objects.create(attribution=attribution)
    except IntegrityError as exc:
        existing = ReferralAttribution.objects.filter(
            campaign=link.campaign,
            invitee=invitee,
        ).first()
        if existing is None or existing.referral_link_id != link.id:
            raise ReferralConflict("The account is already attributed in this campaign.") from exc
        return existing, False
    return attribution, True


@transaction.atomic
def qualify_referral(
    qualification_id: uuid.UUID,
    *,
    actor: User,
    reason: str,
) -> tuple[ReferralQualification, ReferralReward | None]:
    _require_staff_actor(actor)
    qualification = (
        ReferralQualification.objects.select_for_update()
        .select_related("attribution__referral_link__owner", "attribution__campaign")
        .get(pk=qualification_id)
    )
    if qualification.status == QualificationStatus.QUALIFIED:
        return qualification, getattr(qualification, "reward", None)
    if qualification.status != QualificationStatus.PENDING:
        raise ReferralConflict("Only pending referrals can be qualified.")
    qualification.status = QualificationStatus.QUALIFIED
    qualification.decided_at = timezone.now()
    qualification.decided_by = actor
    qualification.decision_reason = reason.strip()
    qualification.save(
        update_fields=("status", "decided_at", "decided_by", "decision_reason", "updated_at")
    )
    campaign = qualification.attribution.campaign
    reward = None
    if campaign.reward_points:
        reward, created = ReferralReward.objects.get_or_create(
            qualification=qualification,
            defaults={
                "campaign": campaign,
                "beneficiary": qualification.attribution.referral_link.owner,
                "points": campaign.reward_points,
                "idempotency_key": f"qualification:{qualification.id}",
            },
        )
        if created:
            ReferralRewardAudit.objects.create(
                reward=reward,
                action=RewardAuditAction.CREATED,
                actor=actor,
                new_status=RewardStatus.PENDING,
                reason=reason.strip(),
            )
    return qualification, reward


@transaction.atomic
def reject_referral(
    qualification_id: uuid.UUID,
    *,
    actor: User,
    reason: str,
) -> ReferralQualification:
    _require_staff_actor(actor)
    qualification = ReferralQualification.objects.select_for_update().get(pk=qualification_id)
    if qualification.status == QualificationStatus.REJECTED:
        return qualification
    if qualification.status != QualificationStatus.PENDING:
        raise ReferralConflict("Only pending referrals can be rejected.")
    qualification.status = QualificationStatus.REJECTED
    qualification.decided_at = timezone.now()
    qualification.decided_by = actor
    qualification.decision_reason = reason.strip()
    qualification.save(
        update_fields=("status", "decided_at", "decided_by", "decision_reason", "updated_at")
    )
    return qualification


@transaction.atomic
def approve_reward(reward_id: uuid.UUID, *, actor: User, reason: str) -> ReferralReward:
    _require_staff_actor(actor)
    reward = ReferralReward.objects.select_for_update().get(pk=reward_id)
    if reward.status == RewardStatus.APPROVED:
        return reward
    if reward.status != RewardStatus.PENDING:
        raise ReferralConflict("Only pending rewards can be approved.")
    previous = reward.status
    reward.status = RewardStatus.APPROVED
    reward.approved_at = timezone.now()
    reward.approved_by = actor
    reward.save(update_fields=("status", "approved_at", "approved_by", "updated_at"))
    ReferralRewardAudit.objects.create(
        reward=reward,
        action=RewardAuditAction.APPROVED,
        actor=actor,
        previous_status=previous,
        new_status=reward.status,
        reason=reason.strip(),
    )
    return reward


@transaction.atomic
def reverse_reward(reward_id: uuid.UUID, *, actor: User, reason: str) -> ReferralReward:
    _require_staff_actor(actor)
    reward = ReferralReward.objects.select_for_update().get(pk=reward_id)
    if reward.status == RewardStatus.REVERSED:
        return reward
    previous = reward.status
    reward.status = RewardStatus.REVERSED
    reward.reversed_at = timezone.now()
    reward.reversed_by = actor
    reward.reversal_reason = reason.strip()
    reward.save(
        update_fields=(
            "status",
            "reversed_at",
            "reversed_by",
            "reversal_reason",
            "updated_at",
        )
    )
    ReferralRewardAudit.objects.create(
        reward=reward,
        action=RewardAuditAction.REVERSED,
        actor=actor,
        previous_status=previous,
        new_status=reward.status,
        reason=reason.strip(),
    )
    return reward


@transaction.atomic
def reverse_qualification(
    qualification_id: uuid.UUID,
    *,
    actor: User,
    reason: str,
) -> ReferralQualification:
    _require_staff_actor(actor)
    qualification = ReferralQualification.objects.select_for_update().get(pk=qualification_id)
    if qualification.status == QualificationStatus.REVERSED:
        return qualification
    if qualification.status != QualificationStatus.QUALIFIED:
        raise ReferralConflict("Only qualified referrals can be reversed.")
    try:
        reward = qualification.reward
    except ReferralReward.DoesNotExist:
        reward = None
    if reward is not None:
        reverse_reward(reward.id, actor=actor, reason=reason)
    qualification.status = QualificationStatus.REVERSED
    qualification.decided_at = timezone.now()
    qualification.decided_by = actor
    qualification.decision_reason = reason.strip()
    qualification.save(
        update_fields=("status", "decided_at", "decided_by", "decision_reason", "updated_at")
    )
    return qualification


def referral_summary(user: User, campaign_key: str | None) -> dict[str, int | str | None]:
    require_verified_account(user)
    campaign = select_available_campaign(campaign_key)
    if campaign is None:
        raise ShareCampaignUnavailable
    link = ReferralLink.objects.filter(campaign=campaign, owner=user).first()
    if link is None:
        return {
            "campaign_key": campaign.key,
            "invited": 0,
            "qualified": 0,
            "reward_balance": 0,
            "pending_reward": 0,
        }
    invited = ReferralAttribution.objects.filter(referral_link=link).count()
    qualified = ReferralQualification.objects.filter(
        attribution__referral_link=link,
        status=QualificationStatus.QUALIFIED,
    ).count()
    totals = ReferralReward.objects.filter(beneficiary=user, campaign=campaign).aggregate(
        reward_balance=Sum("points", filter=Q(status=RewardStatus.APPROVED), default=0),
        pending_reward=Sum("points", filter=Q(status=RewardStatus.PENDING), default=0),
    )
    return {
        "campaign_key": campaign.key,
        "invited": invited,
        "qualified": qualified,
        "reward_balance": int(totals["reward_balance"] or 0),
        "pending_reward": int(totals["pending_reward"] or 0),
    }
