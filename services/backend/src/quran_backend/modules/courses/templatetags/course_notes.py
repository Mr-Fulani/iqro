# Operator-facing text is intentionally Russian.
"""Segments of course notes in the admin preview: bold, Arabic, links and note icons."""

from __future__ import annotations

import itertools
from typing import Any

from django import template
from django.utils.html import format_html, format_html_join
from django.utils.safestring import SafeString

from quran_backend.modules.courses.links import site_href

register = template.Library()
NOTE_LABELS = {"warning": ("!", "Внимание"), "help": ("?", "Пояснение")}
# Popover ids, unique within a page.
_ids = itertools.count(1)


@register.simple_tag
def note_segments(segments: list[dict[str, Any]], language: str = "ru") -> SafeString:
    return format_html_join("", "{}", ((_segment(item, language),) for item in segments))


def _segment(segment: dict[str, Any], language: str) -> SafeString:
    note = segment.get("note")
    if note:
        icon, label = NOTE_LABELS.get(note["kind"], NOTE_LABELS["help"])
        target = f"cv-note-{next(_ids)}"
        return format_html(
            '<button type="button" class="cv-mark is-{}" popovertarget="{}" aria-label="{}" '
            'title="{}">{}</button><span class="cv-mark-pop is-{}" id="{}" popover role="note">'
            "<strong>{}</strong> {}</span>",
            note["kind"],
            target,
            label,
            label,
            icon,
            note["kind"],
            target,
            label,
            note_segments(note["text"], language),
        )
    content: SafeString | str = segment["text"]
    if segment.get("lang") == "ar":
        content = format_html('<bdi lang="ar" class="cv-ar">{}</bdi>', content)
    if segment.get("bold"):
        content = format_html("<strong>{}</strong>", content)
    link = segment.get("link")
    if link:
        content = format_html(
            '<a class="cv-link" href="{}" target="_blank" rel="noopener noreferrer" '
            'title="{}">{}</a>',
            site_href(link["href"], language),
            link["href"],
            content,
        )
    return format_html("{}", content)
