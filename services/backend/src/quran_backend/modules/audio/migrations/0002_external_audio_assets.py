from django.db import migrations, models

import quran_backend.modules.audio.validators


class Migration(migrations.Migration):
    dependencies = [
        ("audio", "0001_initial"),
    ]

    operations = [
        migrations.AlterField(
            model_name="audiotrack",
            name="checksum_sha256",
            field=models.CharField(
                blank=True,
                max_length=64,
                validators=[quran_backend.modules.audio.validators.validate_sha256],
            ),
        ),
        migrations.AlterField(
            model_name="audiotrack",
            name="object_key",
            field=models.CharField(
                blank=True,
                max_length=512,
                null=True,
                unique=True,
                validators=[quran_backend.modules.audio.validators.validate_relative_object_key],
            ),
        ),
        migrations.AddField(
            model_name="audiotrack",
            name="external_url",
            field=models.URLField(blank=True, max_length=1000),
        ),
        migrations.AddConstraint(
            model_name="audiotrack",
            constraint=models.CheckConstraint(
                condition=(
                    models.Q(("external_url", ""), ("object_key__isnull", False))
                    | (models.Q(("object_key__isnull", True)) & ~models.Q(("external_url", "")))
                ),
                name="audio_track_delivery_source_valid",
            ),
        ),
    ]
