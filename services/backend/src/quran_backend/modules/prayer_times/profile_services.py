from __future__ import annotations

import uuid
from typing import Any, cast

from django.db import transaction
from django.db.models import QuerySet

from quran_backend.modules.accounts.models import Device, User
from quran_backend.modules.prayer_times.exceptions import (
    PrayerEngineUnsupportedError,
    PrayerMethodChecksumMismatchError,
    PrayerMethodConfigurationNotFoundError,
    PrayerMethodConfigurationWithdrawnError,
    PrayerProfileNotFoundError,
    PrayerProfileRevisionConflictError,
    PrayerRuleUnsupportedError,
)
from quran_backend.modules.prayer_times.models import (
    PrayerConfigReleaseStatus,
    PrayerMethodConfig,
    PrayerProfile,
    PrayerTimezoneMode,
    high_latitude_support_items,
    polar_support_items,
)
from quran_backend.modules.prayer_times.services import is_release_engine_compatible


def get_prayer_profile(user: User) -> PrayerProfile:
    profile = _profile_queryset().filter(user=user).first()
    if profile is None:
        raise PrayerProfileNotFoundError
    return profile


def prayer_profile_snapshot(profile: PrayerProfile) -> dict[str, Any]:
    configuration = profile.method_config
    return {
        "id": str(profile.id),
        "method_config": {
            "id": str(configuration.id),
            "code": configuration.method.code,
            "catalog_version": configuration.release.version,
            "checksum_sha256": configuration.checksum_sha256,
        },
        "method_available": _configuration_is_available(configuration),
        "asr_method": profile.asr_method,
        "high_latitude_rule": profile.high_latitude_rule,
        "polar_resolution": profile.polar_resolution,
        "adjustments": {
            field.removesuffix("_adjustment_minutes"): getattr(profile, field)
            for field in PrayerProfile.adjustment_fields
        },
        "timezone_mode": profile.timezone_mode,
        "fixed_timezone": (
            profile.fixed_timezone if profile.timezone_mode == PrayerTimezoneMode.FIXED else None
        ),
        "revision": profile.revision,
        "client_updated_at": profile.client_updated_at.isoformat(),
        "device_id": str(profile.device_id) if profile.device_id else None,
        "created_at": profile.created_at.isoformat(),
        "updated_at": profile.updated_at.isoformat(),
    }


@transaction.atomic
def put_prayer_profile(
    *,
    user: User,
    device: Device | None,
    data: dict[str, Any],
) -> dict[str, Any]:
    """Create/replace preferences with optimistic concurrency and idempotent retries."""

    # The user row serializes concurrent first writes before the OneToOne row exists.
    User.objects.select_for_update().only("id").get(pk=user.pk)
    current = _profile_queryset(for_update=True).filter(user=user).first()
    configuration = _configuration_for_write(data["method_config_id"])
    if configuration.checksum_sha256 != data["method_checksum_sha256"]:
        raise PrayerMethodChecksumMismatchError

    desired = _desired_state(data)
    if current is not None and _stored_state(current) == desired:
        # A retry of an already-applied replacement is safe even when its base
        # revision is stale or the exact method was withdrawn after the write.
        return prayer_profile_snapshot(current)

    if current is None:
        if data["base_revision"] != 0:
            raise PrayerProfileRevisionConflictError
    elif data["base_revision"] != current.revision:
        raise PrayerProfileRevisionConflictError

    if not _configuration_is_published_and_active(configuration):
        raise PrayerMethodConfigurationWithdrawnError
    if not is_release_engine_compatible(configuration.release):
        raise PrayerEngineUnsupportedError
    _validate_supported_rules(configuration, data)

    values = {
        "method_config": configuration,
        "asr_method": data["asr_method"],
        "high_latitude_rule": data["high_latitude_rule"],
        "polar_resolution": data["polar_resolution"],
        "timezone_mode": data["timezone_mode"],
        "fixed_timezone": data["fixed_timezone"],
        "client_updated_at": data["client_updated_at"],
        "device": device,
        **{
            f"{name}_adjustment_minutes": value for name, value in dict(data["adjustments"]).items()
        },
    }
    if current is None:
        profile = PrayerProfile(user=user, revision=1, **values)
    else:
        profile = current
        for field, value in values.items():
            setattr(profile, field, value)
        profile.revision += 1
    profile.full_clean()
    profile.save()
    return prayer_profile_snapshot(profile)


def _profile_queryset(*, for_update: bool = False) -> QuerySet[PrayerProfile]:
    queryset = PrayerProfile.objects.select_related(
        "method_config__method",
        "method_config__release",
        "device",
    )
    # Nullable ``device`` is joined with LEFT OUTER JOIN. PostgreSQL refuses a
    # plain FOR UPDATE in that shape because the nullable side cannot be
    # locked; only the profile row participates in optimistic concurrency.
    return queryset.select_for_update(of=("self",)) if for_update else queryset


def _configuration_for_write(configuration_id: uuid.UUID) -> PrayerMethodConfig:
    configuration = cast(
        PrayerMethodConfig | None,
        PrayerMethodConfig.objects.select_related("method", "release")
        .filter(pk=configuration_id)
        .first(),
    )
    if configuration is None or configuration.release.status == PrayerConfigReleaseStatus.DRAFT:
        raise PrayerMethodConfigurationNotFoundError
    return configuration


def _configuration_is_available(configuration: PrayerMethodConfig) -> bool:
    return bool(
        _configuration_is_published_and_active(configuration)
        and is_release_engine_compatible(configuration.release)
    )


def _configuration_is_published_and_active(configuration: PrayerMethodConfig) -> bool:
    return bool(
        configuration.release.status == PrayerConfigReleaseStatus.PUBLISHED
        and configuration.method.is_active
    )


def _validate_supported_rules(
    configuration: PrayerMethodConfig,
    data: dict[str, Any],
) -> None:
    supported_high_latitude = {
        str(rule) for rule, supported in high_latitude_support_items(configuration) if supported
    }
    supported_polar = {
        str(strategy) for strategy, supported in polar_support_items(configuration) if supported
    }
    errors: dict[str, str] = {}
    if data["high_latitude_rule"] not in supported_high_latitude:
        errors["high_latitude_rule"] = "The selected method does not support this rule."
    if data["polar_resolution"] not in supported_polar:
        errors["polar_resolution"] = "The selected method does not support this strategy."
    if errors:
        raise PrayerRuleUnsupportedError(detail=errors)


def _desired_state(data: dict[str, Any]) -> tuple[Any, ...]:
    adjustments = dict(data["adjustments"])
    return (
        data["method_config_id"],
        str(data["asr_method"]),
        str(data["high_latitude_rule"]),
        str(data["polar_resolution"]),
        *(
            int(adjustments[name])
            for name in ("fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha")
        ),
        str(data["timezone_mode"]),
        str(data["fixed_timezone"]),
    )


def _stored_state(profile: PrayerProfile) -> tuple[Any, ...]:
    return (
        profile.method_config_id,
        profile.asr_method,
        profile.high_latitude_rule,
        profile.polar_resolution,
        *(int(getattr(profile, field)) for field in PrayerProfile.adjustment_fields),
        profile.timezone_mode,
        profile.fixed_timezone,
    )
