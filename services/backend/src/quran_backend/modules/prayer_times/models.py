from __future__ import annotations

import hashlib
import json
from decimal import Decimal
from typing import Any, ClassVar

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models, transaction
from django.utils import timezone

from quran_backend.modules.core.models import BaseModel
from quran_backend.modules.prayer_times.timezones import (
    InvalidPrayerTimezoneError,
    get_prayer_timezone,
)
from quran_backend.modules.prayer_times.validators import (
    validate_method_code,
    validate_sha256,
    validate_version_identifier,
)


class PrayerProtectedQuerySet(models.QuerySet[Any]):
    """Force integrity-sensitive prayer aggregates through validated model methods."""

    _bulk_mutation_error = (
        "Bulk mutation is disabled for versioned prayer configuration data; "
        "use validated model methods."
    )

    def update(self, **kwargs: Any) -> int:  # noqa: ARG002
        raise ValidationError(self._bulk_mutation_error)

    def delete(self) -> tuple[int, dict[str, int]]:
        raise ValidationError(self._bulk_mutation_error)

    def bulk_create(self, *args: Any, **kwargs: Any) -> list[Any]:  # noqa: ARG002
        raise ValidationError(self._bulk_mutation_error)

    def bulk_update(self, *args: Any, **kwargs: Any) -> int:  # noqa: ARG002
        raise ValidationError(self._bulk_mutation_error)


PrayerProtectedManager = models.Manager.from_queryset(PrayerProtectedQuerySet)


class PrayerConfigReleaseStatus(models.TextChoices):
    DRAFT = "draft", "Draft"
    PUBLISHED = "published", "Published"
    WITHDRAWN = "withdrawn", "Withdrawn"


class HighLatitudeRule(models.TextChoices):
    MIDDLE_OF_NIGHT = "middle_of_night", "Middle of the night"
    SEVENTH_OF_NIGHT = "seventh_of_night", "Seventh of the night"
    TWILIGHT_ANGLE = "twilight_angle", "Twilight angle"


class PolarCircleResolution(models.TextChoices):
    UNRESOLVED = "unresolved", "No polar-circle substitution"
    AQRAB_BALAD = "aqrab_balad", "Aqrab al-balad (nearest latitude)"
    AQRAB_YAUM = "aqrab_yaum", "Aqrab al-yaum (nearest day)"


class PrayerAsrMethod(models.TextChoices):
    STANDARD = "standard", "Standard"
    HANAFI = "hanafi", "Hanafi"


class PrayerTimezoneMode(models.TextChoices):
    DEVICE_LOCAL = "device_local", "Device local"
    FIXED = "fixed", "Fixed timezone"


class PrayerMethod(BaseModel):
    """Stable public identity for a prayer-time calculation authority/method."""

    code = models.SlugField(max_length=64, unique=True, validators=[validate_method_code])
    name_ar = models.CharField(max_length=255)
    name_en = models.CharField(max_length=255)
    name_ru = models.CharField(max_length=255)
    description_ar = models.TextField(blank=True)
    description_en = models.TextField(blank=True)
    description_ru = models.TextField(blank=True)
    authority_name = models.CharField(max_length=255)
    authority_url = models.URLField()
    is_active = models.BooleanField(default=True)

    identity_fields: ClassVar[tuple[str, ...]] = (
        "code",
        "name_ar",
        "name_en",
        "name_ru",
        "description_ar",
        "description_en",
        "description_ru",
        "authority_name",
        "authority_url",
    )
    objects: ClassVar[models.Manager[PrayerMethod]] = PrayerProtectedManager()

    class Meta:
        db_table = "prayer_method"
        ordering = ["name_en", "code"]
        indexes = [
            models.Index(fields=["is_active", "name_en"], name="prayer_method_active_idx"),
        ]

    def __str__(self) -> str:
        return f"{self.name_en} ({self.code})"

    def clean(self) -> None:
        super().clean()
        if self._state.adding:
            return
        persisted = type(self).objects.filter(pk=self.pk).values(*self.identity_fields).first()
        if persisted is None or not self._has_released_configuration():
            return
        changed = [
            field for field in self.identity_fields if persisted[field] != getattr(self, field)
        ]
        if changed:
            raise ValidationError(
                dict.fromkeys(
                    changed,
                    "Method identity referenced by a released configuration is immutable.",
                )
            )

    def _has_released_configuration(self) -> bool:
        return self.configurations.exclude(release__status=PrayerConfigReleaseStatus.DRAFT).exists()

    def save(self, *args: Any, **kwargs: Any) -> None:
        with transaction.atomic():
            if not self._state.adding:
                type(self).objects.select_for_update().filter(pk=self.pk).exists()
            self.full_clean()
            super().save(*args, **kwargs)


class PrayerConfigRelease(BaseModel):
    """Atomic, append-only release of prayer calculation parameters."""

    version = models.CharField(
        max_length=64,
        unique=True,
        validators=[validate_version_identifier],
    )
    configuration_schema_version = models.PositiveSmallIntegerField()
    algorithm = models.SlugField(max_length=64, validators=[validate_method_code])
    algorithm_version = models.CharField(
        max_length=64,
        validators=[validate_version_identifier],
    )
    timezone_database_version = models.CharField(
        max_length=64,
        validators=[validate_version_identifier],
    )
    status = models.CharField(
        max_length=16,
        choices=PrayerConfigReleaseStatus,
        default=PrayerConfigReleaseStatus.DRAFT,
    )
    is_default = models.BooleanField(default=False)
    manifest_checksum_sha256 = models.CharField(
        max_length=64,
        blank=True,
        default="",
        validators=[validate_sha256],
        editable=False,
    )
    release_notes = models.TextField(blank=True)
    published_at = models.DateTimeField(null=True, blank=True, editable=False)
    withdrawn_at = models.DateTimeField(null=True, blank=True, editable=False)

    immutable_fields: ClassVar[tuple[str, ...]] = (
        "version",
        "configuration_schema_version",
        "algorithm",
        "algorithm_version",
        "timezone_database_version",
        "manifest_checksum_sha256",
        "release_notes",
        "published_at",
    )
    objects: ClassVar[models.Manager[PrayerConfigRelease]] = PrayerProtectedManager()

    class Meta:
        db_table = "prayer_config_release"
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(configuration_schema_version__gte=1),
                name="prayer_release_schema_positive",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(
                        status=PrayerConfigReleaseStatus.DRAFT,
                        is_default=False,
                        manifest_checksum_sha256="",
                        published_at__isnull=True,
                        withdrawn_at__isnull=True,
                    )
                    | (
                        models.Q(
                            status=PrayerConfigReleaseStatus.PUBLISHED,
                            published_at__isnull=False,
                            withdrawn_at__isnull=True,
                        )
                        & ~models.Q(manifest_checksum_sha256="")
                    )
                    | (
                        models.Q(
                            status=PrayerConfigReleaseStatus.WITHDRAWN,
                            is_default=False,
                            published_at__isnull=False,
                            withdrawn_at__isnull=False,
                        )
                        & ~models.Q(manifest_checksum_sha256="")
                    )
                ),
                name="prayer_release_state_valid",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(withdrawn_at__isnull=True)
                    | models.Q(withdrawn_at__gte=models.F("published_at"))
                ),
                name="prayer_release_withdraw_order",
            ),
            models.UniqueConstraint(
                fields=["is_default"],
                condition=models.Q(
                    is_default=True,
                    status=PrayerConfigReleaseStatus.PUBLISHED,
                ),
                name="prayer_one_default_release",
            ),
        ]
        indexes = [
            models.Index(
                fields=["status", "is_default", "version"],
                name="prayer_release_public_idx",
            ),
        ]

    def __str__(self) -> str:
        return f"prayer-config@{self.version}"

    def clean(self) -> None:
        super().clean()
        self._validate_lifecycle_shape()
        self._validate_state_transition_and_immutability()
        self._validate_default_invariant()
        self._validate_publishable_configurations()

    def _validate_lifecycle_shape(self) -> None:
        if self.status == PrayerConfigReleaseStatus.DRAFT:
            self._validate_draft_shape()
            return

        self._validate_released_shape()

    def _validate_draft_shape(self) -> None:
        errors: dict[str, str] = {}
        if self.published_at is not None:
            errors["published_at"] = "A draft release cannot have a publication timestamp."
        if self.withdrawn_at is not None:
            errors["withdrawn_at"] = "A draft release cannot have a withdrawal timestamp."
        if self.is_default:
            errors["is_default"] = "A draft release cannot be the public default."
        if self.manifest_checksum_sha256:
            errors["manifest_checksum_sha256"] = "Draft manifests are finalized on publication."
        if errors:
            raise ValidationError(errors)

    def _validate_released_shape(self) -> None:
        errors = {}
        if self.published_at is None:
            errors["published_at"] = "A released configuration requires a publication timestamp."
        if not self.manifest_checksum_sha256:
            errors["manifest_checksum_sha256"] = "A released configuration requires a manifest."
        if self.status == PrayerConfigReleaseStatus.PUBLISHED and self.withdrawn_at is not None:
            errors["withdrawn_at"] = "A published release cannot have a withdrawal timestamp."
        if self.status == PrayerConfigReleaseStatus.WITHDRAWN:
            if self.withdrawn_at is None:
                errors["withdrawn_at"] = "A withdrawn release requires a timestamp."
            if self.is_default:
                errors["is_default"] = "A withdrawn release cannot remain the default."
        if (
            self.published_at is not None
            and self.withdrawn_at is not None
            and self.withdrawn_at < self.published_at
        ):
            errors["withdrawn_at"] = "Withdrawal cannot precede publication."
        if errors:
            raise ValidationError(errors)

    def _validate_state_transition_and_immutability(self) -> None:
        if self._state.adding:
            return
        persisted = (
            type(self)
            .objects.filter(pk=self.pk)
            .values("status", "is_default", "withdrawn_at", *self.immutable_fields)
            .first()
        )
        if persisted is None:
            return
        if (
            persisted["status"] not in PrayerConfigReleaseStatus.values
            or self.status not in PrayerConfigReleaseStatus.values
        ):
            return
        previous_status = PrayerConfigReleaseStatus(str(persisted["status"]))
        current_status = PrayerConfigReleaseStatus(self.status)
        allowed_transitions = {
            PrayerConfigReleaseStatus.DRAFT: {
                PrayerConfigReleaseStatus.DRAFT,
                PrayerConfigReleaseStatus.PUBLISHED,
            },
            PrayerConfigReleaseStatus.PUBLISHED: {
                PrayerConfigReleaseStatus.PUBLISHED,
                PrayerConfigReleaseStatus.WITHDRAWN,
            },
            PrayerConfigReleaseStatus.WITHDRAWN: {
                PrayerConfigReleaseStatus.WITHDRAWN,
            },
        }
        if current_status not in allowed_transitions[previous_status]:
            raise ValidationError({"status": "This release status transition is not allowed."})
        if previous_status == PrayerConfigReleaseStatus.DRAFT:
            return
        changed = [
            field for field in self.immutable_fields if persisted[field] != getattr(self, field)
        ]
        if changed:
            raise ValidationError(
                dict.fromkeys(changed, "Released configuration is immutable; create a new release.")
            )
        if previous_status == PrayerConfigReleaseStatus.WITHDRAWN and (
            bool(persisted["is_default"]) != self.is_default
            or persisted["withdrawn_at"] != self.withdrawn_at
        ):
            raise ValidationError("Withdrawn release lifecycle metadata is immutable.")

    def _validate_default_invariant(self) -> None:
        if self.status != PrayerConfigReleaseStatus.PUBLISHED or self.is_default:
            return
        default_exists = (
            type(self)
            .objects.filter(
                status=PrayerConfigReleaseStatus.PUBLISHED,
                is_default=True,
            )
            .exclude(pk=self.pk)
            .exists()
        )
        if not default_exists:
            raise ValidationError(
                {"is_default": "The first published release must become the default."}
            )

    def _validate_publishable_configurations(self) -> None:
        if self.status != PrayerConfigReleaseStatus.PUBLISHED:
            return
        if self._state.adding or self.pk is None:
            raise ValidationError(
                {"status": "Create the release as a draft and add method configurations first."}
            )
        configurations = list(
            self.method_configurations.select_related("method").order_by("method__code", "id")
        )
        if not configurations:
            raise ValidationError(
                {"status": "At least one prayer method configuration is required."}
            )
        for configuration in configurations:
            if not configuration.method.is_active:
                raise ValidationError(
                    {"status": f"Method {configuration.method.code!r} is inactive."}
                )
            expected_checksum = configuration.calculate_checksum()
            if configuration.checksum_sha256 != expected_checksum:
                raise ValidationError(
                    {
                        "manifest_checksum_sha256": (
                            f"Configuration checksum is stale for {configuration.method.code!r}."
                        )
                    }
                )
        expected_manifest = self.calculate_manifest_checksum(configurations)
        if self.manifest_checksum_sha256 != expected_manifest:
            raise ValidationError(
                {"manifest_checksum_sha256": "The release manifest checksum is stale."}
            )

    def calculate_manifest_checksum(
        self,
        configurations: list[PrayerMethodConfig] | None = None,
    ) -> str:
        if self.pk is None:
            raise ValidationError("Save the draft release before calculating its manifest.")
        if configurations is None:
            configurations = list(
                self.method_configurations.select_related("method").order_by("method__code", "id")
            )
        payload = {
            "algorithm": self.algorithm,
            "algorithm_version": self.algorithm_version,
            "configuration_schema_version": self.configuration_schema_version,
            "methods": [
                {
                    "checksum_sha256": configuration.checksum_sha256,
                    "code": configuration.method.code,
                }
                for configuration in configurations
            ],
            "timezone_database_version": self.timezone_database_version,
            "version": self.version,
        }
        serialized = json.dumps(
            payload,
            ensure_ascii=True,
            separators=(",", ":"),
            sort_keys=True,
        ).encode()
        return hashlib.sha256(serialized).hexdigest()

    def publish(self, *, make_default: bool) -> None:
        if self.status != PrayerConfigReleaseStatus.DRAFT:
            raise ValidationError({"status": "Only a draft release can be published."})
        if self.pk is None:
            raise ValidationError({"status": "Save the draft before publishing it."})
        configurations = list(
            self.method_configurations.select_related("method").order_by("method__code", "id")
        )
        if not configurations:
            raise ValidationError(
                {"status": "At least one prayer method configuration is required."}
            )
        self.status = PrayerConfigReleaseStatus.PUBLISHED
        self.is_default = make_default
        self.published_at = timezone.now()
        self.withdrawn_at = None
        self.manifest_checksum_sha256 = self.calculate_manifest_checksum(configurations)

    def withdraw(self) -> None:
        if self.status != PrayerConfigReleaseStatus.PUBLISHED:
            raise ValidationError({"status": "Only a published release can be withdrawn."})
        if self.is_default:
            raise ValidationError(
                {"is_default": "Publish another default release before withdrawing this one."}
            )
        self.status = PrayerConfigReleaseStatus.WITHDRAWN
        self.withdrawn_at = timezone.now()

    def save(self, *args: Any, **kwargs: Any) -> None:
        with transaction.atomic():
            list(
                type(self)
                .objects.select_for_update()
                .filter(
                    models.Q(pk=self.pk)
                    | models.Q(
                        status=PrayerConfigReleaseStatus.PUBLISHED,
                        is_default=True,
                    )
                )
                .order_by("pk")
                .values_list("pk", flat=True)
            )
            if self.status == PrayerConfigReleaseStatus.PUBLISHED and self.is_default:
                previous_defaults = (
                    type(self)
                    .objects.filter(
                        status=PrayerConfigReleaseStatus.PUBLISHED,
                        is_default=True,
                    )
                    .exclude(pk=self.pk)
                )
                models.QuerySet.update(
                    previous_defaults,
                    is_default=False,
                    updated_at=timezone.now(),
                )
            if self.pk is not None:
                method_ids = self.method_configurations.values_list("method_id", flat=True)
                list(
                    PrayerMethod.objects.select_for_update()
                    .filter(pk__in=method_ids)
                    .order_by("pk")
                    .values_list("pk", flat=True)
                )
            self.full_clean()
            super().save(*args, **kwargs)

    def delete(self, *args: Any, **kwargs: Any) -> tuple[int, dict[str, int]]:
        with transaction.atomic():
            persisted_status = (
                type(self)
                .objects.select_for_update()
                .filter(pk=self.pk)
                .values_list("status", flat=True)
                .first()
            )
            if (
                self.status != PrayerConfigReleaseStatus.DRAFT
                or persisted_status != PrayerConfigReleaseStatus.DRAFT
            ):
                raise ValidationError("Published or withdrawn prayer releases cannot be deleted.")
            return super().delete(*args, **kwargs)


def _lock_release_rows(release_ids: set[Any]) -> None:
    if not release_ids:
        return
    list(
        PrayerConfigRelease.objects.select_for_update()
        .filter(pk__in=release_ids)
        .order_by("pk")
        .values_list("pk", flat=True)
    )


class PrayerMethodConfig(BaseModel):
    """Strict calculation parameters for one method in an atomic release."""

    release = models.ForeignKey(
        PrayerConfigRelease,
        on_delete=models.CASCADE,
        related_name="method_configurations",
    )
    method = models.ForeignKey(
        PrayerMethod,
        on_delete=models.PROTECT,
        related_name="configurations",
    )
    fajr_angle = models.DecimalField(max_digits=4, decimal_places=2)
    isha_angle = models.DecimalField(max_digits=4, decimal_places=2, null=True, blank=True)
    isha_interval_minutes = models.PositiveSmallIntegerField(null=True, blank=True)
    ramadan_isha_interval_minutes = models.PositiveSmallIntegerField(null=True, blank=True)

    fajr_adjustment_minutes = models.SmallIntegerField(default=0)
    sunrise_adjustment_minutes = models.SmallIntegerField(default=0)
    dhuhr_adjustment_minutes = models.SmallIntegerField(default=0)
    asr_adjustment_minutes = models.SmallIntegerField(default=0)
    maghrib_adjustment_minutes = models.SmallIntegerField(default=0)
    isha_adjustment_minutes = models.SmallIntegerField(default=0)

    supports_middle_of_night = models.BooleanField()
    supports_seventh_of_night = models.BooleanField()
    supports_twilight_angle = models.BooleanField()
    default_high_latitude_rule = models.CharField(max_length=24, choices=HighLatitudeRule)

    supports_polar_unresolved = models.BooleanField()
    supports_polar_aqrab_balad = models.BooleanField()
    supports_polar_aqrab_yaum = models.BooleanField()
    default_polar_resolution = models.CharField(max_length=16, choices=PolarCircleResolution)

    source_name = models.CharField(max_length=255)
    source_url = models.URLField()
    source_version = models.CharField(max_length=128)
    source_checksum_sha256 = models.CharField(max_length=64, validators=[validate_sha256])
    checksum_sha256 = models.CharField(
        max_length=64,
        validators=[validate_sha256],
        editable=False,
    )

    adjustment_fields: ClassVar[tuple[str, ...]] = (
        "fajr_adjustment_minutes",
        "sunrise_adjustment_minutes",
        "dhuhr_adjustment_minutes",
        "asr_adjustment_minutes",
        "maghrib_adjustment_minutes",
        "isha_adjustment_minutes",
    )
    objects: ClassVar[models.Manager[PrayerMethodConfig]] = PrayerProtectedManager()

    class Meta:
        db_table = "prayer_method_config"
        ordering = ["release", "method__name_en", "method__code"]
        constraints = [
            models.UniqueConstraint(
                fields=["release", "method"],
                name="prayer_config_release_method_uq",
            ),
            models.CheckConstraint(
                condition=models.Q(fajr_angle__gt=0, fajr_angle__lte=30),
                name="prayer_config_fajr_angle",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(
                        isha_angle__gt=0,
                        isha_angle__lte=30,
                        isha_interval_minutes__isnull=True,
                        ramadan_isha_interval_minutes__isnull=True,
                    )
                    | models.Q(
                        isha_angle__isnull=True,
                        isha_interval_minutes__gt=0,
                        isha_interval_minutes__lte=300,
                    )
                ),
                name="prayer_config_isha_mode",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(ramadan_isha_interval_minutes__isnull=True)
                    | models.Q(
                        isha_angle__isnull=True,
                        isha_interval_minutes__isnull=False,
                        ramadan_isha_interval_minutes__gt=0,
                        ramadan_isha_interval_minutes__lte=300,
                    )
                ),
                name="prayer_config_ramadan_isha",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(fajr_adjustment_minutes__gte=-120, fajr_adjustment_minutes__lte=120)
                    & models.Q(
                        sunrise_adjustment_minutes__gte=-120,
                        sunrise_adjustment_minutes__lte=120,
                    )
                    & models.Q(
                        dhuhr_adjustment_minutes__gte=-120,
                        dhuhr_adjustment_minutes__lte=120,
                    )
                    & models.Q(asr_adjustment_minutes__gte=-120, asr_adjustment_minutes__lte=120)
                    & models.Q(
                        maghrib_adjustment_minutes__gte=-120,
                        maghrib_adjustment_minutes__lte=120,
                    )
                    & models.Q(isha_adjustment_minutes__gte=-120, isha_adjustment_minutes__lte=120)
                ),
                name="prayer_config_adjustments",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(
                        default_high_latitude_rule=HighLatitudeRule.MIDDLE_OF_NIGHT,
                        supports_middle_of_night=True,
                    )
                    | models.Q(
                        default_high_latitude_rule=HighLatitudeRule.SEVENTH_OF_NIGHT,
                        supports_seventh_of_night=True,
                    )
                    | models.Q(
                        default_high_latitude_rule=HighLatitudeRule.TWILIGHT_ANGLE,
                        supports_twilight_angle=True,
                    )
                ),
                name="prayer_config_hl_default_ok",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(
                        default_polar_resolution=PolarCircleResolution.UNRESOLVED,
                        supports_polar_unresolved=True,
                    )
                    | models.Q(
                        default_polar_resolution=PolarCircleResolution.AQRAB_BALAD,
                        supports_polar_aqrab_balad=True,
                    )
                    | models.Q(
                        default_polar_resolution=PolarCircleResolution.AQRAB_YAUM,
                        supports_polar_aqrab_yaum=True,
                    )
                ),
                name="prayer_config_polar_default_ok",
            ),
        ]
        indexes = [
            models.Index(fields=["release", "method"], name="prayer_config_lookup_idx"),
            models.Index(fields=["method", "release"], name="prayer_config_method_idx"),
        ]

    def __str__(self) -> str:
        return f"{self.release.version}:{self.method.code}"

    def clean(self) -> None:
        super().clean()
        self._assert_release_is_mutable()
        if (self.isha_angle is None) == (self.isha_interval_minutes is None):
            raise ValidationError(
                {
                    "isha_angle": (
                        "Choose exactly one Isha mode: twilight angle or fixed interval."
                    ),
                    "isha_interval_minutes": (
                        "Choose exactly one Isha mode: twilight angle or fixed interval."
                    ),
                }
            )
        if self.isha_angle is not None and self.ramadan_isha_interval_minutes is not None:
            raise ValidationError(
                {
                    "ramadan_isha_interval_minutes": (
                        "A Ramadan interval is only valid for fixed-interval Isha methods."
                    )
                }
            )
        for field in self.adjustment_fields:
            raw_value = getattr(self, field)
            if raw_value is None:
                continue
            value = int(raw_value)
            if not -120 <= value <= 120:
                raise ValidationError({field: "Adjustment must be between -120 and 120 minutes."})
        high_latitude_support: dict[str, bool] = {
            HighLatitudeRule.MIDDLE_OF_NIGHT: self.supports_middle_of_night,
            HighLatitudeRule.SEVENTH_OF_NIGHT: self.supports_seventh_of_night,
            HighLatitudeRule.TWILIGHT_ANGLE: self.supports_twilight_angle,
        }
        if not high_latitude_support.get(self.default_high_latitude_rule, False):
            raise ValidationError(
                {"default_high_latitude_rule": "The default high-latitude rule must be supported."}
            )
        polar_support: dict[str, bool] = {
            PolarCircleResolution.UNRESOLVED: self.supports_polar_unresolved,
            PolarCircleResolution.AQRAB_BALAD: self.supports_polar_aqrab_balad,
            PolarCircleResolution.AQRAB_YAUM: self.supports_polar_aqrab_yaum,
        }
        if not polar_support.get(self.default_polar_resolution, False):
            raise ValidationError(
                {"default_polar_resolution": "The default polar strategy must be supported."}
            )

    def calculate_checksum(self) -> str:
        release_data = (
            PrayerConfigRelease.objects.filter(pk=self.release_id)
            .values("configuration_schema_version")
            .first()
        )
        method_code = (
            PrayerMethod.objects.filter(pk=self.method_id).values_list("code", flat=True).first()
        )
        if release_data is None:
            raise ValidationError({"release": "Save the draft release first."})
        if method_code is None:
            raise ValidationError({"method": "Save the prayer method first."})
        payload = {
            "adjustments": {
                field.removesuffix("_adjustment_minutes"): int(getattr(self, field))
                for field in self.adjustment_fields
            },
            "default_high_latitude_rule": self.default_high_latitude_rule,
            "default_polar_resolution": self.default_polar_resolution,
            "fajr_angle": _canonical_decimal(self.fajr_angle),
            "isha_angle": _canonical_decimal(self.isha_angle),
            "isha_interval_minutes": self.isha_interval_minutes,
            "method": method_code,
            "ramadan_isha_interval_minutes": self.ramadan_isha_interval_minutes,
            "schema_version": release_data["configuration_schema_version"],
            "source": {
                "checksum_sha256": self.source_checksum_sha256,
                "name": self.source_name,
                "url": self.source_url,
                "version": self.source_version,
            },
            "supported_high_latitude_rules": sorted(
                str(rule) for rule, supported in high_latitude_support_items(self) if supported
            ),
            "supported_polar_resolutions": sorted(
                str(strategy) for strategy, supported in polar_support_items(self) if supported
            ),
        }
        serialized = json.dumps(
            payload,
            ensure_ascii=True,
            separators=(",", ":"),
            sort_keys=True,
        ).encode()
        return hashlib.sha256(serialized).hexdigest()

    def _assert_release_is_mutable(self) -> None:
        release_id = self.__dict__.get("release_id")
        if release_id is None:
            return
        target_status = (
            PrayerConfigRelease.objects.filter(pk=release_id)
            .values_list("status", flat=True)
            .first()
        )
        persisted_status = None
        if not self._state.adding:
            persisted_status = (
                type(self)
                .objects.filter(pk=self.pk)
                .values_list("release__status", flat=True)
                .first()
            )
        immutable_statuses = {
            PrayerConfigReleaseStatus.PUBLISHED,
            PrayerConfigReleaseStatus.WITHDRAWN,
        }
        if target_status in immutable_statuses or persisted_status in immutable_statuses:
            raise ValidationError("Configurations in a released manifest are immutable.")

    def save(self, *args: Any, **kwargs: Any) -> None:
        with transaction.atomic():
            _lock_release_rows(self._related_release_ids())
            self._assert_release_is_mutable()
            self.full_clean(exclude={"checksum_sha256"})
            self.checksum_sha256 = self.calculate_checksum()
            update_fields = kwargs.get("update_fields")
            if update_fields is not None:
                kwargs["update_fields"] = {*update_fields, "checksum_sha256"}
            super().save(*args, **kwargs)

    def delete(self, *args: Any, **kwargs: Any) -> tuple[int, dict[str, int]]:
        with transaction.atomic():
            _lock_release_rows(self._related_release_ids())
            self._assert_release_is_mutable()
            return super().delete(*args, **kwargs)

    def _related_release_ids(self) -> set[Any]:
        release_ids = {self.release_id}
        if not self._state.adding:
            persisted_id = (
                type(self).objects.filter(pk=self.pk).values_list("release_id", flat=True).first()
            )
            if persisted_id is not None:
                release_ids.add(persisted_id)
        return release_ids


def _canonical_decimal(value: Decimal | None) -> str | None:
    if value is None:
        return None
    return format(Decimal(value).quantize(Decimal("0.01")), ".2f")


def high_latitude_support_items(
    configuration: PrayerMethodConfig,
) -> tuple[tuple[HighLatitudeRule, bool], ...]:
    return (
        (HighLatitudeRule.MIDDLE_OF_NIGHT, configuration.supports_middle_of_night),
        (HighLatitudeRule.SEVENTH_OF_NIGHT, configuration.supports_seventh_of_night),
        (HighLatitudeRule.TWILIGHT_ANGLE, configuration.supports_twilight_angle),
    )


def polar_support_items(
    configuration: PrayerMethodConfig,
) -> tuple[tuple[PolarCircleResolution, bool], ...]:
    return (
        (PolarCircleResolution.UNRESOLVED, configuration.supports_polar_unresolved),
        (PolarCircleResolution.AQRAB_BALAD, configuration.supports_polar_aqrab_balad),
        (PolarCircleResolution.AQRAB_YAUM, configuration.supports_polar_aqrab_yaum),
    )


class PrayerProfile(BaseModel):
    """Versioned user calculation preferences; deliberately contains no location data."""

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="prayer_profile",
    )
    method_config = models.ForeignKey(
        PrayerMethodConfig,
        on_delete=models.PROTECT,
        related_name="profiles",
    )
    asr_method = models.CharField(
        max_length=16,
        choices=PrayerAsrMethod,
        default=PrayerAsrMethod.STANDARD,
    )
    high_latitude_rule = models.CharField(max_length=24, choices=HighLatitudeRule)
    polar_resolution = models.CharField(max_length=16, choices=PolarCircleResolution)

    fajr_adjustment_minutes = models.SmallIntegerField(default=0)
    sunrise_adjustment_minutes = models.SmallIntegerField(default=0)
    dhuhr_adjustment_minutes = models.SmallIntegerField(default=0)
    asr_adjustment_minutes = models.SmallIntegerField(default=0)
    maghrib_adjustment_minutes = models.SmallIntegerField(default=0)
    isha_adjustment_minutes = models.SmallIntegerField(default=0)

    timezone_mode = models.CharField(
        max_length=16,
        choices=PrayerTimezoneMode,
        default=PrayerTimezoneMode.DEVICE_LOCAL,
    )
    fixed_timezone = models.CharField(max_length=255, blank=True, default="")
    revision = models.PositiveBigIntegerField(default=1)
    client_updated_at = models.DateTimeField()
    device = models.ForeignKey(
        "accounts.Device",
        on_delete=models.SET_NULL,
        related_name="prayer_profiles",
        null=True,
        blank=True,
    )

    adjustment_fields: ClassVar[tuple[str, ...]] = PrayerMethodConfig.adjustment_fields

    class Meta:
        db_table = "prayer_profile"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(revision__gte=1),
                name="prayer_profile_revision_positive",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(
                        timezone_mode=PrayerTimezoneMode.DEVICE_LOCAL,
                        fixed_timezone="",
                    )
                    | (
                        models.Q(timezone_mode=PrayerTimezoneMode.FIXED)
                        & ~models.Q(fixed_timezone="")
                    )
                ),
                name="prayer_profile_timezone_shape",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(fajr_adjustment_minutes__gte=-120, fajr_adjustment_minutes__lte=120)
                    & models.Q(
                        sunrise_adjustment_minutes__gte=-120,
                        sunrise_adjustment_minutes__lte=120,
                    )
                    & models.Q(
                        dhuhr_adjustment_minutes__gte=-120,
                        dhuhr_adjustment_minutes__lte=120,
                    )
                    & models.Q(asr_adjustment_minutes__gte=-120, asr_adjustment_minutes__lte=120)
                    & models.Q(
                        maghrib_adjustment_minutes__gte=-120,
                        maghrib_adjustment_minutes__lte=120,
                    )
                    & models.Q(isha_adjustment_minutes__gte=-120, isha_adjustment_minutes__lte=120)
                ),
                name="prayer_profile_adjustments",
            ),
        ]
        indexes = [
            models.Index(fields=["method_config"], name="prayer_profile_method_idx"),
        ]

    def __str__(self) -> str:
        return f"prayer-profile:{self.user_id}"

    def clean(self) -> None:
        super().clean()
        errors: dict[str, str] = {}
        for field in self.adjustment_fields:
            value = int(getattr(self, field))
            if not -120 <= value <= 120:
                errors[field] = "Adjustment must be between -120 and 120 minutes."

        configuration = self.method_config
        supported_high_latitude = {
            str(rule) for rule, supported in high_latitude_support_items(configuration) if supported
        }
        if self.high_latitude_rule not in supported_high_latitude:
            errors["high_latitude_rule"] = "The selected method does not support this rule."
        supported_polar = {
            str(strategy) for strategy, supported in polar_support_items(configuration) if supported
        }
        if self.polar_resolution not in supported_polar:
            errors["polar_resolution"] = "The selected method does not support this strategy."

        if self.timezone_mode == PrayerTimezoneMode.DEVICE_LOCAL:
            if self.fixed_timezone:
                errors["fixed_timezone"] = "Device-local mode cannot store a fixed timezone."
        elif self.timezone_mode == PrayerTimezoneMode.FIXED:
            if not self.fixed_timezone:
                errors["fixed_timezone"] = "A fixed timezone is required in fixed mode."
            else:
                try:
                    get_prayer_timezone(self.fixed_timezone)
                except InvalidPrayerTimezoneError:
                    errors["fixed_timezone"] = (
                        "Use a timezone identifier available in the pinned IANA database."
                    )

        device = self.device
        if device is not None and device.user_id != self.user_id:
            errors["device"] = "Device must belong to the same user."
        if errors:
            raise ValidationError(errors)

    def save(self, *args: Any, **kwargs: Any) -> None:
        # Database constraints remain authoritative for uniqueness and row
        # shape; domain checks here protect IANA/rule/device invariants that
        # cannot be represented portably as SQL constraints.
        self.full_clean(validate_unique=False, validate_constraints=False)
        super().save(*args, **kwargs)
