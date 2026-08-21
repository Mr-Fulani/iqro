from __future__ import annotations

from typing import Any, ClassVar

from django.core.exceptions import ValidationError
from django.db import models, transaction
from django.utils import timezone

from quran_backend.modules.audio.validators import (
    validate_relative_object_key,
    validate_sha256,
    validate_version_identifier,
)
from quran_backend.modules.core.models import BaseModel
from quran_backend.modules.quran.models import Ayah, PublicationStatus, QuranEditionVersion


class RecitationPublicationStatus(models.TextChoices):
    DRAFT = "draft", "Draft"
    PUBLISHED = "published", "Published"
    WITHDRAWN = "withdrawn", "Withdrawn"


class RecitationStyle(models.TextChoices):
    MURATTAL = "murattal", "Murattal"
    MUJAWWAD = "mujawwad", "Mujawwad"
    MUALLIM = "muallim", "Muallim"


class AudioTrackScope(models.TextChoices):
    SURAH = "surah", "Surah"
    JUZ = "juz", "Juz"
    FULL = "full", "Full Quran"


class AudioCodec(models.TextChoices):
    MP3 = "mp3", "MP3"
    AAC = "aac", "AAC"
    OPUS = "opus", "Opus"
    FLAC = "flac", "FLAC"


class AudioContentType(models.TextChoices):
    MPEG = "audio/mpeg", "audio/mpeg"
    AAC = "audio/aac", "audio/aac"
    OGG = "audio/ogg", "audio/ogg"
    FLAC = "audio/flac", "audio/flac"


CODEC_CONTENT_TYPES: dict[str, str] = {
    AudioCodec.MP3: AudioContentType.MPEG,
    AudioCodec.AAC: AudioContentType.AAC,
    AudioCodec.OPUS: AudioContentType.OGG,
    AudioCodec.FLAC: AudioContentType.FLAC,
}


class Reciter(BaseModel):
    code = models.SlugField(max_length=64, unique=True)
    name_ar = models.CharField(max_length=255)
    name_en = models.CharField(max_length=255)
    name_ru = models.CharField(max_length=255)
    biography_ar = models.TextField(blank=True)
    biography_en = models.TextField(blank=True)
    biography_ru = models.TextField(blank=True)
    country_code = models.CharField(max_length=2, blank=True)
    portrait_object_key = models.CharField(
        max_length=512,
        blank=True,
        validators=[validate_relative_object_key],
    )
    is_active = models.BooleanField(default=True)

    class Meta:
        db_table = "audio_reciter"
        ordering = ["name_en", "code"]
        indexes = [
            models.Index(fields=["is_active", "name_en"], name="audio_reciter_active_idx"),
        ]

    def __str__(self) -> str:
        return self.name_en

    def clean(self) -> None:
        super().clean()
        if self.country_code:
            if (
                len(self.country_code) != 2
                or not self.country_code.isascii()
                or not self.country_code.isalpha()
            ):
                raise ValidationError({"country_code": "Use a two-letter ISO 3166-1 country code."})
            self.country_code = self.country_code.upper()

    def save(self, *args: Any, **kwargs: Any) -> None:
        with transaction.atomic():
            if not self._state.adding:
                type(self).objects.select_for_update().filter(pk=self.pk).exists()
            self.full_clean()
            super().save(*args, **kwargs)


class RecitationEdition(BaseModel):
    """A versioned recitation package; published content is append-only."""

    code = models.SlugField(max_length=64)
    version = models.CharField(max_length=64, validators=[validate_version_identifier])
    style = models.CharField(
        max_length=16,
        choices=RecitationStyle,
        default=RecitationStyle.MURATTAL,
    )
    reciter = models.ForeignKey(Reciter, on_delete=models.PROTECT, related_name="recitations")
    quran_edition_version = models.ForeignKey(
        QuranEditionVersion,
        on_delete=models.PROTECT,
        related_name="recitations",
    )
    status = models.CharField(
        max_length=16,
        choices=RecitationPublicationStatus,
        default=RecitationPublicationStatus.DRAFT,
    )
    published_at = models.DateTimeField(null=True, blank=True)
    source_name = models.CharField(max_length=255)
    source_url = models.URLField(blank=True)
    source_version = models.CharField(max_length=128)
    source_checksum_sha256 = models.CharField(max_length=64, validators=[validate_sha256])
    rights_holder = models.CharField(max_length=255)
    license_name = models.CharField(max_length=255)
    license_url = models.URLField(blank=True)
    license_spdx_id = models.CharField(max_length=64, blank=True)
    license_attribution = models.TextField(blank=True)
    stream_allowed = models.BooleanField(null=True, blank=True)
    offline_download_allowed = models.BooleanField(null=True, blank=True)

    immutable_fields: ClassVar[tuple[str, ...]] = (
        "code",
        "version",
        "style",
        "reciter_id",
        "quran_edition_version_id",
        "published_at",
        "source_name",
        "source_url",
        "source_version",
        "source_checksum_sha256",
        "rights_holder",
        "license_name",
        "license_url",
        "license_spdx_id",
        "license_attribution",
        "stream_allowed",
        "offline_download_allowed",
    )

    class Meta:
        db_table = "audio_recitation_edition"
        ordering = ["code", "-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["code", "version"],
                name="audio_recitation_code_ver_uq",
            ),
            models.UniqueConstraint(
                fields=["reciter", "quran_edition_version", "style", "version"],
                name="audio_recitation_identity_uq",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(
                        status=RecitationPublicationStatus.DRAFT,
                        published_at__isnull=True,
                    )
                    | models.Q(
                        status__in=[
                            RecitationPublicationStatus.PUBLISHED,
                            RecitationPublicationStatus.WITHDRAWN,
                        ],
                        published_at__isnull=False,
                        stream_allowed__isnull=False,
                        offline_download_allowed__isnull=False,
                    )
                ),
                name="audio_recitation_publication_ts",
            ),
        ]
        indexes = [
            models.Index(
                fields=["status", "quran_edition_version", "reciter"],
                name="audio_recitation_public_idx",
            ),
            models.Index(
                fields=["reciter", "status"],
                name="audio_recitation_reciter_idx",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.code}@{self.version}"

    def clean(self) -> None:
        super().clean()
        if self.status == RecitationPublicationStatus.DRAFT and self.published_at is not None:
            raise ValidationError({"published_at": "Draft recitations cannot be published."})
        if self.status != RecitationPublicationStatus.DRAFT and self.published_at is None:
            raise ValidationError({"published_at": "Published content requires a timestamp."})
        if self.status != RecitationPublicationStatus.DRAFT:
            required_rights = {
                "stream_allowed": self.stream_allowed,
                "offline_download_allowed": self.offline_download_allowed,
            }
            missing_rights = [field for field, value in required_rights.items() if value is None]
            if missing_rights:
                raise ValidationError(
                    dict.fromkeys(
                        missing_rights,
                        "An explicit licensing decision is required before publication.",
                    )
                )
        self._validate_quran_version_for_publication()
        self._validate_publishable_children()
        self._validate_state_transition_and_immutability()

    def _validate_publishable_children(self) -> None:
        if self.status != RecitationPublicationStatus.PUBLISHED:
            return
        if self._state.adding or self.pk is None:
            raise ValidationError(
                {
                    "status": (
                        "Create the recitation as a draft and attach its tracks before publishing."
                    )
                }
            )

        tracks = AudioTrack.objects.filter(recitation_edition_id=self.pk)
        if not tracks.filter(scope=AudioTrackScope.SURAH).exists():
            raise ValidationError(
                {"status": "At least one surah audio track is required for publication."}
            )
        if self.offline_download_allowed and tracks.exclude(external_url="").exists():
            raise ValidationError(
                {
                    "offline_download_allowed": (
                        "External provider tracks cannot be offered for offline download."
                    )
                }
            )

        invalid_timing = tracks.filter(segments__isnull=False).filter(
            models.Q(timing_version__isnull=True)
            | models.Q(timing_version__verified_at__isnull=True)
            | ~models.Q(timing_version__recitation_edition_id=self.pk)
        )
        if invalid_timing.exists():
            raise ValidationError(
                {
                    "status": (
                        "Every timed track requires verified timing provenance for this recitation."
                    )
                }
            )

        invalid_segments = AyahAudioSegment.objects.filter(
            track__recitation_edition_id=self.pk
        ).filter(
            models.Q(end_ms__gt=models.F("track__duration_ms"))
            | ~models.Q(ayah__surah__edition_version_id=self.quran_edition_version_id)
            | (
                models.Q(track__scope=AudioTrackScope.SURAH)
                & ~models.Q(ayah__surah__number=models.F("track__surah_number"))
            )
            | (
                models.Q(track__scope=AudioTrackScope.JUZ)
                & ~models.Q(ayah__juz_number=models.F("track__juz_number"))
            )
        )
        if invalid_segments.exists() or self._has_overlapping_segments():
            raise ValidationError(
                {"status": "Audio segments must match the Quran version and form valid timelines."}
            )

    def _has_overlapping_segments(self) -> bool:
        previous_track_id: Any = None
        previous_end = 0
        timeline = (
            AyahAudioSegment.objects.filter(track__recitation_edition_id=self.pk)
            .order_by("track_id", "start_ms", "end_ms", "id")
            .values_list("track_id", "start_ms", "end_ms")
        )
        for track_id, start_ms, end_ms in timeline.iterator(chunk_size=2000):
            if track_id == previous_track_id and start_ms < previous_end:
                return True
            previous_track_id = track_id
            previous_end = end_ms
        return False

    def _validate_quran_version_for_publication(self) -> None:
        if self.status != RecitationPublicationStatus.PUBLISHED:
            return
        version_id = self.__dict__.get("quran_edition_version_id")
        if version_id is None:
            return
        quran_version = (
            QuranEditionVersion.objects.select_related("edition").filter(pk=version_id).first()
        )
        if quran_version is None:
            return
        if quran_version.status != PublicationStatus.PUBLISHED:
            raise ValidationError(
                {"quran_edition_version": "The Quran edition version must be published first."}
            )
        if quran_version.edition.active_version_id != quran_version.id:
            raise ValidationError(
                {
                    "quran_edition_version": (
                        "The Quran edition version must be active when the recitation is published."
                    )
                }
            )

    def _validate_state_transition_and_immutability(self) -> None:
        if self._state.adding:
            return
        persisted = (
            type(self).objects.filter(pk=self.pk).values("status", *self.immutable_fields).first()
        )
        if persisted is None:
            return

        previous_status = RecitationPublicationStatus(str(persisted["status"]))
        current_status = RecitationPublicationStatus(self.status)
        allowed_transitions = {
            RecitationPublicationStatus.DRAFT: {
                RecitationPublicationStatus.DRAFT,
                RecitationPublicationStatus.PUBLISHED,
            },
            RecitationPublicationStatus.PUBLISHED: {
                RecitationPublicationStatus.PUBLISHED,
                RecitationPublicationStatus.WITHDRAWN,
            },
            RecitationPublicationStatus.WITHDRAWN: {
                RecitationPublicationStatus.WITHDRAWN,
            },
        }
        if current_status not in allowed_transitions[previous_status]:
            raise ValidationError({"status": "This publication status transition is not allowed."})

        if previous_status == RecitationPublicationStatus.DRAFT:
            return
        changed = [
            field for field in self.immutable_fields if persisted[field] != getattr(self, field)
        ]
        if changed:
            raise ValidationError(
                dict.fromkeys(
                    changed,
                    "Published recitation metadata is immutable; create a new version.",
                )
            )

    def publish(self) -> None:
        if self.status != RecitationPublicationStatus.DRAFT:
            raise ValidationError({"status": "Only a draft recitation can be published."})
        self.status = RecitationPublicationStatus.PUBLISHED
        self.published_at = timezone.now()

    def withdraw(self) -> None:
        if self.status != RecitationPublicationStatus.PUBLISHED:
            raise ValidationError({"status": "Only a published recitation can be withdrawn."})
        self.status = RecitationPublicationStatus.WITHDRAWN

    def save(self, *args: Any, **kwargs: Any) -> None:
        self.full_clean()
        super().save(*args, **kwargs)

    def delete(self, *args: Any, **kwargs: Any) -> tuple[int, dict[str, int]]:
        with transaction.atomic():
            persisted_status = (
                type(self)
                .objects.select_for_update()
                .filter(pk=self.pk)
                .values_list("status", flat=True)
                .first()
            )
            if (
                self.status != RecitationPublicationStatus.DRAFT
                or persisted_status != RecitationPublicationStatus.DRAFT
            ):
                raise ValidationError(
                    "Published or withdrawn recitation editions cannot be deleted."
                )
            return super().delete(*args, **kwargs)


def _lock_recitation_rows(recitation_ids: set[Any]) -> None:
    if not recitation_ids:
        return
    list(
        RecitationEdition.objects.select_for_update()
        .filter(pk__in=recitation_ids)
        .order_by("pk")
        .values_list("pk", flat=True)
    )


class AudioTimingVersion(BaseModel):
    """Versioned provenance for ayah timing data within a recitation package."""

    recitation_edition = models.ForeignKey(
        RecitationEdition,
        on_delete=models.CASCADE,
        related_name="timing_versions",
    )
    version = models.CharField(max_length=64, validators=[validate_version_identifier])
    source_name = models.CharField(max_length=255)
    source_version = models.CharField(max_length=128)
    source_checksum_sha256 = models.CharField(max_length=64, validators=[validate_sha256])
    verified_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "audio_timing_version"
        ordering = ["recitation_edition", "-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["recitation_edition", "version"],
                name="audio_timing_recitation_ver_uq",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.recitation_edition}:timing@{self.version}"

    def clean(self) -> None:
        super().clean()
        self._assert_parent_is_mutable()
        self._validate_used_timing_immutability()

    def _validate_used_timing_immutability(self) -> None:
        if self._state.adding:
            return
        persisted = (
            type(self)
            .objects.filter(pk=self.pk)
            .values(
                "recitation_edition_id",
                "version",
                "source_name",
                "source_version",
                "source_checksum_sha256",
                "verified_at",
            )
            .first()
        )
        if persisted is None:
            return
        persisted_values: dict[str, Any] = dict(persisted)
        if (
            persisted_values["recitation_edition_id"] != self.recitation_edition_id
            and self.tracks.exists()
        ):
            raise ValidationError(
                {"recitation_edition": "A timing version used by tracks cannot be reassigned."}
            )
        if not self.tracks.filter(segments__isnull=False).exists():
            return
        provenance_fields = (
            "version",
            "source_name",
            "source_version",
            "source_checksum_sha256",
            "verified_at",
        )
        changed = [
            field for field in provenance_fields if persisted_values[field] != getattr(self, field)
        ]
        if changed:
            raise ValidationError(
                dict.fromkeys(
                    changed,
                    "Timing provenance used by ayah segments is immutable.",
                )
            )

    def _assert_parent_is_mutable(self) -> None:
        recitation_id = self.__dict__.get("recitation_edition_id")
        if recitation_id is None:
            return
        current_status = (
            RecitationEdition.objects.filter(pk=recitation_id)
            .values_list("status", flat=True)
            .first()
        )
        persisted_status = None
        if not self._state.adding:
            persisted_status = (
                type(self)
                .objects.filter(pk=self.pk)
                .values_list("recitation_edition__status", flat=True)
                .first()
            )
        if current_status in {
            RecitationPublicationStatus.PUBLISHED,
            RecitationPublicationStatus.WITHDRAWN,
        } or persisted_status in {
            RecitationPublicationStatus.PUBLISHED,
            RecitationPublicationStatus.WITHDRAWN,
        }:
            raise ValidationError("Timing versions in a published recitation are immutable.")

    def save(self, *args: Any, **kwargs: Any) -> None:
        with transaction.atomic():
            _lock_recitation_rows(self._related_recitation_ids())
            self._assert_parent_is_mutable()
            self.full_clean()
            super().save(*args, **kwargs)

    def delete(self, *args: Any, **kwargs: Any) -> tuple[int, dict[str, int]]:
        with transaction.atomic():
            _lock_recitation_rows(self._related_recitation_ids())
            self._assert_parent_is_mutable()
            return super().delete(*args, **kwargs)

    def _related_recitation_ids(self) -> set[Any]:
        recitation_ids = {self.recitation_edition_id}
        if not self._state.adding:
            persisted_id = (
                type(self)
                .objects.filter(pk=self.pk)
                .values_list("recitation_edition_id", flat=True)
                .first()
            )
            if persisted_id is not None:
                recitation_ids.add(persisted_id)
        return recitation_ids


class AudioTrack(BaseModel):
    recitation_edition = models.ForeignKey(
        RecitationEdition,
        on_delete=models.CASCADE,
        related_name="tracks",
    )
    timing_version = models.ForeignKey(
        AudioTimingVersion,
        on_delete=models.RESTRICT,
        related_name="tracks",
        null=True,
        blank=True,
    )
    scope = models.CharField(max_length=8, choices=AudioTrackScope)
    surah_number = models.PositiveSmallIntegerField(null=True, blank=True)
    juz_number = models.PositiveSmallIntegerField(null=True, blank=True)
    duration_ms = models.PositiveBigIntegerField()
    codec = models.CharField(max_length=16, choices=AudioCodec)
    content_type = models.CharField(
        max_length=32,
        choices=AudioContentType,
        default=AudioContentType.MPEG,
    )
    bitrate_kbps = models.PositiveIntegerField()
    size_bytes = models.PositiveBigIntegerField()
    checksum_sha256 = models.CharField(
        max_length=64,
        blank=True,
        validators=[validate_sha256],
    )
    object_key = models.CharField(
        max_length=512,
        null=True,
        blank=True,
        unique=True,
        validators=[validate_relative_object_key],
    )
    external_url = models.URLField(max_length=1000, blank=True)

    class Meta:
        db_table = "audio_track"
        ordering = ["scope", "surah_number", "juz_number"]
        constraints = [
            models.CheckConstraint(
                condition=(
                    models.Q(
                        scope=AudioTrackScope.SURAH,
                        surah_number__gte=1,
                        surah_number__lte=114,
                        juz_number__isnull=True,
                    )
                    | models.Q(
                        scope=AudioTrackScope.JUZ,
                        surah_number__isnull=True,
                        juz_number__gte=1,
                        juz_number__lte=30,
                    )
                    | models.Q(
                        scope=AudioTrackScope.FULL,
                        surah_number__isnull=True,
                        juz_number__isnull=True,
                    )
                ),
                name="audio_track_scope_target_valid",
            ),
            models.CheckConstraint(
                condition=models.Q(duration_ms__gt=0),
                name="audio_track_duration_positive",
            ),
            models.CheckConstraint(
                condition=models.Q(bitrate_kbps__gt=0, bitrate_kbps__lte=100_000),
                name="audio_track_bitrate_valid",
            ),
            models.CheckConstraint(
                condition=models.Q(size_bytes__gt=0),
                name="audio_track_size_positive",
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(object_key__isnull=False, external_url="")
                    | (models.Q(object_key__isnull=True) & ~models.Q(external_url=""))
                ),
                name="audio_track_delivery_source_valid",
            ),
            models.UniqueConstraint(
                fields=["recitation_edition", "surah_number"],
                condition=models.Q(scope=AudioTrackScope.SURAH),
                name="audio_track_surah_scope_uq",
            ),
            models.UniqueConstraint(
                fields=["recitation_edition", "juz_number"],
                condition=models.Q(scope=AudioTrackScope.JUZ),
                name="audio_track_juz_scope_uq",
            ),
            models.UniqueConstraint(
                fields=["recitation_edition"],
                condition=models.Q(scope=AudioTrackScope.FULL),
                name="audio_track_full_scope_uq",
            ),
        ]
        indexes = [
            models.Index(
                fields=["recitation_edition", "scope", "surah_number", "juz_number"],
                name="audio_track_lookup_idx",
            ),
        ]

    def __str__(self) -> str:
        target = self.surah_number if self.scope == AudioTrackScope.SURAH else self.juz_number
        suffix = f":{target}" if target is not None else ""
        return f"{self.recitation_edition}:{self.scope}{suffix}"

    def clean(self) -> None:
        super().clean()
        self._assert_parent_is_mutable()
        self._validate_segment_bound_fields()
        has_object_key = bool(self.object_key)
        has_external_url = bool(self.external_url)
        if has_object_key == has_external_url:
            raise ValidationError(
                "Exactly one managed object key or external provider URL is required."
            )
        if has_object_key and not self.checksum_sha256:
            raise ValidationError(
                {"checksum_sha256": "Managed audio assets require a SHA-256 checksum."}
            )
        timing_version_id = self.__dict__.get("timing_version_id")
        if timing_version_id is not None:
            timing_recitation_id = (
                AudioTimingVersion.objects.filter(pk=timing_version_id)
                .values_list("recitation_edition_id", flat=True)
                .first()
            )
            if (
                timing_recitation_id is not None
                and timing_recitation_id != self.recitation_edition_id
            ):
                raise ValidationError(
                    {"timing_version": "The timing version must belong to this recitation."}
                )
        if self.scope == AudioTrackScope.SURAH:
            if self.surah_number is None or not 1 <= self.surah_number <= 114:
                raise ValidationError(
                    {"surah_number": "Surah tracks require a number from 1 to 114."}
                )
            if self.juz_number is not None:
                raise ValidationError({"juz_number": "Surah tracks cannot target a juz."})
        elif self.scope == AudioTrackScope.JUZ:
            if self.juz_number is None or not 1 <= self.juz_number <= 30:
                raise ValidationError({"juz_number": "Juz tracks require a number from 1 to 30."})
            if self.surah_number is not None:
                raise ValidationError({"surah_number": "Juz tracks cannot target a surah."})
        elif self.scope == AudioTrackScope.FULL and (
            self.surah_number is not None or self.juz_number is not None
        ):
            raise ValidationError("Full-Quran tracks cannot have a surah or juz target.")
        expected_content_type = CODEC_CONTENT_TYPES.get(self.codec)
        if expected_content_type is not None and self.content_type != expected_content_type:
            raise ValidationError(
                {"content_type": "The audio MIME type must match the declared codec."}
            )

    def _validate_segment_bound_fields(self) -> None:
        if self._state.adding or not self.segments.exists():
            return
        fields = (
            "recitation_edition_id",
            "timing_version_id",
            "scope",
            "surah_number",
            "juz_number",
            "duration_ms",
            "object_key",
            "external_url",
            "checksum_sha256",
        )
        persisted = type(self).objects.filter(pk=self.pk).values(*fields).first()
        if persisted is None:
            return
        changed = [field for field in fields if persisted[field] != getattr(self, field)]
        if changed:
            raise ValidationError(
                dict.fromkeys(
                    changed,
                    "Track fields referenced by ayah segments are immutable.",
                )
            )

    def _assert_parent_is_mutable(self) -> None:
        if not self.recitation_edition_id:
            return
        current_status = (
            RecitationEdition.objects.filter(pk=self.recitation_edition_id)
            .values_list("status", flat=True)
            .first()
        )
        persisted_status = None
        if not self._state.adding:
            persisted_status = (
                type(self)
                .objects.filter(pk=self.pk)
                .values_list("recitation_edition__status", flat=True)
                .first()
            )
        if current_status in {
            RecitationPublicationStatus.PUBLISHED,
            RecitationPublicationStatus.WITHDRAWN,
        } or persisted_status in {
            RecitationPublicationStatus.PUBLISHED,
            RecitationPublicationStatus.WITHDRAWN,
        }:
            raise ValidationError("Tracks in a published recitation edition are immutable.")

    def save(self, *args: Any, **kwargs: Any) -> None:
        with transaction.atomic():
            _lock_recitation_rows(self._related_recitation_ids())
            self._assert_parent_is_mutable()
            self.full_clean()
            super().save(*args, **kwargs)

    def delete(self, *args: Any, **kwargs: Any) -> tuple[int, dict[str, int]]:
        with transaction.atomic():
            _lock_recitation_rows(self._related_recitation_ids())
            self._assert_parent_is_mutable()
            return super().delete(*args, **kwargs)

    def _related_recitation_ids(self) -> set[Any]:
        recitation_ids = {self.recitation_edition_id}
        if not self._state.adding:
            persisted_id = (
                type(self)
                .objects.filter(pk=self.pk)
                .values_list("recitation_edition_id", flat=True)
                .first()
            )
            if persisted_id is not None:
                recitation_ids.add(persisted_id)
        return recitation_ids


class AyahAudioSegment(BaseModel):
    track = models.ForeignKey(AudioTrack, on_delete=models.CASCADE, related_name="segments")
    ayah = models.ForeignKey(Ayah, on_delete=models.PROTECT, related_name="audio_segments")
    start_ms = models.PositiveBigIntegerField()
    end_ms = models.PositiveBigIntegerField()

    class Meta:
        db_table = "audio_ayah_segment"
        ordering = ["track", "start_ms"]
        constraints = [
            models.UniqueConstraint(
                fields=["track", "ayah"],
                name="audio_segment_track_ayah_uq",
            ),
            models.CheckConstraint(
                condition=models.Q(end_ms__gt=models.F("start_ms")),
                name="audio_segment_range_valid",
            ),
        ]
        indexes = [
            models.Index(fields=["track", "start_ms"], name="audio_segment_timeline_idx"),
            models.Index(fields=["ayah", "track"], name="audio_segment_ayah_idx"),
        ]

    def __str__(self) -> str:
        return f"{self.track}:{self.ayah} [{self.start_ms}, {self.end_ms})"

    def clean(self) -> None:
        super().clean()
        self._assert_parent_is_mutable()
        start_ms: Any = getattr(self, "start_ms", None)
        end_ms: Any = getattr(self, "end_ms", None)
        if start_ms is None or end_ms is None:
            return
        if end_ms <= start_ms:
            raise ValidationError({"end_ms": "The segment end must be after its start."})
        if not self.track_id or not self.ayah_id:
            return

        track = (
            AudioTrack.objects.select_related("recitation_edition", "timing_version")
            .filter(pk=self.track_id)
            .first()
        )
        ayah = Ayah.objects.select_related("surah__edition_version").filter(pk=self.ayah_id).first()
        if track is None or ayah is None:
            return
        timing_version = track.timing_version if track.timing_version_id is not None else None
        if timing_version is None or timing_version.verified_at is None:
            raise ValidationError(
                {"track": "Ayah segments require a verified, versioned timing source."}
            )
        if end_ms > track.duration_ms:
            raise ValidationError({"end_ms": "The segment must fit within the track duration."})
        if ayah.surah.edition_version_id != track.recitation_edition.quran_edition_version_id:
            raise ValidationError(
                {"ayah": "The ayah and recitation must use the same Quran edition version."}
            )
        if track.scope == AudioTrackScope.SURAH and ayah.surah.number != track.surah_number:
            raise ValidationError({"ayah": "The ayah does not belong to this surah track."})
        if track.scope == AudioTrackScope.JUZ and ayah.juz_number != track.juz_number:
            raise ValidationError({"ayah": "The ayah does not belong to this juz track."})

        overlapping = (
            type(self)
            .objects.filter(
                track_id=self.track_id,
                start_ms__lt=end_ms,
                end_ms__gt=start_ms,
            )
            .exclude(pk=self.pk)
            .exists()
        )
        if overlapping:
            raise ValidationError("Ayah segments within one track must not overlap.")

    def _assert_parent_is_mutable(self) -> None:
        if not self.track_id:
            return
        current_status = (
            AudioTrack.objects.filter(pk=self.track_id)
            .values_list("recitation_edition__status", flat=True)
            .first()
        )
        persisted_status = None
        if not self._state.adding:
            persisted_status = (
                type(self)
                .objects.filter(pk=self.pk)
                .values_list("track__recitation_edition__status", flat=True)
                .first()
            )
        if current_status in {
            RecitationPublicationStatus.PUBLISHED,
            RecitationPublicationStatus.WITHDRAWN,
        } or persisted_status in {
            RecitationPublicationStatus.PUBLISHED,
            RecitationPublicationStatus.WITHDRAWN,
        }:
            raise ValidationError("Segments in a published recitation edition are immutable.")

    def save(self, *args: Any, **kwargs: Any) -> None:
        with transaction.atomic():
            track_ids, recitation_ids = self._related_parent_ids()
            _lock_recitation_rows(recitation_ids)
            list(
                AudioTrack.objects.select_for_update()
                .filter(pk__in=track_ids)
                .order_by("pk")
                .values_list("pk", flat=True)
            )
            self._assert_parent_is_mutable()
            self.full_clean()
            super().save(*args, **kwargs)

    def delete(self, *args: Any, **kwargs: Any) -> tuple[int, dict[str, int]]:
        with transaction.atomic():
            track_ids, recitation_ids = self._related_parent_ids()
            _lock_recitation_rows(recitation_ids)
            list(
                AudioTrack.objects.select_for_update()
                .filter(pk__in=track_ids)
                .order_by("pk")
                .values_list("pk", flat=True)
            )
            self._assert_parent_is_mutable()
            return super().delete(*args, **kwargs)

    def _related_parent_ids(self) -> tuple[set[Any], set[Any]]:
        track_ids = {self.track_id}
        if not self._state.adding:
            persisted_id = (
                type(self).objects.filter(pk=self.pk).values_list("track_id", flat=True).first()
            )
            if persisted_id is not None:
                track_ids.add(persisted_id)
        recitation_ids = set(
            AudioTrack.objects.filter(pk__in=track_ids).values_list(
                "recitation_edition_id",
                flat=True,
            )
        )
        return track_ids, recitation_ids
