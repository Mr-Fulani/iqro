from __future__ import annotations

from django.urls import path

from quran_backend.modules.dua.api import (
    DuaCategoryListView,
    DuaCollectionListView,
    DuaEntryDetailView,
    DuaEntryListView,
    DuaEntryResolveView,
)

app_name = "dua"

urlpatterns = [
    path("collections", DuaCollectionListView.as_view(), name="collection-list"),
    path("categories", DuaCategoryListView.as_view(), name="category-list"),
    path("entries", DuaEntryListView.as_view(), name="entry-list"),
    path("entries/resolve", DuaEntryResolveView.as_view(), name="entry-resolve"),
    path("entries/<uuid:pk>", DuaEntryDetailView.as_view(), name="entry-detail"),
]
