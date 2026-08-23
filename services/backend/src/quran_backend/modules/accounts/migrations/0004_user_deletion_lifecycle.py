from __future__ import annotations

from django.db import migrations, models


def backfill_deleted_at(apps: object, _schema_editor: object) -> None:
    user_model = apps.get_model("accounts", "User")  # type: ignore[attr-defined]
    user_model.objects.filter(status="deleted", deleted_at__isnull=True).update(
        deleted_at=models.F("updated_at")
    )


class Migration(migrations.Migration):
    dependencies = [("accounts", "0003_emailauthchallenge_guestmergeaudit")]

    operations = [
        migrations.AddField(
            model_name="user",
            name="deleted_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="user",
            name="deletion_requested_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="user",
            name="deletion_scheduled_for",
            field=models.DateTimeField(blank=True, db_index=True, null=True),
        ),
        migrations.RunPython(backfill_deleted_at, migrations.RunPython.noop),
        migrations.AddConstraint(
            model_name="user",
            constraint=models.CheckConstraint(
                condition=(
                    models.Q(
                        status="pending_deletion",
                        deletion_requested_at__isnull=False,
                        deletion_scheduled_for__isnull=False,
                        deleted_at__isnull=True,
                    )
                    | models.Q(status="deleted", deleted_at__isnull=False)
                    | (
                        ~models.Q(status__in=["pending_deletion", "deleted"])
                        & models.Q(
                            deletion_requested_at__isnull=True,
                            deletion_scheduled_for__isnull=True,
                            deleted_at__isnull=True,
                        )
                    )
                ),
                name="accounts_user_deletion_state_shape",
            ),
        ),
    ]
