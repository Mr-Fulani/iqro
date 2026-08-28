from __future__ import annotations

from typing import NoReturn, cast

from django.db.models import QuerySet
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import generics, status
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.throttling import BaseThrottle
from rest_framework.views import APIView

from quran_backend.modules.accounts.models import User
from quran_backend.modules.core.privacy import PrivateNoStoreResponseMixin
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
    DuaFavoriteListSerializer,
    DuaFavoriteSerializer,
    DuaFavoriteWriteSerializer,
)
from quran_backend.modules.dua.services import (
    DuaFavoriteTargetNotFoundError,
    list_dua_favorites,
    set_dua_favorite,
)
from quran_backend.modules.reading.throttling import (
    ReadingMutationRateThrottle,
    ReadingRateLimitExceeded,
)

LANGUAGE_PARAMETER = OpenApiParameter(
    "language",
    str,
    OpenApiParameter.QUERY,
    enum=sorted(SUPPORTED_DUA_LANGUAGES),
    default="en",
    description="Localized source edition and meaning.",
)

FAVORITE_INCLUDE_PARAMETER = OpenApiParameter(
    "include",
    str,
    OpenApiParameter.QUERY,
    enum=["entry"],
    description="Set to entry to include the localized published Dua card.",
)


def selected_dua_language(request: Request) -> str:
    language = str(request.query_params.get("language", "en")).strip().lower()
    if language not in SUPPORTED_DUA_LANGUAGES:
        raise ValidationError({"language": "Supported values are ar, en, ru and tr."})
    return language


class PublicDuaViewMixin(PublicReadOnlyViewMixin):
    def selected_language(self) -> str:
        request = cast(Request, vars(self)["request"])
        return selected_dua_language(request)


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


@extend_schema(
    tags=["dua-favorites"],
    parameters=[LANGUAGE_PARAMETER, FAVORITE_INCLUDE_PARAMETER],
)
class DuaFavoriteListView(PrivateNoStoreResponseMixin, APIView):
    @extend_schema(
        operation_id="dua_favorites_list",
        responses={
            status.HTTP_200_OK: DuaFavoriteListSerializer,
            status.HTTP_401_UNAUTHORIZED: None,
        },
    )
    def get(self, request: Request) -> Response:
        snapshot = list_dua_favorites(cast(User, request.user))
        include = str(request.query_params.get("include", "")).strip().lower()
        if include not in {"", "entry"}:
            raise ValidationError({"include": "Supported value is entry."})
        if include != "entry" or not snapshot["results"]:
            return Response(snapshot)

        language = selected_dua_language(request)
        favorite_keys = {
            (item["collection"], item["source_number"]) for item in snapshot["results"]
        }
        entries = published_dua_entries(language).filter(
            collection_version__collection__slug__in={key[0] for key in favorite_keys},
            source_number__in={key[1] for key in favorite_keys},
        )
        serialized_entries = DuaEntrySerializer(entries, many=True).data
        entries_by_key = {
            (entry["collection"], entry["source_number"]): entry
            for entry in serialized_entries
            if (entry["collection"], entry["source_number"]) in favorite_keys
        }
        return Response(
            {
                "results": [
                    {
                        **item,
                        "entry": entries_by_key.get((item["collection"], item["source_number"])),
                    }
                    for item in snapshot["results"]
                ]
            }
        )


@extend_schema(tags=["dua-favorites"])
class DuaFavoriteDetailView(PrivateNoStoreResponseMixin, APIView):
    def get_throttles(self) -> list[BaseThrottle]:
        return [ReadingMutationRateThrottle()]

    def throttled(self, request: Request, wait: float | None) -> NoReturn:  # noqa: ARG002
        raise ReadingRateLimitExceeded(wait)

    @extend_schema(
        operation_id="dua_favorite_set",
        request=DuaFavoriteWriteSerializer,
        responses={
            status.HTTP_200_OK: DuaFavoriteSerializer,
            status.HTTP_400_BAD_REQUEST: None,
            status.HTTP_401_UNAUTHORIZED: None,
            status.HTTP_404_NOT_FOUND: None,
            status.HTTP_429_TOO_MANY_REQUESTS: None,
        },
    )
    def put(
        self,
        request: Request,
        collection_slug: str,
        source_number: int,
    ) -> Response:
        serializer = DuaFavoriteWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            snapshot = set_dua_favorite(
                user=cast(User, request.user),
                collection_slug=collection_slug,
                source_number=source_number,
                is_favorite=serializer.validated_data["is_favorite"],
            )
        except DuaFavoriteTargetNotFoundError as exc:
            raise NotFound("The published Dua entry was not found.") from exc
        return Response(snapshot)
