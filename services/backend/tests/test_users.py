from __future__ import annotations

import pytest
from django.core.exceptions import ValidationError

from quran_backend.modules.accounts.models import User, UserStatus


@pytest.mark.django_db
def test_guest_user_has_unusable_password() -> None:
    user = User.objects.create_user()

    assert user.status == UserStatus.GUEST
    assert user.email is None
    assert not user.has_usable_password()


@pytest.mark.django_db
def test_user_email_is_normalized() -> None:
    user = User.objects.create_user(email="  Reader@Example.COM ")

    assert user.email == "reader@example.com"


@pytest.mark.django_db
def test_active_user_requires_email() -> None:
    with pytest.raises(ValidationError):
        User.objects.create_user(status=UserStatus.ACTIVE)


@pytest.mark.django_db
def test_superuser_has_required_flags() -> None:
    user = User.objects.create_superuser(email="admin@example.com", password="test-password")

    assert user.is_staff
    assert user.is_superuser
    assert user.status == UserStatus.ACTIVE
