from __future__ import annotations

from django.urls import path

from quran_backend.modules.reading.api import (
    BookmarkDetailView,
    BookmarkListCreateView,
    ReadingPositionView,
    SyncPullView,
    SyncPushView,
)

app_name = "reading"

urlpatterns = [
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
    path("sync/push", SyncPushView.as_view(), name="sync-push"),
    path("sync/pull", SyncPullView.as_view(), name="sync-pull"),
]
