from __future__ import annotations

import hashlib
import json
from typing import Any

from quran_backend.modules.calendar.calculation import MAX_YEAR, METHOD, MIN_YEAR, civil_date
from quran_backend.modules.calendar.models import LOCALES, CalendarEvent


def catalog() -> dict[str, Any]:
    events = [
        {
            "code": event.code,
            "kind": event.kind,
            "month": event.month,
            "day_start": event.day_start,
            "day_end": event.day_end,
            "exclude_ramadan": event.exclude_ramadan,
            "titles": {locale: getattr(event, f"title_{locale}") for locale in LOCALES},
            "descriptions": {locale: getattr(event, f"description_{locale}") for locale in LOCALES},
            "source": {"label": event.source_label, "url": event.source_url},
        }
        for event in CalendarEvent.objects.filter(is_published=True)
    ]
    payload: dict[str, Any] = {
        "schema_version": 1,
        "method": METHOD,
        "min_year": MIN_YEAR,
        "max_year": MAX_YEAR,
        "civil_start": civil_date(MIN_YEAR, 1, 1).isoformat(),
        "civil_end": civil_date(MAX_YEAR, 12, 30).isoformat(),
        "events": events,
    }
    payload["version"] = hashlib.sha256(
        json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode(),
    ).hexdigest()
    return payload


def matches(event: dict[str, Any], month: int, day: int) -> bool:
    if event["month"] not in (0, month) or not event["day_start"] <= day <= event["day_end"]:
        return False
    if event["exclude_ramadan"] and month == 9:
        return False
    # Do not let an editable recurring reminder suggest voluntary fasting on Eid
    # or Tashriq, including when the corresponding festival is unpublished.
    no_fast = (month == 10 and day == 1) or (month == 12 and 10 <= day <= 13)
    return not (event["kind"] == "voluntary_fast" and no_fast)
