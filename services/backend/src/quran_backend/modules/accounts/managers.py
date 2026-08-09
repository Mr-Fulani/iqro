from __future__ import annotations

from typing import TYPE_CHECKING, Any

from django.contrib.auth.base_user import BaseUserManager

if TYPE_CHECKING:
    from quran_backend.modules.accounts.models import User


class UserManager(BaseUserManager["User"]):
    use_in_migrations = True

    def create_user(
        self,
        email: str | None = None,
        password: str | None = None,
        **extra_fields: Any,
    ) -> User:
        from quran_backend.modules.accounts.models import User  # noqa: PLC0415

        normalized_email = self.normalize_email(email).lower() if email else None
        user = User(email=normalized_email, **extra_fields)
        if password:
            user.set_password(password)
        else:
            user.set_unusable_password()
        user.full_clean(exclude={"password"})
        user.save(using=self._db)
        return user

    def create_superuser(
        self,
        email: str,
        password: str | None = None,
        **extra_fields: Any,
    ) -> User:
        if not email:
            msg = "Superusers must have an email address."
            raise ValueError(msg)
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        extra_fields.setdefault("is_active", True)
        extra_fields.setdefault("status", "active")
        if extra_fields.get("is_staff") is not True:
            msg = "Superuser must have is_staff=True."
            raise ValueError(msg)
        if extra_fields.get("is_superuser") is not True:
            msg = "Superuser must have is_superuser=True."
            raise ValueError(msg)
        return self.create_user(email=email, password=password, **extra_fields)
