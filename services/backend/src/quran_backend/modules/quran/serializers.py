from __future__ import annotations

from typing import Any

from django.conf import settings
from rest_framework import serializers

from quran_backend.modules.quran.models import (
    Ayah,
    AyahPageRegion,
    Hizb,
    Juz,
    MushafPage,
    QuranEdition,
    QuranEditionVersion,
    QuranFoundationMushaf,
    QuranFoundationMushafPage,
    RubElHizb,
    Surah,
)
from quran_backend.modules.quran.quran_foundation_native import (
    native_page_assets,
    native_rendering_catalog,
)
from quran_backend.modules.quran.quran_foundation_rendering import (
    quran_foundation_rendering,
)


class QuranEditionVersionSerializer(serializers.ModelSerializer[QuranEditionVersion]):
    class Meta:
        model = QuranEditionVersion
        fields = (
            "id",
            "version",
            "checksum_sha256",
            "page_count",
            "surah_count",
            "juz_count",
            "hizb_count",
            "rub_el_hizb_count",
            "published_at",
        )


class QuranEditionSerializer(serializers.ModelSerializer[QuranEdition]):
    active_version = QuranEditionVersionSerializer(read_only=True)

    class Meta:
        model = QuranEdition
        fields = (
            "id",
            "code",
            "name_ar",
            "name_en",
            "name_ru",
            "riwayah",
            "source_name",
            "source_url",
            "license_name",
            "license_url",
            "active_version",
        )


class SurahSerializer(serializers.ModelSerializer[Surah]):
    first_page = serializers.IntegerField(read_only=True, allow_null=True)

    class Meta:
        model = Surah
        fields = (
            "id",
            "number",
            "name_ar",
            "name_en",
            "name_ru",
            "revelation_type",
            "ayah_count",
            "first_page",
        )


class AyahSerializer(serializers.ModelSerializer[Ayah]):
    surah_number = serializers.IntegerField(source="surah.number", read_only=True)
    edition_code = serializers.CharField(
        source="surah.edition_version.edition.code",
        read_only=True,
    )
    content_version = serializers.CharField(source="surah.edition_version.version", read_only=True)
    pages = serializers.SerializerMethodField()

    class Meta:
        model = Ayah
        fields = (
            "id",
            "edition_code",
            "content_version",
            "surah_number",
            "number",
            "text_uthmani",
            "juz_number",
            "hizb_number",
            "rub_el_hizb_number",
            "pages",
        )

    def get_pages(self, obj: Ayah) -> list[int]:
        return list(
            obj.page_regions.order_by("page__number")
            .values_list("page__number", flat=True)
            .distinct()
        )


class AyahReferenceSerializer(serializers.ModelSerializer[Ayah]):
    surah = serializers.IntegerField(source="surah.number", read_only=True)

    class Meta:
        model = Ayah
        fields = ("id", "surah", "number")


class AyahPageRegionSerializer(serializers.ModelSerializer[AyahPageRegion]):
    ayah = AyahReferenceSerializer(read_only=True)

    class Meta:
        model = AyahPageRegion
        fields = ("id", "ayah", "reading_order", "polygon", "x", "y", "width", "height")


class MushafPageSerializer(serializers.ModelSerializer[MushafPage]):
    edition_code = serializers.CharField(source="edition_version.edition.code", read_only=True)
    content_version = serializers.CharField(source="edition_version.version", read_only=True)
    assets = serializers.SerializerMethodField()
    regions = AyahPageRegionSerializer(many=True, read_only=True)

    class Meta:
        model = MushafPage
        fields = (
            "id",
            "edition_code",
            "content_version",
            "number",
            "image_width",
            "image_height",
            "checksum_sha256",
            "assets",
            "regions",
        )

    def get_assets(self, obj: MushafPage) -> list[dict[str, Any]]:
        base_url = settings.PUBLIC_MEDIA_BASE_URL.rstrip("/")
        assets: list[dict[str, Any]] = []
        for variant in obj.asset_variants:
            public_variant = dict(variant)
            public_variant["url"] = f"{base_url}/{str(variant['path']).lstrip('/')}"
            public_variant.pop("path", None)
            assets.append(public_variant)
        return assets


class QuranFoundationMushafSerializer(serializers.ModelSerializer[QuranFoundationMushaf]):
    source = serializers.SerializerMethodField()  # type: ignore[assignment]
    rendering = serializers.SerializerMethodField()
    native_rendering = serializers.SerializerMethodField()

    class Meta:
        model = QuranFoundationMushaf
        fields = (
            "source_id",
            "name",
            "description",
            "qirat_name",
            "pages_count",
            "lines_per_page",
            "default_font_name",
            "mapping_mode",
            "schema_version",
            "sync_sequence",
            "source_checksum_sha256",
            "last_synced_at",
            "rendering",
            "native_rendering",
            "source",
        )

    def get_rendering(self, obj: QuranFoundationMushaf) -> dict[str, Any]:
        return quran_foundation_rendering(obj.source_id)

    def get_native_rendering(self, obj: QuranFoundationMushaf) -> dict[str, Any]:
        return native_rendering_catalog(obj)

    def get_source(self, obj: QuranFoundationMushaf) -> dict[str, str]:  # noqa: ARG002
        return {
            "name": "Quran.Foundation Content API",
            "url": "https://api-docs.quran.foundation/docs/content_apis_versioned/4.0.0/resources-sync/",
            "attribution": "Quran data provided by Quran Foundation.",
        }


class QuranFoundationMushafPageSerializer(serializers.ModelSerializer[QuranFoundationMushafPage]):
    mushaf_id = serializers.IntegerField(source="mushaf.source_id", read_only=True)
    qirat_name = serializers.CharField(source="mushaf.qirat_name", read_only=True)
    font_name = serializers.CharField(source="mushaf.default_font_name", read_only=True)
    rendering = serializers.SerializerMethodField()
    native_rendering = serializers.SerializerMethodField()
    native_assets = serializers.SerializerMethodField()

    class Meta:
        model = QuranFoundationMushafPage
        fields = (
            "mushaf_id",
            "qirat_name",
            "font_name",
            "rendering",
            "native_rendering",
            "native_assets",
            "page_number",
            "verse_mapping",
            "first_verse_id",
            "last_verse_id",
            "first_word_id",
            "last_word_id",
            "verses_count",
            "words",
        )

    def get_rendering(self, obj: QuranFoundationMushafPage) -> dict[str, Any]:
        return quran_foundation_rendering(
            obj.mushaf.source_id,
            page_number=obj.page_number,
        )

    def get_native_rendering(self, obj: QuranFoundationMushafPage) -> dict[str, Any]:
        return native_rendering_catalog(obj.mushaf)

    def get_native_assets(self, obj: QuranFoundationMushafPage) -> list[dict[str, Any]]:
        return native_page_assets(
            obj,
            public_media_base_url=settings.PUBLIC_MEDIA_BASE_URL,
        )


class OfflineMushafManifestQuerySerializer(serializers.Serializer[Any]):
    width = serializers.IntegerField(min_value=1, required=False)


class OfflineMushafAssetSerializer(serializers.Serializer[Any]):
    url = serializers.URLField()
    file_name = serializers.CharField()
    content_type = serializers.CharField()
    width = serializers.IntegerField(min_value=1)
    height = serializers.IntegerField(min_value=1)
    bytes = serializers.IntegerField(min_value=1)
    sha256 = serializers.CharField()


class OfflineMushafPageSerializer(serializers.Serializer[Any]):
    number = serializers.IntegerField(min_value=1)
    metadata_url = serializers.URLField()
    asset = OfflineMushafAssetSerializer()


class OfflineMushafIdentitySerializer(serializers.Serializer[Any]):
    source_id = serializers.IntegerField(min_value=1, allow_null=True)
    edition_code = serializers.CharField(allow_null=True)
    name = serializers.CharField()
    qirat_name = serializers.CharField()
    lines_per_page = serializers.IntegerField(min_value=1, allow_null=True)


class OfflineMushafSourceSerializer(serializers.Serializer[Any]):
    name = serializers.CharField()
    url = serializers.URLField(allow_blank=True)
    checksum_sha256 = serializers.CharField()


class OfflineMushafRightsSerializer(serializers.Serializer[Any]):
    offline_download = serializers.BooleanField()
    attribution_required = serializers.BooleanField()
    attribution = serializers.CharField()
    license_name = serializers.CharField(allow_blank=True)
    license_url = serializers.URLField(allow_blank=True)


class OfflineMushafManifestSerializer(serializers.Serializer[Any]):
    schema_version = serializers.IntegerField(min_value=1)
    package_type = serializers.CharField()
    package_id = serializers.CharField()
    version = serializers.CharField()
    package_checksum_sha256 = serializers.CharField()
    publication_checksum_sha256 = serializers.CharField()
    published_at = serializers.DateTimeField()
    source: Any = OfflineMushafSourceSerializer()
    rights = OfflineMushafRightsSerializer()
    mushaf = OfflineMushafIdentitySerializer()
    width = serializers.IntegerField(min_value=1)
    page_count = serializers.IntegerField(min_value=1)
    total_bytes = serializers.IntegerField(min_value=1)
    pages = OfflineMushafPageSerializer(many=True)


class JuzSerializer(serializers.ModelSerializer[Juz]):
    start_ayah = AyahReferenceSerializer(read_only=True)
    end_ayah = AyahReferenceSerializer(read_only=True)
    start_page = serializers.IntegerField(read_only=True)
    end_page = serializers.IntegerField(read_only=True)

    class Meta:
        model = Juz
        fields = ("id", "number", "start_ayah", "end_ayah", "start_page", "end_page")


class HizbSerializer(serializers.ModelSerializer[Hizb]):
    start_ayah = AyahReferenceSerializer(read_only=True)
    end_ayah = AyahReferenceSerializer(read_only=True)
    start_page = serializers.IntegerField(read_only=True)
    end_page = serializers.IntegerField(read_only=True)

    class Meta:
        model = Hizb
        fields = ("id", "number", "start_ayah", "end_ayah", "start_page", "end_page")


class RubElHizbSerializer(serializers.ModelSerializer[RubElHizb]):
    hizb_number = serializers.IntegerField(source="hizb.number", read_only=True)
    quarter_number = serializers.SerializerMethodField()
    start_ayah = AyahReferenceSerializer(read_only=True)
    end_ayah = AyahReferenceSerializer(read_only=True)
    start_page = serializers.IntegerField(read_only=True)
    end_page = serializers.IntegerField(read_only=True)

    class Meta:
        model = RubElHizb
        fields = (
            "id",
            "number",
            "hizb_number",
            "quarter_number",
            "start_ayah",
            "end_ayah",
            "start_page",
            "end_page",
        )

    def get_quarter_number(self, obj: RubElHizb) -> int:
        return (obj.number - 1) % 4 + 1
