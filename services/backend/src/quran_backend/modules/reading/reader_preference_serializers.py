from __future__ import annotations

from typing import Any

from rest_framework import serializers

from quran_backend.modules.core.serializers import StrictFieldsSerializer


class QuranReaderPreferenceWriteSerializer(StrictFieldsSerializer):
    base_revision = serializers.IntegerField(min_value=0)
    translation_enabled = serializers.BooleanField()
    translation_source_id = serializers.IntegerField(min_value=1, allow_null=True)
    tafsir_enabled = serializers.BooleanField()
    tafsir_source_id = serializers.IntegerField(min_value=1, allow_null=True)
    client_updated_at = serializers.DateTimeField()

    def validate(self, attrs: dict[str, Any]) -> dict[str, Any]:
        attrs = super().validate(attrs)
        if attrs["translation_enabled"] and attrs["translation_source_id"] is None:
            raise serializers.ValidationError(
                {"translation_source_id": "Select a translation before enabling it."}
            )
        if attrs["tafsir_enabled"] and attrs["tafsir_source_id"] is None:
            raise serializers.ValidationError(
                {"tafsir_source_id": "Select a Tafsir before enabling it."}
            )
        return attrs


class QuranReaderPreferenceResponseSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField(allow_null=True)
    locale = serializers.ChoiceField(choices=["ar", "en", "ru", "tr"])
    translation_enabled = serializers.BooleanField()
    translation_source_id = serializers.IntegerField(min_value=1, allow_null=True)
    tafsir_enabled = serializers.BooleanField()
    tafsir_source_id = serializers.IntegerField(min_value=1, allow_null=True)
    revision = serializers.IntegerField(min_value=0)
    client_updated_at = serializers.DateTimeField(allow_null=True)
    device_id = serializers.UUIDField(allow_null=True)
    created_at = serializers.DateTimeField(allow_null=True)
    updated_at = serializers.DateTimeField(allow_null=True)
