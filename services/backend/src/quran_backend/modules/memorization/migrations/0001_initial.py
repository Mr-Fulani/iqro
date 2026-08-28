from __future__ import annotations

import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True

    dependencies = [
        ("accounts", "0005_support_turkish_locale"),
        ("audio", "0001_initial"),
        ("quran", "0003_quranfoundationmushaf_quranfoundationmushafsyncstate_and_more"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="MemorizationPlan",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid7, editable=False, primary_key=True, serialize=False
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("daily_repetitions", models.PositiveSmallIntegerField(default=5)),
                ("pause_seconds", models.PositiveSmallIntegerField(default=2)),
                ("timezone_name", models.CharField(max_length=64)),
                ("client_updated_at", models.DateTimeField()),
                ("revision", models.PositiveBigIntegerField(default=1)),
                (
                    "device",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="memorization_plans",
                        to="accounts.device",
                    ),
                ),
                (
                    "end_ayah",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="memorization_plans_ended",
                        to="quran.ayah",
                    ),
                ),
                (
                    "recitation",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="memorization_plans",
                        to="audio.recitationedition",
                    ),
                ),
                (
                    "start_ayah",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="memorization_plans_started",
                        to="quran.ayah",
                    ),
                ),
                (
                    "user",
                    models.OneToOneField(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="memorization_plan",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "db_table": "memorization_plan",
                "constraints": [
                    models.CheckConstraint(
                        condition=models.Q(
                            ("daily_repetitions__gte", 1), ("daily_repetitions__lte", 100)
                        ),
                        name="memorization_plan_repetitions_range",
                    ),
                    models.CheckConstraint(
                        condition=models.Q(("pause_seconds__gte", 0), ("pause_seconds__lte", 30)),
                        name="memorization_plan_pause_range",
                    ),
                    models.CheckConstraint(
                        condition=models.Q(("revision__gte", 1)),
                        name="memorization_plan_revision_positive",
                    ),
                ],
            },
        ),
        migrations.CreateModel(
            name="MemorizationSession",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid7, editable=False, primary_key=True, serialize=False
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("daily_target_repetitions", models.PositiveSmallIntegerField()),
                ("completed_repetitions", models.PositiveSmallIntegerField()),
                (
                    "assessment",
                    models.CharField(
                        choices=[
                            ("difficult", "Difficult"),
                            ("repeat", "Repeat"),
                            ("memorized", "Memorized"),
                        ],
                        max_length=16,
                    ),
                ),
                ("duration_seconds", models.PositiveIntegerField(default=0)),
                ("timezone_name", models.CharField(max_length=64)),
                ("local_date", models.DateField()),
                ("client_updated_at", models.DateTimeField()),
                (
                    "device",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="memorization_sessions",
                        to="accounts.device",
                    ),
                ),
                (
                    "end_ayah",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="memorization_sessions_ended",
                        to="quran.ayah",
                    ),
                ),
                (
                    "plan",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="sessions",
                        to="memorization.memorizationplan",
                    ),
                ),
                (
                    "start_ayah",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="memorization_sessions_started",
                        to="quran.ayah",
                    ),
                ),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="memorization_sessions",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "db_table": "memorization_session",
                "ordering": ["-local_date", "-created_at"],
                "indexes": [
                    models.Index(fields=["user", "local_date"], name="memorization_user_date_idx")
                ],
                "constraints": [
                    models.CheckConstraint(
                        condition=models.Q(
                            ("daily_target_repetitions__gte", 1),
                            ("daily_target_repetitions__lte", 100),
                        ),
                        name="memorization_session_target_range",
                    ),
                    models.CheckConstraint(
                        condition=models.Q(
                            ("completed_repetitions__gte", 1), ("completed_repetitions__lte", 1000)
                        ),
                        name="memorization_session_completed_range",
                    ),
                    models.CheckConstraint(
                        condition=models.Q(("duration_seconds__lte", 86400)),
                        name="memorization_session_duration_range",
                    ),
                ],
            },
        ),
    ]
