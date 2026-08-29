from __future__ import annotations

from rest_framework import status
from rest_framework.exceptions import APIException, NotFound, PermissionDenied


class VerifiedAccountRequired(PermissionDenied):
    default_detail = "A verified account is required for referral links and rewards."
    default_code = "verified_account_required"


class ShareCampaignUnavailable(NotFound):
    default_detail = "The share campaign is not available."
    default_code = "share_campaign_unavailable"


class ReferralLinkUnavailable(NotFound):
    default_detail = "The referral link is not available."
    default_code = "referral_link_unavailable"


class ReferralConflict(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The referral operation conflicts with existing server state."
    default_code = "referral_conflict"


class ShareEventConflict(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The client event identifier was already used for different data."
    default_code = "share_event_conflict"
