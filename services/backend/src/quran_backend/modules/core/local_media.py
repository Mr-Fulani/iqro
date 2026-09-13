"""Immutable filesystem publication for explicit local development only."""

from __future__ import annotations

import hashlib
from pathlib import Path, PurePosixPath

from django.conf import settings
from django.core.exceptions import ImproperlyConfigured

from quran_backend.modules.core.object_storage import (
    ImmutableObjectSpec,
    ObjectStorageError,
    StoredObject,
)


class LocalMediaUploader:
    def __init__(self) -> None:
        if not (settings.DEBUG and getattr(settings, "LOCAL_DEVELOPMENT", False)):
            raise ImproperlyConfigured(
                "Local media publication requires local development settings"
            )
        self.root = Path(settings.MEDIA_ROOT).resolve()

    def upload_path(self, source_path: Path, spec: ImmutableObjectSpec) -> StoredObject:
        key = PurePosixPath(spec.key)
        if key.is_absolute() or ".." in key.parts or "\\" in spec.key:
            raise ObjectStorageError("Unsafe local media key")
        target = self.root.joinpath(*key.parts)
        if target.is_symlink() or not target.resolve().is_relative_to(self.root):
            raise ObjectStorageError("Local media key escapes storage")
        data = source_path.read_bytes()
        if len(data) != spec.size_bytes or hashlib.sha256(data).hexdigest() != spec.checksum_sha256:
            raise ObjectStorageError("Local source integrity check failed")
        target.parent.mkdir(parents=True, exist_ok=True)
        try:
            with target.open("xb") as stream:
                stream.write(data)
            created = True
        except FileExistsError:
            if target.is_symlink() or target.read_bytes() != data:
                raise ObjectStorageError(
                    "Existing local media differs; nothing overwritten"
                ) from None
            created = False
        return StoredObject(key=spec.key, etag=f'"{spec.checksum_sha256}"', created=created)
