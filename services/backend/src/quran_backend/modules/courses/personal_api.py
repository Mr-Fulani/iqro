# Russian interface strings intentionally contain Cyrillic letters.
# ruff: noqa: RUF001
"""The learner's own lesson progress of the prayer course and the thematic courses."""

from __future__ import annotations

from typing import Any

from drf_spectacular.utils import extend_schema
from rest_framework import serializers
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.permissions import BasePermission
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from quran_backend.modules.accounts.models import UserStatus
from quran_backend.modules.core.privacy import PrivateNoStoreResponseMixin
from quran_backend.modules.courses.models import LearnerProgressKind
from quran_backend.modules.courses.progress import (
    course_exists,
    merge_user_progress,
    user_progress,
)
from quran_backend.modules.tajweed.personal_api import TajweedMutationRateLimitMixin
from quran_backend.modules.tajweed.progress import TajweedProgressError


class AccountRequired(PermissionDenied):
    default_detail = "Прогресс курсов хранится только в аккаунте: войдите или зарегистрируйтесь."
    default_code = "account_required"


class IsAccount(BasePermission):
    """A guest's progress stays on the device; only a signed-in account keeps it here."""

    def has_permission(self, request: Request, view: Any) -> bool:  # noqa: ARG002
        user = request.user
        if not user or not user.is_authenticated:
            return False
        if getattr(user, "status", None) != UserStatus.ACTIVE:
            raise AccountRequired
        return True


class LessonProgressSerializer(serializers.Serializer[Any]):
    status = serializers.ChoiceField(choices=["in_progress", "completed"])
    step_slug = serializers.CharField(allow_blank=True)
    content_version = serializers.CharField()
    updated_at = serializers.DateTimeField()


class CourseProgressSerializer(serializers.Serializer[Any]):
    kind = serializers.ChoiceField(choices=LearnerProgressKind.choices, read_only=True)
    course = serializers.SlugField(read_only=True)
    lessons = serializers.DictField(child=LessonProgressSerializer())


@extend_schema(tags=["courses"])
class CourseProgressView(TajweedMutationRateLimitMixin, PrivateNoStoreResponseMixin, APIView):
    permission_classes = (IsAccount,)

    def _check(self, kind: str, course: str) -> None:
        if kind not in LearnerProgressKind.values or not course_exists(kind, course):
            raise NotFound("Курс не найден.")

    @extend_schema(operation_id="courses_progress_retrieve", responses=CourseProgressSerializer)
    def get(self, request: Request, kind: str, course: str) -> Response:
        self._check(kind, course)
        return Response(user_progress(request.user, kind, course))

    @extend_schema(
        operation_id="courses_progress_merge",
        request=CourseProgressSerializer,
        responses=CourseProgressSerializer,
        description="Сливает переданные уроки с сохранёнными: пройденный урок остаётся "
        "пройденным, иначе побеждает более поздняя запись. Ответ — итог слияния. "
        "`kind` — `salah`, `courses` или `names`. Только для аккаунта, гостю — 403.",
    )
    def put(self, request: Request, kind: str, course: str) -> Response:
        self._check(kind, course)
        data = request.data if isinstance(request.data, dict) else {}
        try:
            return Response(merge_user_progress(request.user, kind, course, data.get("lessons")))
        except TajweedProgressError as error:
            raise ValidationError({"lessons": str(error)}) from error
