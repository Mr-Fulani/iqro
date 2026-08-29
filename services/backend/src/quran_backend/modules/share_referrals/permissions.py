from __future__ import annotations

from typing import Any

from rest_framework.permissions import BasePermission
from rest_framework.request import Request

from quran_backend.modules.accounts.models import UserStatus
from quran_backend.modules.share_referrals.exceptions import VerifiedAccountRequired


class IsVerifiedAccount(BasePermission):
    """Require the repository's post-verification ACTIVE account state."""

    def has_permission(self, request: Request, view: Any) -> bool:  # noqa: ARG002
        user = request.user
        if (
            not user
            or not user.is_authenticated
            or not user.is_active
            or getattr(user, "status", None) != UserStatus.ACTIVE
        ):
            raise VerifiedAccountRequired
        return True
