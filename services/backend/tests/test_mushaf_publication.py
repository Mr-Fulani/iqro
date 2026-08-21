from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import override_settings

from quran_backend.modules.quran.models import MushafPage, PublicationStatus, QuranEdition


def _prepared_assets(media_root: Path) -> Path:
    root = media_root / "quran" / "madani-hafs" / "1.0.0"
    assets: list[dict[str, object]] = []
    for logical_page in range(1, 605):
        relative_path = (
            Path("pages") / f"{logical_page:03d}" / (f"page-{logical_page:03d}-w0900.webp")
        )
        target = root / relative_path
        target.parent.mkdir(parents=True, exist_ok=True)
        payload = f"synthetic-webp-{logical_page}".encode()
        target.write_bytes(payload)
        assets.append(
            {
                "logical_page": logical_page,
                "pdf_page": logical_page + 1,
                "variant": "w0900",
                "format": "webp",
                "dimensions": {"width": 900, "height": 1379},
                "sha256": hashlib.sha256(payload).hexdigest(),
                "bytes": len(payload),
                "path": relative_path.as_posix(),
            }
        )
    manifest = {
        "schema_version": 1,
        "source": {"logical_page_count": 604},
        "render": {
            "first_logical_page": 1,
            "last_logical_page": 604,
            "page_count": 604,
            "asset_count": 604,
            "variant_widths": [900],
            "format": "webp",
            "lossless": True,
        },
        "assets": assets,
    }
    manifest_path = root / "manifest.json"
    manifest_payload = (json.dumps(manifest, sort_keys=True) + "\n").encode()
    manifest_path.write_bytes(manifest_payload)
    checksum = hashlib.sha256(manifest_payload).hexdigest()
    (root / "manifest.sha256").write_text(f"{checksum}  manifest.json\n", encoding="ascii")
    return manifest_path


@pytest.mark.django_db
def test_publish_mushaf_pages_registers_and_activates_catalog(tmp_path: Path) -> None:
    media_root = tmp_path / "media"
    media_root.mkdir()
    manifest = _prepared_assets(media_root)

    with override_settings(MEDIA_ROOT=media_root):
        call_command("publish_mushaf_pages", manifest, "--activate")
        call_command("publish_mushaf_pages", manifest, "--activate")

    edition = QuranEdition.objects.get(code="madani-hafs")
    assert edition.active_version is not None
    assert edition.active_version.status == PublicationStatus.PUBLISHED
    assert edition.active_version.pages.count() == 604
    assert (
        MushafPage.objects.get(edition_version=edition.active_version, number=1).asset_variants[0][
            "path"
        ]
        == "quran/madani-hafs/1.0.0/pages/001/page-001-w0900.webp"
    )


@pytest.mark.django_db
def test_publish_mushaf_pages_rejects_corrupt_asset(tmp_path: Path) -> None:
    media_root = tmp_path / "media"
    media_root.mkdir()
    manifest = _prepared_assets(media_root)
    corrupt_asset = media_root / "quran/madani-hafs/1.0.0/pages/001/page-001-w0900.webp"
    corrupt_asset.write_bytes(b"corrupt")

    with (
        override_settings(MEDIA_ROOT=media_root),
        pytest.raises(CommandError, match="integrity check failed"),
    ):
        call_command("publish_mushaf_pages", manifest, "--activate")
