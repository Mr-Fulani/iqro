from __future__ import annotations

from rest_framework.pagination import CursorPagination


class DuaEntryCursorPagination(CursorPagination):
    page_size = 20
    page_size_query_param = "page_size"
    max_page_size = 100
    ordering = ("sort_order", "id")
