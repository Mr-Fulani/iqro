from __future__ import annotations

from rest_framework import serializers

from quran_backend.modules.tafsirs.models import (
    AyahTafsir,
    TafsirEdition,
    TafsirEditionVersion,
)


class TafsirEditionVersionSerializer(serializers.ModelSerializer[TafsirEditionVersion]):
    class Meta:
        model = TafsirEditionVersion
        fields = (
            "sync_sequence",
            "schema_version",
            "checksum_sha256",
            "record_count",
            "covered_ayah_count",
            "published_at",
        )


class TafsirEditionSerializer(serializers.ModelSerializer[TafsirEdition]):
    active_version = TafsirEditionVersionSerializer(read_only=True)
    source = serializers.SerializerMethodField()  # type: ignore[assignment]

    class Meta:
        model = TafsirEdition
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

    def get_source(self, obj: TafsirEdition) -> dict[str, str]:
        return {
            "name": obj.source_name,
            "url": obj.source_url,
            "license_name": obj.license_name,
            "license_url": obj.license_url,
            "attribution": obj.attribution,
        }


class AyahTafsirSerializer(serializers.ModelSerializer[AyahTafsir]):
    text = serializers.CharField(source="resolved_text", read_only=True)

    class Meta:
        model = AyahTafsir
        fields = (
            "verse_key",
            "surah_number",
            "ayah_number",
            "start_verse_key",
            "end_verse_key",
            "start_surah_number",
            "start_ayah_number",
            "end_surah_number",
            "end_ayah_number",
            "group_verses_count",
            "text",
        )
