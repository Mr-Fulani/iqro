from __future__ import annotations

from rest_framework import status
from rest_framework.exceptions import APIException, NotFound, Throttled


class PrayerConfigurationUnavailableError(APIException):
    status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    default_detail = "A published prayer-time configuration is not available."
    default_code = "prayer_configuration_unavailable"


class PrayerMethodConfigurationNotFoundError(NotFound):
    default_detail = "The requested prayer method configuration is not available."
    default_code = "prayer_method_not_found"


class PrayerMethodConfigurationWithdrawnError(APIException):
    status_code = status.HTTP_410_GONE
    default_detail = "The requested prayer method configuration has been withdrawn."
    default_code = "prayer_method_withdrawn"


class PrayerMethodChecksumMismatchError(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The prayer method checksum does not match the published configuration."
    default_code = "prayer_method_checksum_mismatch"


class PrayerEngineUnsupportedError(APIException):
    status_code = status.HTTP_422_UNPROCESSABLE_ENTITY
    default_detail = "The published prayer calculation engine is not supported by this server."
    default_code = "prayer_engine_unsupported"


class PrayerCalculationUnavailableAPIError(APIException):
    status_code = status.HTTP_422_UNPROCESSABLE_ENTITY
    default_detail = "Prayer times cannot be resolved with the selected fallback settings."
    default_code = "prayer_calculation_unavailable"


class PrayerRuleUnsupportedError(APIException):
    status_code = status.HTTP_422_UNPROCESSABLE_ENTITY
    default_detail = "The selected rule is not supported by this prayer method."
    default_code = "prayer_rule_unsupported"


class PrayerCalculationRateLimitedError(Throttled):
    default_detail = "Prayer-time calculation rate limit exceeded."
    default_code = "prayer_calculation_rate_limited"


class PrayerProfileNotFoundError(NotFound):
    default_detail = "Prayer profile was not found."
    default_code = "prayer_profile_not_found"


class PrayerProfileRevisionConflictError(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The prayer profile changed after the client's base revision."
    default_code = "prayer_profile_revision_conflict"


class PrayerProfileRateLimitedError(Throttled):
    default_detail = "Too many prayer-profile mutations. Retry later."
    default_code = "prayer_profile_rate_limited"
