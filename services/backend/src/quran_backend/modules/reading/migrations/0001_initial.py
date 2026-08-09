import django.db.models.deletion
import django.utils.timezone
import uuid
from decimal import Decimal
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True

    dependencies = [
        ("accounts", "0002_refresh_sessions"),
        ("quran", "0001_initial"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="UserSyncCursor",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid7, editable=False, primary_key=True, serialize=False
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("value", models.PositiveBigIntegerField(default=0)),
                (
                    "user",
                    models.OneToOneField(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="sync_cursor",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "db_table": "reading_user_sync_cursor",
            },
        ),
        migrations.CreateModel(
            name="Bookmark",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid7, editable=False, primary_key=True, serialize=False
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("label", models.CharField(blank=True, max_length=120)),
                ("color_key", models.CharField(default="default", max_length=32)),
                ("note", models.TextField(blank=True, max_length=2000)),
                ("client_updated_at", models.DateTimeField()),
                ("revision", models.PositiveBigIntegerField(default=1)),
                ("deleted_at", models.DateTimeField(blank=True, db_index=True, null=True)),
                (
                    "ayah",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="bookmarks",
                        to="quran.ayah",
                    ),
                ),
                (
                    "device",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="bookmarks",
                        to="accounts.device",
                    ),
                ),
                (
                    "edition",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="bookmarks",
                        to="quran.quranedition",
                    ),
                ),
                (
                    "page",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="bookmarks",
                        to="quran.mushafpage",
                    ),
                ),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="bookmarks",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "db_table": "reading_bookmark",
                "ordering": ["-updated_at", "-id"],
                "indexes": [
                    models.Index(
                        fields=["user", "deleted_at"], name="reading_bookmark_user_del_idx"
                    ),
                    models.Index(fields=["user", "edition"], name="reading_bookmark_user_ed_idx"),
                ],
                "constraints": [
                    models.CheckConstraint(
                        condition=models.Q(
                            ("page__isnull", False), ("ayah__isnull", False), _connector="OR"
                        ),
                        name="reading_bookmark_has_target",
                    ),
                    models.CheckConstraint(
                        condition=models.Q(("revision__gte", 1)),
                        name="reading_bookmark_revision_positive",
                    ),
                ],
            },
        ),
        migrations.CreateModel(
            name="ReadingPosition",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid7, editable=False, primary_key=True, serialize=False
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("intra_page_anchor", models.JSONField(blank=True, default=dict)),
                (
                    "progress_percent",
                    models.DecimalField(decimal_places=2, default=Decimal("0.00"), max_digits=5),
                ),
                (
                    "last_read_at",
                    models.DateTimeField(db_index=True, default=django.utils.timezone.now),
                ),
                ("client_updated_at", models.DateTimeField()),
                ("revision", models.PositiveBigIntegerField(default=1)),
                (
                    "ayah",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="reading_positions",
                        to="quran.ayah",
                    ),
                ),
                (
                    "device",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="reading_positions",
                        to="accounts.device",
                    ),
                ),
                (
                    "edition",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="reading_positions",
                        to="quran.quranedition",
                    ),
                ),
                (
                    "page",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="reading_positions",
                        to="quran.mushafpage",
                    ),
                ),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="reading_positions",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "db_table": "reading_position",
                "indexes": [
                    models.Index(
                        fields=["user", "last_read_at"], name="reading_position_user_time_idx"
                    )
                ],
                "constraints": [
                    models.UniqueConstraint(
                        fields=("user", "edition"), name="reading_position_user_edition_unique"
                    ),
                    models.CheckConstraint(
                        condition=models.Q(("revision__gte", 1)),
                        name="reading_position_revision_positive",
                    ),
                    models.CheckConstraint(
                        condition=models.Q(
                            ("progress_percent__gte", 0), ("progress_percent__lte", 100)
                        ),
                        name="reading_position_progress_range",
                    ),
                ],
            },
        ),
        migrations.CreateModel(
            name="SyncChange",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid7, editable=False, primary_key=True, serialize=False
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("sequence", models.PositiveBigIntegerField()),
                (
                    "entity_type",
                    models.CharField(
                        choices=[
                            ("reading_position", "Reading position"),
                            ("bookmark", "Bookmark"),
                        ],
                        max_length=32,
                    ),
                ),
                ("entity_id", models.UUIDField()),
                (
                    "action",
                    models.CharField(
                        choices=[("upsert", "Upsert"), ("delete", "Delete")], max_length=16
                    ),
                ),
                ("revision", models.PositiveBigIntegerField()),
                ("snapshot", models.JSONField()),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="sync_changes",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "db_table": "reading_sync_change",
                "ordering": ["sequence"],
                "indexes": [
                    models.Index(
                        fields=["user", "sequence"], name="reading_sync_change_cursor_idx"
                    ),
                    models.Index(
                        fields=["user", "entity_type", "entity_id"],
                        name="reading_sync_change_entity_idx",
                    ),
                ],
                "constraints": [
                    models.UniqueConstraint(
                        fields=("user", "sequence"), name="reading_sync_change_user_sequence_unique"
                    ),
                    models.CheckConstraint(
                        condition=models.Q(("sequence__gte", 1)),
                        name="reading_sync_change_sequence_positive",
                    ),
                    models.CheckConstraint(
                        condition=models.Q(("revision__gte", 1)),
                        name="reading_sync_change_revision_positive",
                    ),
                ],
            },
        ),
        migrations.CreateModel(
            name="SyncOperation",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid7, editable=False, primary_key=True, serialize=False
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("operation_id", models.UUIDField()),
                (
                    "entity_type",
                    models.CharField(
                        choices=[
                            ("reading_position", "Reading position"),
                            ("bookmark", "Bookmark"),
                        ],
                        max_length=32,
                    ),
                ),
                ("entity_id", models.UUIDField()),
                (
                    "action",
                    models.CharField(
                        choices=[("upsert", "Upsert"), ("delete", "Delete")], max_length=16
                    ),
                ),
                ("request_hash", models.CharField(max_length=64)),
                (
                    "outcome",
                    models.CharField(
                        choices=[("accepted", "Accepted"), ("conflict", "Conflict")], max_length=16
                    ),
                ),
                ("response", models.JSONField()),
                ("processed_at", models.DateTimeField(default=django.utils.timezone.now)),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="sync_operations",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "db_table": "reading_sync_operation",
                "indexes": [
                    models.Index(
                        fields=["user", "processed_at"], name="reading_sync_op_user_time_idx"
                    )
                ],
                "constraints": [
                    models.UniqueConstraint(
                        fields=("user", "operation_id"),
                        name="reading_sync_operation_user_id_unique",
                    )
                ],
            },
        ),
    ]
