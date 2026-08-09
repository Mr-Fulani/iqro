from __future__ import annotations

import re
import unicodedata
from typing import Any

from django.utils.html import strip_tags
from rest_framework import serializers

from quran_backend.modules.feedback.models import FeedbackCategory, FeedbackChannel

_SAFE_EXTERNAL_ID = re.compile(r"\A[A-Za-z0-9][A-Za-z0-9._:@/-]*\Z")


def validate_plain_text(value: str, *, single_line: bool = False) -> str:
    value = value.strip()
    if strip_tags(value) != value:
        raise serializers.ValidationError("HTML is not accepted; send plain text only.")
    has_unsupported_control = any(
        unicodedata.category(character) in {"Cc", "Cs"}
        for character in value
        if character not in "\n\t"
    )
    if has_unsupported_control:
        raise serializers.ValidationError("Unsupported control characters are not accepted.")
    if single_line and ("\n" in value or "\r" in value):
        raise serializers.ValidationError("This field must contain one line of plain text.")
    return value


def validate_external_id(value: str) -> None:
    if value and not _SAFE_EXTERNAL_ID.fullmatch(value):
        raise serializers.ValidationError("Use only safe identifier characters.")


class FeedbackContextInputSerializer(serializers.Serializer[Any]):
    edition_code = serializers.CharField(
        max_length=64,
        required=False,
        allow_blank=True,
        validators=[validate_external_id],
    )
    content_version = serializers.CharField(
        max_length=64,
        required=False,
        allow_blank=True,
        validators=[validate_external_id],
    )
    surah_number = serializers.IntegerField(min_value=1, max_value=114, required=False)
    ayah_number = serializers.IntegerField(min_value=1, required=False)
    page_number = serializers.IntegerField(min_value=1, max_value=604, required=False)
    reciter_id = serializers.CharField(
        max_length=128,
        required=False,
        allow_blank=True,
        validators=[validate_external_id],
    )
    recitation_id = serializers.CharField(
        max_length=128,
        required=False,
        allow_blank=True,
        validators=[validate_external_id],
    )
    audio_track_id = serializers.CharField(
        max_length=128,
        required=False,
        allow_blank=True,
        validators=[validate_external_id],
    )
    playback_ms = serializers.IntegerField(min_value=0, max_value=86_400_000, required=False)
    ad_campaign_id = serializers.CharField(
        max_length=128,
        required=False,
        allow_blank=True,
        validators=[validate_external_id],
    )
    ad_creative_id = serializers.CharField(
        max_length=128,
        required=False,
        allow_blank=True,
        validators=[validate_external_id],
    )
    route = serializers.CharField(max_length=255, required=False, allow_blank=True)
    app_version = serializers.CharField(max_length=32, required=False, allow_blank=True)
    app_build = serializers.CharField(max_length=32, required=False, allow_blank=True)
    client_platform = serializers.ChoiceField(
        choices=FeedbackChannel.choices,
        required=False,
        allow_blank=True,
    )
    os_version = serializers.CharField(max_length=64, required=False, allow_blank=True)

    def validate_route(self, value: str) -> str:
        value = validate_plain_text(value, single_line=True)
        if value and (not value.startswith("/") or "://" in value or "?" in value or "#" in value):
            raise serializers.ValidationError(
                "Route must be a relative path without query parameters or fragments."
            )
        return value

    def validate_app_version(self, value: str) -> str:
        return validate_plain_text(value, single_line=True)

    def validate_app_build(self, value: str) -> str:
        return validate_plain_text(value, single_line=True)

    def validate_os_version(self, value: str) -> str:
        return validate_plain_text(value, single_line=True)

    def validate(self, attrs: dict[str, Any]) -> dict[str, Any]:
        quran_keys = {"surah_number", "ayah_number", "page_number"}
        if quran_keys.intersection(attrs) and (
            not attrs.get("edition_code") or not attrs.get("content_version")
        ):
            raise serializers.ValidationError(
                "Quran coordinates require edition_code and content_version."
            )
        if "ayah_number" in attrs and "surah_number" not in attrs:
            raise serializers.ValidationError("ayah_number requires surah_number.")
        if "playback_ms" in attrs and not (
            attrs.get("audio_track_id") or attrs.get("recitation_id")
        ):
            raise serializers.ValidationError(
                "playback_ms requires audio_track_id or recitation_id."
            )
        return attrs


class FeedbackTicketCreateSerializer(serializers.Serializer[Any]):
    client_request_id = serializers.UUIDField()
    client_message_id = serializers.UUIDField()
    category = serializers.ChoiceField(choices=FeedbackCategory.choices)
    subject = serializers.CharField(max_length=160)
    message = serializers.CharField(max_length=4000)
    locale = serializers.ChoiceField(choices=("ar", "en", "ru"), required=False)
    contact_email = serializers.EmailField(required=False, allow_null=True, allow_blank=True)
    context = FeedbackContextInputSerializer(required=False)  # type: ignore[assignment]

    def validate_subject(self, value: str) -> str:
        return validate_plain_text(value, single_line=True)

    def validate_message(self, value: str) -> str:
        return validate_plain_text(value)

    def validate_contact_email(self, value: str | None) -> str | None:
        return value.strip().lower() if value else None


class FeedbackMessageCreateSerializer(serializers.Serializer[Any]):
    client_message_id = serializers.UUIDField()
    body = serializers.CharField(max_length=4000)

    def validate_body(self, value: str) -> str:
        return validate_plain_text(value)


class FeedbackTransitionSerializer(serializers.Serializer[Any]):
    reason = serializers.CharField(max_length=500, required=False, allow_blank=True)

    def validate_reason(self, value: str) -> str:
        return validate_plain_text(value)


class FeedbackContextOutputSerializer(serializers.Serializer[Any]):
    edition_code = serializers.CharField()
    content_version = serializers.CharField()
    surah_number = serializers.IntegerField(allow_null=True)
    ayah_number = serializers.IntegerField(allow_null=True)
    page_number = serializers.IntegerField(allow_null=True)
    reciter_id = serializers.CharField()
    recitation_id = serializers.CharField()
    audio_track_id = serializers.CharField()
    playback_ms = serializers.IntegerField(allow_null=True)
    ad_campaign_id = serializers.CharField()
    ad_creative_id = serializers.CharField()
    route = serializers.CharField()
    app_version = serializers.CharField()
    app_build = serializers.CharField()
    client_platform = serializers.CharField()
    os_version = serializers.CharField()


class FeedbackMessageOutputSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    client_message_id = serializers.UUIDField()
    author_type = serializers.CharField()
    body = serializers.CharField()
    created_at = serializers.DateTimeField()


class FeedbackTicketSummarySerializer(serializers.Serializer[Any]):
    public_id = serializers.CharField()
    category = serializers.CharField()
    subject = serializers.CharField()
    status = serializers.CharField()
    priority = serializers.CharField()
    locale = serializers.CharField()
    channel = serializers.CharField()
    sla_response_due_at = serializers.DateTimeField(allow_null=True)
    first_response_at = serializers.DateTimeField(allow_null=True)
    created_at = serializers.DateTimeField()
    updated_at = serializers.DateTimeField()


class FeedbackTicketDetailSerializer(FeedbackTicketSummarySerializer):
    client_request_id = serializers.UUIDField()
    contact_email = serializers.EmailField(allow_null=True)
    team = serializers.CharField()
    resolved_at = serializers.DateTimeField(allow_null=True)
    closed_at = serializers.DateTimeField(allow_null=True)
    reopened_at = serializers.DateTimeField(allow_null=True)
    reopen_count = serializers.IntegerField()
    context = FeedbackContextOutputSerializer()  # type: ignore[assignment]
    messages = FeedbackMessageOutputSerializer(many=True)


class FeedbackTicketPageSerializer(serializers.Serializer[Any]):
    next = serializers.URLField(allow_null=True)
    previous = serializers.URLField(allow_null=True)
    results = FeedbackTicketSummarySerializer(many=True)
