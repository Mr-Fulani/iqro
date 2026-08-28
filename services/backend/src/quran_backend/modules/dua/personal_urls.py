from django.urls import path

from quran_backend.modules.dua.api import DuaFavoriteDetailView, DuaFavoriteListView

app_name = "dua-personal"

urlpatterns = [
    path("me/dua-favorites", DuaFavoriteListView.as_view(), name="favorite-list"),
    path(
        "me/dua-favorites/<slug:collection_slug>/<int:source_number>",
        DuaFavoriteDetailView.as_view(),
        name="favorite-detail",
    ),
]
