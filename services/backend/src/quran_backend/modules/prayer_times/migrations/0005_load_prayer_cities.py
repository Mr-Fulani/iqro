from __future__ import annotations

from django.conf import settings
from django.db import migrations

from quran_backend.modules.prayer_times.cities import import_prayer_cities


def load_prayer_cities(apps, schema_editor):  # noqa: ARG001
    """Fill the city search from the bundled GeoNames extract on every deployment.

    Test databases skip it (QURAN_PRAYER_CITIES_IMPORT_ON_MIGRATE): 172 thousand rows
    would be written before every test run; the tests import their own small files.
    """
    if not getattr(settings, "QURAN_PRAYER_CITIES_IMPORT_ON_MIGRATE", True):
        return
    import_prayer_cities(model=apps.get_model("prayer_times", "PrayerCity"))


class Migration(migrations.Migration):
    dependencies = [
        ("prayer_times", "0004_prayer_city"),
    ]

    operations = [
        migrations.RunPython(load_prayer_cities, migrations.RunPython.noop),
    ]
