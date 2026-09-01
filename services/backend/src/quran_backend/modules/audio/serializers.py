from __future__ import annotations

from typing import Any

from django.conf import settings
from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers

from quran_backend.modules.audio.models import (
    AudioCodec,
    AudioRendition,
    AudioRenditionQuality,
    AudioTimingVersion,
    AudioTrack,
    AudioTrackScope,
    AyahAudioSegment,
    QuranFoundationAyahRecitation,
    QuranFoundationAyahRecitationChapter,
    RecitationEdition,
    RecitationStyle,
    Reciter,
)
from quran_backend.modules.quran.models import QuranEditionVersion


def public_audio_url(object_key: str) -> str:
    """Build a CDN URL from an already validated relative object key."""

    return f"{settings.PUBLIC_AUDIO_BASE_URL.rstrip('/')}/{object_key}"


class ReciterSummarySerializer(serializers.ModelSerializer[Reciter]):
    slug = serializers.CharField(source="code", read_only=True)
    portrait_url = serializers.SerializerMethodField()

    class Meta:
        model = Reciter
        fields = (
            "id",
            "slug",
            "name_ar",
            "name_en",
            "name_ru",
            "name_tr",
            "country_code",
            "portrait_url",
        )

    @extend_schema_field(serializers.URLField(allow_null=True))
    def get_portrait_url(self, obj: Reciter) -> str | None:
        if not obj.portrait_object_key:
            return None
        return public_audio_url(obj.portrait_object_key)


class ReciterDetailSerializer(ReciterSummarySerializer):
    class Meta:
        model = Reciter
        fields = (
            "id",
            "slug",
            "name_ar",
            "name_en",
            "name_ru",
            "name_tr",
            "country_code",
            "biography_ar",
            "biography_en",
            "biography_ru",
            "biography_tr",
            "portrait_url",
        )


class QuranEditionAudioReferenceSerializer(serializers.ModelSerializer[QuranEditionVersion]):
    code = serializers.CharField(source="edition.code", read_only=True)
    content_version = serializers.CharField(source="version", read_only=True)
    riwayah = serializers.CharField(source="edition.riwayah", read_only=True)

    class Meta:
        model = QuranEditionVersion
        fields = ("id", "code", "content_version", "riwayah")


class RecitationSourceSerializer(serializers.Serializer[Any]):
    name = serializers.CharField()
    url = serializers.URLField(allow_blank=True)
    version = serializers.CharField()
    checksum_sha256 = serializers.CharField()


class RecitationLicenseSerializer(serializers.Serializer[Any]):
    rights_holder = serializers.CharField()
    name = serializers.CharField()
    url = serializers.URLField(allow_blank=True)
    spdx_id = serializers.CharField(allow_blank=True)
    attribution = serializers.CharField(allow_blank=True)


class RecitationRightsSerializer(serializers.Serializer[Any]):
    stream = serializers.BooleanField()
    offline_download = serializers.BooleanField()


class RecitationCoverageSerializer(serializers.Serializer[Any]):
    track_count = serializers.IntegerField(min_value=0)
    surah_count = serializers.IntegerField(min_value=0)
    complete = serializers.BooleanField()


class RecitationTimingsSerializer(serializers.Serializer[Any]):
    available = serializers.BooleanField()
    segment_count = serializers.IntegerField(min_value=0)


class RecitationEditionSerializer(serializers.ModelSerializer[RecitationEdition]):
    reciter = ReciterSummarySerializer(read_only=True)
    quran_edition = QuranEditionAudioReferenceSerializer(
        source="quran_edition_version",
        read_only=True,
    )
    source: Any = serializers.SerializerMethodField()
    license = serializers.SerializerMethodField()
    rights = serializers.SerializerMethodField()
    coverage = serializers.SerializerMethodField()
    timings = serializers.SerializerMethodField()

    class Meta:
        model = RecitationEdition
        fields = (
            "id",
            "code",
            "version",
            "style",
            "reciter",
            "quran_edition",
            "source",
            "license",
            "rights",
            "coverage",
            "timings",
            "published_at",
        )

    @extend_schema_field(RecitationSourceSerializer)
    def get_source(self, obj: RecitationEdition) -> dict[str, str]:
        return {
            "name": obj.source_name,
            "url": obj.source_url,
            "version": obj.source_version,
            "checksum_sha256": obj.source_checksum_sha256,
        }

    @extend_schema_field(RecitationLicenseSerializer)
    def get_license(self, obj: RecitationEdition) -> dict[str, str]:
        return {
            "rights_holder": obj.rights_holder,
            "name": obj.license_name,
            "url": obj.license_url,
            "spdx_id": obj.license_spdx_id,
            "attribution": obj.license_attribution,
        }

    @extend_schema_field(RecitationRightsSerializer)
    def get_rights(self, obj: RecitationEdition) -> dict[str, bool]:
        return {
            "stream": bool(obj.stream_allowed),
            "offline_download": bool(obj.offline_download_allowed),
        }

    @extend_schema_field(RecitationCoverageSerializer)
    def get_coverage(self, obj: RecitationEdition) -> dict[str, int | bool]:
        track_count = int(getattr(obj, "track_count", 0))
        surah_count = int(getattr(obj, "surah_track_count", 0))
        return {
            "track_count": track_count,
            "surah_count": surah_count,
            "complete": surah_count == 114,
        }

    @extend_schema_field(RecitationTimingsSerializer)
    def get_timings(self, obj: RecitationEdition) -> dict[str, int | bool]:
        segment_count = int(getattr(obj, "timing_segment_count", 0))
        return {"available": segment_count > 0, "segment_count": segment_count}


class QuranFoundationAyahCoverageSerializer(serializers.Serializer[Any]):
    chapter_count = serializers.IntegerField(min_value=0)
    audio_file_count = serializers.IntegerField(min_value=0)
    complete = serializers.BooleanField()


class QuranFoundationAyahRecitationSerializer(
    serializers.ModelSerializer[QuranFoundationAyahRecitation]
):
    quran_edition = QuranEditionAudioReferenceSerializer(
        source="quran_edition_version",
        read_only=True,
    )
    coverage = serializers.SerializerMethodField()
    source: Any = serializers.SerializerMethodField()
    rights = serializers.SerializerMethodField()

    class Meta:
        model = QuranFoundationAyahRecitation
        fields = (
            "source_id",
            "name_ar",
            "name_en",
            "name_ru",
            "style",
            "quran_edition",
            "coverage",
            "source",
            "rights",
            "last_synced_at",
        )

    @extend_schema_field(QuranFoundationAyahCoverageSerializer)
    def get_coverage(self, obj: QuranFoundationAyahRecitation) -> dict[str, object]:
        chapter_count = int(getattr(obj, "chapter_count", 0))
        audio_file_count = int(getattr(obj, "cached_audio_file_count", 0) or 0)
        return {
            "chapter_count": chapter_count,
            "audio_file_count": audio_file_count,
            "complete": chapter_count == 114 and audio_file_count == obj.audio_file_count,
        }

    @extend_schema_field(RecitationSourceSerializer)
    def get_source(self, obj: QuranFoundationAyahRecitation) -> dict[str, str]:
        return {
            "name": "Quran.Foundation Content API",
            "url": (
                "https://api-docs.quran.foundation/docs/"
                "content_apis_versioned/4.0.0/recitation-audio-files/"
            ),
            "version": "content-api-v4",
            "checksum_sha256": obj.source_checksum_sha256,
        }

    @extend_schema_field(RecitationRightsSerializer)
    def get_rights(self, obj: QuranFoundationAyahRecitation) -> dict[str, bool]:  # noqa: ARG002
        return {"stream": True, "offline_download": False}


class QuranFoundationAyahAudioFileSerializer(serializers.Serializer[Any]):
    ayah_number = serializers.IntegerField(min_value=1)
    verse_key = serializers.CharField()
    url = serializers.URLField()


class QuranFoundationAyahChapterSerializer(
    serializers.ModelSerializer[QuranFoundationAyahRecitationChapter]
):
    recitation_id = serializers.IntegerField(source="recitation.source_id", read_only=True)
    reciter_name = serializers.CharField(source="recitation.name_en", read_only=True)
    style = serializers.CharField(  # type: ignore[assignment]
        source="recitation.style",
        read_only=True,
    )
    audio_files = QuranFoundationAyahAudioFileSerializer(many=True, read_only=True)

    class Meta:
        model = QuranFoundationAyahRecitationChapter
        fields = (
            "recitation_id",
            "reciter_name",
            "style",
            "chapter_number",
            "ayah_count",
            "audio_files",
        )


class AudioAssetSerializer(serializers.Serializer[Any]):
    url = serializers.URLField()
    content_type = serializers.CharField()
    codec = serializers.ChoiceField(choices=list(AudioCodec.choices))
    bitrate_kbps = serializers.IntegerField(min_value=1)
    bytes = serializers.IntegerField(min_value=1)
    sha256 = serializers.CharField(allow_null=True)
    etag = serializers.CharField(allow_null=True)
    range_supported = serializers.BooleanField()
    immutable = serializers.BooleanField()


def audio_asset_payload(rendition: AudioRendition) -> dict[str, Any]:
    checksum = rendition.checksum_sha256 or None
    if rendition.object_key is not None:
        url = public_audio_url(rendition.object_key)
        is_managed = True
    else:
        url = rendition.external_url
        is_managed = False
    return {
        "url": url,
        "content_type": rendition.content_type,
        "codec": rendition.codec,
        "bitrate_kbps": rendition.bitrate_kbps,
        "bytes": rendition.size_bytes,
        "sha256": checksum,
        "etag": rendition.etag or None,
        "range_supported": is_managed,
        "immutable": is_managed,
    }


class AudioRenditionSerializer(serializers.ModelSerializer[AudioRendition]):
    asset = serializers.SerializerMethodField()

    class Meta:
        model = AudioRendition
        fields = ("id", "quality", "is_default", "asset")

    @extend_schema_field(AudioAssetSerializer)
    def get_asset(self, obj: AudioRendition) -> dict[str, Any]:
        return audio_asset_payload(obj)


class AudioTimingVersionSerializer(serializers.ModelSerializer[AudioTimingVersion]):
    class Meta:
        model = AudioTimingVersion
        fields = (
            "id",
            "version",
            "source_name",
            "source_version",
            "source_checksum_sha256",
            "verified_at",
        )


class AudioTrackSerializer(serializers.ModelSerializer[AudioTrack]):
    recitation_id = serializers.UUIDField(source="recitation_edition_id", read_only=True)
    asset = serializers.SerializerMethodField()
    renditions = serializers.SerializerMethodField()
    offline_download_allowed = serializers.BooleanField(
        source="recitation_edition.offline_download_allowed",
        read_only=True,
    )
    timing_version = AudioTimingVersionSerializer(read_only=True, allow_null=True)

    class Meta:
        model = AudioTrack
        fields = (
            "id",
            "recitation_id",
            "scope",
            "surah_number",
            "juz_number",
            "duration_ms",
            "timing_version",
            "asset",
            "renditions",
            "offline_download_allowed",
        )

    def _renditions(self, obj: AudioTrack) -> list[AudioRendition]:
        prefetched = getattr(obj, "public_renditions", None)
        renditions = list(prefetched if prefetched is not None else obj.renditions.all())
        quality_rank = {"economy": 0, "standard": 1, "high": 2}
        return sorted(
            renditions,
            key=lambda item: (quality_rank.get(item.quality, 99), str(item.id)),
        )

    @extend_schema_field(AudioAssetSerializer(allow_null=True))
    def get_asset(self, obj: AudioTrack) -> dict[str, Any] | None:
        default = next(
            (rendition for rendition in self._renditions(obj) if rendition.is_default),
            None,
        )
        return audio_asset_payload(default) if default is not None else None

    @extend_schema_field(AudioRenditionSerializer(many=True))
    def get_renditions(self, obj: AudioTrack) -> Any:
        return AudioRenditionSerializer(self._renditions(obj), many=True).data


class OfflineAudioManifestQuerySerializer(serializers.Serializer[Any]):
    quality = serializers.ChoiceField(
        choices=list(AudioRenditionQuality.choices),
        required=False,
    )


class OfflineAudioAssetSerializer(serializers.Serializer[Any]):
    url = serializers.URLField()
    file_name = serializers.CharField()
    content_type = serializers.CharField()
    codec = serializers.ChoiceField(choices=list(AudioCodec.choices))
    bitrate_kbps = serializers.IntegerField(min_value=1)
    bytes = serializers.IntegerField(min_value=1)
    sha256 = serializers.CharField()
    etag = serializers.CharField()
    range_supported = serializers.BooleanField()
    immutable = serializers.BooleanField()


class OfflineAudioTimingSerializer(serializers.Serializer[Any]):
    version = serializers.CharField()
    source_checksum_sha256 = serializers.CharField()


class OfflineAudioSegmentSerializer(serializers.Serializer[Any]):
    ayah_id = serializers.UUIDField()
    ayah_number = serializers.IntegerField(min_value=1)
    start_ms = serializers.IntegerField(min_value=0)
    end_ms = serializers.IntegerField(min_value=1)


class OfflineAudioTrackSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    surah_number = serializers.IntegerField(min_value=1, max_value=114)
    duration_ms = serializers.IntegerField(min_value=1)
    rendition_quality = serializers.ChoiceField(choices=list(AudioRenditionQuality.choices))
    timing = OfflineAudioTimingSerializer(allow_null=True)
    segments = OfflineAudioSegmentSerializer(many=True)
    asset = OfflineAudioAssetSerializer()


class OfflineAudioQuranEditionSerializer(serializers.Serializer[Any]):
    code = serializers.CharField()
    version = serializers.CharField()
    checksum_sha256 = serializers.CharField()


class OfflineAudioManifestSerializer(serializers.Serializer[Any]):
    schema_version = serializers.IntegerField(min_value=1)
    package_type = serializers.CharField()
    package_id = serializers.CharField()
    version = serializers.CharField()
    quality = serializers.CharField()
    available_qualities = serializers.ListField(child=serializers.CharField())
    package_checksum_sha256 = serializers.CharField()
    published_at = serializers.DateTimeField()
    source: Any = RecitationSourceSerializer()
    license = RecitationLicenseSerializer()
    rights = RecitationRightsSerializer()
    reciter = ReciterSummarySerializer()
    quran_edition = OfflineAudioQuranEditionSerializer()
    track_count = serializers.IntegerField(min_value=1)
    total_bytes = serializers.IntegerField(min_value=1)
    tracks = OfflineAudioTrackSerializer(many=True)


class AyahAudioSegmentSerializer(serializers.ModelSerializer[AyahAudioSegment]):
    ayah_id = serializers.UUIDField(source="ayah.id", read_only=True)
    surah_number = serializers.IntegerField(source="ayah.surah.number", read_only=True)
    ayah_number = serializers.IntegerField(source="ayah.number", read_only=True)

    class Meta:
        model = AyahAudioSegment
        fields = ("ayah_id", "surah_number", "ayah_number", "start_ms", "end_ms")


class SurahPlaybackSerializer(serializers.Serializer[Any]):
    track = AudioTrackSerializer()
    segments = AyahAudioSegmentSerializer(many=True)


class AyahPlaybackSerializer(serializers.Serializer[Any]):
    track = AudioTrackSerializer()
    segment = AyahAudioSegmentSerializer()


class PublicCatalogPageQuerySerializer(serializers.Serializer[Any]):
    cursor = serializers.CharField(required=False, max_length=2048)
    page_size = serializers.IntegerField(required=False, min_value=1, max_value=100)


class RecitationListQuerySerializer(PublicCatalogPageQuerySerializer):
    reciter_id = serializers.UUIDField(required=False)
    quran_edition = serializers.SlugField(required=False, max_length=64)
    style: Any = serializers.ChoiceField(
        choices=list(RecitationStyle.choices),
        required=False,
    )


class TrackListQuerySerializer(PublicCatalogPageQuerySerializer):
    page_size = serializers.IntegerField(required=False, min_value=1, max_value=114)
    scope = serializers.ChoiceField(choices=list(AudioTrackScope.choices), required=False)
