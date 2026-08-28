from django.db import migrations


def remove_daily_quran_reading_schedules(apps, _schema_editor):
    web_push_schedule = apps.get_model("reminders", "WebPushSchedule")
    web_push_schedule.objects.filter(
        reminder__reminder_type="quran_reading",
    ).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("reminders", "0004_normalize_prayer_reminder_offsets"),
    ]

    operations = [
        migrations.RunPython(
            remove_daily_quran_reading_schedules,
            reverse_code=migrations.RunPython.noop,
        ),
    ]
