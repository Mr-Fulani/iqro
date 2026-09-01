from __future__ import annotations

import hashlib
import json
from typing import Any

OFFLINE_PACKAGE_SCHEMA_VERSION = 1


def offline_package_checksum(payload: dict[str, Any]) -> str:
    """Return a stable digest for URL-independent offline package metadata."""

    encoded = json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode()
    return hashlib.sha256(encoded).hexdigest()
