from __future__ import annotations

from django.conf import settings
from django.http import Http404
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from quran_backend.modules.core.public_api import PublicReadOnlyViewMixin
from quran_backend.modules.tajweed.models import TajweedEdition
from quran_backend.modules.tajweed.rules import RULE_ORDER, rules_reference
from quran_backend.modules.tajweed.selectors import (
    published_tajweed_ayahs,
    published_tajweed_edition,
)
from quran_backend.modules.tajweed.serializers import (
    AyahTajweedSerializer,
    TajweedAyahResponseSerializer,
    TajweedPageResponseSerializer,
    TajweedRulesResponseSerializer,
    tajweed_source,
)


def _edition() -> TajweedEdition:
    edition = published_tajweed_edition(settings.QURAN_QF_ENV)
    if edition is None:
        raise Http404
    return edition


@extend_schema(tags=["quran"], responses=TajweedRulesResponseSerializer)
class TajweedRuleListView(PublicReadOnlyViewMixin, APIView):
    def get(self, request: Request) -> Response:  # noqa: ARG002
        return Response(rules_reference())


@extend_schema(
    tags=["quran"],
    parameters=[OpenApiParameter("page", int, OpenApiParameter.PATH)],
    responses=TajweedPageResponseSerializer,
)
class TajweedPageView(PublicReadOnlyViewMixin, APIView):
    def get(self, request: Request, page: int) -> Response:  # noqa: ARG002
        edition = _edition()
        ayahs = list(published_tajweed_ayahs(edition).filter(page_number=page))
        if not ayahs:
            raise Http404
        codes = {code for ayah in ayahs for code in ayah.rules}
        return Response(
            {
                "page_number": page,
                "rules": sorted(codes, key=RULE_ORDER.__getitem__),
                "ayahs": AyahTajweedSerializer(ayahs, many=True).data,
                "source": tajweed_source(edition),
            }
        )


@extend_schema(
    tags=["quran"],
    parameters=[
        OpenApiParameter("surah", int, OpenApiParameter.PATH),
        OpenApiParameter("ayah", int, OpenApiParameter.PATH),
    ],
    responses=TajweedAyahResponseSerializer,
)
class TajweedAyahView(PublicReadOnlyViewMixin, APIView):
    def get(self, request: Request, surah: int, ayah: int) -> Response:  # noqa: ARG002
        edition = _edition()
        row = published_tajweed_ayahs(edition).filter(surah_number=surah, ayah_number=ayah).first()
        if row is None:
            raise Http404
        return Response({**AyahTajweedSerializer(row).data, "source": tajweed_source(edition)})
