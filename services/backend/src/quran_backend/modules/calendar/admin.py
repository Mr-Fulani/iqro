# ruff: noqa: RUF001
from django.contrib import admin

from quran_backend.modules.calendar.models import CalendarEvent


@admin.register(CalendarEvent)
class CalendarEventAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("title_ru", "month", "day_start", "day_end", "kind", "is_published")
    list_filter = ("is_published", "month", "kind")
    search_fields = ("title_ru", "title_en", "title_ar", "title_tr", "code")
    readonly_fields = ("code", "created_at", "updated_at")
    fieldsets = (
        (
            "Когда отмечать",
            {
                "fields": ("month", ("day_start", "day_end"), "kind", "exclude_ramadan"),
                "description": (
                    "Событие повторяется каждый год по Хиджре. Григорианские даты рассчитываются "
                    "автоматически по Умм аль-Кура, как в мобильном приложении."
                ),
            },
        ),
        ("Русский", {"fields": ("title_ru", "description_ru")}),
        ("English", {"fields": ("title_en", "description_en")}),
        ("العربية", {"fields": ("title_ar", "description_ar")}),
        ("Türkçe", {"fields": ("title_tr", "description_tr")}),
        (
            "Достоверность и публикация",
            {
                "fields": ("source_label", "source_url", "is_published", "sort_order"),
                "description": (
                    "Проверьте источник и переводы. Расчётные даты не заменяют местное наблюдение "
                    "луны. Добровольный пост никогда не отмечается в дни праздников и ташрика."
                ),
            },
        ),
        (
            "Служебные данные",
            {"fields": ("code", "created_at", "updated_at"), "classes": ("collapse",)},
        ),
    )
