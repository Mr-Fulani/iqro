import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


def migrate_legacy_bookmark_details(apps, schema_editor) -> None:  # noqa: ARG001
    Bookmark = apps.get_model("reading", "Bookmark")
    AyahAnnotation = apps.get_model("reading", "AyahAnnotation")
    for bookmark in Bookmark.objects.filter(ayah__isnull=False).iterator():
        note = bookmark.note or ""
        color_key = bookmark.color_key or "default"
        if not note.strip() and color_key == "default":
            continue
        AyahAnnotation.objects.create(
            id=uuid.uuid7(),
            user_id=bookmark.user_id,
            edition_id=bookmark.edition_id,
            page_id=bookmark.page_id,
            ayah_id=bookmark.ayah_id,
            color_key="lime" if color_key == "default" else color_key,
            note=note,
            client_updated_at=bookmark.client_updated_at,
            revision=1,
            device_id=bookmark.device_id,
        )


class Migration(migrations.Migration):
    dependencies = [
        ("reading", "0010_prayerreadingplan_notifications_enabled"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="AyahAnnotation",
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
                ("color_key", models.CharField(default="lime", max_length=32)),
                ("note", models.TextField(blank=True, max_length=2000)),
                ("client_updated_at", models.DateTimeField()),
                ("revision", models.PositiveBigIntegerField(default=1)),
                ("deleted_at", models.DateTimeField(blank=True, db_index=True, null=True)),
                (
                    "ayah",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="annotations",
                        to="quran.ayah",
                    ),
                ),
                (
                    "device",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="ayah_annotations",
                        to="accounts.device",
                    ),
                ),
                (
                    "edition",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="ayah_annotations",
                        to="quran.quranedition",
                    ),
                ),
                (
                    "page",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="ayah_annotations",
                        to="quran.mushafpage",
                    ),
                ),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="ayah_annotations",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "db_table": "reading_ayah_annotation",
                "ordering": ["-updated_at", "-id"],
                "indexes": [
                    models.Index(
                        fields=["user", "deleted_at"],
                        name="reading_annot_user_del_idx",
                    ),
                    models.Index(
                        fields=["user", "edition", "ayah"],
                        name="reading_annot_user_ayah_idx",
                    ),
                ],
                "constraints": [
                    models.CheckConstraint(
                        condition=models.Q(("revision__gte", 1)),
                        name="reading_annotation_revision_positive",
                    ),
                ],
            },
        ),
        migrations.RunPython(migrate_legacy_bookmark_details, migrations.RunPython.noop),
    ]
