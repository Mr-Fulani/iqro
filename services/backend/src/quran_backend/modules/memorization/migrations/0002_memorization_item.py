from __future__ import annotations

import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("memorization", "0001_initial"),
        ("quran", "0007_canonical_page_mapping"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="MemorizationItem",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid7, editable=False, primary_key=True, serialize=False
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("active", "Active"),
                            ("queued", "Queued"),
                            ("memorized", "Memorized"),
                        ],
                        max_length=16,
                    ),
                ),
                ("position", models.PositiveIntegerField(default=0)),
                (
                    "source",
                    models.CharField(
                        choices=[("mushaf", "Mushaf"), ("manual", "Manual")],
                        default="manual",
                        max_length=16,
                    ),
                ),
                ("memorized_at", models.DateTimeField(blank=True, null=True)),
                (
                    "end_ayah",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="memorization_items_ended",
                        to="quran.ayah",
                    ),
                ),
                (
                    "start_ayah",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="memorization_items_started",
                        to="quran.ayah",
                    ),
                ),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="memorization_items",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "db_table": "memorization_item",
                "ordering": ["position", "created_at"],
                "indexes": [
                    models.Index(
                        fields=["user", "status", "position"], name="memorization_item_list_idx"
                    )
                ],
                "constraints": [
                    models.UniqueConstraint(
                        condition=models.Q(("status", "active")),
                        fields=("user",),
                        name="memorization_item_one_active",
                    )
                ],
            },
        ),
    ]
