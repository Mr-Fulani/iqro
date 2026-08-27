from datetime import timedelta

from django.db import migrations


def normalize_prayer_reminder_offsets(apps, schema_editor):
    ReminderRule = apps.get_model("reminders", "ReminderRule")
    WebPushSchedule = apps.get_model("reminders", "WebPushSchedule")
    database = schema_editor.connection.alias

    reminders = (
        ReminderRule.objects.using(database)
        .filter(reminder_type="prayer", deleted_at__isnull=True)
        .exclude(prayer_offset_minutes=0)
        .only("id", "prayer_offset_minutes")
    )
    for reminder in reminders.iterator():
        old_offset = int(reminder.prayer_offset_minutes or 0)
        if old_offset:
            delta = timedelta(minutes=-old_offset)
            schedules = WebPushSchedule.objects.using(database).filter(reminder_id=reminder.id)
            for schedule in schedules.iterator():
                schedule.occurrence_at += delta
                schedule.next_attempt_at += delta
                schedule.attempt_count = 0
                schedule.claim_token = None
                schedule.claimed_until = None
                schedule.last_error_code = ""
                schedule.save(
                    update_fields=[
                        "occurrence_at",
                        "next_attempt_at",
                        "attempt_count",
                        "claim_token",
                        "claimed_until",
                        "last_error_code",
                    ]
                )
        ReminderRule.objects.using(database).filter(pk=reminder.pk).update(prayer_offset_minutes=0)


class Migration(migrations.Migration):
    dependencies = [
        ("reminders", "0003_webpushsubscription_prayer_location"),
    ]

    operations = [
        migrations.RunPython(
            normalize_prayer_reminder_offsets,
            migrations.RunPython.noop,
        ),
    ]
