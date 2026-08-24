from __future__ import annotations

import re

from django.core.exceptions import ValidationError

SHA256_PATTERN = re.compile(r"[0-9a-f]{64}\Z")
VERSION_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}\Z")
OBJECT_KEY_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._/-]{0,511}\Z")
STRONG_ETAG_PATTERN = re.compile(r'"[^"\r\n]+"\Z')


def validate_sha256(value: str) -> None:
    """Accept canonical, lowercase SHA-256 digests only."""
    if SHA256_PATTERN.fullmatch(value) is None:
        raise ValidationError("Enter a lowercase 64-character SHA-256 digest.")


def validate_version_identifier(value: str) -> None:
    """Keep externally visible content versions stable and path-safe."""
    if VERSION_PATTERN.fullmatch(value) is None:
        raise ValidationError(
            "Use 1-64 ASCII letters, digits, dots, underscores, or hyphens; "
            "start with a letter or digit."
        )


def validate_relative_object_key(value: str) -> None:
    """Reject URLs, absolute paths, traversal, and ambiguous object-store keys."""
    if OBJECT_KEY_PATTERN.fullmatch(value) is None:
        raise ValidationError(
            "Use a safe relative object key containing only ASCII letters, digits, '.', '_', "
            "'-', and '/'."
        )
    parts = value.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        raise ValidationError("Object keys must not contain empty, current, or parent segments.")


def validate_strong_etag(value: str) -> None:
    """Store the exact quoted strong ETag observed at the public CDN edge."""
    if STRONG_ETAG_PATTERN.fullmatch(value) is None:
        raise ValidationError("Enter a quoted strong ETag without the W/ prefix.")
