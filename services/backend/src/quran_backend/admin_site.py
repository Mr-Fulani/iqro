# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""The admin home: sections instead of twenty apps, and «Требует внимания» on top.

Only the home page and the sidebar are grouped. App pages (/admin/<app>/),
model URLs and permissions stay Django's own.

A new model lands in its app's section by itself. A new app needs a line in
SECTIONS; until then it shows up in «Прочее» and test_admin_sections fails.
"""

from __future__ import annotations

from typing import Any

from django.contrib import admin
from django.contrib.admin.apps import AdminConfig
from django.http import HttpRequest
from django.template.response import TemplateResponse

# (key, title, apps in the order their groups are shown)
SECTIONS: tuple[tuple[str, str, tuple[str, ...]], ...] = (
    ("learning", "Обучение", ("courses", "tajweed", "salah", "quiz")),
    ("feedback", "Обратная связь", ("feedback", "course_feedback")),
    ("announcements", "Объявления", ("announcements",)),
    ("quran", "Коран и аудио", ("quran", "translations", "tafsirs", "audio")),
    ("dua", "Ду’а и календарь", ("dua", "calendar", "prayer_times")),
    (
        "users",
        "Пользователи и доступ",
        ("accounts", "auth", "reading", "memorization", "reminders"),
    ),
    ("site", "Сайт и настройки", ("website", "share_referrals", "core", "alerts")),
)
OTHER_SECTION = ("other", "Прочее")

# Models that belong with another section than their app: (section, group heading).
MODEL_PLACEMENT: dict[str, tuple[str, str]] = {
    # The colour markup of the Quran text, not the tajweed course.
    "tajweed.TajweedEdition": ("quran", "Разметка таджвида"),
    "tajweed.TajweedEditionVersion": ("quran", "Разметка таджвида"),
    "tajweed.AyahTajweed": ("quran", "Разметка таджвида"),
    # Personal data of users kept by content apps.
    "audio.AudioPlaybackPosition": ("users", "Данные пользователей"),
    "dua.DuaFavorite": ("users", "Данные пользователей"),
    "prayer_times.PrayerProfile": ("users", "Данные пользователей"),
}

# Ratings and remarks on courses live in the courses app but are feedback.
COURSE_FEEDBACK_HINTS = ("Feedback", "Rating", "Remark", "Review", "Comment")
COURSE_FEEDBACK_GROUP = "Оценки и замечания по курсам"


def placement(app_label: str, object_name: str) -> tuple[str, str | None]:
    """The section key of a model and its group heading (None: its app's name)."""
    label = f"{app_label}.{object_name}"
    if label in MODEL_PLACEMENT:
        return MODEL_PLACEMENT[label]
    if app_label == "courses" and any(hint in object_name for hint in COURSE_FEEDBACK_HINTS):
        return "feedback", COURSE_FEEDBACK_GROUP
    for key, _title, apps in SECTIONS:
        if app_label in apps:
            return key, None
    return OTHER_SECTION[0], None


def group_sections(app_list: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Django's app list regrouped into SECTIONS; each model keeps its URLs."""
    titles = {key: title for key, title, _apps in SECTIONS}
    titles[OTHER_SECTION[0]] = OTHER_SECTION[1]
    app_order = {
        app: position for _key, _title, apps in SECTIONS for position, app in enumerate(apps)
    }
    groups: dict[str, dict[tuple[int, str], list[dict[str, Any]]]] = {key: {} for key in titles}
    for app in app_list:
        for model in app["models"]:
            section, heading = placement(app["app_label"], model["object_name"])
            position = app_order.get(app["app_label"], len(app_order))
            if heading is not None:
                # Moved models go after the section's own apps.
                position = len(app_order) + 1
            title = heading or str(app["name"])
            # «Обратная связь» inside «Обратная связь» says nothing: no heading then.
            shown = "" if title.lower() == titles[section].lower() else title
            groups[section].setdefault((position, title), []).append(
                {**model, "group": shown, "group_url": "" if heading else app["app_url"]}
            )
    sections = []
    for key, title in titles.items():
        if not groups[key]:
            continue
        models = [model for _order, group in sorted(groups[key].items()) for model in group]
        sections.append(
            {
                "name": title,
                "app_label": f"section-{key}",
                "app_url": "",
                "has_module_perms": True,
                "models": models,
            }
        )
    return sections


class IqroAdminSite(admin.AdminSite):
    index_template = "admin/iqro/index.html"

    def get_app_list(
        self, request: HttpRequest, app_label: str | None = None
    ) -> list[dict[str, Any]]:
        app_list = super().get_app_list(request, app_label)
        if app_label is not None:
            return app_list
        return group_sections(app_list)

    def index(
        self, request: HttpRequest, extra_context: dict[str, Any] | None = None
    ) -> TemplateResponse:
        from quran_backend.admin_attention import attention_items  # noqa: PLC0415

        return super().index(
            request, {"attention": attention_items(request), **(extra_context or {})}
        )


class IqroAdminConfig(AdminConfig):
    default_site = "quran_backend.admin_site.IqroAdminSite"
