from __future__ import annotations

import secrets

from django.conf import settings
from django.core.cache import caches
from django.db import connection
from django.http import HttpResponse
from drf_spectacular.utils import OpenApiResponse, extend_schema
from rest_framework.authentication import BaseAuthentication
from rest_framework.permissions import AllowAny, BasePermission
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from quran_backend.modules.audio.operations import quran_foundation_operational_summary
from quran_backend.modules.core.metrics import render_platform_metrics


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
            "cache": self._cache_ready("default"),
            "throttling": self._cache_ready("throttling"),
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
    def _cache_ready(alias: str) -> bool:
        role_cache = caches[alias]
        key = f"health:ready:{alias}"
        try:
            role_cache.set(key, "ok", timeout=5)
            ready = role_cache.get(key) == "ok"
            role_cache.delete(key)
        except Exception:
            return False
        return bool(ready)


class OperationsViewBase(APIView):
    authentication_classes: list[type[BaseAuthentication]] = []
    permission_classes: list[type[BasePermission]] = [AllowAny]

    @staticmethod
    def authorization_error(request: Request) -> Response | None:
        expected_token = settings.QURAN_OPERATIONS_TOKEN
        if not expected_token:
            return Response({"detail": "Not found."}, status=404)
        scheme, separator, supplied_token = request.headers.get("Authorization", "").partition(" ")
        if (
            separator != " "
            or scheme.casefold() != "bearer"
            or not supplied_token
            or not secrets.compare_digest(supplied_token, expected_token)
        ):
            response = Response(
                {"detail": "Valid operations credentials are required."},
                status=401,
            )
            response["WWW-Authenticate"] = "Bearer"
            return response
        return None


class OperationalHealthView(OperationsViewBase):
    @extend_schema(
        operation_id="health_operations",
        tags=["health"],
        responses={
            200: OpenApiResponse(description="Optional integrations are healthy or disabled."),
            401: OpenApiResponse(description="Operations credentials are missing or invalid."),
            503: OpenApiResponse(description="At least one optional integration is degraded."),
        },
    )
    def get(self, request: Request) -> Response:
        authorization_error = self.authorization_error(request)
        if authorization_error is not None:
            return authorization_error
        summary = quran_foundation_operational_summary()
        response = Response(
            {
                "status": summary.status,
                "components": {"quran_foundation_audio": summary.as_dict()},
            },
            status=503 if summary.status == "degraded" else 200,
        )
        response["Cache-Control"] = "private, no-store"
        return response


class MetricsView(OperationsViewBase):
    @extend_schema(exclude=True)
    def get(self, request: Request) -> Response | HttpResponse:
        authorization_error = self.authorization_error(request)
        if authorization_error is not None:
            return authorization_error
        summary = quran_foundation_operational_summary()
        payload, content_type = render_platform_metrics(summary, app_version=settings.APP_VERSION)
        response = HttpResponse(payload, content_type=content_type)
        response["Cache-Control"] = "private, no-store"
        return response
