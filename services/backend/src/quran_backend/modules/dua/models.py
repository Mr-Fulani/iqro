from __future__ import annotations

from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone

from quran_backend.modules.core.models import BaseModel


class DuaPublicationStatus(models.TextChoices):
    DRAFT = "draft", "Draft"
    PUBLISHED = "published", "Published"
    WITHDRAWN = "withdrawn", "Withdrawn"


class DuaEvidenceKind(models.TextChoices):
    HADITH = "hadith", "Hadith"
    QURAN = "quran", "Quran"
    SOURCE_NOTE = "source_note", "Source note"


class DuaEvidenceVerification(models.TextChoices):
    SOURCE_ONLY = "source_only", "Copied from source edition"
    EDITORIALLY_VERIFIED = "editorially_verified", "Editorially verified"


class DuaCollection(BaseModel):
    slug = models.SlugField(max_length=100, unique=True)
    active_version = models.ForeignKey(
        "DuaCollectionVersion",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="active_for_collections",
    )

    class Meta:
        db_table = "dua_collection"
        ordering = ("slug",)

    def __str__(self) -> str:
        return self.slug

    def clean(self) -> None:
        super().clean()
        active_version = self.active_version if self.active_version_id else None
        if active_version and active_version.collection_id != self.id:
            raise ValidationError("The active version must belong to this Dua collection.")
        if active_version and active_version.status != DuaPublicationStatus.PUBLISHED:
            raise ValidationError("Only a published Dua collection version can be active.")


class DuaCollectionVersion(BaseModel):
    collection = models.ForeignKey(
        DuaCollection,
        on_delete=models.PROTECT,
        related_name="versions",
    )
    version = models.CharField(max_length=64)
    schema_version = models.PositiveSmallIntegerField(default=1)
    checksum_sha256 = models.CharField(max_length=64)
    status = models.CharField(
        max_length=16,
        choices=DuaPublicationStatus,
        default=DuaPublicationStatus.DRAFT,
    )
    category_count = models.PositiveIntegerField(default=0)
    entry_count = models.PositiveIntegerField(default=0)
    published_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "dua_collection_version"
        ordering = ("collection", "-created_at")
        constraints = [
            models.UniqueConstraint(
                fields=("collection", "version"),
                name="dua_collection_version_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(schema_version__gt=0),
                name="dua_version_schema_positive",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(
                        status=DuaPublicationStatus.PUBLISHED,
                        published_at__isnull=False,
                    )
                    | ~models.Q(status=DuaPublicationStatus.PUBLISHED)
                ),
                name="dua_published_version_timestamp",
            ),
        ]
        indexes = [
            models.Index(fields=("status", "collection"), name="dua_version_status_idx"),
        ]

    def __str__(self) -> str:
        return f"{self.collection.slug}@{self.version}"

    def publish(self) -> None:
        self.status = DuaPublicationStatus.PUBLISHED
        self.published_at = timezone.now()


class DuaSourceEdition(BaseModel):
    collection_version = models.ForeignKey(
        DuaCollectionVersion,
        on_delete=models.PROTECT,
        related_name="source_editions",
    )
    language_code = models.CharField(max_length=8)
    provider = models.CharField(max_length=64)
    source_item_id = models.CharField(max_length=64)
    title = models.CharField(max_length=255)
    author = models.CharField(max_length=255)
    translator = models.CharField(max_length=255, blank=True)
    reviewer = models.CharField(max_length=255, blank=True)
    source_url = models.URLField(max_length=500)
    rights_url = models.URLField(max_length=500)
    source_version = models.CharField(max_length=64)

    class Meta:
        db_table = "dua_source_edition"
        ordering = ("language_code",)
        constraints = [
            models.UniqueConstraint(
                fields=("collection_version", "language_code"),
                name="dua_source_edition_language_unique",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.collection_version}:{self.language_code}"


class DuaCategory(BaseModel):
    collection_version = models.ForeignKey(
        DuaCollectionVersion,
        on_delete=models.PROTECT,
        related_name="categories",
    )
    source_number = models.PositiveSmallIntegerField()
    slug = models.SlugField(max_length=120)
    sort_order = models.PositiveSmallIntegerField()

    class Meta:
        db_table = "dua_category"
        ordering = ("sort_order", "source_number")
        constraints = [
            models.UniqueConstraint(
                fields=("collection_version", "source_number"),
                name="dua_category_source_number_unique",
            ),
            models.UniqueConstraint(
                fields=("collection_version", "slug"),
                name="dua_category_slug_unique",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.collection_version}:{self.source_number}"


class DuaCategoryTranslation(BaseModel):
    category = models.ForeignKey(
        DuaCategory,
        on_delete=models.CASCADE,
        related_name="translations",
    )
    language_code = models.CharField(max_length=8)
    title = models.CharField(max_length=255)

    class Meta:
        db_table = "dua_category_translation"
        ordering = ("language_code",)
        constraints = [
            models.UniqueConstraint(
                fields=("category", "language_code"),
                name="dua_category_translation_unique",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.category}:{self.language_code}"


class DuaEntry(BaseModel):
    collection_version = models.ForeignKey(
        DuaCollectionVersion,
        on_delete=models.PROTECT,
        related_name="entries",
    )
    category = models.ForeignKey(
        DuaCategory,
        on_delete=models.PROTECT,
        related_name="entries",
    )
    source_number = models.PositiveSmallIntegerField()
    slug = models.SlugField(max_length=120)
    arabic_text = models.TextField()
    repetitions = models.PositiveSmallIntegerField(default=1)
    repetition_label = models.CharField(max_length=32, blank=True)
    sort_order = models.PositiveSmallIntegerField()

    class Meta:
        db_table = "dua_entry"
        ordering = ("sort_order", "source_number")
        constraints = [
            models.UniqueConstraint(
                fields=("collection_version", "source_number"),
                name="dua_entry_source_number_unique",
            ),
            models.UniqueConstraint(
                fields=("collection_version", "slug"),
                name="dua_entry_slug_unique",
            ),
            models.CheckConstraint(
                condition=models.Q(repetitions__gt=0),
                name="dua_entry_repetitions_positive",
            ),
        ]
        indexes = [
            models.Index(
                fields=("collection_version", "category", "sort_order"),
                name="dua_entry_catalog_idx",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.collection_version}:{self.source_number}"

    def clean(self) -> None:
        super().clean()
        if (
            self.category_id
            and self.collection_version_id
            and self.category.collection_version_id != self.collection_version_id
        ):
            raise ValidationError("The entry and category must belong to the same version.")


class DuaEntryTranslation(BaseModel):
    entry = models.ForeignKey(
        DuaEntry,
        on_delete=models.CASCADE,
        related_name="translations",
    )
    language_code = models.CharField(max_length=8)
    meaning_text = models.TextField()
    transliteration = models.TextField(blank=True)

    class Meta:
        db_table = "dua_entry_translation"
        ordering = ("language_code",)
        constraints = [
            models.UniqueConstraint(
                fields=("entry", "language_code"),
                name="dua_entry_translation_unique",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.entry}:{self.language_code}"


class DuaEvidence(BaseModel):
    entry = models.ForeignKey(
        DuaEntry,
        on_delete=models.CASCADE,
        related_name="evidence",
    )
    kind = models.CharField(max_length=16, choices=DuaEvidenceKind)
    provider = models.CharField(max_length=64)
    source_name = models.CharField(max_length=255)
    source_reference = models.CharField(max_length=500)
    source_url = models.URLField(max_length=500, blank=True)
    grade = models.CharField(max_length=255, blank=True)
    external_id = models.CharField(max_length=64, blank=True)
    verification_status = models.CharField(
        max_length=32,
        choices=DuaEvidenceVerification,
        default=DuaEvidenceVerification.SOURCE_ONLY,
    )
    sort_order = models.PositiveSmallIntegerField(default=1)

    class Meta:
        db_table = "dua_evidence"
        ordering = ("sort_order", "created_at")
        constraints = [
            models.UniqueConstraint(
                fields=("entry", "sort_order"),
                name="dua_evidence_entry_order_unique",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.entry}:{self.source_reference}"
