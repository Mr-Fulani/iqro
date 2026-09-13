import hashlib
from pathlib import Path

import pytest
from django.core.exceptions import ImproperlyConfigured
from django.test import override_settings

from quran_backend.modules.core.local_media import LocalMediaUploader
from quran_backend.modules.core.object_storage import ImmutableObjectSpec, ObjectStorageError
from quran_backend.modules.quran.rendition_publication import KFGQPC_FONT_SHA, validate_source


def test_local_uploader_requires_debug_and_explicit_local_settings() -> None:
    for debug, local in ((False, True), (True, False), (False, False)):
        with (
            override_settings(DEBUG=debug, LOCAL_DEVELOPMENT=local),
            pytest.raises(ImproperlyConfigured),
        ):
            LocalMediaUploader()


@override_settings(DEBUG=True, LOCAL_DEVELOPMENT=True)
def test_local_publication_verifies_and_never_overwrites(tmp_path: Path) -> None:
    source = tmp_path / "source.webp"
    source.write_bytes(b"verified-pixels")
    spec = ImmutableObjectSpec(
        key="mushafs/v1/page.webp",
        content_type="image/webp",
        checksum_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
        size_bytes=source.stat().st_size,
    )
    with override_settings(MEDIA_ROOT=tmp_path / "media"):
        uploader = LocalMediaUploader()
        assert uploader.upload_path(source, spec).created
        assert not uploader.upload_path(source, spec).created
        target = uploader.root / spec.key
        target.write_bytes(b"existing-different-object")
        with pytest.raises(ObjectStorageError, match="nothing overwritten"):
            uploader.upload_path(source, spec)
        assert target.read_bytes() == b"existing-different-object"
        source.write_bytes(b"corrupted-download")
        with pytest.raises(ObjectStorageError, match="integrity"):
            uploader.upload_path(source, spec)


@override_settings(DEBUG=True, LOCAL_DEVELOPMENT=True)
@pytest.mark.parametrize(
    "key", ["../outside", "/absolute", "a/../../outside", "a\\outside", "link/file"]
)
def test_local_publication_rejects_escape_and_symlink(tmp_path: Path, key: str) -> None:
    root = tmp_path / "media"
    root.mkdir()
    (root / "link").symlink_to(tmp_path, target_is_directory=True)
    with override_settings(MEDIA_ROOT=root), pytest.raises(ObjectStorageError):
        LocalMediaUploader().upload_path(
            tmp_path / "unused",
            ImmutableObjectSpec(
                key=key, content_type="image/webp", checksum_sha256="a" * 64, size_bytes=1
            ),
        )


def test_dynamic_source_lock_cannot_enable_production_publication() -> None:
    manifest = {
        "publication_scope": "local",
        "edition": "kfgqpc-hafs",
        "source": {
            "kind": "quran-foundation",
            "source_id": 5,
            "font_sha256": KFGQPC_FONT_SHA,
            "snapshot_sha256": "a" * 64,
            "source_checksum_sha256": "b" * 64,
        },
    }
    assert not validate_source(manifest)
    with override_settings(DEBUG=True, LOCAL_DEVELOPMENT=True):
        assert validate_source(manifest)
        manifest["source"]["font_sha256"] = "c" * 64
        assert not validate_source(manifest)
