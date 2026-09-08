from typing import Any

from rest_framework import serializers


class CalendarSourceSerializer(serializers.Serializer[Any]):
    label = serializers.CharField()  # type: ignore[assignment]
    url = serializers.URLField()


class CalendarEventSerializer(serializers.Serializer[Any]):
    code = serializers.CharField()
    kind = serializers.ChoiceField(choices=("occasion", "voluntary_fast", "no_fast"))
    month = serializers.IntegerField(min_value=0, max_value=12)
    day_start = serializers.IntegerField(min_value=1, max_value=30)
    day_end = serializers.IntegerField(min_value=1, max_value=30)
    exclude_ramadan = serializers.BooleanField()
    titles = serializers.DictField(child=serializers.CharField())
    descriptions = serializers.DictField(child=serializers.CharField())
    source = CalendarSourceSerializer()  # type: ignore[assignment]


class CalendarCatalogSerializer(serializers.Serializer[Any]):
    schema_version = serializers.IntegerField()
    version = serializers.CharField()
    method = serializers.CharField()
    min_year = serializers.IntegerField()
    max_year = serializers.IntegerField()
    civil_start = serializers.DateField()
    civil_end = serializers.DateField()
    events = CalendarEventSerializer(many=True)


class CalendarDateSerializer(serializers.Serializer[Any]):
    day = serializers.IntegerField()
    civil_date = serializers.DateField()
    events = serializers.ListField(child=serializers.CharField())


class CalendarMonthSerializer(serializers.Serializer[Any]):
    method = serializers.CharField()
    catalog_version = serializers.CharField()
    catalog = CalendarCatalogSerializer()
    year = serializers.IntegerField()
    month = serializers.IntegerField()
    selected_day = serializers.IntegerField(allow_null=True)
    adjustment = serializers.IntegerField()
    first_weekday = serializers.IntegerField(min_value=1, max_value=7)
    days = CalendarDateSerializer(many=True)
