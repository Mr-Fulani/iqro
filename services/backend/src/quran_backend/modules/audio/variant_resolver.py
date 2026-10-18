from __future__ import annotations

import uuid
from dataclasses import dataclass
from enum import StrEnum
from typing import Protocol

from django.conf import settings
from django.db.models import Count, F, Prefetch, Q, QuerySet, Sum

from quran_backend.modules.audio.models import (
    AudioRendition,
    AudioTrack,
    AudioTrackScope,
    AyahAudioSegment,
    QuranFoundationAyahRecitation,
    QuranFoundationAyahRecitationChapter,
    RecitationEdition,
    RecitationPublicationStatus,
)
from quran_backend.modules.audio.quran_foundation import ENVIRONMENTS
from quran_backend.modules.audio.selectors import (
    ordered_renditions,
    public_quran_foundation_ayah_recitations,
    public_recitation_base,
    verified_audio_segments,
)
from quran_backend.modules.quran.models import PublicationStatus, Surah

QF_AYAH_VARIANT_PREFIX = "qf-ayah"


class AudioVariantProvider(StrEnum):
    IQRO = "iqro"
    QURAN_FOUNDATION = "quran_foundation"


class AudioVariantDelivery(StrEnum):
    MANAGED = "managed"
    EXTERNAL = "external"
    MIXED = "mixed"


class AudioVariantGranularity(StrEnum):
    SURAH = "surah"
    AYAH = "ayah"


class AudioVariantTimingMode(StrEnum):
    TIMED = "timed"
    UNTIMED = "untimed"
    AYAH = "ayah"


class AudioVariantRole(StrEnum):
    LISTEN = "listen"
    AYAH_PLAYBACK = "ayah_playback"
    MEMORIZATION = "memorization"
    OFFLINE = "offline"


class AudioVariantResolutionError(LookupError):
    """Base error for resolving a public audio variant or its delivery."""


class AudioVariantNotFoundError(AudioVariantResolutionError):
    """The stable variant ID does not identify an available audio variant."""


class AudioVariantRoleNotSupportedError(AudioVariantResolutionError):
    """The variant exists but cannot serve the requested playback role."""


class AudioAyahNotAvailableError(AudioVariantResolutionError):
    """The requested ayah has no delivery in the selected variant."""


@dataclass(frozen=True, slots=True)
class AudioVariantCoverage:
    track_count: int
    surah_count: int
    expected_ayahs: int
    delivered_ayahs: int
    timed_ayahs: int
    complete: bool

    @property
    def timings_complete(self) -> bool:
        return self.expected_ayahs > 0 and self.timed_ayahs >= self.expected_ayahs

    @property
    def partial(self) -> bool:
        return not self.complete

    def to_dict(self) -> dict[str, int | bool]:
        return {
            "track_count": self.track_count,
            "surah_count": self.surah_count,
            "expected_ayahs": self.expected_ayahs,
            "delivered_ayahs": self.delivered_ayahs,
            "timed_ayahs": self.timed_ayahs,
            "complete": self.complete,
            "timings_complete": self.timings_complete,
        }


@dataclass(frozen=True, slots=True)
class AudioVariantCapabilities:
    listen: bool
    ayah_playback: bool
    memorization: bool
    offline: bool

    def supports(self, role: AudioVariantRole) -> bool:
        return {
            AudioVariantRole.LISTEN: self.listen,
            AudioVariantRole.AYAH_PLAYBACK: self.ayah_playback,
            AudioVariantRole.MEMORIZATION: self.memorization,
            AudioVariantRole.OFFLINE: self.offline,
        }[role]

    def to_dict(self) -> dict[str, bool]:
        return {
            "listen": self.listen,
            "ayah_playback": self.ayah_playback,
            "memorization": self.memorization,
            "offline": self.offline,
        }


@dataclass(frozen=True, slots=True)
class AudioVariantDescriptor:
    id: str
    provider: AudioVariantProvider
    delivery: AudioVariantDelivery
    granularity: AudioVariantGranularity
    timing_mode: AudioVariantTimingMode
    quran_edition_version_id: uuid.UUID
    reciter_id: uuid.UUID | None
    source_id: int | None
    code: str
    version: str
    style: str
    name_ar: str
    name_en: str
    name_ru: str
    name_tr: str
    coverage: AudioVariantCoverage
    capabilities: AudioVariantCapabilities

    def to_dict(self) -> dict[str, object]:
        return {
            "id": self.id,
            "provider": self.provider.value,
            "delivery": self.delivery.value,
            "granularity": self.granularity.value,
            "timing_mode": self.timing_mode.value,
            "quran_edition_version_id": str(self.quran_edition_version_id),
            "reciter_id": str(self.reciter_id) if self.reciter_id is not None else None,
            "source_id": self.source_id,
            "code": self.code,
            "version": self.version,
            "style": self.style,
            "name_ar": self.name_ar,
            "name_en": self.name_en,
            "name_ru": self.name_ru,
            "name_tr": self.name_tr,
            "coverage": self.coverage.to_dict(),
            "capabilities": self.capabilities.to_dict(),
        }


@dataclass(frozen=True, slots=True)
class ResolvedAudioAyah:
    variant: AudioVariantDescriptor
    surah_number: int
    ayah_number: int
    url: str
    delivery: AudioVariantDelivery
    track_id: uuid.UUID | None
    duration_ms: int | None
    start_ms: int | None
    end_ms: int | None

    def to_dict(self) -> dict[str, object]:
        return {
            "variant_id": self.variant.id,
            "surah_number": self.surah_number,
            "ayah_number": self.ayah_number,
            "url": self.url,
            "delivery": self.delivery.value,
            "track_id": str(self.track_id) if self.track_id is not None else None,
            "duration_ms": self.duration_ms,
            "start_ms": self.start_ms,
            "end_ms": self.end_ms,
        }


@dataclass(frozen=True, slots=True)
class ResolvedAudioTrack:
    variant: AudioVariantDescriptor
    surah_number: int
    url: str | None
    delivery: AudioVariantDelivery
    track_id: uuid.UUID | None
    duration_ms: int | None
    ayahs: tuple[ResolvedAudioAyah, ...]

    def to_dict(self) -> dict[str, object]:
        return {
            "variant": self.variant.to_dict(),
            "surah_number": self.surah_number,
            "url": self.url,
            "delivery": self.delivery.value,
            "track_id": str(self.track_id) if self.track_id is not None else None,
            "duration_ms": self.duration_ms,
            "ayahs": [ayah.to_dict() for ayah in self.ayahs],
        }


@dataclass(frozen=True, slots=True)
class _RecitationSummary:
    coverage: AudioVariantCoverage
    delivery: AudioVariantDelivery
    segment_count: int
    track_count: int


def recitation_variant_id(recitation_id: uuid.UUID | str) -> str:
    """Return the stable ID used for a native RecitationEdition variant."""

    return str(recitation_id)


def quran_foundation_ayah_variant_id(
    *,
    environment: str,
    source_id: int,
    quran_edition_version_id: uuid.UUID | str,
) -> str:
    if environment not in ENVIRONMENTS:
        raise ValueError("Quran.Foundation environment is invalid.")
    if source_id <= 0:
        raise ValueError("Quran.Foundation source IDs must be positive.")
    return f"{QF_AYAH_VARIANT_PREFIX}:{environment}:{source_id}:{quran_edition_version_id}"


def _parse_quran_foundation_ayah_variant_id(
    variant_id: str,
) -> tuple[str, int, uuid.UUID] | None:
    parts = variant_id.split(":")
    if len(parts) != 4 or parts[0] != QF_AYAH_VARIANT_PREFIX:
        return None
    environment, raw_source_id, raw_version_id = parts[1:]
    if environment not in ENVIRONMENTS:
        return None
    try:
        source_id = int(raw_source_id)
        version_id = uuid.UUID(raw_version_id)
    except TypeError, ValueError:
        return None
    if source_id <= 0:
        return None
    return environment, source_id, version_id


class AudioVariantAdapter(Protocol):
    provider: AudioVariantProvider

    def resolve(self, variant_id: str) -> AudioVariantDescriptor | None: ...

    def resolve_track(
        self,
        variant: AudioVariantDescriptor,
        surah_number: int,
    ) -> ResolvedAudioTrack: ...


class RecitationEditionAudioAdapter:
    provider = AudioVariantProvider.IQRO

    def __init__(self, *, public_only: bool) -> None:
        self.public_only = public_only

    def _queryset(self) -> QuerySet[RecitationEdition]:
        if self.public_only:
            return public_recitation_base()
        return (
            RecitationEdition.objects.filter(
                status=RecitationPublicationStatus.PUBLISHED,
                stream_allowed=True,
                reciter__is_active=True,
                quran_edition_version__status=PublicationStatus.PUBLISHED,
                quran_edition_version__edition__active_version_id=F("quran_edition_version_id"),
            )
            .select_related("reciter", "quran_edition_version__edition")
            .order_by("id")
        )

    def _get(self, variant_id: str) -> RecitationEdition | None:
        try:
            parsed = uuid.UUID(variant_id)
        except ValueError, AttributeError:
            return None
        return self._queryset().filter(pk=parsed).first()

    def resolve(self, variant_id: str) -> AudioVariantDescriptor | None:
        recitation = self._get(variant_id)
        if recitation is None:
            return None

        summary = _recitation_summary(recitation)
        return AudioVariantDescriptor(
            id=recitation_variant_id(recitation.id),
            provider=self.provider,
            delivery=summary.delivery,
            granularity=AudioVariantGranularity.SURAH,
            timing_mode=(
                AudioVariantTimingMode.TIMED
                if summary.segment_count > 0
                else AudioVariantTimingMode.UNTIMED
            ),
            quran_edition_version_id=recitation.quran_edition_version_id,
            reciter_id=recitation.reciter_id,
            source_id=None,
            code=recitation.code,
            version=recitation.version,
            style=recitation.style,
            name_ar=recitation.reciter.name_ar,
            name_en=recitation.reciter.name_en,
            name_ru=recitation.reciter.name_ru,
            name_tr=recitation.reciter.name_tr,
            coverage=summary.coverage,
            capabilities=AudioVariantCapabilities(
                listen=bool(recitation.stream_allowed and summary.track_count),
                ayah_playback=summary.coverage.timings_complete and not recitation.listening_only,
                memorization=summary.coverage.timings_complete and not recitation.listening_only,
                offline=bool(recitation.offline_download_allowed),
            ),
        )

    def resolve_track(
        self,
        variant: AudioVariantDescriptor,
        surah_number: int,
    ) -> ResolvedAudioTrack:
        if variant.provider is not self.provider:
            raise AudioVariantNotFoundError(
                "The selected audio adapter cannot resolve this variant."
            )
        try:
            recitation_id = uuid.UUID(variant.id)
        except ValueError as exc:
            raise AudioVariantNotFoundError("The recitation variant ID is invalid.") from exc
        track = (
            AudioTrack.objects.filter(
                recitation_edition_id=recitation_id,
                scope=AudioTrackScope.SURAH,
                surah_number=surah_number,
            )
            .select_related("timing_version")
            .prefetch_related(
                # The resolver only exposes the public delivery contract.
                # Storage/object keys never leave the adapter.
                Prefetch(
                    "renditions",
                    queryset=ordered_renditions(),
                    to_attr="public_renditions",
                )
            )
            .first()
        )
        if track is None:
            raise AudioVariantNotFoundError("A track is not available for this surah.")
        renditions = list(getattr(track, "public_renditions", []))
        rendition = next((item for item in renditions if item.is_default), None)
        if rendition is None:
            raise AudioVariantNotFoundError("The selected track has no default delivery.")
        url = _rendition_url(rendition)
        delivery = _rendition_delivery(rendition)
        segments = verified_audio_segments().filter(track=track).select_related("ayah__surah")
        ayahs = tuple(
            ResolvedAudioAyah(
                variant=variant,
                surah_number=segment.ayah.surah.number,
                ayah_number=segment.ayah.number,
                url=url,
                delivery=delivery,
                track_id=track.id,
                duration_ms=track.duration_ms,
                start_ms=segment.start_ms,
                end_ms=segment.end_ms,
            )
            for segment in segments
        )
        return ResolvedAudioTrack(
            variant=variant,
            surah_number=surah_number,
            url=url,
            delivery=delivery,
            track_id=track.id,
            duration_ms=track.duration_ms,
            ayahs=ayahs,
        )


class QuranFoundationAyahAudioAdapter:
    provider = AudioVariantProvider.QURAN_FOUNDATION

    def __init__(self, *, public_only: bool) -> None:
        self.public_only = public_only

    def _queryset(
        self,
        environment: str,
    ) -> QuerySet[QuranFoundationAyahRecitation]:
        if self.public_only:
            return public_quran_foundation_ayah_recitations(environment)
        return (
            QuranFoundationAyahRecitation.objects.filter(
                environment=environment,
                is_available=True,
                quran_edition_version__status=PublicationStatus.PUBLISHED,
                quran_edition_version__edition__active_version_id=F("quran_edition_version_id"),
            )
            .select_related("quran_edition_version__edition")
            .annotate(
                chapter_count=Count("chapters", distinct=True),
                cached_audio_file_count=Sum("chapters__ayah_count"),
            )
            .order_by("source_id")
        )

    def _get(self, variant_id: str) -> QuranFoundationAyahRecitation | None:
        parsed = _parse_quran_foundation_ayah_variant_id(variant_id)
        if parsed is None:
            return None
        environment, source_id, version_id = parsed
        return (
            self._queryset(environment)
            .filter(
                source_id=source_id,
                quran_edition_version_id=version_id,
            )
            .first()
        )

    def resolve(self, variant_id: str) -> AudioVariantDescriptor | None:
        recitation = self._get(variant_id)
        if recitation is None:
            return None
        chapter_count = int(getattr(recitation, "chapter_count", 0))
        delivered_ayahs = int(getattr(recitation, "cached_audio_file_count", 0) or 0)
        expected_ayahs = int(
            Surah.objects.filter(edition_version_id=recitation.quran_edition_version_id).aggregate(
                total=Sum("ayah_count")
            )["total"]
            or 0
        )
        coverage = AudioVariantCoverage(
            track_count=chapter_count,
            surah_count=chapter_count,
            expected_ayahs=expected_ayahs,
            delivered_ayahs=delivered_ayahs,
            timed_ayahs=0,
            complete=(
                chapter_count == 114
                and delivered_ayahs == expected_ayahs
                and delivered_ayahs == recitation.audio_file_count
            ),
        )
        return AudioVariantDescriptor(
            id=quran_foundation_ayah_variant_id(
                environment=recitation.environment,
                source_id=recitation.source_id,
                quran_edition_version_id=recitation.quran_edition_version_id,
            ),
            provider=self.provider,
            delivery=AudioVariantDelivery.EXTERNAL,
            granularity=AudioVariantGranularity.AYAH,
            timing_mode=AudioVariantTimingMode.AYAH,
            quran_edition_version_id=recitation.quran_edition_version_id,
            reciter_id=None,
            source_id=recitation.source_id,
            code=f"qf-ayah-{recitation.source_id}",
            version=recitation.source_checksum_sha256,
            style=recitation.style,
            name_ar=recitation.name_ar,
            name_en=recitation.name_en,
            name_ru=recitation.name_ru,
            name_tr=recitation.name_en,
            coverage=coverage,
            capabilities=AudioVariantCapabilities(
                listen=coverage.complete,
                ayah_playback=coverage.complete,
                memorization=coverage.complete,
                offline=False,
            ),
        )

    def resolve_track(
        self,
        variant: AudioVariantDescriptor,
        surah_number: int,
    ) -> ResolvedAudioTrack:
        parsed = _parse_quran_foundation_ayah_variant_id(variant.id)
        if parsed is None:
            raise AudioVariantNotFoundError("The Quran.Foundation variant ID is invalid.")
        environment, source_id, version_id = parsed
        chapter = QuranFoundationAyahRecitationChapter.objects.filter(
            recitation__environment=environment,
            recitation__source_id=source_id,
            recitation__quran_edition_version_id=version_id,
            recitation__is_available=True,
            chapter_number=surah_number,
        ).first()
        if chapter is None:
            raise AudioVariantNotFoundError("Ayah audio is not available for this surah.")
        ayahs: list[ResolvedAudioAyah] = []
        for item in chapter.audio_files:
            if not isinstance(item, dict):
                continue
            try:
                ayah_number = int(item["ayah_number"])
                url = str(item["url"])
            except KeyError, TypeError, ValueError:
                continue
            if ayah_number <= 0 or not url:
                continue
            ayahs.append(
                ResolvedAudioAyah(
                    variant=variant,
                    surah_number=surah_number,
                    ayah_number=ayah_number,
                    url=url,
                    delivery=AudioVariantDelivery.EXTERNAL,
                    track_id=None,
                    duration_ms=None,
                    start_ms=None,
                    end_ms=None,
                )
            )
        if not ayahs:
            raise AudioVariantNotFoundError("The selected surah has no valid ayah deliveries.")
        ayahs.sort(key=lambda item: item.ayah_number)
        return ResolvedAudioTrack(
            variant=variant,
            surah_number=surah_number,
            url=None,
            delivery=AudioVariantDelivery.EXTERNAL,
            track_id=None,
            duration_ms=None,
            ayahs=tuple(ayahs),
        )


class AudioVariantResolver:
    """Resolve every public audio source through one role-aware delivery API."""

    def __init__(self, *, public_only: bool = True, environment: str = "production") -> None:
        if environment not in ENVIRONMENTS:
            raise ValueError("Quran.Foundation environment is invalid.")
        self._adapters: tuple[AudioVariantAdapter, ...] = (
            RecitationEditionAudioAdapter(public_only=public_only),
            QuranFoundationAyahAudioAdapter(public_only=public_only),
        )
        self._adapters_by_provider = {adapter.provider: adapter for adapter in self._adapters}
        # The QF adapter reads the environment from the namespaced variant ID.  Keep this
        # argument in the resolver constructor so callers can validate deployment config once.
        self.environment = environment

    def resolve(
        self,
        variant_id: str,
        *,
        role: AudioVariantRole | None = None,
    ) -> AudioVariantDescriptor:
        normalized = str(variant_id).strip()
        if not normalized:
            raise AudioVariantNotFoundError("An audio variant ID is required.")
        for adapter in self._adapters:
            variant = adapter.resolve(normalized)
            if variant is None:
                continue
            if role is not None and not variant.capabilities.supports(role):
                raise AudioVariantRoleNotSupportedError(
                    f"Audio variant '{normalized}' does not support '{role.value}'."
                )
            return variant
        raise AudioVariantNotFoundError(f"Audio variant '{normalized}' was not found.")

    def resolve_track(
        self,
        variant_id: str,
        *,
        surah_number: int,
        role: AudioVariantRole | None = AudioVariantRole.LISTEN,
    ) -> ResolvedAudioTrack:
        variant = self.resolve(variant_id, role=role)
        adapter = self._adapters_by_provider[variant.provider]
        return adapter.resolve_track(variant, surah_number)

    def resolve_ayah(
        self,
        variant_id: str,
        *,
        surah_number: int,
        ayah_number: int,
        role: AudioVariantRole | None = AudioVariantRole.AYAH_PLAYBACK,
    ) -> ResolvedAudioAyah:
        track = self.resolve_track(
            variant_id,
            surah_number=surah_number,
            role=role,
        )
        for ayah in track.ayahs:
            if ayah.ayah_number == ayah_number:
                return ayah
        raise AudioAyahNotAvailableError(
            f"Ayah {surah_number}:{ayah_number} is not available in variant '{variant_id}'."
        )


def _recitation_summary(recitation: RecitationEdition) -> _RecitationSummary:
    tracks = AudioTrack.objects.filter(recitation_edition_id=recitation.id)
    aggregate = tracks.aggregate(
        track_count=Count("id", distinct=True),
        surah_count=Count(
            "id",
            filter=Q(scope=AudioTrackScope.SURAH),
            distinct=True,
        ),
        default_track_count=Count(
            "id",
            filter=Q(scope=AudioTrackScope.SURAH, renditions__is_default=True),
            distinct=True,
        ),
        managed_track_count=Count(
            "id",
            filter=Q(
                scope=AudioTrackScope.SURAH,
                renditions__is_default=True,
                renditions__object_key__isnull=False,
            ),
            distinct=True,
        ),
        external_track_count=Count(
            "id",
            filter=Q(
                scope=AudioTrackScope.SURAH,
                renditions__is_default=True,
                renditions__object_key__isnull=True,
            ),
            distinct=True,
        ),
    )
    expected_ayahs = int(
        Surah.objects.filter(edition_version_id=recitation.quran_edition_version_id).aggregate(
            total=Sum("ayah_count")
        )["total"]
        or 0
    )
    segments = AyahAudioSegment.objects.filter(
        track__recitation_edition_id=recitation.id,
        track__timing_version__verified_at__isnull=False,
        track__timing_version__recitation_edition_id=recitation.id,
        ayah__surah__edition_version_id=recitation.quran_edition_version_id,
        end_ms__lte=F("track__duration_ms"),
    ).filter(
        Q(
            track__scope=AudioTrackScope.SURAH,
            ayah__surah__number=F("track__surah_number"),
        )
        | Q(
            track__scope=AudioTrackScope.JUZ,
            ayah__juz_number=F("track__juz_number"),
        )
        | Q(track__scope=AudioTrackScope.FULL)
    )
    segment_count = segments.count()
    timed_ayahs = segments.values("ayah_id").distinct().count()
    track_count = int(aggregate["track_count"] or 0)
    surah_count = int(aggregate["surah_count"] or 0)
    default_track_count = int(aggregate["default_track_count"] or 0)
    managed_track_count = int(aggregate["managed_track_count"] or 0)
    external_track_count = int(aggregate["external_track_count"] or 0)
    delivery = (
        AudioVariantDelivery.MANAGED
        if managed_track_count == default_track_count and default_track_count > 0
        else AudioVariantDelivery.EXTERNAL
        if external_track_count == default_track_count and default_track_count > 0
        else AudioVariantDelivery.MIXED
    )
    coverage = AudioVariantCoverage(
        track_count=track_count,
        surah_count=surah_count,
        expected_ayahs=expected_ayahs,
        delivered_ayahs=expected_ayahs if surah_count == 114 else 0,
        timed_ayahs=timed_ayahs,
        complete=surah_count == 114 and default_track_count == 114,
    )
    return _RecitationSummary(
        coverage=coverage,
        delivery=delivery,
        segment_count=segment_count,
        track_count=track_count,
    )


def _rendition_url(rendition: AudioRendition) -> str:
    if rendition.object_key:
        return f"{settings.PUBLIC_AUDIO_BASE_URL.rstrip('/')}/{rendition.object_key}"
    if rendition.external_url:
        return rendition.external_url
    raise AudioVariantNotFoundError("The selected rendition has no public delivery URL.")


def _rendition_delivery(rendition: AudioRendition) -> AudioVariantDelivery:
    return AudioVariantDelivery.MANAGED if rendition.object_key else AudioVariantDelivery.EXTERNAL
