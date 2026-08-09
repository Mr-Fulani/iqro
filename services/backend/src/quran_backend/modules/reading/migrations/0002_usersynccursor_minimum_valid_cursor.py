from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("reading", "0001_initial"),
    ]

    operations = [
        migrations.AddField(
            model_name="usersynccursor",
            name="minimum_valid_cursor",
            field=models.PositiveBigIntegerField(default=0),
        ),
        migrations.AddConstraint(
            model_name="usersynccursor",
            constraint=models.CheckConstraint(
                condition=models.Q(minimum_valid_cursor__lte=models.F("value")),
                name="reading_sync_cursor_floor_lte_value",
            ),
        ),
        migrations.AddIndex(
            model_name="syncoperation",
            index=models.Index(fields=["processed_at"], name="reading_sync_op_prune_idx"),
        ),
    ]
