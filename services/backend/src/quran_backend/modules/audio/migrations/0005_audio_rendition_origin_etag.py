from django.db import migrations, models

import quran_backend.modules.audio.validators


class Migration(migrations.Migration):
    dependencies = [
        ("audio", "0004_audio_rendition"),
    ]

    operations = [
        migrations.AddField(
            model_name="audiorendition",
            name="origin_etag",
            field=models.CharField(
                blank=True,
                max_length=255,
                validators=[quran_backend.modules.audio.validators.validate_strong_etag],
            ),
        ),
    ]
