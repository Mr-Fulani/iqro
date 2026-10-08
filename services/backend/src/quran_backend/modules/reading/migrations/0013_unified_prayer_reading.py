from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("reading", "0012_sync_annotation_choices")]

    operations = [
        migrations.RemoveConstraint(
            model_name="prayerreadingcheckin",
            name="prayer_reading_check_in_pages_range",
        ),
        migrations.AddConstraint(
            model_name="prayerreadingcheckin",
            constraint=models.CheckConstraint(
                condition=models.Q(pages__gte=0, pages__lte=604),
                name="prayer_reading_check_in_pages_range",
            ),
        ),
    ]
