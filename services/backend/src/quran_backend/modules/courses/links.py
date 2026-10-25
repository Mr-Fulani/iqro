# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""Links of course and tajweed notes checked against the site (docs/courses/README.md, «Ссылки»).

The parser only knows the shape of an address; here an address must lead somewhere a
student can open: an existing ayah, a published course and its lesson, a tajweed
lesson, or a site from «Разрешённые сайты для ссылок».
"""

from __future__ import annotations

import re
from collections.abc import Iterable
from typing import Any
from urllib.parse import urlsplit

from django.conf import settings

from quran_backend.modules.core.editorial.markup import markup_issues, markup_links
from quran_backend.modules.courses.models import Course
from quran_backend.modules.tajweed.models import TajweedCourse
from quran_backend.modules.website.models import AllowedLinkSite, link_host

# Ayahs in each surah, Hafs numbering: 6236 in all.
SURAH_AYAHS = (
    7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128, 111, 110, 98, 135,
    112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34, 30, 73, 54, 45, 83, 182, 88, 75, 85, 54, 53,
    89, 59, 37, 35, 38, 29, 18, 45, 60, 49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12,
    12, 30, 52, 52, 44, 28, 28, 20, 56, 40, 31, 50, 40, 46, 42, 29, 19, 36, 25, 22, 17, 19, 26,
    30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11, 11, 8, 3, 9, 5, 4, 7, 3, 6, 3, 5, 4, 5, 6,
)  # fmt: skip
QURAN = re.compile(r"/quran/(\d+)(?::(\d+))?")
COURSE = re.compile(r"/courses/([^/]+)(?:/([^/]+))?")
TAJWEED = re.compile(r"/tajweed/([^/]+)")
TAJWEED_PAGES = frozenset({"practice"})
# The editors' cheat sheet for links and notes: course lessons and tajweed lessons.
INLINE_HELP = (
    "слово[!текст] — значок «!» после слова, по нажатию предупреждение; слово[?текст] — "
    "значок «?» с пояснением. Внутри можно **жирный** и арабский, но не скобки. "
    "[текст](/quran/2:255) — ссылка на раздел: /quran/2, /quran/2:255, /courses/курс/тема, "
    "/dua/…, /tajweed/урок. [текст](https://sunnah.com/…) — на сайт из «Разрешённых сайтов "
    "для ссылок» (Сайт и настройки)."
)


class LinkChecker:
    """Checks the links of one release; what it reads from the database is read once."""

    def __init__(
        self,
        *,
        course: str = "",
        lessons: Iterable[str] = (),
        tajweed_lessons: Iterable[str] = (),
    ) -> None:
        # The course being released links to its own lessons before they are published.
        self.course = course
        self.lessons = set(lessons)
        self.extra_tajweed = set(tajweed_lessons)
        self._hosts: set[str] | None = None
        self._tajweed: set[str] | None = None
        self._courses: dict[str, set[str] | None] = {}

    def problems(self, text: str) -> list[str]:
        """«строка 3: …» for every bracket that is not a link or a note and every bad link."""
        found = [(line, problem) for line, problem in markup_issues(text)]
        for link in markup_links(text):
            problem = self.problem(link["href"], link["kind"])
            if problem:
                found.append((link["line"], problem))
        return [f"строка {line}: {problem}" for line, problem in sorted(found)]

    def problem(self, href: str, kind: str) -> str | None:
        if kind == "external":
            return self._external(href)
        if match := QURAN.fullmatch(href):
            return _ayah(int(match[1]), int(match[2]) if match[2] else None)
        if match := COURSE.fullmatch(href):
            return self._course(match[1], match[2])
        match = TAJWEED.fullmatch(href)
        if match and match[1] not in TAJWEED_PAGES and match[1] not in self.tajweed_lessons():
            return f"в курсе таджвида нет урока «{match[1]}»"
        return None

    def _external(self, href: str) -> str | None:
        parts = urlsplit(href)
        if parts.scheme.lower() != "https":
            return f"«{href}»: внешние ссылки — только https://"
        host = link_host(parts.hostname or "")
        if host not in self.hosts():
            return f"сайта {host} нет в «Разрешённых сайтах для ссылок» (раздел «Сайт и настройки»)"
        return None

    def _course(self, slug: str, lesson: str | None) -> str | None:
        if slug not in self._courses:
            self._courses[slug] = self.lessons if slug == self.course else _published_lessons(slug)
        lessons = self._courses[slug]
        if lessons is None:
            return f"курса «{slug}» нет на сайте"
        if lesson is not None and lesson not in lessons:
            return f"в курсе «{slug}» нет темы «{lesson}»"
        return None

    def hosts(self) -> set[str]:
        if self._hosts is None:
            self._hosts = {
                link_host(domain)
                for domain in AllowedLinkSite.objects.values_list("domain", flat=True)
            }
        return self._hosts

    def tajweed_lessons(self) -> set[str]:
        if self._tajweed is None:
            self._tajweed = set(self.extra_tajweed)
            for course in TajweedCourse.objects.select_related("active_version").filter(
                active_version__isnull=False
            ):
                snapshot: dict[str, Any] = course.active_version.snapshot  # type: ignore[union-attr]
                self._tajweed.update(lesson["slug"] for lesson in snapshot.get("lessons", []))
        return self._tajweed


def site_href(href: str, language: str) -> str:
    """Where a link of the notes leads on the site: the site adds the language and opens an
    ayah in its reader."""
    if not href.startswith("/"):
        return href
    if match := QURAN.fullmatch(href):
        ayah = f"&ayah={match[2]}" if match[2] else ""
        return f"{settings.PUBLIC_SITE_URL}/{language}/quran?surah={match[1]}{ayah}"
    return f"{settings.PUBLIC_SITE_URL}/{language}{href}"


def link_rows(texts: Iterable[tuple[str, str, str]]) -> list[dict[str, Any]]:
    """Every link of (where, language, text) for the reviewer: where it is and where it leads."""
    return [
        {
            **link,
            "where": f"{where} ({language}), строка {link['line']}",
            "url": site_href(link["href"], language),
        }
        for where, language, text in texts
        for link in markup_links(text)
    ]


def _ayah(surah: int, ayah: int | None) -> str | None:
    if not 1 <= surah <= len(SURAH_AYAHS):
        return f"суры {surah} нет: в Коране {len(SURAH_AYAHS)} сур"
    count = SURAH_AYAHS[surah - 1]
    if ayah is not None and not 1 <= ayah <= count:
        return f"аята {surah}:{ayah} нет: в суре {surah} аятов {count}"
    return None


def _published_lessons(slug: str) -> set[str] | None:
    """The lessons of a course students see now; None when they do not see the course."""
    course = Course.objects.select_related("live_release").filter(slug=slug).first()
    if course is None or course.live_release is None or course.hidden_at is not None:
        return None
    return {lesson["slug"] for lesson in course.live_release.snapshot.get("lessons", [])}
