from __future__ import annotations

from django.urls import path

from quran_backend.modules.reading.api import (
    BookmarkDetailView,
    BookmarkListCreateView,
    ReadingPositionView,
    SyncPullView,
    SyncPushView,
)
from quran_backend.modules.reading.habit_api import (
    AutomaticReadingSessionCreateView,
    ManualReadingSessionCreateView,
    ManualReadingSessionDetailView,
    PrayerReadingCheckInCreateView,
    PrayerReadingCheckInDetailView,
    PrayerReadingPlanView,
    ReadingGoalView,
    ReadingPlannerView,
    ReadingSessionListView,
    TodayView,
)
from quran_backend.modules.reading.reader_preference_api import QuranReaderPreferenceView

app_name = "reading"

urlpatterns = [
    path(
        "me/quran-reader-preferences/<str:locale>",
        QuranReaderPreferenceView.as_view(),
        name="quran-reader-preference",
    ),
    path(
        "me/reading-position/<slug:edition>",
        ReadingPositionView.as_view(),
        name="reading-position",
    ),
    path("me/bookmarks", BookmarkListCreateView.as_view(), name="bookmark-list"),
    path(
        "me/bookmarks/<uuid:bookmark_id>",
        BookmarkDetailView.as_view(),
        name="bookmark-detail",
    ),
    path("me/today", TodayView.as_view(), name="today"),
    path("me/reading-goal", ReadingGoalView.as_view(), name="reading-goal"),
    path("me/reading-planner", ReadingPlannerView.as_view(), name="reading-planner"),
    path(
        "me/prayer-reading-plan",
        PrayerReadingPlanView.as_view(),
        name="prayer-reading-plan",
    ),
    path(
        "me/prayer-reading-check-ins",
        PrayerReadingCheckInCreateView.as_view(),
        name="prayer-reading-check-in-create",
    ),
    path(
        "me/prayer-reading-check-ins/<uuid:check_in_id>",
        PrayerReadingCheckInDetailView.as_view(),
        name="prayer-reading-check-in-detail",
    ),
    path(
        "me/reading-sessions",
        ReadingSessionListView.as_view(),
        name="reading-session-list",
    ),
    path(
        "me/reading-sessions/automatic",
        AutomaticReadingSessionCreateView.as_view(),
        name="reading-session-automatic",
    ),
    path(
        "me/reading-sessions/manual",
        ManualReadingSessionCreateView.as_view(),
        name="reading-session-manual",
    ),
    path(
        "me/reading-sessions/<uuid:session_id>",
        ManualReadingSessionDetailView.as_view(),
        name="reading-session-detail",
    ),
    path("sync/push", SyncPushView.as_view(), name="sync-push"),
    path("sync/pull", SyncPullView.as_view(), name="sync-pull"),
]
