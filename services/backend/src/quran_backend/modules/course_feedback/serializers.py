from __future__ import annotations

from typing import Any

from rest_framework import serializers

from quran_backend.modules.announcements.models import PLATFORMS
from quran_backend.modules.course_feedback.models import MAX_COMMENT_CHARS, CourseStatEvent
from quran_backend.modules.courses.models import COURSE_LANGUAGES
from quran_backend.modules.feedback.serializers import validate_plain_text

MAX_EVENTS_PER_BATCH = 50


class CourseEventSerializer(serializers.Serializer[Any]):
    course = serializers.SlugField(max_length=64)
    lesson = serializers.SlugField(max_length=64)
    event = serializers.ChoiceField(choices=CourseStatEvent.choices)


class CourseEventBatchSerializer(serializers.Serializer[Any]):
    platform = serializers.ChoiceField(choices=PLATFORMS)
    events = CourseEventSerializer(many=True, allow_empty=False)

    def validate_events(self, value: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if len(value) > MAX_EVENTS_PER_BATCH:
            raise serializers.ValidationError(f"Send at most {MAX_EVENTS_PER_BATCH} events.")
        return value


class CourseEventResultSerializer(serializers.Serializer[Any]):
    accepted = serializers.IntegerField()


class CourseRatingSerializer(serializers.Serializer[Any]):
    stars = serializers.IntegerField(min_value=1, max_value=5)
    comment = serializers.CharField(
        max_length=MAX_COMMENT_CHARS, required=False, allow_blank=True, default=""
    )
    language = serializers.ChoiceField(choices=COURSE_LANGUAGES)
    platform = serializers.ChoiceField(choices=PLATFORMS)

    def validate_comment(self, value: str) -> str:
        return validate_plain_text(value)
