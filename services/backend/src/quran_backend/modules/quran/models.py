from __future__ import annotations

from decimal import Decimal
from typing import Any

from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone

from quran_backend.modules.core.models import BaseModel


class PublicationStatus(models.TextChoices):
    DRAFT = "draft", "Draft"
    PUBLISHED = "published", "Published"
    WITHDRAWN = "withdrawn", "Withdrawn"


class QuranEdition(BaseModel):
    code = models.SlugField(max_length=64, unique=True)
    name_ar = models.CharField(max_length=255)
    name_en = models.CharField(max_length=255)
    name_ru = models.CharField(max_length=255)
    riwayah = models.CharField(max_length=128)
    source_name = models.CharField(max_length=255)
    source_url = models.URLField(blank=True)
    license_name = models.CharField(max_length=255)
    license_url = models.URLField(blank=True)
    active_version = models.ForeignKey(
        "QuranEditionVersion",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="active_for_editions",
    )

    class Meta:
        db_table = "quran_edition"

    def __str__(self) -> str:
        return self.code

    def clean(self) -> None:
        super().clean()
        active_version = self.active_version if self.active_version_id else None
        if active_version and active_version.edition_id != self.id:
            raise ValidationError("The active version must belong to this Quran edition.")
        if active_version and active_version.status != PublicationStatus.PUBLISHED:
            raise ValidationError("Only a published Quran edition version can be active.")


class QuranEditionVersion(BaseModel):
    edition = models.ForeignKey(QuranEdition, on_delete=models.PROTECT, related_name="versions")
    version = models.CharField(max_length=64)
    checksum_sha256 = models.CharField(max_length=64)
    status = models.CharField(
        max_length=16, choices=PublicationStatus, default=PublicationStatus.DRAFT
    )
    page_count = models.PositiveSmallIntegerField(default=604)
    surah_count = models.PositiveSmallIntegerField(default=114)
    juz_count = models.PositiveSmallIntegerField(default=30)
    hizb_count = models.PositiveSmallIntegerField(default=0)
    rub_el_hizb_count = models.PositiveSmallIntegerField(default=0)
    published_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "quran_edition_version"
        constraints = [
            models.UniqueConstraint(
                fields=["edition", "version"],
                name="quran_edition_version_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(page_count__gt=0),
                name="quran_version_positive_pages",
            ),
            models.CheckConstraint(
                condition=models.Q(surah_count__gt=0),
                name="quran_version_positive_surahs",
            ),
            models.CheckConstraint(
                condition=models.Q(juz_count__gt=0),
                name="quran_version_positive_juz",
            ),
            models.CheckConstraint(
                condition=models.Q(hizb_count__gte=0, hizb_count__lte=60),
                name="quran_version_hizb_count_range",
            ),
            models.CheckConstraint(
                condition=models.Q(rub_el_hizb_count__gte=0, rub_el_hizb_count__lte=240),
                name="quran_version_rub_count_range",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(status=PublicationStatus.PUBLISHED, published_at__isnull=False)
                    | ~models.Q(status=PublicationStatus.PUBLISHED)
                ),
                name="quran_published_version_has_timestamp",
            ),
        ]
        indexes = [
            models.Index(fields=["status", "edition"], name="quran_version_status_idx"),
        ]

    def __str__(self) -> str:
        return f"{self.edition.code}@{self.version}"

    def publish(self) -> None:
        self.status = PublicationStatus.PUBLISHED
        self.published_at = timezone.now()


class RevelationType(models.TextChoices):
    MECCAN = "meccan", "Meccan"
    MEDINAN = "medinan", "Medinan"


class Surah(BaseModel):
    edition_version = models.ForeignKey(
        QuranEditionVersion,
        on_delete=models.PROTECT,
        related_name="surahs",
    )
    number = models.PositiveSmallIntegerField()
    name_ar = models.CharField(max_length=128)
    name_en = models.CharField(max_length=128)
    name_ru = models.CharField(max_length=128)
    revelation_type = models.CharField(max_length=16, choices=RevelationType)
    ayah_count = models.PositiveSmallIntegerField()

    class Meta:
        db_table = "quran_surah"
        ordering = ["number"]
        constraints = [
            models.UniqueConstraint(
                fields=["edition_version", "number"],
                name="quran_surah_version_number_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(number__gte=1, number__lte=114),
                name="quran_surah_number_range",
            ),
            models.CheckConstraint(
                condition=models.Q(ayah_count__gt=0),
                name="quran_surah_positive_ayah_count",
            ),
        ]

    def __str__(self) -> str:
        version = self.edition_version
        return f"{version.edition.code}@{version.version}:{self.number}"


class Ayah(BaseModel):
    surah = models.ForeignKey(Surah, on_delete=models.PROTECT, related_name="ayahs")
    number = models.PositiveSmallIntegerField()
    text_uthmani = models.TextField()
    text_search = models.TextField(blank=True)
    juz_number = models.PositiveSmallIntegerField()
    hizb_number = models.PositiveSmallIntegerField(null=True, blank=True)
    rub_el_hizb_number = models.PositiveSmallIntegerField(null=True, blank=True)

    class Meta:
        db_table = "quran_ayah"
        ordering = ["surah__number", "number"]
        constraints = [
            models.UniqueConstraint(
                fields=["surah", "number"],
                name="quran_ayah_surah_number_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(number__gte=1),
                name="quran_ayah_positive_number",
            ),
            models.CheckConstraint(
                condition=models.Q(juz_number__gte=1, juz_number__lte=30),
                name="quran_ayah_juz_range",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(hizb_number__isnull=True)
                    | models.Q(hizb_number__gte=1, hizb_number__lte=60)
                ),
                name="quran_ayah_hizb_range",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(rub_el_hizb_number__isnull=True)
                    | models.Q(rub_el_hizb_number__gte=1, rub_el_hizb_number__lte=240)
                ),
                name="quran_ayah_rub_range",
            ),
        ]
        indexes = [
            models.Index(fields=["juz_number", "surah", "number"], name="quran_ayah_juz_idx"),
            models.Index(fields=["hizb_number", "surah", "number"], name="quran_ayah_hizb_idx"),
            models.Index(
                fields=["rub_el_hizb_number", "surah", "number"],
                name="quran_ayah_rub_idx",
            ),
        ]

    def __str__(self) -> str:
        version = self.surah.edition_version
        return f"{version.edition.code}@{version.version}:{self.surah.number}:{self.number}"


class MushafPage(BaseModel):
    edition_version = models.ForeignKey(
        QuranEditionVersion,
        on_delete=models.PROTECT,
        related_name="pages",
    )
    number = models.PositiveSmallIntegerField()
    image_width = models.PositiveIntegerField()
    image_height = models.PositiveIntegerField()
    checksum_sha256 = models.CharField(max_length=64)
    asset_variants = models.JSONField(default=list)

    class Meta:
        db_table = "quran_mushaf_page"
        ordering = ["number"]
        constraints = [
            models.UniqueConstraint(
                fields=["edition_version", "number"],
                name="quran_page_version_number_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(number__gte=1, number__lte=604),
                name="quran_page_number_range",
            ),
            models.CheckConstraint(
                condition=models.Q(image_width__gt=0, image_height__gt=0),
                name="quran_page_positive_dimensions",
            ),
        ]

    def clean(self) -> None:
        super().clean()
        if not isinstance(self.asset_variants, list) or not self.asset_variants:
            raise ValidationError({"asset_variants": "At least one asset variant is required."})
        for variant in self.asset_variants:
            self._validate_asset_variant(variant)

    @staticmethod
    def _validate_asset_variant(variant: Any) -> None:
        required = {"format", "width", "height", "path", "sha256", "bytes"}
        if not isinstance(variant, dict) or not required.issubset(variant):
            raise ValidationError({"asset_variants": "An asset variant is malformed."})
        path = str(variant["path"])
        if path.startswith(("/", "http://", "https://")) or ".." in path.split("/"):
            raise ValidationError({"asset_variants": "Asset paths must be safe relative paths."})
        if int(variant["width"]) <= 0 or int(variant["height"]) <= 0 or int(variant["bytes"]) <= 0:
            raise ValidationError({"asset_variants": "Asset dimensions and size must be positive."})


class AyahPageRegion(BaseModel):
    page = models.ForeignKey(MushafPage, on_delete=models.CASCADE, related_name="regions")
    ayah = models.ForeignKey(Ayah, on_delete=models.PROTECT, related_name="page_regions")
    reading_order = models.PositiveSmallIntegerField()
    polygon = models.JSONField(default=list)
    x = models.DecimalField(max_digits=8, decimal_places=7)
    y = models.DecimalField(max_digits=8, decimal_places=7)
    width = models.DecimalField(max_digits=8, decimal_places=7)
    height = models.DecimalField(max_digits=8, decimal_places=7)

    class Meta:
        db_table = "quran_ayah_page_region"
        ordering = ["reading_order"]
        constraints = [
            models.UniqueConstraint(
                fields=["page", "ayah", "reading_order"],
                name="quran_region_page_ayah_order_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(x__gte=0, x__lte=1),
                name="quran_region_x_range",
            ),
            models.CheckConstraint(
                condition=models.Q(y__gte=0, y__lte=1),
                name="quran_region_y_range",
            ),
            models.CheckConstraint(
                condition=models.Q(width__gt=0, width__lte=1),
                name="quran_region_width_range",
            ),
            models.CheckConstraint(
                condition=models.Q(height__gt=0, height__lte=1),
                name="quran_region_height_range",
            ),
            models.CheckConstraint(
                condition=models.Q(x__lte=1) & models.Q(width__lte=1),
                name="quran_region_bbox_values_lte_one",
            ),
        ]
        indexes = [
            models.Index(fields=["ayah", "page"], name="quran_region_ayah_idx"),
        ]

    def clean(self) -> None:
        super().clean()
        if self.page.edition_version_id != self.ayah.surah.edition_version_id:
            raise ValidationError("Page and ayah must belong to the same Quran edition.")
        if self.x + self.width > Decimal(1) or self.y + self.height > Decimal(1):
            raise ValidationError("The region bounding box must fit within the page.")
        if not isinstance(self.polygon, list) or len(self.polygon) < 3:
            raise ValidationError({"polygon": "A polygon must contain at least three points."})
        for point in self.polygon:
            if (
                not isinstance(point, list | tuple)
                or len(point) != 2
                or not all(0 <= Decimal(str(coordinate)) <= 1 for coordinate in point)
            ):
                raise ValidationError({"polygon": "Polygon coordinates must be normalized."})


class Juz(BaseModel):
    edition_version = models.ForeignKey(
        QuranEditionVersion,
        on_delete=models.PROTECT,
        related_name="juz",
    )
    number = models.PositiveSmallIntegerField()
    start_ayah = models.ForeignKey(Ayah, on_delete=models.PROTECT, related_name="juz_starts")
    end_ayah = models.ForeignKey(Ayah, on_delete=models.PROTECT, related_name="juz_ends")

    class Meta:
        db_table = "quran_juz"
        ordering = ["number"]
        constraints = [
            models.UniqueConstraint(
                fields=["edition_version", "number"],
                name="quran_juz_version_number_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(number__gte=1, number__lte=30),
                name="quran_juz_number_range",
            ),
        ]

    def clean(self) -> None:
        super().clean()
        version_ids = {
            self.start_ayah.surah.edition_version_id,
            self.end_ayah.surah.edition_version_id,
        }
        if version_ids != {self.edition_version_id}:
            raise ValidationError("Juz boundaries must belong to the same Quran edition.")


class Hizb(BaseModel):
    edition_version = models.ForeignKey(
        QuranEditionVersion,
        on_delete=models.PROTECT,
        related_name="hizb",
    )
    number = models.PositiveSmallIntegerField()
    start_ayah = models.ForeignKey(Ayah, on_delete=models.PROTECT, related_name="hizb_starts")
    end_ayah = models.ForeignKey(Ayah, on_delete=models.PROTECT, related_name="hizb_ends")

    class Meta:
        db_table = "quran_hizb"
        ordering = ["number"]
        constraints = [
            models.UniqueConstraint(
                fields=["edition_version", "number"],
                name="quran_hizb_version_number_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(number__gte=1, number__lte=60),
                name="quran_hizb_number_range",
            ),
        ]

    def clean(self) -> None:
        super().clean()
        version_ids = {
            self.start_ayah.surah.edition_version_id,
            self.end_ayah.surah.edition_version_id,
        }
        if version_ids != {self.edition_version_id}:
            raise ValidationError("Hizb boundaries must belong to the same Quran edition.")


class RubElHizb(BaseModel):
    edition_version = models.ForeignKey(
        QuranEditionVersion,
        on_delete=models.PROTECT,
        related_name="rub_el_hizb",
    )
    hizb = models.ForeignKey(Hizb, on_delete=models.PROTECT, related_name="quarters")
    number = models.PositiveSmallIntegerField()
    start_ayah = models.ForeignKey(Ayah, on_delete=models.PROTECT, related_name="rub_starts")
    end_ayah = models.ForeignKey(Ayah, on_delete=models.PROTECT, related_name="rub_ends")

    class Meta:
        db_table = "quran_rub_el_hizb"
        ordering = ["number"]
        constraints = [
            models.UniqueConstraint(
                fields=["edition_version", "number"],
                name="quran_rub_version_number_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(number__gte=1, number__lte=240),
                name="quran_rub_number_range",
            ),
        ]

    def clean(self) -> None:
        super().clean()
        version_ids = {
            self.hizb.edition_version_id,
            self.start_ayah.surah.edition_version_id,
            self.end_ayah.surah.edition_version_id,
        }
        if version_ids != {self.edition_version_id}:
            raise ValidationError("Rub el Hizb boundaries must belong to the same Quran edition.")


class SourceManifest(BaseModel):
    edition_version = models.ForeignKey(
        QuranEditionVersion,
        on_delete=models.PROTECT,
        related_name="manifests",
    )
    source_version = models.CharField(max_length=128)
    checksum_sha256 = models.CharField(max_length=64)
    expected_surahs = models.PositiveSmallIntegerField()
    expected_ayahs = models.PositiveIntegerField()
    expected_pages = models.PositiveSmallIntegerField()
    payload = models.JSONField(default=dict)
    imported_at = models.DateTimeField(default=timezone.now)

    class Meta:
        db_table = "quran_source_manifest"
        constraints = [
            models.UniqueConstraint(
                fields=["edition_version", "source_version"],
                name="quran_manifest_source_version_unique",
            )
        ]


class QuranFoundationMushafSyncState(BaseModel):
    """Checkpoint for the canonical Quran.Foundation Mushaf catalog filter."""

    environment = models.CharField(max_length=16)
    resources_filter = models.CharField(max_length=128, default="mushafs:*")
    sync_token = models.TextField(blank=True)
    last_sync_sequence = models.PositiveBigIntegerField(null=True, blank=True)
    last_attempt_at = models.DateTimeField(null=True, blank=True)
    last_success_at = models.DateTimeField(null=True, blank=True, db_index=True)
    consecutive_failures = models.PositiveIntegerField(default=0)
    last_error_code = models.CharField(max_length=64, blank=True)

    class Meta:
        db_table = "quran_qf_mushaf_sync_state"
        ordering = ["environment", "resources_filter"]
        constraints = [
            models.UniqueConstraint(
                fields=["environment", "resources_filter"],
                name="quran_qf_mushaf_sync_filter_uq",
            ),
            models.CheckConstraint(
                condition=models.Q(environment__in=["prelive", "production"]),
                name="quran_qf_mushaf_sync_env_valid",
            ),
        ]

    def __str__(self) -> str:
        return f"QF {self.environment} {self.resources_filter}"


class QuranFoundationMushaf(BaseModel):
    """Locally cached metadata for one public Quran.Foundation Mushaf resource."""

    environment = models.CharField(max_length=16)
    source_id = models.PositiveIntegerField()
    resource_content_id = models.PositiveBigIntegerField(null=True, blank=True)
    name = models.CharField(max_length=255)
    description = models.TextField(blank=True)
    qirat_id = models.PositiveIntegerField(null=True, blank=True)
    qirat_name = models.CharField(max_length=128)
    pages_count = models.PositiveSmallIntegerField()
    lines_per_page = models.PositiveSmallIntegerField()
    default_font_name = models.CharField(max_length=128)
    mapping_mode = models.CharField(max_length=64)
    schema_version = models.CharField(max_length=32)
    sync_sequence = models.PositiveBigIntegerField()
    source_checksum_sha256 = models.CharField(max_length=64)
    is_available = models.BooleanField(default=True)
    last_synced_at = models.DateTimeField()

    class Meta:
        db_table = "quran_qf_mushaf"
        ordering = ["source_id"]
        constraints = [
            models.UniqueConstraint(
                fields=["environment", "source_id"],
                name="quran_qf_mushaf_source_uq",
            ),
            models.CheckConstraint(
                condition=models.Q(environment__in=["prelive", "production"]),
                name="quran_qf_mushaf_env_valid",
            ),
            models.CheckConstraint(
                condition=models.Q(pages_count__gt=0),
                name="quran_qf_mushaf_pages_positive",
            ),
            models.CheckConstraint(
                condition=models.Q(lines_per_page__gt=0),
                name="quran_qf_mushaf_lines_positive",
            ),
        ]
        indexes = [
            models.Index(
                fields=["environment", "is_available", "source_id"],
                name="quran_qf_mushaf_public_idx",
            )
        ]

    def __str__(self) -> str:
        return f"QF {self.environment} mushaf {self.source_id}: {self.name}"


class QuranFoundationMushafPage(BaseModel):
    """One page of positioned words from a Quran.Foundation Mushaf snapshot."""

    mushaf = models.ForeignKey(
        QuranFoundationMushaf,
        on_delete=models.CASCADE,
        related_name="cached_pages",
    )
    source_id = models.PositiveBigIntegerField()
    page_number = models.PositiveSmallIntegerField()
    verse_mapping = models.JSONField(default=dict)
    first_verse_id = models.PositiveBigIntegerField(null=True, blank=True)
    last_verse_id = models.PositiveBigIntegerField(null=True, blank=True)
    first_word_id = models.PositiveBigIntegerField(null=True, blank=True)
    last_word_id = models.PositiveBigIntegerField(null=True, blank=True)
    verses_count = models.PositiveSmallIntegerField()
    words = models.JSONField(default=list)

    class Meta:
        db_table = "quran_qf_mushaf_page"
        ordering = ["page_number"]
        constraints = [
            models.UniqueConstraint(
                fields=["mushaf", "page_number"],
                name="quran_qf_mushaf_page_number_uq",
            ),
            models.CheckConstraint(
                condition=models.Q(page_number__gt=0),
                name="quran_qf_mushaf_page_positive",
            ),
        ]
        indexes = [models.Index(fields=["mushaf", "page_number"], name="quran_qf_page_lookup_idx")]

    def __str__(self) -> str:
        return f"{self.mushaf}: page {self.page_number}"


class QuranFoundationNativePublicationStatus(models.TextChoices):
    PREPARING = "preparing", "Preparing"
    PUBLISHED = "published", "Published"
    WITHDRAWN = "withdrawn", "Withdrawn"
    FAILED = "failed", "Failed"


class QuranFoundationNativePublication(BaseModel):
    """Immutable native page rendition bound to one exact QF source snapshot."""

    mushaf = models.ForeignKey(
        QuranFoundationMushaf,
        on_delete=models.CASCADE,
        related_name="native_publications",
    )
    render_version = models.CharField(max_length=96)
    renderer_name = models.CharField(max_length=128)
    renderer_version = models.CharField(max_length=96)
    source_checksum_sha256 = models.CharField(max_length=64)
    manifest_checksum_sha256 = models.CharField(max_length=64, blank=True)
    expected_pages = models.PositiveSmallIntegerField()
    required_widths = models.JSONField(default=list)
    prepared_pages = models.PositiveSmallIntegerField(default=0)
    assets_count = models.PositiveIntegerField(default=0)
    status = models.CharField(
        max_length=16,
        choices=QuranFoundationNativePublicationStatus,
        default=QuranFoundationNativePublicationStatus.PREPARING,
    )
    is_active = models.BooleanField(default=False)
    published_at = models.DateTimeField(null=True, blank=True)
    last_error_code = models.CharField(max_length=64, blank=True)
    last_error_message = models.CharField(max_length=500, blank=True)

    class Meta:
        db_table = "quran_qf_native_publication"
        ordering = ["mushaf", "-published_at", "render_version"]
        constraints = [
            models.UniqueConstraint(
                fields=["mushaf", "render_version"],
                name="quran_qf_native_pub_version_uq",
            ),
            models.UniqueConstraint(
                fields=["mushaf"],
                condition=models.Q(is_active=True),
                name="quran_qf_native_one_active_uq",
            ),
            models.CheckConstraint(
                condition=models.Q(expected_pages__gt=0),
                name="quran_qf_native_expected_pages_positive",
            ),
            models.CheckConstraint(
                condition=models.Q(prepared_pages__lte=models.F("expected_pages")),
                name="quran_qf_native_prepared_pages_lte_expected",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(
                        status=QuranFoundationNativePublicationStatus.PUBLISHED,
                        published_at__isnull=False,
                    )
                    | ~models.Q(status=QuranFoundationNativePublicationStatus.PUBLISHED)
                ),
                name="quran_qf_native_published_at_required",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(
                        is_active=False,
                    )
                    | models.Q(status=QuranFoundationNativePublicationStatus.PUBLISHED)
                ),
                name="quran_qf_native_active_is_published",
            ),
        ]
        indexes = [
            models.Index(
                fields=["mushaf", "status", "is_active"],
                name="quran_qf_native_public_idx",
            )
        ]

    def __str__(self) -> str:
        return f"{self.mushaf} native {self.render_version}"

    def clean(self) -> None:
        super().clean()
        if self.mushaf.source_id not in {1, 5, 19}:
            raise ValidationError("Only Quran.Foundation resources 1, 5 and 19 are renderable.")
        if not isinstance(self.required_widths, list) or not self.required_widths:
            raise ValidationError({"required_widths": "At least one output width is required."})
        widths = self.required_widths
        if any(
            isinstance(width, bool) or not isinstance(width, int) or width <= 0 for width in widths
        ) or widths != sorted(set(widths)):
            raise ValidationError(
                {"required_widths": "Widths must be sorted unique positive integers."}
            )
        if not _is_sha256(self.source_checksum_sha256):
            raise ValidationError({"source_checksum_sha256": "A lowercase SHA-256 is required."})
        if self.manifest_checksum_sha256 and not _is_sha256(self.manifest_checksum_sha256):
            raise ValidationError({"manifest_checksum_sha256": "A lowercase SHA-256 is required."})
        if self.status == QuranFoundationNativePublicationStatus.PUBLISHED and (
            not self.manifest_checksum_sha256
            or self.prepared_pages != self.expected_pages
            or self.assets_count != self.expected_pages * len(widths)
        ):
            raise ValidationError("Published native renditions require complete verified coverage.")


class QuranFoundationNativePageAsset(BaseModel):
    """One create-only page rendition stored under a checksum-versioned object key."""

    publication = models.ForeignKey(
        QuranFoundationNativePublication,
        on_delete=models.CASCADE,
        related_name="page_assets",
    )
    page_number = models.PositiveSmallIntegerField()
    width = models.PositiveIntegerField()
    height = models.PositiveIntegerField()
    content_type = models.CharField(max_length=64, default="image/webp")
    storage_key = models.CharField(max_length=500, unique=True)
    checksum_sha256 = models.CharField(max_length=64)
    size_bytes = models.PositiveBigIntegerField()

    class Meta:
        db_table = "quran_qf_native_page_asset"
        ordering = ["publication", "page_number", "width"]
        constraints = [
            models.UniqueConstraint(
                fields=["publication", "page_number", "width"],
                name="quran_qf_native_asset_page_width_uq",
            ),
            models.CheckConstraint(
                condition=models.Q(page_number__gt=0),
                name="quran_qf_native_asset_page_positive",
            ),
            models.CheckConstraint(
                condition=models.Q(width__gt=0, height__gt=0, size_bytes__gt=0),
                name="quran_qf_native_asset_dimensions_positive",
            ),
        ]
        indexes = [
            models.Index(
                fields=["publication", "page_number"],
                name="quran_qf_native_asset_page_idx",
            )
        ]

    def __str__(self) -> str:
        return f"{self.publication}: page {self.page_number} @ {self.width}px"

    def clean(self) -> None:
        super().clean()
        path = self.storage_key.split("/")
        if (
            self.storage_key.startswith("/")
            or "\\" in self.storage_key
            or "" in path
            or ".." in path
            or self.content_type != "image/webp"
        ):
            raise ValidationError("Native assets require a safe relative WebP storage key.")
        if self.page_number > self.publication.expected_pages:
            raise ValidationError("Native asset page exceeds the publication page count.")
        if self.width not in self.publication.required_widths:
            raise ValidationError("Native asset width is not declared by the publication.")
        if not _is_sha256(self.checksum_sha256):
            raise ValidationError({"checksum_sha256": "A lowercase SHA-256 is required."})


def _is_sha256(value: str) -> bool:
    return len(value) == 64 and set(value) <= set("0123456789abcdef")


class MushafRendition(BaseModel):
    """Visual presentation only: never replaces canonical Quran/audio identities."""

    code = models.SlugField("Код оформления", max_length=64, unique=True)
    names = models.JSONField("Названия на языках приложения", default=dict)
    active_release = models.ForeignKey(
        "MushafRenditionRelease",
        verbose_name="Доступная версия страниц",
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="active_for",
    )

    class Meta:
        db_table = "quran_mushaf_rendition"
        verbose_name = "оформление Мусхафа"
        verbose_name_plural = "Оформления Мусхафа"

    def __str__(self) -> str:
        return str(self.names.get("ru") or self.code)


class MushafRenditionRelease(BaseModel):
    rendition = models.ForeignKey(
        MushafRendition, on_delete=models.PROTECT, related_name="releases"
    )
    version = models.CharField("Версия набора", max_length=64)
    canonical_version = models.ForeignKey(
        QuranEditionVersion,
        verbose_name="Канонические аяты (не изменяются)",
        on_delete=models.PROTECT,
    )
    checksum_sha256 = models.CharField("SHA-256 полного набора", max_length=64)
    source_commit = models.CharField("Commit источника", max_length=40)
    source_url = models.URLField("Источник страниц")
    renderer = models.CharField("Версия раскладки", max_length=64)
    widths = models.JSONField("Разрешения страниц", default=list)
    page_count = models.PositiveSmallIntegerField("Количество страниц", default=604)
    staging_only = models.BooleanField("Только тестовый сервер", default=True)
    published_at = models.DateTimeField("Подключено", null=True, blank=True)

    class Meta:
        db_table = "quran_mushaf_rendition_release"
        verbose_name = "версия оформления Мусхафа"
        verbose_name_plural = "Версии оформления Мусхафа"
        constraints = [
            models.UniqueConstraint(
                fields=["rendition", "version"],
                name="quran_rendition_version_unique",
            )
        ]

    def __str__(self) -> str:
        return f"{self.rendition.code}@{self.version}"


class MushafRenditionPage(BaseModel):
    release = models.ForeignKey(
        MushafRenditionRelease, on_delete=models.PROTECT, related_name="pages"
    )
    number = models.PositiveSmallIntegerField("Номер страницы")
    image_width = models.PositiveIntegerField("Ширина исходной раскладки")
    image_height = models.PositiveIntegerField("Высота исходной раскладки")
    checksum_sha256 = models.CharField("SHA-256 карты страницы", max_length=64)
    assets = models.JSONField("Проверенные изображения", default=list)
    regions = models.JSONField("Области аятов", default=list)

    class Meta:
        db_table = "quran_mushaf_rendition_page"
        verbose_name = "страница оформления Мусхафа"
        verbose_name_plural = "Страницы оформления Мусхафа"
        ordering = ["number"]
        constraints = [
            models.UniqueConstraint(
                fields=["release", "number"], name="quran_rendition_page_unique"
            ),
            models.CheckConstraint(
                condition=models.Q(number__gte=1, number__lte=604),
                name="quran_rendition_page_range",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.release}: {self.number}"
