from __future__ import annotations

from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("accounts", "0004_user_deletion_lifecycle")]

    operations = [
        migrations.RemoveConstraint(
            model_name="user",
            name="accounts_user_supported_locale",
        ),
        migrations.RemoveConstraint(
            model_name="device",
            name="accounts_device_supported_locale",
        ),
        migrations.AddConstraint(
            model_name="user",
            constraint=models.CheckConstraint(
                condition=models.Q(preferred_locale__in=["ar", "en", "ru", "tr"]),
                name="accounts_user_supported_locale",
            ),
        ),
        migrations.AddConstraint(
            model_name="device",
            constraint=models.CheckConstraint(
                condition=models.Q(locale__in=["ar", "en", "ru", "tr"]),
                name="accounts_device_supported_locale",
            ),
        ),
    ]
