from __future__ import annotations

from decimal import Decimal

import pytest
from django.contrib import admin
from django.core.exceptions import ValidationError
from django.db import models
from django.test import RequestFactory

from quran_backend.modules.accounts.models import User
from quran_backend.modules.prayer_times.admin import (
    PrayerConfigReleaseAdmin,
    PrayerMethodAdmin,
    PrayerMethodConfigAdmin,
)
from quran_backend.modules.prayer_times.models import (
    HighLatitudeRule,
    PolarCircleResolution,
    PrayerConfigRelease,
    PrayerConfigReleaseStatus,
    PrayerMethod,
    PrayerMethodConfig,
)
from quran_backend.modules.prayer_times.validators import (
    validate_method_code,
    validate_sha256,
    validate_version_identifier,
)


@pytest.fixture
def prayer_method(db: None) -> PrayerMethod:
    return PrayerMethod.objects.create(
        code="test-authority",
        name_ar="طريقة اختبارية",
        name_en="Test authority",
        name_ru="Тестовый метод",
        authority_name="Synthetic test authority",
        authority_url="https://example.test/prayer-method",
    )


def _create_release(*, version: str = "test-2026.1") -> PrayerConfigRelease:
    return PrayerConfigRelease.objects.create(
        version=version,
        configuration_schema_version=1,
        algorithm="test-engine",
        algorithm_version="1.0.0",
        timezone_database_version="2026a",
        release_notes="Synthetic test release; not religious source data.",
    )


def _create_config(  # noqa: PLR0913
    release: PrayerConfigRelease,
    method: PrayerMethod,
    *,
    fajr_angle: Decimal = Decimal("18.00"),
    isha_angle: Decimal | None = Decimal("17.00"),
    isha_interval_minutes: int | None = None,
    ramadan_isha_interval_minutes: int | None = None,
) -> PrayerMethodConfig:
    return PrayerMethodConfig.objects.create(
        release=release,
        method=method,
        fajr_angle=fajr_angle,
        isha_angle=isha_angle,
        isha_interval_minutes=isha_interval_minutes,
        ramadan_isha_interval_minutes=ramadan_isha_interval_minutes,
        supports_middle_of_night=True,
        supports_seventh_of_night=True,
        supports_twilight_angle=True,
        default_high_latitude_rule=HighLatitudeRule.MIDDLE_OF_NIGHT,
        supports_polar_unresolved=True,
        supports_polar_aqrab_balad=True,
        supports_polar_aqrab_yaum=True,
        default_polar_resolution=PolarCircleResolution.UNRESOLVED,
        source_name="Synthetic parameter fixture",
        source_url="https://example.test/prayer-parameters",
        source_version="1.0.0",
        source_checksum_sha256="a" * 64,
    )


def _publish(release: PrayerConfigRelease, *, make_default: bool) -> None:
    release.publish(make_default=make_default)
    release.save()


@pytest.mark.parametrize("value", ["", "A" * 64, "a" * 63, "g" * 64])
def test_prayer_sha256_validator_requires_canonical_digest(value: str) -> None:
    with pytest.raises(ValidationError):
        validate_sha256(value)
    validate_sha256("0123456789abcdef" * 4)


@pytest.mark.parametrize("value", ["", ".version", "release/1", "v 1", "v" * 65])
def test_prayer_version_validator_rejects_unsafe_identifiers(value: str) -> None:
    with pytest.raises(ValidationError):
        validate_version_identifier(value)
    validate_version_identifier("2026.1-tzdb_2026a")


@pytest.mark.parametrize("value", ["a", "Uppercase", "under_score", "method/path", "метод"])
def test_prayer_method_code_is_stable_lowercase_ascii(value: str) -> None:
    with pytest.raises(ValidationError):
        validate_method_code(value)
    validate_method_code("muslim-world-league")


@pytest.mark.django_db
def test_method_config_checksum_is_deterministic_and_tracks_parameter_changes(
    prayer_method: PrayerMethod,
) -> None:
    release = _create_release()
    config = _create_config(release, prayer_method)
    initial_checksum = config.checksum_sha256

    assert initial_checksum == config.calculate_checksum()
    assert len(initial_checksum) == 64

    config.fajr_adjustment_minutes = 2
    config.save()
    assert config.checksum_sha256 == config.calculate_checksum()
    assert config.checksum_sha256 != initial_checksum


@pytest.mark.django_db
def test_method_config_partial_save_persists_recalculated_checksum(
    prayer_method: PrayerMethod,
) -> None:
    release = _create_release()
    config = _create_config(release, prayer_method)
    initial_checksum = config.checksum_sha256

    config.fajr_adjustment_minutes = 3
    config.save(update_fields={"fajr_adjustment_minutes"})
    config.refresh_from_db()

    assert config.checksum_sha256 != initial_checksum
    assert config.checksum_sha256 == config.calculate_checksum()


@pytest.mark.django_db
def test_method_config_requires_exactly_one_isha_mode(
    prayer_method: PrayerMethod,
) -> None:
    release = _create_release()
    config = _create_config(release, prayer_method)

    config.isha_interval_minutes = 90
    with pytest.raises(ValidationError) as both_error:
        config.save()
    assert "isha_angle" in both_error.value.message_dict

    config.isha_angle = None
    config.isha_interval_minutes = None
    with pytest.raises(ValidationError) as neither_error:
        config.save()
    assert "isha_interval_minutes" in neither_error.value.message_dict


@pytest.mark.django_db
def test_ramadan_interval_only_applies_to_fixed_interval_isha(
    prayer_method: PrayerMethod,
) -> None:
    release = _create_release()
    config = _create_config(release, prayer_method)
    config.ramadan_isha_interval_minutes = 120

    with pytest.raises(ValidationError) as error:
        config.save()

    assert "ramadan_isha_interval_minutes" in error.value.message_dict

    config.isha_angle = None
    config.isha_interval_minutes = 90
    config.save()
    assert config.ramadan_isha_interval_minutes == 120


@pytest.mark.django_db
def test_defaults_must_be_declared_as_supported(prayer_method: PrayerMethod) -> None:
    release = _create_release()
    config = _create_config(release, prayer_method)

    config.supports_middle_of_night = False
    with pytest.raises(ValidationError) as high_latitude_error:
        config.save()
    assert "default_high_latitude_rule" in high_latitude_error.value.message_dict

    config.supports_middle_of_night = True
    config.supports_polar_unresolved = False
    with pytest.raises(ValidationError) as polar_error:
        config.save()
    assert "default_polar_resolution" in polar_error.value.message_dict


@pytest.mark.django_db
def test_first_published_release_must_be_default(prayer_method: PrayerMethod) -> None:
    models.QuerySet.update(
        PrayerConfigRelease.objects.filter(is_default=True),
        is_default=False,
    )
    release = _create_release()
    _create_config(release, prayer_method)
    release.publish(make_default=False)

    with pytest.raises(ValidationError) as error:
        release.save()

    assert "is_default" in error.value.message_dict
    release.refresh_from_db()
    assert release.status == PrayerConfigReleaseStatus.DRAFT
    assert release.manifest_checksum_sha256 == ""


@pytest.mark.django_db
def test_release_cannot_publish_without_method_configurations() -> None:
    release = _create_release()

    with pytest.raises(ValidationError) as error:
        release.publish(make_default=True)

    assert "status" in error.value.message_dict
    assert release.status == PrayerConfigReleaseStatus.DRAFT


@pytest.mark.django_db
def test_publication_rejects_stale_child_checksum(prayer_method: PrayerMethod) -> None:
    release = _create_release()
    config = _create_config(release, prayer_method)
    models.QuerySet.update(
        PrayerMethodConfig.objects.filter(pk=config.pk),
        fajr_angle=Decimal("19.00"),
    )

    release.publish(make_default=True)
    with pytest.raises(ValidationError) as error:
        release.save()

    assert "manifest_checksum_sha256" in error.value.message_dict
    release.refresh_from_db()
    assert release.status == PrayerConfigReleaseStatus.DRAFT


@pytest.mark.django_db
def test_publication_rejects_inactive_method(prayer_method: PrayerMethod) -> None:
    release = _create_release()
    _create_config(release, prayer_method)
    prayer_method.is_active = False
    prayer_method.save()

    release.publish(make_default=True)
    with pytest.raises(ValidationError) as error:
        release.save()

    assert "status" in error.value.message_dict


@pytest.mark.django_db
def test_publication_builds_verified_manifest_and_freezes_aggregate(
    prayer_method: PrayerMethod,
) -> None:
    release = _create_release()
    config = _create_config(release, prayer_method)

    _publish(release, make_default=True)
    release.refresh_from_db()
    assert release.status == PrayerConfigReleaseStatus.PUBLISHED
    assert release.is_default is True
    assert release.published_at is not None
    assert release.manifest_checksum_sha256 == release.calculate_manifest_checksum()

    config.fajr_angle = Decimal("19.00")
    with pytest.raises(ValidationError):
        config.save()

    release.release_notes = "Attempted retroactive edit"
    with pytest.raises(ValidationError) as release_error:
        release.save()
    assert "release_notes" in release_error.value.message_dict

    with pytest.raises(ValidationError):
        release.delete()


@pytest.mark.django_db
def test_versioned_prayer_aggregates_reject_all_public_bulk_mutation_apis(
    prayer_method: PrayerMethod,
) -> None:
    release = _create_release()
    config = _create_config(release, prayer_method)
    _publish(release, make_default=True)

    for queryset in (
        PrayerMethod.objects.filter(pk=prayer_method.pk),
        PrayerConfigRelease.objects.filter(pk=release.pk),
        PrayerMethodConfig.objects.filter(pk=config.pk),
    ):
        with pytest.raises(ValidationError, match="Bulk mutation is disabled"):
            queryset.update(updated_at=release.updated_at)
        with pytest.raises(ValidationError, match="Bulk mutation is disabled"):
            queryset.delete()

    config.fajr_angle = Decimal("19.00")
    with pytest.raises(ValidationError, match="Bulk mutation is disabled"):
        PrayerMethodConfig.objects.bulk_update([config], ["fajr_angle"])
    with pytest.raises(ValidationError, match="Bulk mutation is disabled"):
        PrayerMethod.objects.bulk_create([])

    release.refresh_from_db()
    config.refresh_from_db()
    prayer_method.refresh_from_db()
    assert release.status == PrayerConfigReleaseStatus.PUBLISHED
    assert config.fajr_angle == Decimal("18.00")
    assert prayer_method.code == "test-authority"


@pytest.mark.django_db
def test_published_config_cannot_be_reparented_via_stale_object(
    prayer_method: PrayerMethod,
) -> None:
    published_release = _create_release(version="test-2026.1")
    config = _create_config(published_release, prayer_method)
    _publish(published_release, make_default=True)
    draft_release = _create_release(version="test-2026.2")

    config.release = draft_release
    with pytest.raises(ValidationError):
        config.save()

    config.refresh_from_db()
    assert config.release_id == published_release.id


@pytest.mark.django_db
def test_publishing_new_default_atomically_demotes_previous_default(
    prayer_method: PrayerMethod,
) -> None:
    first = _create_release(version="test-2026.1")
    _create_config(first, prayer_method)
    _publish(first, make_default=True)

    second = _create_release(version="test-2026.2")
    _create_config(second, prayer_method)
    _publish(second, make_default=True)

    first.refresh_from_db()
    second.refresh_from_db()
    assert first.is_default is False
    assert second.is_default is True
    assert (
        PrayerConfigRelease.objects.filter(
            status=PrayerConfigReleaseStatus.PUBLISHED,
            is_default=True,
        ).count()
        == 1
    )


@pytest.mark.django_db
def test_default_cannot_be_withdrawn_until_replaced(prayer_method: PrayerMethod) -> None:
    first = _create_release(version="test-2026.1")
    _create_config(first, prayer_method)
    _publish(first, make_default=True)

    with pytest.raises(ValidationError) as error:
        first.withdraw()
    assert "is_default" in error.value.message_dict

    second = _create_release(version="test-2026.2")
    _create_config(second, prayer_method)
    _publish(second, make_default=True)
    first.refresh_from_db()
    first.withdraw()
    first.save()
    assert first.status == PrayerConfigReleaseStatus.WITHDRAWN
    assert first.withdrawn_at is not None


@pytest.mark.django_db
def test_method_identity_freezes_after_release_but_can_be_deactivated(
    prayer_method: PrayerMethod,
) -> None:
    release = _create_release()
    _create_config(release, prayer_method)
    _publish(release, make_default=True)

    prayer_method.code = "renamed-authority"
    with pytest.raises(ValidationError) as error:
        prayer_method.save()
    assert "code" in error.value.message_dict

    prayer_method.refresh_from_db()
    prayer_method.is_active = False
    prayer_method.save()
    assert prayer_method.is_active is False


@pytest.mark.django_db
def test_prayer_admin_disables_bulk_delete_and_freezes_released_rows(
    prayer_method: PrayerMethod,
) -> None:
    release = _create_release()
    config = _create_config(release, prayer_method)
    _publish(release, make_default=True)
    config.refresh_from_db()

    operator = User.objects.create_user(
        email="prayer-admin@example.test",
        status="active",
        is_staff=True,
        is_superuser=True,
    )
    request = RequestFactory().get("/admin/prayer-times/")
    request.user = operator

    method_admin = PrayerMethodAdmin(PrayerMethod, admin.site)
    release_admin = PrayerConfigReleaseAdmin(PrayerConfigRelease, admin.site)
    config_admin = PrayerMethodConfigAdmin(PrayerMethodConfig, admin.site)

    for model_admin, obj in (
        (method_admin, prayer_method),
        (release_admin, release),
        (config_admin, config),
    ):
        assert "delete_selected" not in model_admin.get_actions(request)
        assert model_admin.has_delete_permission(request, None) is False
        assert model_admin.has_delete_permission(request, obj) is False

    assert set(release.immutable_fields).issubset(
        release_admin.get_readonly_fields(request, release)
    )
    assert "fajr_angle" in config_admin.get_readonly_fields(request, config)
    assert set(prayer_method.identity_fields).issubset(
        method_admin.get_readonly_fields(request, prayer_method)
    )
