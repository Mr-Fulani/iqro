from django.db import migrations, models


def _ayah_snapshot(ayah):
    if ayah is None:
        return None
    return {
        "id": str(ayah.id),
        "surah_number": ayah.surah.number,
        "ayah_number": ayah.number,
    }


def _reminder_snapshot(reminder):
    if reminder.deleted_at is not None:
        schedule = None
    elif reminder.prayer_event is not None:
        schedule = {
            "kind": "prayer",
            "prayer_event": reminder.prayer_event,
            "prayer_offset_minutes": reminder.prayer_offset_minutes,
        }
    else:
        schedule = {
            "kind": "local_time",
            "local_time": reminder.local_time.isoformat(),
        }

    review_target = None
    if reminder.start_ayah_id is not None and reminder.end_ayah_id is not None:
        review_target = {
            "start": _ayah_snapshot(reminder.start_ayah),
            "end": _ayah_snapshot(reminder.end_ayah),
        }

    timezone_data = {"mode": reminder.timezone_mode}
    if reminder.timezone_mode == "fixed":
        timezone_data["name"] = reminder.timezone_name
    return {
        "entity_type": "reminder",
        "id": str(reminder.id),
        "reminder_type": reminder.reminder_type,
        "schedule": schedule,
        "review_target": review_target,
        "weekdays_mask": reminder.weekdays_mask,
        "timezone": timezone_data,
        "delivery_mode": reminder.delivery_mode,
        "signal": reminder.signal,
        "is_enabled": reminder.is_enabled,
        "revision": reminder.revision,
        "client_updated_at": reminder.client_updated_at.isoformat(),
        "device_id": str(reminder.device_id) if reminder.device_id else None,
        "deleted_at": reminder.deleted_at.isoformat() if reminder.deleted_at else None,
        "created_at": reminder.created_at.isoformat(),
        "updated_at": reminder.updated_at.isoformat(),
    }


def backfill_reminder_changes(apps, schema_editor):
    ReminderRule = apps.get_model("reminders", "ReminderRule")
    SyncChange = apps.get_model("reading", "SyncChange")
    UserSyncCursor = apps.get_model("reading", "UserSyncCursor")
    User = apps.get_model("accounts", "User")
    database = schema_editor.connection.alias

    user_ids = (
        ReminderRule.objects.using(database).order_by().values_list("user_id", flat=True).distinct()
    )
    for user_id in user_ids.iterator():
        User.objects.using(database).select_for_update().only("id").get(id=user_id)
        cursor, _created = UserSyncCursor.objects.using(database).get_or_create(
            user_id=user_id,
            defaults={"value": 0, "minimum_valid_cursor": 0},
        )
        cursor = UserSyncCursor.objects.using(database).select_for_update().get(pk=cursor.pk)
        existing_ids = set(
            SyncChange.objects.using(database)
            .filter(user_id=user_id, entity_type="reminder")
            .values_list("entity_id", flat=True)
        )
        reminders = (
            ReminderRule.objects.using(database)
            .filter(user_id=user_id)
            .exclude(id__in=existing_ids)
            .select_related("start_ayah__surah", "end_ayah__surah")
            .order_by("id")
        )
        changes = []
        sequence = cursor.value
        for reminder in reminders.iterator():
            sequence += 1
            changes.append(
                SyncChange(
                    user_id=user_id,
                    sequence=sequence,
                    entity_type="reminder",
                    entity_id=reminder.id,
                    action="delete" if reminder.deleted_at is not None else "upsert",
                    revision=reminder.revision,
                    snapshot=_reminder_snapshot(reminder),
                )
            )
        if changes:
            SyncChange.objects.using(database).bulk_create(changes, batch_size=1_000)
            UserSyncCursor.objects.using(database).filter(pk=cursor.pk).update(value=sequence)


class Migration(migrations.Migration):
    dependencies = [
        ("reading", "0004_retiredbookmarkid"),
        ("reminders", "0001_initial"),
    ]

    operations = [
        migrations.AlterField(
            model_name="syncchange",
            name="entity_type",
            field=models.CharField(
                choices=[
                    ("reading_position", "Reading position"),
                    ("bookmark", "Bookmark"),
                    ("reminder", "Reminder"),
                ],
                max_length=32,
            ),
        ),
        migrations.AlterField(
            model_name="syncoperation",
            name="entity_type",
            field=models.CharField(
                choices=[
                    ("reading_position", "Reading position"),
                    ("bookmark", "Bookmark"),
                    ("reminder", "Reminder"),
                ],
                max_length=32,
            ),
        ),
        migrations.RunPython(backfill_reminder_changes),
    ]
