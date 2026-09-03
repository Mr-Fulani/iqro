import hashlib

import django.db.models.deletion
import quran_backend.modules.audio.validators
from django.db import migrations, models


def scope_existing_audio_to_versions(apps, schema_editor):  # noqa: ARG001
    audio_model = apps.get_model("dua", "DuaAudioAsset")
    collection_model = apps.get_model("dua", "DuaCollection")
    version_model = apps.get_model("dua", "DuaCollectionVersion")

    collection_ids = audio_model.objects.values_list("collection_id", flat=True).distinct()
    for collection in collection_model.objects.filter(pk__in=collection_ids).iterator():
        version = None
        if collection.active_version_id:
            version = version_model.objects.filter(pk=collection.active_version_id).first()
        if version is None:
            version = (
                version_model.objects.filter(collection_id=collection.pk)
                .order_by("-created_at", "-id")
                .first()
            )
        if version is None:
            marker = f"legacy-unscoped-audio:{collection.pk}"
            version = version_model.objects.create(
                collection_id=collection.pk,
                version="legacy-unscoped-audio",
                schema_version=1,
                checksum_sha256=hashlib.sha256(marker.encode()).hexdigest(),
                status="draft",
                category_count=0,
                entry_count=0,
            )
        assets = audio_model.objects.filter(collection_id=collection.pk)
        if collection.active_version_id != version.pk:
            assets.update(is_active=False)
        assets.update(collection_version_id=version.pk)


def unscope_audio(apps, schema_editor):  # noqa: ARG001
    audio_model = apps.get_model("dua", "DuaAudioAsset")
    audio_model.objects.update(collection_version_id=None)


class Migration(migrations.Migration):
    dependencies = [
        ("dua", "0006_dua_search_trigram_indexes"),
    ]

    operations = [
        migrations.RemoveConstraint(
            model_name="duaaudioasset",
            name="dua_audio_collection_entry_url_unique",
        ),
        migrations.RemoveIndex(
            model_name="duaaudioasset",
            name="dua_audio_catalog_idx",
        ),
        migrations.RenameField(
            model_name="duaaudioasset",
            old_name="url",
            new_name="external_url",
        ),
        migrations.AlterField(
            model_name="duaaudioasset",
            name="external_url",
            field=models.URLField(blank=True, max_length=1000),
        ),
        migrations.AddField(
            model_name="duaaudioasset",
            name="collection_version",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.CASCADE,
                related_name="audio_assets",
                to="dua.duacollectionversion",
            ),
        ),
        migrations.AddField(
            model_name="duaaudioasset",
            name="object_key",
            field=models.CharField(
                blank=True,
                max_length=512,
                null=True,
                unique=True,
                validators=[quran_backend.modules.audio.validators.validate_relative_object_key],
            ),
        ),
        migrations.AddField(
            model_name="duaaudioasset",
            name="content_type",
            field=models.CharField(default="audio/mpeg", max_length=64),
        ),
        migrations.AddField(
            model_name="duaaudioasset",
            name="size_bytes",
            field=models.PositiveBigIntegerField(default=0),
        ),
        migrations.AddField(
            model_name="duaaudioasset",
            name="checksum_sha256",
            field=models.CharField(
                blank=True,
                max_length=64,
                validators=[quran_backend.modules.audio.validators.validate_sha256],
            ),
        ),
        migrations.AddField(
            model_name="duaaudioasset",
            name="origin_etag",
            field=models.CharField(
                blank=True,
                max_length=255,
                validators=[quran_backend.modules.audio.validators.validate_strong_etag],
            ),
        ),
        migrations.AddField(
            model_name="duaaudioasset",
            name="etag",
            field=models.CharField(
                blank=True,
                max_length=255,
                validators=[quran_backend.modules.audio.validators.validate_strong_etag],
            ),
        ),
        migrations.AddField(
            model_name="duaaudioasset",
            name="cdn_contract_verified_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="duaaudioasset",
            name="rights_basis",
            field=models.CharField(
                choices=[
                    ("source_documented", "Documented by the source"),
                    ("iqro_owner_attested", "Attested by the IQRO owner"),
                ],
                default="source_documented",
                max_length=32,
            ),
        ),
        migrations.AddField(
            model_name="duasourceedition",
            name="rights_basis",
            field=models.CharField(
                choices=[
                    ("source_documented", "Documented by the source"),
                    ("iqro_owner_attested", "Attested by the IQRO owner"),
                ],
                default="source_documented",
                max_length=32,
            ),
        ),
        migrations.AlterField(
            model_name="duaaudioasset",
            name="reader_name",
            field=models.CharField(blank=True, max_length=255),
        ),
        migrations.AlterField(
            model_name="duaaudioasset",
            name="collection",
            field=models.ForeignKey(
                editable=False,
                on_delete=django.db.models.deletion.CASCADE,
                related_name="audio_assets",
                to="dua.duacollection",
            ),
        ),
        migrations.AlterField(
            model_name="duasourceedition",
            name="author",
            field=models.CharField(blank=True, max_length=255),
        ),
        migrations.AlterField(
            model_name="duasourceedition",
            name="rights_url",
            field=models.URLField(blank=True, max_length=500),
        ),
        migrations.RunPython(scope_existing_audio_to_versions, unscope_audio),
        migrations.AlterField(
            model_name="duaaudioasset",
            name="collection_version",
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.CASCADE,
                related_name="audio_assets",
                to="dua.duacollectionversion",
            ),
        ),
        migrations.AddIndex(
            model_name="duaaudioasset",
            index=models.Index(
                fields=["collection_version", "source_number", "is_active"],
                name="dua_audio_catalog_idx",
            ),
        ),
        migrations.AddConstraint(
            model_name="duaaudioasset",
            constraint=models.UniqueConstraint(
                fields=("collection_version", "source_number", "sort_order"),
                name="dua_audio_version_entry_order_unique",
            ),
        ),
        migrations.AddConstraint(
            model_name="duaaudioasset",
            constraint=models.CheckConstraint(
                condition=(
                    models.Q(object_key__isnull=False, external_url="")
                    | (models.Q(object_key__isnull=True) & ~models.Q(external_url=""))
                ),
                name="dua_audio_delivery_valid",
            ),
        ),
        migrations.AddConstraint(
            model_name="duaaudioasset",
            constraint=models.CheckConstraint(
                condition=(
                    models.Q(is_active=False)
                    | models.Q(object_key__isnull=True)
                    | (
                        ~models.Q(checksum_sha256="")
                        & ~models.Q(origin_etag="")
                        & ~models.Q(etag="")
                        & models.Q(cdn_contract_verified_at__isnull=False)
                        & models.Q(size_bytes__gt=0)
                    )
                ),
                name="dua_audio_active_managed_verified",
            ),
        ),
    ]
