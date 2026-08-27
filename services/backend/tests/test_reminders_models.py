from __future__ import annotations

from datetime import time
from typing import Any

import pytest
from django.contrib import admin
from django.contrib.admin.sites import AdminSite
from django.core.exceptions import ValidationError
from django.db import IntegrityError, transaction
from django.test import RequestFactory
from django.utils import timezone

from quran_backend.modules.accounts.models import Device, DevicePlatform, User
from quran_backend.modules.quran.models import (
    Ayah,
    PublicationStatus,
    QuranEdition,
    QuranEditionVersion,
    RevelationType,
    Surah,
)
from quran_backend.modules.reminders.admin import ReminderRuleAdmin
from quran_backend.modules.reminders.models import (
    ALL_WEEKDAYS_MASK,
    MAX_PRAYER_OFFSET_MINUTES,
    MIN_PRAYER_OFFSET_MINUTES,
    ReminderDeliveryMode,
    ReminderPrayerEvent,
    ReminderRule,
    ReminderSignal,
    ReminderTimezoneMode,
    ReminderType,
    ReminderWeekday,
)


@pytest.fixture
def reminder_user(db: None) -> User:
    return User.objects.create_user()


def _prayer_rule(user: User, **overrides: Any) -> ReminderRule:
    values: dict[str, Any] = {
        "user": user,
        "reminder_type": ReminderType.PRAYER,
        "prayer_event": ReminderPrayerEvent.FAJR,
        "prayer_offset_minutes": 0,
        "client_updated_at": timezone.now(),
    }
    values.update(overrides)
    return ReminderRule(**values)


def _reading_rule(user: User, **overrides: Any) -> ReminderRule:
    values: dict[str, Any] = {
        "user": user,
        "reminder_type": ReminderType.QURAN_READING,
        "local_time": time(7, 30),
        "client_updated_at": timezone.now(),
    }
    values.update(overrides)
    return ReminderRule(**values)


def _review_rule(user: User, quran_dataset: dict[str, Any], **overrides: Any) -> ReminderRule:
    values: dict[str, Any] = {
        "user": user,
        "reminder_type": ReminderType.QURAN_REVIEW,
        "local_time": time(20, 0),
        "start_ayah": quran_dataset["first_ayah"],
        "end_ayah": quran_dataset["second_ayah"],
        "client_updated_at": timezone.now(),
    }
    values.update(overrides)
    return ReminderRule(**values)


def _other_edition_ayah() -> Ayah:
    edition = QuranEdition.objects.create(
        code="other-reminder-edition",
        name_ar="اختبار",
        name_en="Other reminder edition",
        name_ru="Другое издание",
        riwayah="Hafs 'an Asim",
        source_name="Synthetic test source",
        license_name="Test",
    )
    version = QuranEditionVersion.objects.create(
        edition=edition,
        version="1.0.0",
        checksum_sha256="e" * 64,
        status=PublicationStatus.PUBLISHED,
        published_at=timezone.now(),
    )
    surah = Surah.objects.create(
        edition_version=version,
        number=1,
        name_ar="اختبار",
        name_en="Test",
        name_ru="Тест",
        revelation_type=RevelationType.MECCAN,
        ayah_count=1,
    )
    return Ayah.objects.create(
        surah=surah,
        number=1,
        text_uthmani="اختبار",
        text_search="اختبار",
        juz_number=1,
    )


@pytest.mark.django_db
@pytest.mark.parametrize("event", ReminderPrayerEvent.values)
def test_each_of_five_prayer_events_is_a_valid_local_rule(
    reminder_user: User,
    event: str,
) -> None:
    rule = _prayer_rule(
        reminder_user,
        prayer_event=event,
        prayer_offset_minutes=MIN_PRAYER_OFFSET_MINUTES,
        weekdays_mask=0b0101010,
        signal=ReminderSignal.VIBRATION,
    )

    rule.save()

    assert rule.id.version == 7
    assert rule.delivery_mode == ReminderDeliveryMode.LOCAL
    assert rule.timezone_mode == ReminderTimezoneMode.DEVICE_LOCAL
    assert rule.local_time is None


@pytest.mark.django_db
def test_quran_reading_rule_uses_wall_clock_without_target(
    reminder_user: User,
) -> None:
    rule = _reading_rule(
        reminder_user,
        timezone_mode=ReminderTimezoneMode.FIXED,
        timezone_name="Europe/Istanbul",
        signal=ReminderSignal.SILENT,
    )

    rule.save()

    assert rule.local_time == time(7, 30)
    assert rule.start_ayah_id is None
    assert rule.end_ayah_id is None
    assert rule.weekdays_mask == ALL_WEEKDAYS_MASK


@pytest.mark.django_db
def test_rule_persists_client_timestamp_and_same_user_device(reminder_user: User) -> None:
    device = Device.objects.create(
        user=reminder_user,
        platform=DevicePlatform.ANDROID,
        installation_id_hash="d" * 64,
    )
    client_updated_at = timezone.now()
    rule = _reading_rule(
        reminder_user,
        device=device,
        client_updated_at=client_updated_at,
    )

    rule.save()
    rule.refresh_from_db()

    assert rule.device_id == device.id
    assert rule.client_updated_at == client_updated_at

    device.delete()
    rule.refresh_from_db()
    assert rule.device_id is None


@pytest.mark.django_db
def test_rule_rejects_device_owned_by_another_user(reminder_user: User) -> None:
    another_user = User.objects.create_user()
    another_device = Device.objects.create(
        user=another_user,
        platform=DevicePlatform.IOS,
        installation_id_hash="e" * 64,
    )
    rule = _reading_rule(reminder_user, device=another_device)

    with pytest.raises(ValidationError) as error:
        rule.save()

    assert "device" in error.value.message_dict


def test_weekday_mask_uses_iso_week_order() -> None:
    assert int(ReminderWeekday.MONDAY) == 0b0000001
    assert int(ReminderWeekday.FRIDAY) == 0b0010000
    assert int(ReminderWeekday.SUNDAY) == 0b1000000
    assert ALL_WEEKDAYS_MASK == 0b1111111


@pytest.mark.django_db
def test_quran_review_rule_persists_normalized_ayah_range(
    reminder_user: User,
    quran_dataset: dict[str, Any],
) -> None:
    rule = _review_rule(reminder_user, quran_dataset)

    rule.save()

    assert rule.start_ayah_id == quran_dataset["first_ayah"].id
    assert rule.end_ayah_id == quran_dataset["second_ayah"].id


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("overrides", "error_field"),
    [
        ({"prayer_event": None}, "prayer_event"),
        ({"prayer_event": "sunrise"}, "prayer_event"),
        ({"local_time": time(5, 0)}, "local_time"),
        ({"prayer_offset_minutes": None}, "prayer_offset_minutes"),
        ({"start_ayah_id": "01900000-0000-7000-8000-000000000001"}, "start_ayah"),
    ],
)
def test_prayer_rule_rejects_non_event_schedule_fields(
    reminder_user: User,
    overrides: dict[str, Any],
    error_field: str,
) -> None:
    rule = _prayer_rule(reminder_user, **overrides)

    with pytest.raises(ValidationError) as error:
        rule.full_clean()

    assert error_field in error.value.message_dict


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("overrides", "error_field"),
    [
        ({"local_time": None}, "local_time"),
        ({"prayer_event": ReminderPrayerEvent.ISHA}, "prayer_event"),
        ({"prayer_offset_minutes": 0}, "prayer_offset_minutes"),
        ({"start_ayah_id": "01900000-0000-7000-8000-000000000001"}, "start_ayah"),
        ({"end_ayah_id": "01900000-0000-7000-8000-000000000001"}, "end_ayah"),
    ],
)
def test_reading_rule_rejects_prayer_and_review_fields(
    reminder_user: User,
    overrides: dict[str, Any],
    error_field: str,
) -> None:
    rule = _reading_rule(reminder_user, **overrides)

    with pytest.raises(ValidationError) as error:
        rule.full_clean()

    assert error_field in error.value.message_dict


@pytest.mark.django_db
@pytest.mark.parametrize("missing_field", ["start_ayah", "end_ayah"])
def test_review_rule_requires_both_range_boundaries(
    reminder_user: User,
    quran_dataset: dict[str, Any],
    missing_field: str,
) -> None:
    rule = _review_rule(reminder_user, quran_dataset, **{missing_field: None})

    with pytest.raises(ValidationError) as error:
        rule.full_clean()

    assert missing_field in error.value.message_dict


@pytest.mark.django_db
def test_review_range_must_be_ordered(
    reminder_user: User,
    quran_dataset: dict[str, Any],
) -> None:
    rule = _review_rule(
        reminder_user,
        quran_dataset,
        start_ayah=quran_dataset["second_ayah"],
        end_ayah=quran_dataset["first_ayah"],
    )

    with pytest.raises(ValidationError) as error:
        rule.save()

    assert "end_ayah" in error.value.message_dict


@pytest.mark.django_db
def test_review_range_must_use_one_edition_version(
    reminder_user: User,
    quran_dataset: dict[str, Any],
) -> None:
    rule = _review_rule(reminder_user, quran_dataset, end_ayah=_other_edition_ayah())

    with pytest.raises(ValidationError) as error:
        rule.save()

    assert {"start_ayah", "end_ayah"} <= error.value.message_dict.keys()


@pytest.mark.django_db
@pytest.mark.parametrize("timezone_name", ["UTC", "America/New_York", "Asia/Karachi"])
def test_fixed_timezone_is_loaded_from_pinned_tzdata(
    reminder_user: User,
    timezone_name: str,
) -> None:
    rule = _reading_rule(
        reminder_user,
        timezone_mode=ReminderTimezoneMode.FIXED,
        timezone_name=timezone_name,
    )

    rule.save()

    assert rule.timezone_name == timezone_name


@pytest.mark.django_db
@pytest.mark.parametrize("timezone_name", [None, "", " Europe/Istanbul", "../UTC", "Mars/Base"])
def test_fixed_timezone_rejects_missing_or_unknown_iana_name(
    reminder_user: User,
    timezone_name: str | None,
) -> None:
    rule = _reading_rule(
        reminder_user,
        timezone_mode=ReminderTimezoneMode.FIXED,
        timezone_name=timezone_name,
    )

    with pytest.raises(ValidationError) as error:
        rule.save()

    assert "timezone_name" in error.value.message_dict


@pytest.mark.django_db
def test_device_local_timezone_forbids_server_pinned_name(reminder_user: User) -> None:
    rule = _reading_rule(reminder_user, timezone_name="Europe/Istanbul")

    with pytest.raises(ValidationError) as error:
        rule.save()

    assert "timezone_name" in error.value.message_dict


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("weekdays_mask", 0),
        ("weekdays_mask", ALL_WEEKDAYS_MASK + 1),
        ("prayer_offset_minutes", MIN_PRAYER_OFFSET_MINUTES - 1),
        ("prayer_offset_minutes", MAX_PRAYER_OFFSET_MINUTES + 1),
        ("revision", 0),
        ("signal", "full_azan"),
        ("delivery_mode", "push"),
    ],
)
def test_bounded_and_local_only_fields_reject_invalid_values(
    reminder_user: User,
    field: str,
    value: Any,
) -> None:
    rule = _prayer_rule(reminder_user, **{field: value})

    with pytest.raises(ValidationError) as error:
        rule.save()

    assert field in error.value.message_dict or "__all__" in error.value.message_dict


@pytest.mark.django_db
@pytest.mark.parametrize(
    "offset",
    [MIN_PRAYER_OFFSET_MINUTES, 0, MAX_PRAYER_OFFSET_MINUTES],
)
def test_prayer_offset_boundary_values_are_valid(reminder_user: User, offset: int) -> None:
    rule = _prayer_rule(reminder_user, prayer_offset_minutes=offset)

    rule.save()

    assert rule.prayer_offset_minutes == offset


@pytest.mark.django_db
def test_tombstone_must_be_disabled_and_preserves_revision(reminder_user: User) -> None:
    rule = _reading_rule(reminder_user)
    rule.save()
    original_id = rule.id
    rule.deleted_at = timezone.now()
    rule.revision += 1

    with pytest.raises(ValidationError) as error:
        rule.save()
    assert "is_enabled" in error.value.message_dict

    rule.is_enabled = False
    rule.local_time = None
    rule.signal = ReminderSignal.SILENT
    rule.save()
    rule.refresh_from_db()
    assert rule.id == original_id
    assert rule.revision == 2
    assert rule.deleted_at is not None


@pytest.mark.django_db
@pytest.mark.parametrize(
    "invalid_update",
    [
        {"weekdays_mask": 0},
        {"revision": 0},
        {"delivery_mode": "push"},
        {"signal": "full_azan"},
        {"timezone_mode": ReminderTimezoneMode.FIXED, "timezone_name": None},
        {"timezone_mode": "server_local", "timezone_name": None},
        {"deleted_at": timezone.now(), "is_enabled": True},
        {"local_time": time(5, 0)},
        {"prayer_offset_minutes": MAX_PRAYER_OFFSET_MINUTES + 1},
        {"reminder_type": "unknown"},
        {"reminder_type": ReminderType.QURAN_REVIEW, "local_time": time(20, 0)},
    ],
)
def test_database_constraints_reject_invalid_bulk_updates(
    reminder_user: User,
    invalid_update: dict[str, Any],
) -> None:
    rule = _prayer_rule(reminder_user)
    rule.save()

    with pytest.raises(IntegrityError), transaction.atomic():
        ReminderRule.objects.filter(pk=rule.pk).update(**invalid_update)


@pytest.mark.django_db
def test_model_has_sync_indexes_and_no_location_or_delivery_secrets() -> None:
    index_names = {index.name for index in ReminderRule._meta.indexes}
    field_names = {field.name for field in ReminderRule._meta.fields}

    assert index_names == {
        "reminder_user_sync_idx",
        "reminder_user_active_idx",
        "reminder_retention_idx",
    }
    assert (
        not {
            "latitude",
            "longitude",
            "coordinates",
            "push_token",
            "scheduled_at",
            "prayer_instant",
        }
        & field_names
    )


@pytest.mark.django_db
def test_review_ayahs_are_protected_while_rule_exists(
    reminder_user: User,
    quran_dataset: dict[str, Any],
) -> None:
    rule = _review_rule(reminder_user, quran_dataset)
    rule.save()

    with pytest.raises(IntegrityError), transaction.atomic():
        Ayah.objects.filter(pk=quran_dataset["first_ayah"].pk).delete()


@pytest.mark.django_db
def test_admin_is_registered_read_only_and_formats_local_schedule(reminder_user: User) -> None:
    operator = User.objects.create_user(
        email="reminder-admin@example.com",
        status="active",
        is_staff=True,
        is_superuser=True,
    )
    prayer = _prayer_rule(reminder_user)
    prayer.save()
    reading = _reading_rule(reminder_user)
    reading.save()
    model_admin = ReminderRuleAdmin(ReminderRule, AdminSite())
    request = RequestFactory().get("/admin/reminders/reminderrule/")
    request.user = operator

    assert isinstance(admin.site._registry[ReminderRule], ReminderRuleAdmin)
    assert set(model_admin.readonly_fields) == {field.name for field in ReminderRule._meta.fields}
    assert model_admin.has_add_permission(request) is False
    assert model_admin.has_change_permission(request, prayer) is False
    assert model_admin.has_delete_permission(request, prayer) is False
    assert model_admin.schedule(prayer) == "fajr"
    assert model_admin.schedule(reading) == "07:30"
    assert model_admin.get_queryset(request).query.select_related is not False
