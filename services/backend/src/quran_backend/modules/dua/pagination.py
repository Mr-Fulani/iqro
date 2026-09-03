from __future__ import annotations

from rest_framework.pagination import CursorPagination


class DuaEntryCursorPagination(CursorPagination):
    page_size = 20
    page_size_query_param = "page_size"
    max_page_size = 100
    # DRF encodes only the first ordering field as the cursor position and falls
    # back to an offset for ties. UUIDv7 is unique and time-sortable, so keeping
    # it first avoids an ever-growing offset while preserving import order.
    ordering = ("id",)
