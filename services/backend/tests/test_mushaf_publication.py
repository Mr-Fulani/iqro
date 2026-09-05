from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import override_settings

from quran_backend.modules.core.object_storage import ImmutableObjectSpec, StoredObject
from quran_backend.modules.quran.models import MushafPage, PublicationStatus, QuranEdition
from quran_backend.modules.quran.mushaf_publication import (
    load_prepared_mushaf_catalog,
    upload_prepared_mushaf_catalog,
)


class FakeMushafUploader:
    def __init__(self) -> None:
        self.specs: list[ImmutableObjectSpec] = []

    def upload_path(self, source_path: Path, spec: ImmutableObjectSpec) -> StoredObject:
        assert source_path.read_bytes()
        self.specs.append(spec)
        return StoredObject(key=spec.key, etag=f'"etag-{len(self.specs)}"', created=True)


def _prepared_assets(
    media_root: Path,
    *,
    edition_code: str = "madani-hafs",
    page_count: int = 604,
    schema_version: int = 1,
) -> Path:
    root = media_root / "quran" / edition_code / "1.0.0"
    assets: list[dict[str, object]] = []
    for logical_page in range(1, page_count + 1):
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
        "schema_version": schema_version,
        "source": {
            "logical_page_count": page_count,
            "cover_pdf_pages": [1],
        },
        "render": {
            "first_logical_page": 1,
            "last_logical_page": page_count,
            "page_count": page_count,
            "asset_count": page_count,
            "variant_widths": [900],
            "format": "webp",
            "lossless": True,
        },
        "assets": assets,
    }
    if schema_version == 2:
        manifest["edition"] = {
            "code": edition_code,
            "name_ar": "مصحف ورش",
            "name_en": "Warsh Mushaf",
            "name_ru": "Мусхаф Варш",
            "riwayah": "Warsh 'an Nafi",
            "source_name": "Synthetic Warsh source",
            "source_url": "https://example.test/warsh",
            "license_name": "Synthetic test license",
            "license_url": "https://example.test/terms",
            "surah_count": 114,
            "juz_count": 30,
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
def test_schema_v2_manifest_publishes_warsh_without_hafs_defaults(tmp_path: Path) -> None:
    media_root = tmp_path / "media"
    media_root.mkdir()
    manifest = _prepared_assets(
        media_root,
        edition_code="madani-warsh",
        page_count=1,
        schema_version=2,
    )

    with override_settings(MEDIA_ROOT=media_root):
        call_command(
            "publish_mushaf_pages",
            manifest,
            "--content-version",
            "warsh-pages-test",
            "--activate",
        )

    edition = QuranEdition.objects.get(code="madani-warsh")
    assert edition.riwayah == "Warsh 'an Nafi"
    assert edition.active_version is not None
    assert edition.active_version.page_count == 1
    assert edition.active_version.pages.count() == 1


@pytest.mark.django_db
def test_schema_v2_manifest_rejects_a_different_requested_edition(tmp_path: Path) -> None:
    media_root = tmp_path / "media"
    media_root.mkdir()
    manifest = _prepared_assets(
        media_root,
        edition_code="madani-warsh",
        page_count=1,
        schema_version=2,
    )

    with (
        override_settings(MEDIA_ROOT=media_root),
        pytest.raises(CommandError, match="does not match"),
    ):
        call_command("publish_mushaf_pages", manifest, "--edition", "madani-hafs")


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


def test_prepared_mushaf_catalog_uploads_all_assets_immutably(tmp_path: Path) -> None:
    media_root = tmp_path / "media"
    media_root.mkdir()
    manifest = _prepared_assets(media_root)
    catalog = load_prepared_mushaf_catalog(manifest, media_root=media_root)
    uploader = FakeMushafUploader()

    result = upload_prepared_mushaf_catalog(
        catalog,
        media_root=media_root,
        uploader=uploader,
    )

    assert result.assets == 604
    assert result.created == 604
    assert result.verified_existing == 0
    assert uploader.specs[0].key == ("quran/madani-hafs/1.0.0/pages/001/page-001-w0900.webp")
    assert uploader.specs[-1].content_type == "image/webp"


@pytest.mark.django_db
def test_upload_only_never_creates_a_page_only_version(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    media_root = tmp_path / "media"
    media_root.mkdir()
    manifest = _prepared_assets(media_root)
    uploader = FakeMushafUploader()
    monkeypatch.setattr(
        "quran_backend.modules.quran.management.commands.publish_mushaf_pages."
        "upload_prepared_mushaf_catalog",
        lambda catalog, *, media_root: upload_prepared_mushaf_catalog(
            catalog,
            media_root=media_root,
            uploader=uploader,
        ),
    )

    with override_settings(MEDIA_ROOT=media_root):
        call_command("publish_mushaf_pages", manifest, "--upload", "--upload-only")

    assert len(uploader.specs) == 604
    assert not QuranEdition.objects.filter(code="madani-hafs").exists()


@override_settings(MEDIA_OBJECT_STORAGE_REQUIRED=True)
def test_production_activation_requires_object_upload(tmp_path: Path) -> None:
    media_root = tmp_path / "media"
    media_root.mkdir()
    manifest = _prepared_assets(media_root)

    with (
        override_settings(MEDIA_ROOT=media_root),
        pytest.raises(CommandError, match="requires --upload"),
    ):
        call_command("publish_mushaf_pages", manifest, "--activate")
