from __future__ import annotations

import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("accounts", "0005_support_turkish_locale"),
        ("reading", "0006_reading_habit"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="PrayerReadingPlan",
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
                ("pages_per_prayer", models.PositiveSmallIntegerField(default=2)),
                ("timezone_name", models.CharField(max_length=64)),
                ("client_updated_at", models.DateTimeField()),
                ("revision", models.PositiveBigIntegerField(default=1)),
                (
                    "device",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="prayer_reading_plans",
                        to="accounts.device",
                    ),
                ),
                (
                    "user",
                    models.OneToOneField(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="prayer_reading_plan",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={"db_table": "prayer_reading_plan"},
        ),
        migrations.CreateModel(
            name="PrayerReadingCheckIn",
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
                (
                    "prayer",
                    models.CharField(
                        choices=[
                            ("fajr", "Fajr"),
                            ("dhuhr", "Dhuhr"),
                            ("asr", "Asr"),
                            ("maghrib", "Maghrib"),
                            ("isha", "Isha"),
                        ],
                        max_length=16,
                    ),
                ),
                ("local_date", models.DateField()),
                ("timezone_name", models.CharField(max_length=64)),
                ("pages", models.PositiveSmallIntegerField()),
                ("client_updated_at", models.DateTimeField()),
                ("revision", models.PositiveBigIntegerField(default=1)),
                (
                    "device",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="prayer_reading_check_ins",
                        to="accounts.device",
                    ),
                ),
                (
                    "plan",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="check_ins",
                        to="reading.prayerreadingplan",
                    ),
                ),
                (
                    "reading_session",
                    models.OneToOneField(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="prayer_reading_check_in",
                        to="reading.readingsession",
                    ),
                ),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="prayer_reading_check_ins",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={"db_table": "prayer_reading_check_in"},
        ),
        migrations.AddConstraint(
            model_name="prayerreadingplan",
            constraint=models.CheckConstraint(
                condition=models.Q(("pages_per_prayer__gte", 1), ("pages_per_prayer__lte", 20)),
                name="prayer_reading_plan_pages_range",
            ),
        ),
        migrations.AddConstraint(
            model_name="prayerreadingplan",
            constraint=models.CheckConstraint(
                condition=models.Q(("revision__gte", 1)),
                name="prayer_reading_plan_revision_positive",
            ),
        ),
        migrations.AddConstraint(
            model_name="prayerreadingcheckin",
            constraint=models.UniqueConstraint(
                fields=("user", "local_date", "prayer"),
                name="prayer_reading_check_in_daily_prayer_unique",
            ),
        ),
        migrations.AddConstraint(
            model_name="prayerreadingcheckin",
            constraint=models.CheckConstraint(
                condition=models.Q(("pages__gte", 1), ("pages__lte", 20)),
                name="prayer_reading_check_in_pages_range",
            ),
        ),
        migrations.AddConstraint(
            model_name="prayerreadingcheckin",
            constraint=models.CheckConstraint(
                condition=models.Q(("revision__gte", 1)),
                name="prayer_reading_check_in_revision_positive",
            ),
        ),
        migrations.AddIndex(
            model_name="prayerreadingcheckin",
            index=models.Index(
                fields=["user", "local_date"],
                name="prayer_reading_user_date_idx",
            ),
        ),
    ]
