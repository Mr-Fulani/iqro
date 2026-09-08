from __future__ import annotations

from typing import Any

from drf_spectacular.utils import extend_schema
from rest_framework import serializers
from rest_framework.exceptions import ValidationError
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from quran_backend.modules.calendar.calculation import (
    MAX_YEAR,
    METHOD,
    MIN_YEAR,
    civil_date,
    hijri_date,
    month_length,
)
from quran_backend.modules.calendar.serializers import (
    CalendarCatalogSerializer,
    CalendarMonthSerializer,
)
from quran_backend.modules.calendar.services import catalog, matches
from quran_backend.modules.core.public_api import PublicReadOnlyViewMixin


class MonthQuery(serializers.Serializer[Any]):
    year = serializers.IntegerField(min_value=MIN_YEAR, max_value=MAX_YEAR, required=False)
    month = serializers.IntegerField(min_value=1, max_value=12, required=False)
    date = serializers.DateField(required=False)
    adjustment = serializers.IntegerField(min_value=-2, max_value=2, default=0)


class CalendarCatalogView(PublicReadOnlyViewMixin, APIView):
    @extend_schema(tags=["calendar"], responses=CalendarCatalogSerializer)
    def get(self, request: Request) -> Response:  # noqa: ARG002
        return Response(catalog())


class CalendarMonthView(PublicReadOnlyViewMixin, APIView):
    @extend_schema(
        tags=["calendar"],
        parameters=[MonthQuery],
        responses=CalendarMonthSerializer,
        description=(
            "Supply either a local civil date (YYYY-MM-DD) or Hijri year + month. "
            "No guessed sunset. Personal adjustment is -2 to 2 days."
        ),
    )
    def get(self, request: Request) -> Response:
        query = MonthQuery(data=request.query_params)
        query.is_valid(raise_exception=True)
        args = query.validated_data
        has_date = "date" in args
        if (has_date and ("year" in args or "month" in args)) or (
            not has_date and not ("year" in args and "month" in args)
        ):
            raise ValidationError("Supply date OR year and month.")
        adjustment = args["adjustment"]
        selected = None
        try:
            if has_date:
                year, month, selected = hijri_date(args["date"], adjustment)
            else:
                year, month = args["year"], args["month"]
            length = month_length(year, month)
        except ValueError as exc:
            raise ValidationError(str(exc)) from exc
        data = catalog()
        days = [
            {
                "day": day,
                "civil_date": civil_date(year, month, day, adjustment).isoformat(),
                "events": [event["code"] for event in data["events"] if matches(event, month, day)],
            }
            for day in range(1, length + 1)
        ]
        return Response(
            {
                "method": METHOD,
                "catalog_version": data["version"],
                "catalog": data,
                "year": year,
                "month": month,
                "selected_day": selected,
                "adjustment": adjustment,
                "first_weekday": civil_date(year, month, 1, adjustment).isoweekday(),
                "days": days,
            }
        )
