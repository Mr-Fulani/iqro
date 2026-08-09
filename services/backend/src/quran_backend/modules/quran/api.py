from __future__ import annotations

import hashlib
import json
from collections.abc import Sequence
from typing import TYPE_CHECKING, Any

from django.core.serializers.json import DjangoJSONEncoder
from django.db.models import QuerySet
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import generics
from rest_framework.authentication import BaseAuthentication
from rest_framework.permissions import AllowAny
from rest_framework.request import Request
from rest_framework.response import Response

if TYPE_CHECKING:
    from rest_framework.permissions import _PermissionClass

from quran_backend.modules.quran.models import Ayah, Juz, MushafPage, QuranEdition, Surah
from quran_backend.modules.quran.selectors import (
    published_ayahs,
    published_editions,
    published_juz,
    published_pages,
    published_surahs,
)
from quran_backend.modules.quran.serializers import (
    AyahSerializer,
    JuzSerializer,
    MushafPageSerializer,
    QuranEditionSerializer,
    SurahSerializer,
)


class PublicQuranViewMixin:
    authentication_classes: Sequence[type[BaseAuthentication]] = ()
    permission_classes: Sequence[_PermissionClass] = (AllowAny,)

    def finalize_response(
        self,
        request: Request,
        response: Response,
        *args: Any,
        **kwargs: Any,
    ) -> Response:
        if response.status_code == 200 and response.data is not None:
            payload = json.dumps(
                response.data,
                cls=DjangoJSONEncoder,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            ).encode()
            etag = f'"{hashlib.sha256(payload).hexdigest()}"'
            if request.headers.get("If-None-Match") == etag:
                response = Response(status=304)
            response["ETag"] = etag
            response["Cache-Control"] = "public, max-age=300, stale-while-revalidate=86400"
        return super().finalize_response(request, response, *args, **kwargs)  # type: ignore[misc,no-any-return]


@extend_schema(tags=["quran"])
class QuranEditionListView(PublicQuranViewMixin, generics.ListAPIView[QuranEdition]):
    serializer_class = QuranEditionSerializer
    pagination_class = None

    def get_queryset(self) -> QuerySet[QuranEdition]:
        return published_editions()


@extend_schema(tags=["quran"])
class QuranEditionDetailView(PublicQuranViewMixin, generics.RetrieveAPIView[QuranEdition]):
    serializer_class = QuranEditionSerializer
    lookup_field = "code"
    lookup_url_kwarg = "edition"

    def get_queryset(self) -> QuerySet[QuranEdition]:
        return published_editions()


@extend_schema(
    tags=["quran"],
    parameters=[OpenApiParameter("edition", str, OpenApiParameter.PATH)],
)
class SurahListView(PublicQuranViewMixin, generics.ListAPIView[Surah]):
    serializer_class = SurahSerializer
    pagination_class = None

    def get_queryset(self) -> QuerySet[Surah]:
        return published_surahs(self.kwargs["edition"])


@extend_schema(
    tags=["quran"],
    parameters=[
        OpenApiParameter("edition", str, OpenApiParameter.PATH),
        OpenApiParameter("surah", int, OpenApiParameter.PATH),
    ],
)
class SurahDetailView(PublicQuranViewMixin, generics.RetrieveAPIView[Surah]):
    serializer_class = SurahSerializer
    lookup_field = "number"
    lookup_url_kwarg = "surah"

    def get_queryset(self) -> QuerySet[Surah]:
        return published_surahs(self.kwargs["edition"])


@extend_schema(
    tags=["quran"],
    parameters=[
        OpenApiParameter("edition", str, OpenApiParameter.PATH),
        OpenApiParameter("surah", int, OpenApiParameter.PATH),
    ],
)
class AyahListView(PublicQuranViewMixin, generics.ListAPIView[Ayah]):
    serializer_class = AyahSerializer
    pagination_class = None

    def get_queryset(self) -> QuerySet[Ayah]:
        return published_ayahs(self.kwargs["edition"], self.kwargs["surah"])


@extend_schema(
    tags=["quran"],
    parameters=[
        OpenApiParameter("edition", str, OpenApiParameter.PATH),
        OpenApiParameter("surah", int, OpenApiParameter.PATH),
        OpenApiParameter("ayah", int, OpenApiParameter.PATH),
    ],
)
class AyahDetailView(PublicQuranViewMixin, generics.RetrieveAPIView[Ayah]):
    serializer_class = AyahSerializer
    lookup_field = "number"
    lookup_url_kwarg = "ayah"

    def get_queryset(self) -> QuerySet[Ayah]:
        return published_ayahs(self.kwargs["edition"], self.kwargs["surah"])


@extend_schema(
    tags=["quran"],
    parameters=[
        OpenApiParameter("edition", str, OpenApiParameter.PATH),
        OpenApiParameter("page", int, OpenApiParameter.PATH),
    ],
)
class MushafPageDetailView(PublicQuranViewMixin, generics.RetrieveAPIView[MushafPage]):
    serializer_class = MushafPageSerializer
    lookup_field = "number"
    lookup_url_kwarg = "page"

    def get_queryset(self) -> QuerySet[MushafPage]:
        return published_pages(self.kwargs["edition"])


@extend_schema(
    tags=["quran"],
    parameters=[OpenApiParameter("edition", str, OpenApiParameter.PATH)],
)
class JuzListView(PublicQuranViewMixin, generics.ListAPIView[Juz]):
    serializer_class = JuzSerializer
    pagination_class = None

    def get_queryset(self) -> QuerySet[Juz]:
        return published_juz(self.kwargs["edition"])
