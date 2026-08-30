import django.db.models.deletion
import uuid
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("quran", "0003_quranfoundationmushaf_quranfoundationmushafsyncstate_and_more"),
    ]

    operations = [
        migrations.CreateModel(
            name="QuranFoundationNativePublication",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid7, editable=False, primary_key=True, serialize=False
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("render_version", models.CharField(max_length=96)),
                ("renderer_name", models.CharField(max_length=128)),
                ("renderer_version", models.CharField(max_length=96)),
                ("source_checksum_sha256", models.CharField(max_length=64)),
                ("manifest_checksum_sha256", models.CharField(blank=True, max_length=64)),
                ("expected_pages", models.PositiveSmallIntegerField()),
                ("required_widths", models.JSONField(default=list)),
                ("prepared_pages", models.PositiveSmallIntegerField(default=0)),
                ("assets_count", models.PositiveIntegerField(default=0)),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("preparing", "Preparing"),
                            ("published", "Published"),
                            ("withdrawn", "Withdrawn"),
                            ("failed", "Failed"),
                        ],
                        default="preparing",
                        max_length=16,
                    ),
                ),
                ("is_active", models.BooleanField(default=False)),
                ("published_at", models.DateTimeField(blank=True, null=True)),
                ("last_error_code", models.CharField(blank=True, max_length=64)),
                ("last_error_message", models.CharField(blank=True, max_length=500)),
                (
                    "mushaf",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="native_publications",
                        to="quran.quranfoundationmushaf",
                    ),
                ),
            ],
            options={
                "db_table": "quran_qf_native_publication",
                "ordering": ["mushaf", "-published_at", "render_version"],
            },
        ),
        migrations.CreateModel(
            name="QuranFoundationNativePageAsset",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid7, editable=False, primary_key=True, serialize=False
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("page_number", models.PositiveSmallIntegerField()),
                ("width", models.PositiveIntegerField()),
                ("height", models.PositiveIntegerField()),
                ("content_type", models.CharField(default="image/webp", max_length=64)),
                ("storage_key", models.CharField(max_length=500, unique=True)),
                ("checksum_sha256", models.CharField(max_length=64)),
                ("size_bytes", models.PositiveBigIntegerField()),
                (
                    "publication",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="page_assets",
                        to="quran.quranfoundationnativepublication",
                    ),
                ),
            ],
            options={
                "db_table": "quran_qf_native_page_asset",
                "ordering": ["publication", "page_number", "width"],
            },
        ),
        migrations.AddIndex(
            model_name="quranfoundationnativepublication",
            index=models.Index(
                fields=["mushaf", "status", "is_active"], name="quran_qf_native_public_idx"
            ),
        ),
        migrations.AddConstraint(
            model_name="quranfoundationnativepublication",
            constraint=models.UniqueConstraint(
                fields=("mushaf", "render_version"), name="quran_qf_native_pub_version_uq"
            ),
        ),
        migrations.AddConstraint(
            model_name="quranfoundationnativepublication",
            constraint=models.UniqueConstraint(
                condition=models.Q(("is_active", True)),
                fields=("mushaf",),
                name="quran_qf_native_one_active_uq",
            ),
        ),
        migrations.AddConstraint(
            model_name="quranfoundationnativepublication",
            constraint=models.CheckConstraint(
                condition=models.Q(("expected_pages__gt", 0)),
                name="quran_qf_native_expected_pages_positive",
            ),
        ),
        migrations.AddConstraint(
            model_name="quranfoundationnativepublication",
            constraint=models.CheckConstraint(
                condition=models.Q(("prepared_pages__lte", models.F("expected_pages"))),
                name="quran_qf_native_prepared_pages_lte_expected",
            ),
        ),
        migrations.AddConstraint(
            model_name="quranfoundationnativepublication",
            constraint=models.CheckConstraint(
                condition=models.Q(
                    models.Q(("published_at__isnull", False), ("status", "published")),
                    models.Q(("status", "published"), _negated=True),
                    _connector="OR",
                ),
                name="quran_qf_native_published_at_required",
            ),
        ),
        migrations.AddConstraint(
            model_name="quranfoundationnativepublication",
            constraint=models.CheckConstraint(
                condition=models.Q(("is_active", False), ("status", "published"), _connector="OR"),
                name="quran_qf_native_active_is_published",
            ),
        ),
        migrations.AddIndex(
            model_name="quranfoundationnativepageasset",
            index=models.Index(
                fields=["publication", "page_number"], name="quran_qf_native_asset_page_idx"
            ),
        ),
        migrations.AddConstraint(
            model_name="quranfoundationnativepageasset",
            constraint=models.UniqueConstraint(
                fields=("publication", "page_number", "width"),
                name="quran_qf_native_asset_page_width_uq",
            ),
        ),
        migrations.AddConstraint(
            model_name="quranfoundationnativepageasset",
            constraint=models.CheckConstraint(
                condition=models.Q(("page_number__gt", 0)),
                name="quran_qf_native_asset_page_positive",
            ),
        ),
        migrations.AddConstraint(
            model_name="quranfoundationnativepageasset",
            constraint=models.CheckConstraint(
                condition=models.Q(("height__gt", 0), ("size_bytes__gt", 0), ("width__gt", 0)),
                name="quran_qf_native_asset_dimensions_positive",
            ),
        ),
    ]
