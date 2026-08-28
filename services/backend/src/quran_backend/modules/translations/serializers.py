from __future__ import annotations

from rest_framework import serializers

from quran_backend.modules.translations.models import (
    AyahTranslation,
    TranslationEdition,
    TranslationEditionVersion,
)


class TranslationEditionVersionSerializer(serializers.ModelSerializer[TranslationEditionVersion]):
    class Meta:
        model = TranslationEditionVersion
        fields = (
            "sync_sequence",
            "schema_version",
            "checksum_sha256",
            "ayah_count",
            "published_at",
        )


class TranslationEditionSerializer(serializers.ModelSerializer[TranslationEdition]):
    active_version = TranslationEditionVersionSerializer(read_only=True)
    source = serializers.SerializerMethodField()  # type: ignore[assignment]

    class Meta:
        model = TranslationEdition
        fields = (
            "source_id",
            "slug",
            "language_code",
            "language_name",
            "name",
            "author_name",
            "active_version",
            "source",
        )

    def get_source(self, obj: TranslationEdition) -> dict[str, str]:
        return {
            "name": obj.source_name,
            "url": obj.source_url,
            "license_name": obj.license_name,
            "license_url": obj.license_url,
            "attribution": obj.attribution,
        }


class AyahTranslationSerializer(serializers.ModelSerializer[AyahTranslation]):
    class Meta:
        model = AyahTranslation
        fields = (
            "verse_key",
            "surah_number",
            "ayah_number",
            "text",
            "foot_notes",
        )
