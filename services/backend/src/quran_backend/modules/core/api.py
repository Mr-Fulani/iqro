from __future__ import annotations

from django.conf import settings
from django.core.cache import cache
from django.db import connection
from drf_spectacular.utils import OpenApiResponse, extend_schema
from rest_framework.authentication import BaseAuthentication
from rest_framework.permissions import AllowAny, BasePermission
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView


class LiveHealthView(APIView):
    authentication_classes: list[type[BaseAuthentication]] = []
    permission_classes: list[type[BasePermission]] = [AllowAny]

    @extend_schema(
        operation_id="health_live",
        tags=["health"],
        responses={200: OpenApiResponse(description="The API process is alive.")},
    )
    def get(self, request: Request) -> Response:  # noqa: ARG002
        response = Response(
            {
                "status": "ok",
                "service": "quran-platform-backend",
                "version": settings.APP_VERSION,
            }
        )
        response["Cache-Control"] = "no-store"
        return response


class ReadyHealthView(APIView):
    authentication_classes: list[type[BaseAuthentication]] = []
    permission_classes: list[type[BasePermission]] = [AllowAny]

    @extend_schema(
        operation_id="health_ready",
        tags=["health"],
        responses={
            200: OpenApiResponse(description="All critical dependencies are ready."),
            503: OpenApiResponse(description="At least one critical dependency is unavailable."),
        },
    )
    def get(self, request: Request) -> Response:  # noqa: ARG002
        components = {
            "database": self._database_ready(),
            "cache": self._cache_ready(),
        }
        ready = all(components.values())
        response = Response(
            {"status": "ok" if ready else "unavailable", "components": components},
            status=200 if ready else 503,
        )
        response["Cache-Control"] = "no-store"
        return response

    @staticmethod
    def _database_ready() -> bool:
        try:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1")
                row = cursor.fetchone()
        except Exception:
            return False
        return bool(row) and int(row[0]) == 1

    @staticmethod
    def _cache_ready() -> bool:
        key = "health:ready"
        try:
            cache.set(key, "ok", timeout=5)
            ready = cache.get(key) == "ok"
            cache.delete(key)
        except Exception:
            return False
        return bool(ready)
