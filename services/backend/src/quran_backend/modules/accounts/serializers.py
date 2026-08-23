from __future__ import annotations

from uuid import UUID

from rest_framework import serializers

from quran_backend.modules.accounts.models import DevicePlatform

SUPPORTED_LOCALES = ("ar", "en", "ru")


class GuestBootstrapRequestSerializer(serializers.Serializer[dict[str, object]]):
    installation_id = serializers.UUIDField()
    installation_credential = serializers.RegexField(
        regex=r"^[A-Za-z0-9_-]{43,128}$",
        min_length=43,
        max_length=128,
        trim_whitespace=False,
        write_only=True,
        help_text=(
            "Client-generated base64url credential containing at least 256 bits of entropy. "
            "Generate and persist it before the first bootstrap request."
        ),
    )
    platform = serializers.ChoiceField(choices=DevicePlatform.choices)
    locale = serializers.ChoiceField(choices=SUPPORTED_LOCALES)
    app_version = serializers.RegexField(
        regex=r"^[A-Za-z0-9][A-Za-z0-9._+()\-]{0,31}$",
        max_length=32,
    )

    def validate_installation_id(self, value: UUID) -> UUID:
        if value.int == 0:
            raise serializers.ValidationError("A non-zero UUID is required.", code="invalid")
        return value


class RefreshTokenRequestSerializer(serializers.Serializer[dict[str, str]]):
    refresh_token = serializers.CharField(
        max_length=256,
        trim_whitespace=False,
        write_only=True,
    )


class UserSummarySerializer(serializers.Serializer[dict[str, object]]):
    id = serializers.UUIDField()
    status = serializers.CharField()
    preferred_locale = serializers.CharField()
    email = serializers.EmailField(allow_null=True)
    deletion_requested_at = serializers.DateTimeField(allow_null=True)
    deletion_scheduled_for = serializers.DateTimeField(allow_null=True)


class DeviceSummarySerializer(serializers.Serializer[dict[str, object]]):
    id = serializers.UUIDField()
    platform = serializers.CharField()
    locale = serializers.CharField()
    app_version = serializers.CharField()
    bootstrap_generation = serializers.IntegerField(min_value=1)


class TokenPairResponseSerializer(serializers.Serializer[dict[str, object]]):
    token_type = serializers.CharField()
    access_token = serializers.CharField()
    expires_in = serializers.IntegerField()
    access_expires_at = serializers.DateTimeField()
    refresh_token = serializers.CharField()
    refresh_expires_in = serializers.IntegerField()
    refresh_expires_at = serializers.DateTimeField()


class GuestBootstrapResponseSerializer(TokenPairResponseSerializer):
    user = UserSummarySerializer()
    device = DeviceSummarySerializer()


class EmailChallengeStartRequestSerializer(serializers.Serializer[dict[str, str]]):
    email = serializers.EmailField(max_length=254)

    def validate_email(self, value: str) -> str:
        return value.strip().lower()


class EmailChallengeStartResponseSerializer(serializers.Serializer[dict[str, object]]):
    challenge_id = serializers.UUIDField()
    expires_in = serializers.IntegerField(min_value=1)
    expires_at = serializers.DateTimeField()


class EmailChallengeVerifyRequestSerializer(serializers.Serializer[dict[str, object]]):
    challenge_id = serializers.UUIDField()
    code = serializers.RegexField(
        regex=r"^[0-9]{6}$",
        min_length=6,
        max_length=6,
        trim_whitespace=False,
        write_only=True,
    )
    installation_credential = serializers.RegexField(
        regex=r"^[A-Za-z0-9_-]{43,128}$",
        min_length=43,
        max_length=128,
        trim_whitespace=False,
        write_only=True,
    )
    idempotency_key = serializers.UUIDField()

    def validate_idempotency_key(self, value: UUID) -> UUID:
        if value.int == 0:
            raise serializers.ValidationError("A non-zero UUID is required.", code="invalid")
        return value


class EmailChallengeVerifyResponseSerializer(GuestBootstrapResponseSerializer):
    merged_guest = serializers.BooleanField()
    replayed = serializers.BooleanField()


class CurrentSessionResponseSerializer(serializers.Serializer[dict[str, object]]):
    user = UserSummarySerializer()
    device = DeviceSummarySerializer()


class DeviceInventorySerializer(serializers.Serializer[dict[str, object]]):
    id = serializers.UUIDField()
    platform = serializers.ChoiceField(choices=DevicePlatform.choices)
    locale = serializers.ChoiceField(choices=SUPPORTED_LOCALES)
    app_version = serializers.CharField()
    created_at = serializers.DateTimeField()
    last_seen_at = serializers.DateTimeField()
    last_session_used_at = serializers.DateTimeField(allow_null=True)
    active_session_count = serializers.IntegerField(min_value=0)
    is_current = serializers.BooleanField()


class AccountDeletionRequestSerializer(serializers.Serializer[dict[str, object]]):
    reauth_challenge_id = serializers.UUIDField()

    def validate_reauth_challenge_id(self, value: UUID) -> UUID:
        if value.int == 0:
            raise serializers.ValidationError("A non-zero UUID is required.", code="invalid")
        return value
