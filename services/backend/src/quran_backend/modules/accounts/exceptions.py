from __future__ import annotations

from rest_framework import status
from rest_framework.exceptions import APIException, AuthenticationFailed, NotFound, Throttled


class AccessTokenInvalid(AuthenticationFailed):
    default_detail = "Authentication credentials could not be validated."
    default_code = "access_token_invalid"


class RefreshTokenInvalid(APIException):
    status_code = status.HTTP_401_UNAUTHORIZED
    default_detail = "Refresh credentials could not be validated."
    default_code = "refresh_token_invalid"
    auth_header = "Bearer"


class RefreshTokenReused(APIException):
    status_code = status.HTTP_401_UNAUTHORIZED
    default_detail = "Refresh credentials could not be validated."
    default_code = "refresh_token_reused"
    auth_header = "Bearer"


class GuestBootstrapUnavailable(APIException):
    status_code = status.HTTP_403_FORBIDDEN
    default_detail = "Guest bootstrap is unavailable for this installation."
    default_code = "guest_bootstrap_unavailable"


class DeviceRecoveryUnavailable(APIException):
    status_code = status.HTTP_403_FORBIDDEN
    default_detail = "Device session recovery is unavailable."
    default_code = "device_recovery_unavailable"


class AuthRateLimitExceeded(Throttled):
    default_detail = "Too many authentication requests. Retry later."
    default_code = "auth_rate_limited"


class EmailChallengeInvalid(APIException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = "Email verification could not be completed."
    default_code = "email_challenge_invalid"


class EmailChallengeExpired(APIException):
    status_code = status.HTTP_410_GONE
    default_detail = "Email verification could not be completed."
    default_code = "email_challenge_expired"


class EmailChallengeDeliveryFailed(APIException):
    status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    default_detail = "The verification message could not be delivered. Retry later."
    default_code = "email_delivery_failed"


class IdentityAlreadyLinked(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "This identity is already linked to another account."
    default_code = "identity_already_linked"


class AccountLinkUnavailable(APIException):
    status_code = status.HTTP_403_FORBIDDEN
    default_detail = "Account linking is unavailable for this session."
    default_code = "account_link_unavailable"


class DeviceNotFound(NotFound):
    default_detail = "Device was not found."
    default_code = "device_not_found"


class CurrentDeviceRevokeConflict(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "Use logout to end the current device session."
    default_code = "current_device_revoke_conflict"


class AccountLifecycleUnavailable(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The account lifecycle action is unavailable."
    default_code = "account_lifecycle_unavailable"


class AccountReauthenticationRequired(APIException):
    status_code = status.HTTP_403_FORBIDDEN
    default_detail = "A recent email verification is required."
    default_code = "account_reauthentication_required"
