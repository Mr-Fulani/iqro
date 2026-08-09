from __future__ import annotations

from rest_framework import status
from rest_framework.exceptions import APIException, NotFound, Throttled


class ReminderNotFoundError(NotFound):
    default_detail = "Reminder was not found."
    default_code = "reminder_not_found"


class ReminderCreateConflictError(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "Reminder id already represents a different reminder state."
    default_code = "reminder_create_conflict"


class ReminderIdNotReusableError(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "A new reminder requires a recent UUIDv7 id. Generate a new id and retry."
    default_code = "reminder_id_not_reusable"


class ReminderRevisionConflictError(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The reminder changed after the client's base revision. Refresh and retry."
    default_code = "reminder_revision_conflict"


class ReminderQuotaExceededError(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The per-user reminder quota has been reached."
    default_code = "reminder_quota_exceeded"


class ReminderDeletedError(APIException):
    status_code = status.HTTP_410_GONE
    default_detail = "A deleted reminder cannot be reused. Generate a new UUIDv7 id."
    default_code = "reminder_deleted"


class ReminderRateLimitExceeded(Throttled):
    default_detail = "Too many reminder mutations. Retry later."
    default_code = "reminder_rate_limited"
