"""Public read-only API of the Names of Allah, shared by the app and the site.

The list is compiled at publication and stored per language, so a request is
one indexed row read; ETag/304 come from PublicReadOnlyViewMixin.
"""

from __future__ import annotations

from django.db.models import F
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from quran_backend.modules.core.public_api import PublicReadOnlyViewMixin
from quran_backend.modules.names.models import NAMES_LANGUAGES, NamesDocument, NamesStatus

LANGUAGE_PARAMETER = OpenApiParameter(
    "language", str, enum=list(NAMES_LANGUAGES), default="ru", description="Язык карточек."
)


@extend_schema(tags=["names"])
class NamesDocumentView(PublicReadOnlyViewMixin, APIView):
    @extend_schema(
        operation_id="names_collection_retrieve",
        parameters=[LANGUAGE_PARAMETER],
        responses=OpenApiTypes.OBJECT,
        description="Опубликованный список имён на одном языке (docs/names-of-allah/README.md).",
    )
    def get(self, request: Request, slug: str) -> Response:
        language = request.query_params.get("language", "ru")
        if language not in NAMES_LANGUAGES:
            raise ValidationError({"language": f"Поддерживаются: {', '.join(NAMES_LANGUAGES)}."})
        document = NamesDocument.objects.filter(
            version__status=NamesStatus.PUBLISHED,
            version__collection__active_version=F("version"),
            version__collection__slug=slug,
            language=language,
        ).first()
        if document is None:
            raise NotFound("Такого списка нет.")
        return Response(document.payload)
