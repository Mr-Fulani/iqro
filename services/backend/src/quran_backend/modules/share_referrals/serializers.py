from __future__ import annotations

from typing import Any, ClassVar, cast

from rest_framework import serializers

from quran_backend.modules.share_referrals.models import (
    ShareEventAction,
    ShareEventChannel,
    ShareEventResult,
)
from quran_backend.modules.share_referrals.services import EVENT_METADATA_KEYS


class ShareConfigQuerySerializer(serializers.Serializer[Any]):
    locale = serializers.RegexField(r"^[a-z]{2}$", default="en", max_length=8)
    campaign = serializers.SlugField(required=False, max_length=64)


class ShareCampaignConfigSerializer(serializers.Serializer[Any]):
    key = serializers.SlugField()
    config_version = serializers.IntegerField(min_value=1)
    updated_at = serializers.DateTimeField()
    locale = serializers.CharField()
    title = serializers.CharField()
    message = serializers.CharField()
    cta_label = serializers.CharField()
    canonical_download_url = serializers.URLField()
    ios_url = serializers.URLField(allow_blank=True)
    android_url = serializers.URLField(allow_blank=True)
    referral_enabled = serializers.BooleanField()


class ShareConfigResponseSerializer(serializers.Serializer[Any]):
    available = serializers.BooleanField()
    fallback_reason = serializers.CharField(allow_null=True)
    requested_locale = serializers.CharField()
    used_fallback = serializers.BooleanField()
    campaign = ShareCampaignConfigSerializer(allow_null=True)


class ReferralLinkRequestSerializer(serializers.Serializer[Any]):
    campaign_key = serializers.SlugField(required=False, max_length=64)


class ReferralLinkOutputSerializer(serializers.Serializer[Any]):
    campaign_key = serializers.SlugField()
    code = serializers.CharField()
    short_url = serializers.URLField()
    is_enabled = serializers.BooleanField()
    created_at = serializers.DateTimeField()


class ReferralSummarySerializer(serializers.Serializer[Any]):
    campaign_key = serializers.SlugField()
    invited = serializers.IntegerField(min_value=0)
    qualified = serializers.IntegerField(min_value=0)
    reward_balance = serializers.IntegerField(min_value=0)
    pending_reward = serializers.IntegerField(min_value=0)


class ShareEventMetadataSerializer(serializers.DictField):
    def to_internal_value(self, data: Any) -> dict[str, str | int | bool]:
        value = super().to_internal_value(data)
        unknown = set(value) - EVENT_METADATA_KEYS
        if unknown:
            names = ", ".join(sorted(unknown))
            raise serializers.ValidationError(f"Unsupported metadata fields: {names}.")
        normalized: dict[str, str | int | bool] = {}
        for key, item in value.items():
            if not isinstance(item, (str, int, bool)) or isinstance(item, float):
                raise serializers.ValidationError(
                    f"Metadata field {key} must be a string, integer or boolean."
                )
            if isinstance(item, str) and len(item) > 120:
                raise serializers.ValidationError(f"Metadata field {key} is too long.")
            normalized[key] = item
        return normalized


class ShareEventCreateSerializer(serializers.Serializer[Any]):
    client_event_id = serializers.UUIDField()
    campaign_key = serializers.SlugField(max_length=64)
    referral_code = serializers.CharField(required=False, allow_blank=True, max_length=32)
    action = serializers.ChoiceField(
        choices=(*ShareEventAction.values, "open-system-share", "copy-link", "copy-code")
    )
    result = serializers.ChoiceField(
        choices=(*ShareEventResult.values, "shared", "copied", "dismissed", "unavailable")
    )
    channel = serializers.ChoiceField(choices=ShareEventChannel.values, required=False)
    occurred_at = serializers.DateTimeField()
    account_mode = serializers.ChoiceField(
        choices=("guest", "verified"), required=False, write_only=True
    )
    metadata = ShareEventMetadataSerializer(required=False)

    CLIENT_ACTION_MAP: ClassVar[dict[str, str]] = {
        "open-system-share": ShareEventAction.SHARE_SHEET_OPENED,
        "copy-link": ShareEventAction.LINK_COPIED,
        "copy-code": ShareEventAction.REFERRAL_CODE_COPIED,
    }
    CLIENT_RESULT_MAP: ClassVar[dict[str, str]] = {
        "shared": ShareEventResult.SUCCEEDED,
        "copied": ShareEventResult.SUCCEEDED,
        "dismissed": ShareEventResult.CANCELLED,
        "unavailable": ShareEventResult.FAILED,
    }

    def to_internal_value(self, data: Any) -> dict[str, Any]:
        """Accept the prototype/Flutter gateway envelope as well as API snake_case."""
        mapped = dict(data)
        aliases = {
            "eventId": "client_event_id",
            "campaignId": "campaign_key",
            "occurredAt": "occurred_at",
            "accountMode": "account_mode",
        }
        for source, target in aliases.items():
            if source in mapped and target not in mapped:
                mapped[target] = mapped[source]
            mapped.pop(source, None)
        return cast(dict[str, Any], super().to_internal_value(mapped))

    def validate(self, attrs: dict[str, Any]) -> dict[str, Any]:
        original_action = str(attrs["action"])
        attrs["action"] = self.CLIENT_ACTION_MAP.get(original_action, original_action)
        original_result = str(attrs["result"])
        attrs["result"] = self.CLIENT_RESULT_MAP.get(original_result, original_result)
        if "channel" not in attrs:
            attrs["channel"] = (
                ShareEventChannel.COPY
                if original_action in {"copy-link", "copy-code"}
                else ShareEventChannel.SYSTEM
            )
        # account_mode is intentionally ignored; the server derives it from auth.
        attrs.pop("account_mode", None)
        return attrs


class ShareEventOutputSerializer(serializers.Serializer[Any]):
    client_event_id = serializers.UUIDField()
    accepted = serializers.BooleanField()
    replayed = serializers.BooleanField()
    received_at = serializers.DateTimeField()


class ReferralRedirectQuerySerializer(serializers.Serializer[Any]):
    channel = serializers.ChoiceField(
        choices=ShareEventChannel.values,
        required=False,
        default=ShareEventChannel.OTHER,
    )
