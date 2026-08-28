import django.db.models.deletion
import uuid
from django.conf import settings
from django.db import migrations, models


AUDIO_PROVIDER = "hisnmuslim"
AUDIO_SOURCE_VERSION = "hisnmuslim-audio-2026-08-29"


def seed_hisn_audio(apps, schema_editor):  # noqa: ARG001
    collection_model = apps.get_model("dua", "DuaCollection")
    audio_model = apps.get_model("dua", "DuaAudioAsset")
    collection = collection_model.objects.filter(slug="hisn-al-muslim").first()
    if collection is None:
        return
    existing_numbers = set(
        audio_model.objects.filter(
            collection=collection,
            provider=AUDIO_PROVIDER,
            source_version=AUDIO_SOURCE_VERSION,
        ).values_list("source_number", flat=True)
    )
    audio_model.objects.bulk_create(
        [
            audio_model(
                collection=collection,
                source_number=source_number,
                language_code="ar",
                provider=AUDIO_PROVIDER,
                reader_name="Hamad Al-Duraihem",
                reader_name_ar="حمد الدريهم",
                url=f"https://www.hisnmuslim.com/audio/ar/{source_number}.mp3",
                source_url="https://hisnmuslim.com/",
                rights_url="",
                source_version=AUDIO_SOURCE_VERSION,
                sort_order=1,
                is_active=True,
            )
            for source_number in range(1, 268)
            if source_number not in existing_numbers
        ]
    )


def remove_hisn_audio(apps, schema_editor):  # noqa: ARG001
    audio_model = apps.get_model("dua", "DuaAudioAsset")
    audio_model.objects.filter(
        provider=AUDIO_PROVIDER,
        source_version=AUDIO_SOURCE_VERSION,
    ).delete()


class Migration(migrations.Migration):
    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ("dua", "0004_seed_hisn_full"),
    ]

    operations = [
        migrations.CreateModel(
            name="DuaAudioAsset",
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
                ("source_number", models.PositiveSmallIntegerField()),
                ("language_code", models.CharField(default="ar", max_length=8)),
                ("provider", models.CharField(max_length=64)),
                ("reader_name", models.CharField(max_length=255)),
                ("reader_name_ar", models.CharField(blank=True, max_length=255)),
                ("url", models.URLField(max_length=500)),
                ("source_url", models.URLField(max_length=500)),
                ("rights_url", models.URLField(blank=True, max_length=500)),
                ("source_version", models.CharField(max_length=64)),
                ("sort_order", models.PositiveSmallIntegerField(default=1)),
                ("is_active", models.BooleanField(default=True)),
                (
                    "collection",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="audio_assets",
                        to="dua.duacollection",
                    ),
                ),
            ],
            options={
                "db_table": "dua_audio_asset",
                "ordering": ("source_number", "sort_order", "created_at"),
                "indexes": [
                    models.Index(
                        fields=["collection", "source_number", "is_active"],
                        name="dua_audio_catalog_idx",
                    ),
                ],
                "constraints": [
                    models.UniqueConstraint(
                        fields=("collection", "source_number", "url"),
                        name="dua_audio_collection_entry_url_unique",
                    ),
                    models.CheckConstraint(
                        condition=models.Q(("source_number__gt", 0)),
                        name="dua_audio_source_number_positive",
                    ),
                    models.CheckConstraint(
                        condition=models.Q(("sort_order__gt", 0)),
                        name="dua_audio_sort_order_positive",
                    ),
                ],
            },
        ),
        migrations.CreateModel(
            name="DuaFavorite",
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
                ("source_number", models.PositiveSmallIntegerField()),
                (
                    "collection",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="favorites",
                        to="dua.duacollection",
                    ),
                ),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="dua_favorites",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "db_table": "dua_favorite",
                "ordering": ("-created_at", "-id"),
                "indexes": [
                    models.Index(
                        fields=["user", "created_at"],
                        name="dua_favorite_user_idx",
                    ),
                ],
                "constraints": [
                    models.UniqueConstraint(
                        fields=("user", "collection", "source_number"),
                        name="dua_favorite_user_entry_unique",
                    ),
                    models.CheckConstraint(
                        condition=models.Q(("source_number__gt", 0)),
                        name="dua_favorite_source_number_positive",
                    ),
                ],
            },
        ),
        migrations.RunPython(seed_hisn_audio, remove_hisn_audio),
    ]
