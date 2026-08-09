from __future__ import annotations

from rest_framework import status
from rest_framework.exceptions import APIException, NotFound


class FeedbackConflict(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The feedback request conflicts with the current ticket state."
    default_code = "feedback_conflict"


class FeedbackLimitReached(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The feedback limit has been reached."
    default_code = "feedback_limit_reached"


class FeedbackTicketNotFound(NotFound):
    default_detail = "Feedback ticket was not found."
    default_code = "feedback_ticket_not_found"
