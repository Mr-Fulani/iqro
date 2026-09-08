"""Initial reviewed markers; never replace subsequent operator edits."""

import json
from pathlib import Path

from django.db import migrations


def seed(apps, schema_editor):
    model = apps.get_model("calendar", "CalendarEvent")
    data = json.loads((Path(__file__).parents[1] / "data/events-v1.json").read_text())
    for index, event in enumerate(data["events"]):
        defaults = {
            key: event[key]
            for key in (
                "month",
                "day_start",
                "day_end",
                "kind",
                "exclude_ramadan",
            )
        }
        defaults.update(
            {
                "is_published": True,
                "sort_order": index * 10,
                "source_label": event["source"]["label"],
                "source_url": event["source"]["url"],
            }
        )
        for locale in ("ru", "en", "ar", "tr"):
            defaults[f"title_{locale}"] = event["titles"][locale]
            defaults[f"description_{locale}"] = event["descriptions"][locale]
        model.objects.using(schema_editor.connection.alias).get_or_create(
            code=event["code"], defaults=defaults
        )


class Migration(migrations.Migration):
    dependencies = [("calendar", "0001_initial")]
    operations = [migrations.RunPython(seed, reverse_code=migrations.RunPython.noop)]
