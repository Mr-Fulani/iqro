# ruff: noqa: RUF001
"""One action, two destinations: a path on the site and a route in the app.

Clients never build these themselves, so a link added here works the same on
every platform.
"""

from __future__ import annotations

from dataclasses import dataclass
from urllib.parse import urlsplit

from django.conf import settings

from quran_backend.modules.announcements.models import ActionType, Announcement


@dataclass(frozen=True, slots=True)
class Screen:
    label: str
    web: str
    app: str


# Sections an announcement may open. The app routes that do not exist yet
# (`/news`, `/prayer?qibla=1`) are added together with the app screens.
SCREENS: dict[str, Screen] = {
    "quran": Screen("Коран", "/quran", "/app?tab=1"),
    "plan": Screen("План", "/planner", "/app?tab=2"),
    "audio": Screen("Аудио", "/audio", "/app?tab=3"),
    "prayer": Screen("Время намаза", "/prayer", "/prayer"),
    "qibla": Screen("Компас Киблы", "/prayer?qibla=1", "/prayer?qibla=1"),
    "memorization": Screen("Заучивание", "/memorization", "/memorization"),
    "dua": Screen("Ду’а", "/dua", "/dua"),
    "salah": Screen("Обучение намазу", "/salah", "/salah"),
    "calendar": Screen("Календарь", "/calendar", "/calendar"),
    "news": Screen("Что нового", "/news", "/news"),
}


@dataclass(frozen=True, slots=True)
class ActionTarget:
    web_path: str | None
    app_route: str | None
    external_url: str | None


def external_url_allowed(url: str) -> bool:
    parsed = urlsplit(url)
    return (
        parsed.scheme == "https"
        and parsed.hostname is not None
        and not parsed.username
        and not parsed.password
        and parsed.port is None
        and parsed.hostname.lower() in settings.ANNOUNCEMENT_EXTERNAL_HOSTS
    )


def action_target(announcement: Announcement, locale: str) -> ActionTarget:
    action = announcement.action_type
    if action == ActionType.RECITER and announcement.action_reciter:
        reciter = announcement.action_reciter
        return ActionTarget(
            web_path=f"/{locale}/audio?reciter={reciter}&play=1",
            app_route=f"/audio/reciter/{reciter}?play=1",
            external_url=None,
        )
    if action == ActionType.SURAH and announcement.action_surah:
        surah = announcement.action_surah
        ayah = announcement.action_ayah
        return ActionTarget(
            web_path=f"/{locale}/quran?surah={surah}" + (f"&ayah={ayah}" if ayah else ""),
            app_route=f"/reader/{surah}" + (f"?ayah={ayah}" if ayah else ""),
            external_url=None,
        )
    if action == ActionType.SALAH_LESSON and announcement.action_slug:
        slug = announcement.action_slug
        return ActionTarget(
            web_path=f"/{locale}/salah/{slug}",
            app_route=f"/salah/lesson/{slug}",
            external_url=None,
        )
    if action == ActionType.SCREEN and announcement.action_slug in SCREENS:
        screen = SCREENS[announcement.action_slug]
        return ActionTarget(
            web_path=f"/{locale}{screen.web}",
            app_route=screen.app,
            external_url=None,
        )
    if action == ActionType.EXTERNAL and external_url_allowed(announcement.action_url):
        # Clicks go through the server so they are counted and re-checked.
        return ActionTarget(
            web_path=None,
            app_route=None,
            external_url=f"/api/v1/announcements/{announcement.id}/go",
        )
    return ActionTarget(web_path=None, app_route=None, external_url=None)
