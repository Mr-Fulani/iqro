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
    RubElHizb,
    Surah,
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
