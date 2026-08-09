from __future__ import annotations

import uuid
from typing import cast

from django.db.models import Prefetch

from quran_backend.modules.prayer_times.exceptions import (
    PrayerConfigurationUnavailableError,
    PrayerMethodConfigurationNotFoundError,
    PrayerMethodConfigurationWithdrawnError,
)
from quran_backend.modules.prayer_times.models import (
    PrayerConfigRelease,
    PrayerConfigReleaseStatus,
    PrayerMethodConfig,
)


def default_public_release() -> PrayerConfigRelease:
    configurations = PrayerMethodConfig.objects.select_related("method").order_by(
        "method__name_en",
        "method__code",
        "id",
    )
    release = (
        PrayerConfigRelease.objects.filter(
            status=PrayerConfigReleaseStatus.PUBLISHED,
            is_default=True,
        )
        .prefetch_related(
            Prefetch(
                "method_configurations",
                queryset=configurations,
                to_attr="public_method_configurations",
            )
        )
        .first()
    )
    if release is None:
        raise PrayerConfigurationUnavailableError
    return cast(PrayerConfigRelease, release)


def calculation_method_configuration(configuration_id: uuid.UUID) -> PrayerMethodConfig:
    configuration = (
        PrayerMethodConfig.objects.select_related("release", "method")
        .filter(pk=configuration_id)
        .first()
    )
    if configuration is None or configuration.release.status == PrayerConfigReleaseStatus.DRAFT:
        raise PrayerMethodConfigurationNotFoundError
    if (
        configuration.release.status == PrayerConfigReleaseStatus.WITHDRAWN
        or not configuration.method.is_active
    ):
        raise PrayerMethodConfigurationWithdrawnError
    return cast(PrayerMethodConfig, configuration)
