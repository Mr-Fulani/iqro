from __future__ import annotations

from typing import cast

from django.db.models import QuerySet
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import generics
from rest_framework.exceptions import ValidationError
from rest_framework.request import Request

from quran_backend.modules.core.public_api import PublicReadOnlyViewMixin
from quran_backend.modules.dua.importer import SUPPORTED_DUA_LANGUAGES
from quran_backend.modules.dua.models import DuaCategory, DuaCollection, DuaEntry
from quran_backend.modules.dua.pagination import DuaEntryCursorPagination
from quran_backend.modules.dua.selectors import (
    published_dua_categories,
    published_dua_collections,
    published_dua_entries,
)
from quran_backend.modules.dua.serializers import (
    DuaCategorySerializer,
    DuaCollectionSerializer,
    DuaEntrySerializer,
)

LANGUAGE_PARAMETER = OpenApiParameter(
    "language",
    str,
    OpenApiParameter.QUERY,
    enum=sorted(SUPPORTED_DUA_LANGUAGES),
    default="en",
    description="Localized source edition and meaning.",
)


class PublicDuaViewMixin(PublicReadOnlyViewMixin):
    def selected_language(self) -> str:
        request = cast(Request, vars(self)["request"])
        language = str(request.query_params.get("language", "en")).strip().lower()
        if language not in SUPPORTED_DUA_LANGUAGES:
            raise ValidationError({"language": "Supported values are ar, en, ru and tr."})
        return language


@extend_schema(tags=["dua"], parameters=[LANGUAGE_PARAMETER])
class DuaCollectionListView(PublicDuaViewMixin, generics.ListAPIView[DuaCollection]):
    serializer_class = DuaCollectionSerializer
    pagination_class = None

    def get_queryset(self) -> QuerySet[DuaCollection]:
        return published_dua_collections(self.selected_language())


@extend_schema(tags=["dua"], parameters=[LANGUAGE_PARAMETER])
class DuaCategoryListView(PublicDuaViewMixin, generics.ListAPIView[DuaCategory]):
    serializer_class = DuaCategorySerializer
    pagination_class = None

    def get_queryset(self) -> QuerySet[DuaCategory]:
        return published_dua_categories(self.selected_language())


@extend_schema(
    tags=["dua"],
    parameters=[
        LANGUAGE_PARAMETER,
        OpenApiParameter("category", str, OpenApiParameter.QUERY),
        OpenApiParameter("q", str, OpenApiParameter.QUERY),
    ],
)
class DuaEntryListView(PublicDuaViewMixin, generics.ListAPIView[DuaEntry]):
    serializer_class = DuaEntrySerializer
    pagination_class = DuaEntryCursorPagination

    def get_queryset(self) -> QuerySet[DuaEntry]:
        query = self.request.query_params.get("q", "").strip()
        if len(query) > 120:
            raise ValidationError({"q": "Search text must not exceed 120 characters."})
        category = self.request.query_params.get("category", "").strip()
        if len(category) > 120:
            raise ValidationError({"category": "Category slug is too long."})
        return published_dua_entries(
            self.selected_language(),
            category=category,
            query=query,
        )


@extend_schema(tags=["dua"], parameters=[LANGUAGE_PARAMETER])
class DuaEntryDetailView(PublicDuaViewMixin, generics.RetrieveAPIView[DuaEntry]):
    serializer_class = DuaEntrySerializer

    def get_queryset(self) -> QuerySet[DuaEntry]:
        return published_dua_entries(self.selected_language())
