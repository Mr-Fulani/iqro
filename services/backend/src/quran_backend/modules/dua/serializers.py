from __future__ import annotations

from typing import Any

from rest_framework import serializers

from quran_backend.modules.dua.models import (
    DuaAudioAsset,
    DuaCategory,
    DuaCollection,
    DuaEntry,
    DuaEvidence,
    DuaSourceEdition,
)


class DuaAudioAssetSerializer(serializers.ModelSerializer[DuaAudioAsset]):
    class Meta:
        model = DuaAudioAsset
        fields = (
            "id",
            "language_code",
            "provider",
            "reader_name",
            "reader_name_ar",
            "url",
            "source_url",
            "rights_url",
            "source_version",
        )


class DuaSourceEditionSerializer(serializers.ModelSerializer[DuaSourceEdition]):
    class Meta:
        model = DuaSourceEdition
        fields = (
            "language_code",
            "provider",
            "source_item_id",
            "title",
            "author",
            "translator",
            "reviewer",
            "source_url",
            "rights_url",
            "source_version",
        )


class DuaEvidenceSerializer(serializers.ModelSerializer[DuaEvidence]):
    class Meta:
        model = DuaEvidence
        fields = (
            "kind",
            "provider",
            "source_name",
            "source_reference",
            "source_url",
            "grade",
            "external_id",
            "verification_status",
        )


def _first_localized(obj: Any, attribute: str) -> Any | None:
    values = getattr(obj, attribute, ())
    return values[0] if values else None


class DuaCollectionSerializer(serializers.ModelSerializer[DuaCollection]):
    version = serializers.CharField(source="active_version.version", read_only=True)
    schema_version = serializers.IntegerField(
        source="active_version.schema_version",
        read_only=True,
    )
    category_count = serializers.IntegerField(
        source="active_version.category_count",
        read_only=True,
    )
    entry_count = serializers.IntegerField(
        source="active_version.entry_count",
        read_only=True,
    )
    published_at = serializers.DateTimeField(
        source="active_version.published_at",
        read_only=True,
    )
    source = serializers.SerializerMethodField()  # type: ignore[assignment]

    class Meta:
        model = DuaCollection
        fields = (
            "id",
            "slug",
            "version",
            "schema_version",
            "category_count",
            "entry_count",
            "published_at",
            "source",
        )

    def get_source(self, obj: DuaCollection) -> dict[str, Any] | None:
        source = _first_localized(obj.active_version, "localized_source_editions")
        return DuaSourceEditionSerializer(source).data if source else None


class DuaCategorySerializer(serializers.ModelSerializer[DuaCategory]):
    title = serializers.SerializerMethodField()
    entry_count = serializers.IntegerField(read_only=True)

    class Meta:
        model = DuaCategory
        fields = ("id", "source_number", "slug", "title", "entry_count")

    def get_title(self, obj: DuaCategory) -> str:
        translation = _first_localized(obj, "localized_category_translations")
        return translation.title if translation else obj.slug


class DuaEntrySerializer(serializers.ModelSerializer[DuaEntry]):
    category = serializers.SerializerMethodField()
    translation = serializers.SerializerMethodField()
    evidence = DuaEvidenceSerializer(many=True, read_only=True)
    source = serializers.SerializerMethodField()  # type: ignore[assignment]
    audio = serializers.SerializerMethodField()
    collection = serializers.CharField(
        source="collection_version.collection.slug",
        read_only=True,
    )
    collection_version = serializers.CharField(
        source="collection_version.version",
        read_only=True,
    )

    class Meta:
        model = DuaEntry
        fields = (
            "id",
            "source_number",
            "slug",
            "collection",
            "collection_version",
            "category",
            "arabic_text",
            "repetitions",
            "repetition_label",
            "translation",
            "evidence",
            "source",
            "audio",
        )

    def get_category(self, obj: DuaEntry) -> dict[str, Any]:
        translation = _first_localized(obj.category, "localized_category_translations")
        return {
            "source_number": obj.category.source_number,
            "slug": obj.category.slug,
            "title": translation.title if translation else obj.category.slug,
        }

    def get_translation(self, obj: DuaEntry) -> dict[str, str] | None:
        translation = _first_localized(obj, "localized_entry_translations")
        if not translation:
            return None
        return {
            "language_code": translation.language_code,
            "meaning_text": translation.meaning_text,
            "transliteration": translation.transliteration,
        }

    def get_source(self, obj: DuaEntry) -> dict[str, Any] | None:
        source = _first_localized(obj.collection_version, "localized_source_editions")
        return DuaSourceEditionSerializer(source).data if source else None

    def get_audio(self, obj: DuaEntry) -> list[dict[str, Any]]:
        assets = getattr(obj.collection_version.collection, "active_audio_assets", ())
        matching_assets = [asset for asset in assets if asset.source_number == obj.source_number]
        return list(DuaAudioAssetSerializer(matching_assets, many=True).data)


class DuaFavoriteWriteSerializer(serializers.Serializer[dict[str, Any]]):
    is_favorite = serializers.BooleanField()


class DuaFavoriteSerializer(serializers.Serializer[dict[str, Any]]):
    id = serializers.UUIDField(allow_null=True)
    collection = serializers.CharField()
    source_number = serializers.IntegerField(min_value=1)
    is_favorite = serializers.BooleanField()
    created_at = serializers.DateTimeField(allow_null=True)
    entry = DuaEntrySerializer(allow_null=True, required=False)


class DuaFavoriteListSerializer(serializers.Serializer[dict[str, Any]]):
    results = DuaFavoriteSerializer(many=True)
