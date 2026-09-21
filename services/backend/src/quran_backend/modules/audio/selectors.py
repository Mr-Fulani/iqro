from __future__ import annotations

import uuid

from django.db.models import (
    Case,
    Count,
    Exists,
    F,
    IntegerField,
    OuterRef,
    Prefetch,
    Q,
    QuerySet,
    Subquery,
    Sum,
    When,
)

from quran_backend.modules.audio.models import (
    AudioRendition,
    AudioTrack,
    AudioTrackScope,
    AyahAudioSegment,
    QuranFoundationAyahRecitation,
    QuranFoundationAyahRecitationChapter,
    RecitationEdition,
    RecitationPublicationStatus,
    Reciter,
)
from quran_backend.modules.quran.models import PublicationStatus, Surah


def public_recitation_base() -> QuerySet[RecitationEdition]:
    """Cheap visibility predicate shared by catalog and playback selectors."""

    complete_surah_catalog = (
        AudioTrack.objects.filter(
            recitation_edition_id=OuterRef("pk"),
            scope=AudioTrackScope.SURAH,
            renditions__is_default=True,
        )
        .values("recitation_edition_id")
        .annotate(surah_count=Count("surah_number", distinct=True))
        .filter(surah_count=114)
    )
    return (
        RecitationEdition.objects.alias(
            has_complete_surah_catalog=Exists(complete_surah_catalog),
        )
        .filter(
            status=RecitationPublicationStatus.PUBLISHED,
            stream_allowed=True,
            has_complete_surah_catalog=True,
            reciter__is_active=True,
            quran_edition_version__status=PublicationStatus.PUBLISHED,
            quran_edition_version__edition__active_version_id=F("quran_edition_version_id"),
        )
        .select_related("reciter", "quran_edition_version__edition")
        .order_by("code", "version", "id")
    )


def public_recitations() -> QuerySet[RecitationEdition]:
    """Return visible recitations with catalog summary annotations."""

    expected_ayah_count = (
        Surah.objects.filter(
            edition_version_id=OuterRef("quran_edition_version_id"),
        )
        .values("edition_version_id")
        .annotate(total=Sum("ayah_count"))
        .values("total")[:1]
    )
    catalog_segment_scope = _segment_scope_matches_track(
        track_lookup="tracks__",
        ayah_lookup="tracks__segments__ayah__",
    )
    return (
        public_recitation_base()
        .annotate(
            track_count=Count("tracks", distinct=True),
            surah_track_count=Count(
                "tracks",
                filter=Q(tracks__scope=AudioTrackScope.SURAH),
                distinct=True,
            ),
            timing_segment_count=Count(
                "tracks__segments",
                filter=Q(
                    tracks__timing_version__verified_at__isnull=False,
                    tracks__timing_version__recitation_edition_id=F("id"),
                    tracks__segments__ayah__surah__edition_version_id=F("quran_edition_version_id"),
                    tracks__segments__end_ms__lte=F("tracks__duration_ms"),
                )
                & catalog_segment_scope,
                distinct=True,
            ),
            expected_ayah_count=Subquery(expected_ayah_count),
            timed_ayah_count=Count(
                "tracks__segments__ayah",
                filter=Q(
                    tracks__timing_version__verified_at__isnull=False,
                    tracks__timing_version__recitation_edition_id=F("id"),
                    tracks__segments__ayah__surah__edition_version_id=F("quran_edition_version_id"),
                    tracks__segments__end_ms__lte=F("tracks__duration_ms"),
                )
                & catalog_segment_scope,
                distinct=True,
            ),
        )
        .order_by("code", "version", "id")
    )


def public_reciters() -> QuerySet[Reciter]:
    public_recitation = public_recitation_base().filter(reciter_id=OuterRef("pk"))
    return (
        Reciter.objects.alias(has_public_recitation=Exists(public_recitation))
        .filter(is_active=True, has_public_recitation=True)
        .order_by("name_en", "code", "id")
    )


def public_quran_foundation_ayah_recitations(
    environment: str,
) -> QuerySet[QuranFoundationAyahRecitation]:
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
        .filter(chapter_count=114, cached_audio_file_count=F("audio_file_count"))
        .order_by("source_id")
    )


def public_quran_foundation_ayah_chapters(
    environment: str,
    source_id: int,
) -> QuerySet[QuranFoundationAyahRecitationChapter]:
    public_recitations = public_quran_foundation_ayah_recitations(environment).filter(
        source_id=source_id
    )
    return (
        QuranFoundationAyahRecitationChapter.objects.filter(
            recitation__in=public_recitations,
        )
        .select_related("recitation__quran_edition_version__edition")
        .order_by("chapter_number")
    )


def public_tracks(recitation_id: uuid.UUID) -> QuerySet[AudioTrack]:
    return (
        AudioTrack.objects.filter(
            recitation_edition__in=public_recitation_base(),
            recitation_edition_id=recitation_id,
            renditions__is_default=True,
        )
        .select_related(
            "recitation_edition",
            "recitation_edition__reciter",
            "recitation_edition__quran_edition_version__edition",
            "timing_version",
        )
        .prefetch_related(
            Prefetch(
                "renditions",
                queryset=ordered_renditions(),
                to_attr="public_renditions",
            )
        )
        .order_by("scope", "surah_number", "juz_number", "id")
    )


def ordered_renditions() -> QuerySet[AudioRendition]:
    quality_order = Case(
        When(quality="economy", then=0),
        When(quality="standard", then=1),
        When(quality="high", then=2),
        default=99,
        output_field=IntegerField(),
    )
    return AudioRendition.objects.order_by(quality_order, "id")


def public_surah_tracks(recitation_id: uuid.UUID, surah_number: int) -> QuerySet[AudioTrack]:
    return (
        public_tracks(recitation_id)
        .filter(
            scope=AudioTrackScope.SURAH,
            surah_number=surah_number,
        )
        .prefetch_related(
            Prefetch(
                "segments",
                queryset=verified_audio_segments().select_related("ayah__surah"),
                to_attr="verified_segments",
            )
        )
    )


def verified_audio_segments() -> QuerySet[AyahAudioSegment]:
    return (
        AyahAudioSegment.objects.filter(
            track__timing_version__verified_at__isnull=False,
            track__timing_version__recitation_edition_id=F("track__recitation_edition_id"),
            ayah__surah__edition_version_id=F(
                "track__recitation_edition__quran_edition_version_id"
            ),
            end_ms__lte=F("track__duration_ms"),
        )
        .filter(
            _segment_scope_matches_track(
                track_lookup="track__",
                ayah_lookup="ayah__",
            )
        )
        .order_by("start_ms", "id")
    )


def _segment_scope_matches_track(*, track_lookup: str, ayah_lookup: str) -> Q:
    return (
        Q(
            **{
                f"{track_lookup}scope": AudioTrackScope.SURAH,
                f"{ayah_lookup}surah__number": F(f"{track_lookup}surah_number"),
            }
        )
        | Q(
            **{
                f"{track_lookup}scope": AudioTrackScope.JUZ,
                f"{ayah_lookup}juz_number": F(f"{track_lookup}juz_number"),
            }
        )
        | Q(**{f"{track_lookup}scope": AudioTrackScope.FULL})
    )


def public_ayah_segments(
    recitation_id: uuid.UUID,
    surah_number: int,
    ayah_number: int,
) -> QuerySet[AyahAudioSegment]:
    return (
        verified_audio_segments()
        .filter(
            track__in=public_surah_tracks(recitation_id, surah_number),
            ayah__surah__number=surah_number,
            ayah__number=ayah_number,
        )
        .select_related(
            "ayah__surah__edition_version",
            "track__timing_version",
            "track__recitation_edition__quran_edition_version__edition",
        )
        .prefetch_related(
            Prefetch(
                "track__renditions",
                queryset=ordered_renditions(),
                to_attr="public_renditions",
            )
        )
        .order_by("start_ms", "id")
    )
