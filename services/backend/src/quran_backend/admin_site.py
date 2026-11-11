# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""The admin home: a few sections with the daily tables on top of each.

Every section has a one-line hint, its main tables in a fixed order, and the
rest of its tables folded under «Служебные таблицы». «Каждый день» and «Требует
внимания» sit above the sections on the home page.

Only the home page and the sidebar are grouped. App pages (/admin/<app>/),
model URLs and permissions stay Django's own.

A new model lands among the service tables of its app's section by itself; list
it in the section's `main` to show it openly. A new app needs a line in
SECTIONS; until then it shows up in «Прочее» and test_admin_sections fails.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from django.contrib import admin
from django.contrib.admin.apps import AdminConfig
from django.http import HttpRequest
from django.template.response import TemplateResponse


@dataclass(frozen=True)
class Section:
    key: str
    title: str
    # One line under the title: what people do here.
    hint: str
    # Apps in the order their groups are shown among the service tables.
    apps: tuple[str, ...]
    # Tables shown openly, in this order; every other table of the section is folded.
    main: tuple[str, ...]


SECTIONS: tuple[Section, ...] = (
    Section(
        "feedback",
        "Обращения и отзывы",
        "Что пишут пользователи и как оценивают курсы",
        ("feedback", "course_feedback"),
        ("feedback.FeedbackTicket", "feedback.FeedbackMessage", "course_feedback.CourseAnalytics"),
    ),
    Section(
        "announcements",
        "Объявления",
        "Что показать людям в приложении и на сайте",
        ("announcements",),
        (
            "announcements.Announcement",
            "announcements.AnnouncementSettings",
            "announcements.AppReleaseSettings",
        ),
    ),
    Section(
        "learning",
        "Обучение",
        "Курсы, таджвид и обучение намазу: править и публиковать",
        ("courses", "tajweed", "salah", "quiz"),
        (
            "courses.Course",
            "courses.CourseRelease",
            "courses.LearnerProgress",
            "tajweed.TajweedCourseVersion",
            "salah.SalahCourseVersion",
            "courses.BuiltInCourseCover",
        ),
    ),
    Section(
        "audio",
        "Чтецы и аудио",
        "Чтецы, их чтения и оформление плеера",
        ("audio",),
        (
            "audio.Reciter",
            "audio.RecitationEdition",
            "audio.AudioCatalogSettings",
            "audio.PlayerBackground",
        ),
    ),
    Section(
        "quran",
        "Коран, переводы и тафсиры",
        "Текст Корана загружается сам. Здесь включают переводы и тафсиры",
        ("quran", "translations", "tafsirs"),
        ("translations.TranslationEdition", "tafsirs.TafsirEdition"),
    ),
    Section(
        "dua",
        "Ду’а и календарь",
        "Ду’а, праздники и расчёт времени намаза",
        ("dua", "calendar", "prayer_times"),
        ("dua.DuaEntry", "dua.DuaCategory", "calendar.CalendarEvent", "prayer_times.PrayerMethod"),
    ),
    Section(
        "users",
        "Пользователи и доступ",
        "Аккаунты людей и права сотрудников",
        ("accounts", "auth", "reading", "memorization", "reminders"),
        ("accounts.User", "auth.Group"),
    ),
    Section(
        "site",
        "Сайт и приглашения",
        "Ссылки на соцсети и акция «Поделиться приложением»",
        ("website", "share_referrals", "core", "alerts"),
        ("website.SocialProfile", "website.AllowedLinkSite", "share_referrals.ShareCampaign"),
    ),
)
OTHER_SECTION = ("other", "Прочее")

# «Каждый день» on the home page: (title, what is done there, model).
TILES: tuple[tuple[str, str, str], ...] = (
    ("Обращения", "Письма пользователей: прочитать, ответить, закрыть", "feedback.FeedbackTicket"),
    ("Объявления", "Новости в приложении и на сайте", "announcements.Announcement"),
    ("Курсы", "Темы, видео, слайды и выпуски", "courses.Course"),
    ("Чтецы", "Карточки, фото и биографии чтецов", "audio.Reciter"),
    ("Ду’а", "Тексты, переводы и разделы", "dua.DuaEntry"),
    ("Пользователи", "Кто зарегистрирован, доступ сотрудников", "accounts.User"),
)

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
    for section in SECTIONS:
        if app_label in section.apps:
            return section.key, None
    return OTHER_SECTION[0], None


def group_sections(app_list: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Django's app list regrouped into SECTIONS; each model keeps its URLs."""
    by_key = {section.key: section for section in SECTIONS}
    app_order = {app: position for section in SECTIONS for position, app in enumerate(section.apps)}
    # Sort key: main tables first in their fixed order, then service groups by app.
    rows: dict[str, list[tuple[tuple[int, int, str], dict[str, Any]]]] = {
        key: [] for key in (*by_key, OTHER_SECTION[0])
    }
    for app in app_list:
        for model in app["models"]:
            label = f"{app['app_label']}.{model['object_name']}"
            key, heading = placement(app["app_label"], model["object_name"])
            main = by_key[key].main if key in by_key else ()
            if label in main:
                rows[key].append(
                    (
                        (0, main.index(label), ""),
                        {**model, "service": False, "group": "", "group_url": ""},
                    )
                )
                continue
            # Moved models go after the section's own apps.
            position = (
                len(app_order) + 1 if heading else app_order.get(app["app_label"], len(app_order))
            )
            title = heading or str(app["name"])
            rows[key].append(
                (
                    (1, position, title),
                    {
                        **model,
                        # «Прочее» is where a forgotten app shows up: nothing is folded there.
                        "service": key in by_key,
                        "group": title,
                        "group_url": "" if heading else app["app_url"],
                    },
                )
            )
    sections = []
    for key, entries in rows.items():
        if not entries:
            continue
        models = [model for _order, model in sorted(entries, key=lambda entry: entry[0])]
        sections.append(
            {
                "name": by_key[key].title if key in by_key else OTHER_SECTION[1],
                "hint": by_key[key].hint if key in by_key else "",
                "app_label": f"section-{key}",
                "app_url": "",
                "has_module_perms": True,
                "models": models,
                "service_count": sum(model["service"] for model in models),
            }
        )
    return sections


def tiles(sections: list[dict[str, Any]]) -> list[dict[str, str]]:
    """«Каждый день»: the tiles whose list this user may open."""
    urls = {
        model["model"]._meta.label: model["admin_url"]
        for section in sections
        for model in section["models"]
        if model.get("admin_url")
    }
    return [
        {"title": title, "hint": hint, "url": urls[label]}
        for title, hint, label in TILES
        if label in urls
    ]


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
            request,
            {
                "attention": attention_items(request),
                "tiles": tiles(self.get_app_list(request)),
                **(extra_context or {}),
            },
        )


class IqroAdminConfig(AdminConfig):
    default_site = "quran_backend.admin_site.IqroAdminSite"
