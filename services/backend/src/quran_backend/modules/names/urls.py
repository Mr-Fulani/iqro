from __future__ import annotations

from django.urls import path

from quran_backend.modules.names.api import NamesDocumentView

urlpatterns = [
    path("collections/<slug:slug>", NamesDocumentView.as_view(), name="names-collection"),
]
