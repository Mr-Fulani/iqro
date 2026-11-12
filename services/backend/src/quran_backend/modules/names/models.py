# Russian interface strings intentionally contain Cyrillic letters.
# ruff: noqa: RUF001
"""The Names of Allah: a list of names taken from a book, versioned like the prayer course.

A version is a set of rows (one per name) the owner edits in the admin while it
is an unsigned draft. He signs it off and publishes it; published versions never
change, a correction is a new version (docs/names-of-allah/README.md).
"""

from __future__ import annotations

from typing import Any

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.utils import timezone

from quran_backend.modules.core.models import BaseModel

# Every language of the project: a card is written in each of them.
NAMES_LANGUAGES = tuple(code for code, _name in settings.LANGUAGES)
# The Arabic interface shows the name itself, so it has no transliteration.
TRANSLITERATION_LANGUAGES = tuple(code for code in NAMES_LANGUAGES if code != "ar")


class NamesStatus(models.TextChoices):
    DRAFT = "draft", "Черновик"
    PUBLISHED = "published", "Опубликована"
    WITHDRAWN = "withdrawn", "Отозвана"


class NamesCollection(BaseModel):
    slug = models.SlugField(max_length=64, unique=True)
    active_version = models.ForeignKey(
        "NamesVersion",
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="+",
    )

    class Meta:
        db_table = "names_collection"
        ordering = ["slug"]

    def __str__(self) -> str:
        return self.slug

    def clean(self) -> None:
        super().clean()
        version = self.active_version if self.active_version_id else None
        if version and version.collection_id != self.id:
            raise ValidationError({"active_version": "Версия принадлежит другому списку."})
        if version and version.status != NamesStatus.PUBLISHED:
            raise ValidationError(
                {"active_version": "Активной может быть только опубликованная версия."}
            )


class NamesVersion(BaseModel):
    collection = models.ForeignKey(
        NamesCollection, on_delete=models.PROTECT, related_name="versions"
    )
    version = models.CharField(max_length=64)
    status = models.CharField(
        max_length=16, choices=NamesStatus, default=NamesStatus.DRAFT, db_index=True
    )
    # The book the list and its order come from, as the card names it.
    list_source_ru = models.CharField(max_length=300, blank=True)
    list_source_en = models.CharField(max_length=300, blank=True)
    list_source_tr = models.CharField(max_length=300, blank=True)
    list_source_ar = models.CharField(max_length=300, blank=True)
    # The book the explanations come from.
    tafsir_source_ru = models.CharField(max_length=300, blank=True)
    tafsir_source_en = models.CharField(max_length=300, blank=True)
    tafsir_source_tr = models.CharField(max_length=300, blank=True)
    tafsir_source_ar = models.CharField(max_length=300, blank=True)
    published_at = models.DateTimeField(null=True, blank=True)
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="+",
    )
    reviewed_at = models.DateTimeField(null=True, blank=True)
    review_note = models.TextField(blank=True)

    class Meta:
        db_table = "names_version"
        ordering = ["collection", "-created_at"]
        constraints = [
            models.UniqueConstraint(fields=["collection", "version"], name="names_version_unique"),
            models.CheckConstraint(
                condition=~models.Q(status=NamesStatus.PUBLISHED)
                | (models.Q(published_at__isnull=False) & models.Q(reviewed_by__isnull=False)),
                name="names_published_is_signed",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.collection.slug}@{self.version}"

    @property
    def is_signed(self) -> bool:
        return self.reviewed_by_id is not None and self.reviewed_at is not None

    @property
    def is_editable(self) -> bool:
        """Names and sources change only in a draft nobody has signed yet."""
        return self.status == NamesStatus.DRAFT and not self.is_signed

    def sign(self, user: Any, note: str = "") -> None:
        """Records the owner's religious sign-off; only drafts can be signed."""
        if self.status != NamesStatus.DRAFT:
            raise ValidationError("Подписать можно только черновик.")
        self.reviewed_by = user
        self.reviewed_at = timezone.now()
        self.review_note = note
        self.save(update_fields=["reviewed_by", "reviewed_at", "review_note", "updated_at"])


class DivineName(BaseModel):
    """One name in one version: its card in every language."""

    version = models.ForeignKey(NamesVersion, on_delete=models.CASCADE, related_name="names")
    position = models.PositiveSmallIntegerField(validators=[MinValueValidator(1)])
    # Stays the same from version to version: the learner's marks are kept by it.
    slug = models.SlugField(
        max_length=64,
        help_text="Латиницей, например ar-rahman. По коду хранятся отметки «пройдено» и "
        "«выучено», поэтому у имени он не меняется от версии к версии.",
    )
    arabic = models.CharField(max_length=120)
    transliteration_ru = models.CharField(max_length=120, blank=True)
    transliteration_en = models.CharField(max_length=120, blank=True)
    transliteration_tr = models.CharField(max_length=120, blank=True)
    meaning_ru = models.CharField(max_length=200, blank=True)
    meaning_en = models.CharField(max_length=200, blank=True)
    meaning_tr = models.CharField(max_length=200, blank=True)
    meaning_ar = models.CharField(max_length=200, blank=True)
    tafsir_ru = models.TextField(blank=True)
    tafsir_en = models.TextField(blank=True)
    tafsir_tr = models.TextField(blank=True)
    tafsir_ar = models.TextField(blank=True)
    # Filled in only where the explanation comes from another book than the version's.
    tafsir_source_ru = models.CharField(max_length=300, blank=True)
    tafsir_source_en = models.CharField(max_length=300, blank=True)
    tafsir_source_tr = models.CharField(max_length=300, blank=True)
    tafsir_source_ar = models.CharField(max_length=300, blank=True)
    tafsir_ref = models.CharField(
        max_length=120,
        blank=True,
        help_text="Необязательно: страница или аят, откуда взято толкование. "
        "Показывается после названия книги.",
    )
    # The ayah the card links to.
    surah = models.PositiveSmallIntegerField(
        null=True, blank=True, validators=[MinValueValidator(1), MaxValueValidator(114)]
    )
    ayah = models.PositiveSmallIntegerField(
        null=True, blank=True, validators=[MinValueValidator(1), MaxValueValidator(286)]
    )
    # «Слушать»: the reciter's recording of this word of the ayah. Empty when the
    # name is not one word of the Quran: the card then has no «Слушать».
    word_position = models.PositiveSmallIntegerField(
        null=True,
        blank=True,
        validators=[MinValueValidator(1)],
        help_text="Слово аята, которое звучит по кнопке «Слушать». Пусто — кнопки нет.",
    )

    class Meta:
        db_table = "names_name"
        ordering = ["version", "position"]
        constraints = [
            models.UniqueConstraint(fields=["version", "slug"], name="names_name_slug_unique"),
            models.UniqueConstraint(
                fields=["version", "position"], name="names_name_position_unique"
            ),
        ]

    def __str__(self) -> str:
        return f"{self.position}. {self.arabic}"

    def clean(self) -> None:
        super().clean()
        if (self.surah is None) != (self.ayah is None):
            raise ValidationError({"ayah": "Укажите и суру, и аят — или ни того, ни другого."})
        if self.word_position is not None and self.surah is None:
            raise ValidationError({"word_position": "Слово указывают вместе с сурой и аятом."})


class NamesDocument(BaseModel):
    """The ready-to-serve list for one language."""

    version = models.ForeignKey(NamesVersion, on_delete=models.CASCADE, related_name="documents")
    language = models.CharField(max_length=8)
    payload = models.JSONField()
    checksum_sha256 = models.CharField(max_length=64)
    bytes = models.PositiveIntegerField()

    class Meta:
        db_table = "names_document"
        ordering = ["version", "language"]
        constraints = [
            models.UniqueConstraint(fields=["version", "language"], name="names_document_unique"),
        ]

    def __str__(self) -> str:
        return f"{self.version}:{self.language}"
