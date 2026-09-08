"""Civil-date Umm al-Qura conversion, pinned to the mobile hijri 3.0.1 table.

No server timezone or guessed sunset enters this calculation. Clients provide
their civil date and personal adjustment; local Maghrib remains a client concern.
"""

from __future__ import annotations

import json
from bisect import bisect_right
from datetime import date, timedelta
from pathlib import Path

DATA = json.loads(Path(__file__).with_name("data").joinpath("ummalqura-v1.json").read_text())
MONTH_STARTS: tuple[int, ...] = tuple(DATA["month_starts_mcjdn"])
MIN_YEAR, MAX_YEAR = 1356, 1500
METHOD = "ummalqura-hijri-3.0.1"
# Chronological Julian day number = Gregorian ordinal + 1721425.
MCJDN_OFFSET = 678575


def month_index(year: int, month: int) -> int:
    if not MIN_YEAR <= year <= MAX_YEAR or not 1 <= month <= 12:
        raise ValueError("Hijri month outside supported range (1356-1500).")
    return (year - MIN_YEAR) * 12 + month - 1


def month_length(year: int, month: int) -> int:
    index = month_index(year, month)
    return MONTH_STARTS[index + 1] - MONTH_STARTS[index]


def civil_date(year: int, month: int, day: int, adjustment: int = 0) -> date:
    index = month_index(year, month)
    if not 1 <= day <= month_length(year, month) or not -2 <= adjustment <= 2:
        raise ValueError("Invalid day or adjustment.")
    return date.fromordinal(MONTH_STARTS[index] + MCJDN_OFFSET + day - 1 - adjustment)


def hijri_date(civil: date, adjustment: int = 0) -> tuple[int, int, int]:
    if not -2 <= adjustment <= 2:
        raise ValueError("Invalid adjustment.")
    mjd = (civil + timedelta(days=adjustment)).toordinal() - MCJDN_OFFSET
    index = bisect_right(MONTH_STARTS, mjd) - 1
    if index < 0 or index >= len(MONTH_STARTS) - 1:
        raise ValueError("Civil date outside supported range (1937-2077).")
    return MIN_YEAR + index // 12, index % 12 + 1, mjd - MONTH_STARTS[index] + 1
