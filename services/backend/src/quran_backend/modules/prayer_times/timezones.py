from __future__ import annotations

import importlib.metadata
import importlib.resources
import re
from functools import lru_cache
from typing import Final
from zoneinfo import ZoneInfo

TZDB_VERSION: Final = importlib.metadata.version("tzdata")
_IANA_NAME_RE: Final = re.compile(r"^[A-Za-z0-9._+-]+(?:/[A-Za-z0-9._+-]+)*$")


class InvalidPrayerTimezoneError(ValueError):
    pass


@lru_cache(maxsize=512)
def get_prayer_timezone(name: str) -> ZoneInfo:
    """Load a timezone from the pinned Python tzdata wheel, not the host OS."""

    if (
        name != name.strip()
        or not _IANA_NAME_RE.fullmatch(name)
        or any(part in {"", ".", ".."} for part in name.split("/"))
    ):
        raise InvalidPrayerTimezoneError("Invalid IANA timezone identifier.")
    resource = importlib.resources.files("tzdata.zoneinfo")
    for part in name.split("/"):
        resource = resource.joinpath(part)
    try:
        with resource.open("rb") as timezone_file:
            return ZoneInfo.from_file(timezone_file, key=name)
    except (FileNotFoundError, IsADirectoryError, ValueError) as exc:
        raise InvalidPrayerTimezoneError("Unknown IANA timezone identifier.") from exc
