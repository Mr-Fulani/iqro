from __future__ import annotations

from django.conf import settings
from django.db.models import QuerySet
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import generics

from quran_backend.modules.core.public_api import PublicReadOnlyViewMixin
from quran_backend.modules.translations.models import AyahTranslation, TranslationEdition
from quran_backend.modules.translations.selectors import (
    published_surah_translation,
    published_translation_editions,
)
from quran_backend.modules.translations.serializers import (
    AyahTranslationSerializer,
    TranslationEditionSerializer,
)


@extend_schema(
    tags=["quran-translations"],
    parameters=[
        OpenApiParameter(
            "language",
            str,
            OpenApiParameter.QUERY,
            required=False,
            description="Optional ISO 639-1 interface language filter.",
        )
    ],
)
class TranslationEditionListView(
    PublicReadOnlyViewMixin,
    generics.ListAPIView[TranslationEdition],
):
    serializer_class = TranslationEditionSerializer
    pagination_class = None

    def get_queryset(self) -> QuerySet[TranslationEdition]:
        return published_translation_editions(
            settings.QURAN_QF_ENV,
            language_code=self.request.query_params.get("language"),
        )


@extend_schema(
    tags=["quran-translations"],
    parameters=[
        OpenApiParameter("translation", int, OpenApiParameter.PATH),
        OpenApiParameter("surah", int, OpenApiParameter.PATH),
    ],
)
class SurahTranslationListView(
    PublicReadOnlyViewMixin,
    generics.ListAPIView[AyahTranslation],
):
    serializer_class = AyahTranslationSerializer
    pagination_class = None

    def get_queryset(self) -> QuerySet[AyahTranslation]:
        return published_surah_translation(
            settings.QURAN_QF_ENV,
            source_id=self.kwargs["translation"],
            surah_number=self.kwargs["surah"],
        )
