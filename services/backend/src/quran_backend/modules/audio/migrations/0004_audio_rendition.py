import uuid

import django.db.models.deletion
from django.db import migrations, models

import quran_backend.modules.audio.validators


def copy_track_assets_to_renditions(apps: object, _schema_editor: object) -> None:
    audio_track = apps.get_model("audio", "AudioTrack")
    audio_rendition = apps.get_model("audio", "AudioRendition")
    for track in audio_track.objects.all().iterator(chunk_size=1000):
        audio_rendition.objects.create(
            track_id=track.id,
            quality="standard",
            is_default=True,
            codec=track.codec,
            content_type=track.content_type,
            bitrate_kbps=track.bitrate_kbps,
            size_bytes=track.size_bytes,
            checksum_sha256=track.checksum_sha256 or "",
            object_key=track.object_key,
            external_url=track.external_url or "",
        )


def restore_default_renditions_to_tracks(apps: object, _schema_editor: object) -> None:
    audio_track = apps.get_model("audio", "AudioTrack")
    audio_rendition = apps.get_model("audio", "AudioRendition")
    for track in audio_track.objects.all().iterator(chunk_size=1000):
        rendition = (
            audio_rendition.objects.filter(track_id=track.id)
            .order_by("-is_default", "quality", "id")
            .first()
        )
        if rendition is None:
            continue
        audio_track.objects.filter(pk=track.id).update(
            codec=rendition.codec,
            content_type=rendition.content_type,
            bitrate_kbps=rendition.bitrate_kbps,
            size_bytes=rendition.size_bytes,
            checksum_sha256=rendition.checksum_sha256,
            object_key=rendition.object_key,
            external_url=rendition.external_url,
        )


class Migration(migrations.Migration):
    dependencies = [
        ("audio", "0003_quranfoundationsyncstate"),
    ]

    operations = [
        migrations.CreateModel(
            name="AudioRendition",
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
                    "quality",
                    models.CharField(
                        choices=[
                            ("economy", "Economy"),
                            ("standard", "Standard"),
                            ("high", "High"),
                        ],
                        default="standard",
                        max_length=16,
                    ),
                ),
                ("is_default", models.BooleanField(default=False)),
                (
                    "codec",
                    models.CharField(
                        choices=[
                            ("mp3", "MP3"),
                            ("aac", "AAC"),
                            ("opus", "Opus"),
                            ("flac", "FLAC"),
                        ],
                        max_length=16,
                    ),
                ),
                (
                    "content_type",
                    models.CharField(
                        choices=[
                            ("audio/mpeg", "audio/mpeg"),
                            ("audio/aac", "audio/aac"),
                            ("audio/ogg", "audio/ogg"),
                            ("audio/flac", "audio/flac"),
                        ],
                        default="audio/mpeg",
                        max_length=32,
                    ),
                ),
                ("bitrate_kbps", models.PositiveIntegerField()),
                ("size_bytes", models.PositiveBigIntegerField()),
                (
                    "checksum_sha256",
                    models.CharField(
                        blank=True,
                        max_length=64,
                        validators=[quran_backend.modules.audio.validators.validate_sha256],
                    ),
                ),
                (
                    "object_key",
                    models.CharField(
                        blank=True,
                        max_length=512,
                        null=True,
                        unique=True,
                        validators=[
                            quran_backend.modules.audio.validators.validate_relative_object_key
                        ],
                    ),
                ),
                ("external_url", models.URLField(blank=True, max_length=1000)),
                (
                    "etag",
                    models.CharField(
                        blank=True,
                        max_length=255,
                        validators=[quran_backend.modules.audio.validators.validate_strong_etag],
                    ),
                ),
                ("cdn_contract_verified_at", models.DateTimeField(blank=True, null=True)),
                (
                    "track",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="renditions",
                        to="audio.audiotrack",
                    ),
                ),
            ],
            options={
                "db_table": "audio_rendition",
                "ordering": ["track", "quality", "id"],
                "indexes": [
                    models.Index(
                        fields=["track", "is_default", "quality"],
                        name="audio_rendition_track_idx",
                    )
                ],
                "constraints": [
                    models.CheckConstraint(
                        condition=models.Q(bitrate_kbps__gt=0, bitrate_kbps__lte=100000),
                        name="audio_rendition_bitrate_valid",
                    ),
                    models.CheckConstraint(
                        condition=models.Q(size_bytes__gt=0),
                        name="audio_rendition_size_positive",
                    ),
                    models.CheckConstraint(
                        condition=(
                            models.Q(external_url="", object_key__isnull=False)
                            | (models.Q(object_key__isnull=True) & ~models.Q(external_url=""))
                        ),
                        name="audio_rendition_delivery_valid",
                    ),
                    models.UniqueConstraint(
                        fields=("track", "quality"),
                        name="audio_rendition_track_quality_uq",
                    ),
                    models.UniqueConstraint(
                        condition=models.Q(is_default=True),
                        fields=("track",),
                        name="audio_rendition_default_uq",
                    ),
                ],
            },
        ),
        migrations.AlterField(
            model_name="audiotrack",
            name="codec",
            field=models.CharField(
                blank=True,
                choices=[
                    ("mp3", "MP3"),
                    ("aac", "AAC"),
                    ("opus", "Opus"),
                    ("flac", "FLAC"),
                ],
                max_length=16,
                null=True,
            ),
        ),
        migrations.AlterField(
            model_name="audiotrack",
            name="content_type",
            field=models.CharField(
                blank=True,
                choices=[
                    ("audio/mpeg", "audio/mpeg"),
                    ("audio/aac", "audio/aac"),
                    ("audio/ogg", "audio/ogg"),
                    ("audio/flac", "audio/flac"),
                ],
                default="audio/mpeg",
                max_length=32,
                null=True,
            ),
        ),
        migrations.AlterField(
            model_name="audiotrack",
            name="bitrate_kbps",
            field=models.PositiveIntegerField(blank=True, null=True),
        ),
        migrations.AlterField(
            model_name="audiotrack",
            name="size_bytes",
            field=models.PositiveBigIntegerField(blank=True, null=True),
        ),
        migrations.AlterField(
            model_name="audiotrack",
            name="checksum_sha256",
            field=models.CharField(
                blank=True,
                max_length=64,
                null=True,
                validators=[quran_backend.modules.audio.validators.validate_sha256],
            ),
        ),
        migrations.AlterField(
            model_name="audiotrack",
            name="external_url",
            field=models.URLField(blank=True, max_length=1000, null=True),
        ),
        migrations.RunPython(
            copy_track_assets_to_renditions,
            restore_default_renditions_to_tracks,
        ),
        migrations.RemoveConstraint(
            model_name="audiotrack",
            name="audio_track_bitrate_valid",
        ),
        migrations.RemoveConstraint(
            model_name="audiotrack",
            name="audio_track_size_positive",
        ),
        migrations.RemoveConstraint(
            model_name="audiotrack",
            name="audio_track_delivery_source_valid",
        ),
        migrations.RemoveField(model_name="audiotrack", name="codec"),
        migrations.RemoveField(model_name="audiotrack", name="content_type"),
        migrations.RemoveField(model_name="audiotrack", name="bitrate_kbps"),
        migrations.RemoveField(model_name="audiotrack", name="size_bytes"),
        migrations.RemoveField(model_name="audiotrack", name="checksum_sha256"),
        migrations.RemoveField(model_name="audiotrack", name="object_key"),
        migrations.RemoveField(model_name="audiotrack", name="external_url"),
    ]
