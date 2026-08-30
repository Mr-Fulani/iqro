from __future__ import annotations

from typing import Any

from django.db import migrations, models

from quran_backend.modules.audio.reciter_profiles import RECITER_PROFILES


def populate_reciter_profiles(apps: Any, _schema_editor: Any) -> None:
    reciter_model = apps.get_model("audio", "Reciter")
    for code, profile in RECITER_PROFILES.items():
        reciter_model.objects.filter(code=code).update(**profile)


class Migration(migrations.Migration):
    dependencies = [
        ("audio", "0008_reciter_turkish_content"),
    ]

    operations = [
        migrations.AddField(
            model_name="reciter",
            name="profile_source_checked_on",
            field=models.DateField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="reciter",
            name="profile_source_url",
            field=models.URLField(blank=True, max_length=1000),
        ),
        migrations.RunPython(populate_reciter_profiles, migrations.RunPython.noop),
    ]
