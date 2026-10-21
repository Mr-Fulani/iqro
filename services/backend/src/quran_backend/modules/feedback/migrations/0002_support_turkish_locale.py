from __future__ import annotations

from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("feedback", "0001_initial")]

    operations = [
        migrations.RemoveConstraint(
            model_name="feedbackticket",
            name="feedback_ticket_supported_locale",
        ),
        migrations.AddConstraint(
            model_name="feedbackticket",
            constraint=models.CheckConstraint(
                condition=models.Q(locale__in=["ar", "en", "ru", "tr"]),
                name="feedback_ticket_supported_locale",
            ),
        ),
    ]
