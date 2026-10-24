from __future__ import annotations

from django.urls import path

from quran_backend.modules.course_feedback.api import CourseEventsView, CourseRatingView

app_name = "course_feedback"

# Included before the courses module: «events» is a reserved course slug.
urlpatterns = [
    path("courses/events", CourseEventsView.as_view(), name="events"),
    path("courses/<slug:slug>/rating", CourseRatingView.as_view(), name="rating"),
]
