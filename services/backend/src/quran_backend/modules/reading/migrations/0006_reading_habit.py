from decimal import Decimal
import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("accounts", "0005_support_turkish_locale"),
        ("quran", "0003_quranfoundationmushaf_quranfoundationmushafsyncstate_and_more"),
        ("reading", "0005_sync_entity_reminder"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="ReadingGoal",
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
                    "metric",
                    models.CharField(
                        choices=[
                            ("minutes", "Minutes"),
                            ("pages", "Pages"),
                            ("ayahs", "Ayahs"),
                        ],
                        max_length=16,
                    ),
                ),
                ("target_amount", models.DecimalField(decimal_places=2, max_digits=8)),
                ("timezone_name", models.CharField(max_length=64)),
                ("started_on", models.DateField()),
                ("ended_on", models.DateField(blank=True, null=True)),
                (
                    "status",
                    models.CharField(
                        choices=[("active", "Active"), ("archived", "Archived")],
                        default="active",
                        max_length=16,
                    ),
                ),
                ("client_updated_at", models.DateTimeField()),
                ("revision", models.PositiveBigIntegerField(default=1)),
                (
                    "device",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="reading_goals",
                        to="accounts.device",
                    ),
                ),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="reading_goals",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={"db_table": "reading_goal"},
        ),
        migrations.CreateModel(
            name="GoalProgress",
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
                ("local_date", models.DateField()),
                (
                    "achieved_amount",
                    models.DecimalField(
                        decimal_places=2,
                        default=Decimal("0"),
                        max_digits=10,
                    ),
                ),
                ("completed_at", models.DateTimeField(blank=True, null=True)),
                ("recalculation_version", models.PositiveIntegerField(default=1)),
                (
                    "goal",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="progress",
                        to="reading.readinggoal",
                    ),
                ),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="reading_goal_progress",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={"db_table": "reading_goal_progress"},
        ),
        migrations.CreateModel(
            name="ReadingSession",
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
                    "source",
                    models.CharField(
                        choices=[("automatic", "Automatic"), ("manual", "Manual")],
                        max_length=16,
                    ),
                ),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("active", "Active"),
                            ("completed", "Completed"),
                            ("discarded", "Discarded"),
                        ],
                        default="completed",
                        max_length=16,
                    ),
                ),
                ("timezone_name", models.CharField(max_length=64)),
                ("local_date", models.DateField()),
                ("started_at", models.DateTimeField(blank=True, null=True)),
                ("ended_at", models.DateTimeField(blank=True, null=True)),
                ("active_seconds", models.PositiveIntegerField(default=0)),
                ("credited_pages", models.PositiveSmallIntegerField(default=0)),
                ("credited_ayahs", models.PositiveSmallIntegerField(default=0)),
                (
                    "manual_metric",
                    models.CharField(
                        blank=True,
                        choices=[
                            ("minutes", "Minutes"),
                            ("pages", "Pages"),
                            ("ayahs", "Ayahs"),
                        ],
                        default="",
                        max_length=16,
                    ),
                ),
                (
                    "manual_amount",
                    models.DecimalField(
                        blank=True,
                        decimal_places=2,
                        max_digits=8,
                        null=True,
                    ),
                ),
                ("client_updated_at", models.DateTimeField()),
                ("revision", models.PositiveBigIntegerField(default=1)),
                ("deleted_at", models.DateTimeField(blank=True, db_index=True, null=True)),
                (
                    "device",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="reading_sessions",
                        to="accounts.device",
                    ),
                ),
                (
                    "edition",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="reading_sessions",
                        to="quran.quranedition",
                    ),
                ),
                (
                    "end_ayah",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="reading_sessions_ended",
                        to="quran.ayah",
                    ),
                ),
                (
                    "end_page",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="reading_sessions_ended",
                        to="quran.mushafpage",
                    ),
                ),
                (
                    "goal",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="sessions",
                        to="reading.readinggoal",
                    ),
                ),
                (
                    "start_ayah",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="reading_sessions_started",
                        to="quran.ayah",
                    ),
                ),
                (
                    "start_page",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="reading_sessions_started",
                        to="quran.mushafpage",
                    ),
                ),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="reading_sessions",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={"db_table": "reading_session"},
        ),
        migrations.CreateModel(
            name="ReadingStreak",
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
                ("current_count", models.PositiveIntegerField(default=0)),
                ("longest_count", models.PositiveIntegerField(default=0)),
                ("last_qualifying_date", models.DateField(blank=True, null=True)),
                ("recalculation_version", models.PositiveIntegerField(default=1)),
                (
                    "user",
                    models.OneToOneField(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="reading_streak",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={"db_table": "reading_streak"},
        ),
        migrations.AddIndex(
            model_name="readinggoal",
            index=models.Index(
                fields=["user", "status"],
                name="reading_goal_user_status_idx",
            ),
        ),
        migrations.AddIndex(
            model_name="readinggoal",
            index=models.Index(
                fields=["user", "started_on", "ended_on"],
                name="reading_goal_user_dates_idx",
            ),
        ),
        migrations.AddConstraint(
            model_name="readinggoal",
            constraint=models.UniqueConstraint(
                condition=models.Q(("status", "active")),
                fields=("user",),
                name="reading_goal_one_active_per_user",
            ),
        ),
        migrations.AddConstraint(
            model_name="readinggoal",
            constraint=models.CheckConstraint(
                condition=models.Q(("target_amount__gt", 0)),
                name="reading_goal_target_positive",
            ),
        ),
        migrations.AddConstraint(
            model_name="readinggoal",
            constraint=models.CheckConstraint(
                condition=models.Q(("revision__gte", 1)),
                name="reading_goal_revision_positive",
            ),
        ),
        migrations.AddConstraint(
            model_name="readinggoal",
            constraint=models.CheckConstraint(
                condition=models.Q(
                    ("ended_on__isnull", True),
                    ("ended_on__gte", models.F("started_on")),
                    _connector="OR",
                ),
                name="reading_goal_date_order",
            ),
        ),
        migrations.AddConstraint(
            model_name="readinggoal",
            constraint=models.CheckConstraint(
                condition=models.Q(
                    models.Q(("ended_on__isnull", True), ("status", "active")),
                    models.Q(("ended_on__isnull", False), ("status", "archived")),
                    _connector="OR",
                ),
                name="reading_goal_status_shape",
            ),
        ),
        migrations.AddIndex(
            model_name="goalprogress",
            index=models.Index(
                fields=["user", "local_date"],
                name="reading_progress_user_date_idx",
            ),
        ),
        migrations.AddIndex(
            model_name="goalprogress",
            index=models.Index(
                fields=["user", "completed_at"],
                name="reading_progress_user_done_idx",
            ),
        ),
        migrations.AddConstraint(
            model_name="goalprogress",
            constraint=models.UniqueConstraint(
                fields=("goal", "local_date"),
                name="reading_goal_progress_goal_date_unique",
            ),
        ),
        migrations.AddConstraint(
            model_name="goalprogress",
            constraint=models.CheckConstraint(
                condition=models.Q(("achieved_amount__gte", 0)),
                name="reading_goal_progress_amount_nonnegative",
            ),
        ),
        migrations.AddConstraint(
            model_name="goalprogress",
            constraint=models.CheckConstraint(
                condition=models.Q(("recalculation_version__gte", 1)),
                name="reading_goal_progress_version_positive",
            ),
        ),
        migrations.AddIndex(
            model_name="readingsession",
            index=models.Index(
                fields=["user", "local_date", "deleted_at"],
                name="reading_session_user_date_idx",
            ),
        ),
        migrations.AddIndex(
            model_name="readingsession",
            index=models.Index(
                fields=["goal", "local_date", "deleted_at"],
                name="reading_session_goal_date_idx",
            ),
        ),
        migrations.AddIndex(
            model_name="readingsession",
            index=models.Index(
                fields=["user", "created_at"],
                name="reading_session_user_time_idx",
            ),
        ),
        migrations.AddConstraint(
            model_name="readingsession",
            constraint=models.CheckConstraint(
                condition=models.Q(("revision__gte", 1)),
                name="reading_session_revision_positive",
            ),
        ),
        migrations.AddConstraint(
            model_name="readingsession",
            constraint=models.CheckConstraint(
                condition=models.Q(
                    ("ended_at__isnull", True),
                    ("started_at__isnull", True),
                    ("ended_at__gte", models.F("started_at")),
                    _connector="OR",
                ),
                name="reading_session_time_order",
            ),
        ),
        migrations.AddConstraint(
            model_name="readingsession",
            constraint=models.CheckConstraint(
                condition=models.Q(
                    models.Q(
                        ("manual_amount__gt", 0),
                        ("manual_metric__in", ["minutes", "pages", "ayahs"]),
                        ("source", "manual"),
                    ),
                    models.Q(
                        ("manual_amount__isnull", True),
                        ("manual_metric", ""),
                        ("source", "automatic"),
                    ),
                    _connector="OR",
                ),
                name="reading_session_source_shape",
            ),
        ),
        migrations.AddConstraint(
            model_name="readingsession",
            constraint=models.CheckConstraint(
                condition=models.Q(
                    models.Q(
                        ("deleted_at__isnull", True),
                        ("ended_at__isnull", True),
                        ("status", "active"),
                    ),
                    models.Q(
                        ("deleted_at__isnull", True),
                        ("ended_at__isnull", False),
                        ("status", "completed"),
                    ),
                    models.Q(
                        ("deleted_at__isnull", False),
                        ("ended_at__isnull", False),
                        ("status", "discarded"),
                    ),
                    _connector="OR",
                ),
                name="reading_session_status_shape",
            ),
        ),
        migrations.AddConstraint(
            model_name="readingsession",
            constraint=models.CheckConstraint(
                condition=models.Q(
                    models.Q(("status", "completed"), _negated=True),
                    ("source", "manual"),
                    ("active_seconds__gt", 0),
                    ("credited_pages__gt", 0),
                    ("credited_ayahs__gt", 0),
                    _connector="OR",
                ),
                name="reading_session_completed_has_activity",
            ),
        ),
        migrations.AddConstraint(
            model_name="readingstreak",
            constraint=models.CheckConstraint(
                condition=models.Q(("longest_count__gte", models.F("current_count"))),
                name="reading_streak_longest_gte_current",
            ),
        ),
        migrations.AddConstraint(
            model_name="readingstreak",
            constraint=models.CheckConstraint(
                condition=models.Q(
                    ("current_count", 0),
                    models.Q(
                        ("current_count__gt", 0),
                        ("last_qualifying_date__isnull", False),
                    ),
                    _connector="OR",
                ),
                name="reading_streak_current_date_shape",
            ),
        ),
        migrations.AddConstraint(
            model_name="readingstreak",
            constraint=models.CheckConstraint(
                condition=models.Q(("recalculation_version__gte", 1)),
                name="reading_streak_version_positive",
            ),
        ),
    ]
