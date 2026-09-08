from django.urls import path

from quran_backend.modules.calendar.api import CalendarCatalogView, CalendarMonthView

urlpatterns = [
    path("catalog", CalendarCatalogView.as_view(), name="calendar-catalog"),
    path("month", CalendarMonthView.as_view(), name="calendar-month"),
]
