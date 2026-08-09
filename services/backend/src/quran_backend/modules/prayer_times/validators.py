from __future__ import annotations

import re

from django.core.exceptions import ValidationError

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
VERSION_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
METHOD_CODE_RE = re.compile(r"^[a-z][a-z0-9-]{1,63}$")


def validate_sha256(value: str) -> None:
    """Require a canonical, lowercase SHA-256 hexadecimal digest."""

    if not SHA256_RE.fullmatch(value):
        raise ValidationError("Use a 64-character lowercase SHA-256 digest.")


def validate_version_identifier(value: str) -> None:
    """Validate a compact identifier safe for manifests, logs, and URLs."""

    if not VERSION_RE.fullmatch(value):
        raise ValidationError(
            "Use 1-64 ASCII letters, digits, dots, underscores, or hyphens; "
            "start with a letter or digit."
        )


def validate_method_code(value: str) -> None:
    """Keep public method identifiers stable, lowercase, and URL-safe."""

    if not METHOD_CODE_RE.fullmatch(value):
        raise ValidationError(
            "Use 2-64 lowercase ASCII letters, digits, or hyphens; start with a letter."
        )
