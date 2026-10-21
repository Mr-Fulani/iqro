from __future__ import annotations

from typing import Any

from rest_framework import serializers

from quran_backend.modules.tajweed.models import AyahTajweed, TajweedEdition


class AyahTajweedSerializer(serializers.ModelSerializer[AyahTajweed]):
    class Meta:
        model = AyahTajweed
        fields = ("verse_key", "surah_number", "ayah_number", "page_number", "rules", "words")


def tajweed_source(edition: TajweedEdition) -> dict[str, Any]:
    version = edition.active_version
    return {
        "name": edition.source_name,
        "url": edition.source_url,
        "license_name": edition.license_name,
        "license_url": edition.license_url,
        "attribution": edition.attribution,
        "checksum_sha256": version.checksum_sha256 if version else "",
    }


class TajweedFragmentSchemaSerializer(serializers.Serializer[Any]):
    code = serializers.CharField()
    start = serializers.IntegerField(min_value=0)
    end = serializers.IntegerField(min_value=1)
    joins_previous = serializers.BooleanField(required=False)
    joins_next = serializers.BooleanField(required=False)
    variant = serializers.CharField(required=False)


class TajweedWordSchemaSerializer(serializers.Serializer[Any]):
    position = serializers.IntegerField(min_value=1)
    text = serializers.CharField()
    rules = TajweedFragmentSchemaSerializer(many=True)


class AyahTajweedSchemaSerializer(serializers.Serializer[Any]):
    verse_key = serializers.CharField()
    surah_number = serializers.IntegerField()
    ayah_number = serializers.IntegerField()
    page_number = serializers.IntegerField()
    rules = serializers.ListField(child=serializers.CharField())
    words = TajweedWordSchemaSerializer(many=True)


class TajweedSourceSchemaSerializer(serializers.Serializer[Any]):
    name = serializers.CharField()
    url = serializers.URLField()
    license_name = serializers.CharField()
    license_url = serializers.URLField()
    attribution = serializers.CharField()
    checksum_sha256 = serializers.CharField()


class TajweedAyahResponseSerializer(AyahTajweedSchemaSerializer):
    source: Any = TajweedSourceSchemaSerializer()


class TajweedPageResponseSerializer(serializers.Serializer[Any]):
    page_number = serializers.IntegerField()
    rules = serializers.ListField(child=serializers.CharField())
    ayahs = AyahTajweedSchemaSerializer(many=True)
    source: Any = TajweedSourceSchemaSerializer()


class TajweedVariantSchemaSerializer(serializers.Serializer[Any]):
    code = serializers.CharField()
    name = serializers.DictField(child=serializers.CharField())
    why = serializers.DictField(child=serializers.CharField())
    how = serializers.DictField(child=serializers.CharField())


class TajweedRuleSchemaSerializer(TajweedVariantSchemaSerializer):
    arabic_name = serializers.CharField()
    color = serializers.CharField()
    variants = TajweedVariantSchemaSerializer(many=True)


class TajweedRulesResponseSerializer(serializers.Serializer[Any]):
    version = serializers.CharField()
    review_status = serializers.CharField()
    languages = serializers.ListField(child=serializers.CharField())
    rules = TajweedRuleSchemaSerializer(many=True)
