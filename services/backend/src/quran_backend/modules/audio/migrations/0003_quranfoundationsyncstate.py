import uuid

from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("audio", "0002_external_audio_assets"),
    ]

    operations = [
        migrations.CreateModel(
            name="QuranFoundationSyncState",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid7,
                        editable=False,
                        primary_key=True,
                        serialize=False,
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("environment", models.CharField(max_length=16)),
                ("source_reciter_id", models.PositiveIntegerField()),
                (
                    "content_sync_resource_id",
                    models.PositiveIntegerField(blank=True, null=True),
                ),
                ("sync_token", models.TextField(blank=True)),
                ("last_sync_sequence", models.PositiveBigIntegerField(blank=True, null=True)),
                ("last_attempt_at", models.DateTimeField(blank=True, null=True)),
                (
                    "last_success_at",
                    models.DateTimeField(blank=True, db_index=True, null=True),
                ),
                ("last_change_at", models.DateTimeField(blank=True, null=True)),
                ("consecutive_failures", models.PositiveIntegerField(default=0)),
                ("last_error_code", models.CharField(blank=True, max_length=64)),
            ],
            options={
                "db_table": "audio_qf_sync_state",
                "ordering": ["environment", "source_reciter_id"],
                "indexes": [
                    models.Index(
                        fields=["environment", "last_success_at"],
                        name="audio_qf_sync_freshness_idx",
                    )
                ],
                "constraints": [
                    models.UniqueConstraint(
                        fields=("environment", "source_reciter_id"),
                        name="audio_qf_sync_source_uq",
                    ),
                    models.CheckConstraint(
                        condition=models.Q(environment__in=["prelive", "production"]),
                        name="audio_qf_sync_environment_valid",
                    ),
                ],
            },
        ),
    ]
