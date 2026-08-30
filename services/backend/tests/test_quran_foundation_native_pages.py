from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

import pytest
from django.test import override_settings
from rest_framework.test import APIClient

from quran_backend.modules.core.object_storage import ImmutableObjectSpec, StoredObject
from quran_backend.modules.quran.models import (
    QuranFoundationMushaf,
    QuranFoundationMushafPage,
    QuranFoundationNativePublicationStatus,
)
from quran_backend.modules.quran.quran_foundation_native import (
    QuranFoundationNativeError,
    RenderedNativeAsset,
    native_rendering_catalog,
    prepare_quran_foundation_native_pages,
    publish_quran_foundation_native_pages,
)

SOURCE_CHECKSUM = "a" * 64


class FakeRenderer:
    name = "fake-qf-renderer"
    version = "1.0.0"

    def __init__(self) -> None:
        self.rendered_pages: list[int] = []

    def render_page(
        self,
        page: QuranFoundationMushafPage,
        *,
        widths: tuple[int, ...],
        output: Path,
    ) -> list[RenderedNativeAsset]:
        self.rendered_pages.append(page.page_number)
        assets = []
        for width in widths:
            path = output / f"page-{page.page_number}-{width}.webp"
            payload = f"page={page.page_number};width={width}".encode()
            path.write_bytes(b"RIFF" + len(payload).to_bytes(4, "little") + b"WEBP" + payload)
            assets.append(
                RenderedNativeAsset(
                    page_number=page.page_number,
                    width=width,
                    height=width * 3 // 2,
                    content_type="image/webp",
                    path=path,
                )
            )
        return assets


class FakeUploader:
    def __init__(self) -> None:
        self.keys: set[str] = set()
        self.specs: list[ImmutableObjectSpec] = []

    def upload_path(self, source_path: Path, spec: ImmutableObjectSpec) -> StoredObject:
        assert source_path.is_file()
        self.specs.append(spec)
        created = spec.key not in self.keys
        self.keys.add(spec.key)
        return StoredObject(key=spec.key, etag='"immutable"', created=created)


def _create_mushaf(*, source_id: int = 1, pages: int = 2) -> QuranFoundationMushaf:
    mushaf = QuranFoundationMushaf.objects.create(
        environment="production",
        source_id=source_id,
        resource_content_id=100 + source_id,
        name=f"Mushaf {source_id}",
        description="",
        qirat_id=1,
        qirat_name="Hafs",
        pages_count=pages,
        lines_per_page=15,
        default_font_name="qcf",
        mapping_mode="reference",
        schema_version="1",
        sync_sequence=1,
        source_checksum_sha256=SOURCE_CHECKSUM,
        is_available=True,
        last_synced_at=datetime(2026, 8, 30, tzinfo=UTC),
    )
    QuranFoundationMushafPage.objects.bulk_create(
        [
            QuranFoundationMushafPage(
                mushaf=mushaf,
                source_id=1_000 + number,
                page_number=number,
                verse_mapping={str(number): "1-1"},
                first_verse_id=number,
                last_verse_id=number,
                first_word_id=number,
                last_word_id=number,
                verses_count=1,
                words=[
                    {
                        "id": number,
                        "page_number": number,
                        "line_number": 1,
                        "position_in_line": 1,
                        "position_in_page": 1,
                        "text": "ﱁ",
                    }
                ],
            )
            for number in range(1, pages + 1)
        ]
    )
    return mushaf


@pytest.mark.django_db
def test_preparation_is_bounded_resumable_and_idempotent(tmp_path: Path) -> None:
    mushaf = _create_mushaf()
    renderer = FakeRenderer()
    uploader = FakeUploader()

    first = prepare_quran_foundation_native_pages(
        mushaf,
        render_version="test-1.0.0",
        renderer=renderer,
        first_page=1,
        limit=2,
        widths=(320, 640),
        uploader=uploader,
        work_root=tmp_path,
    )
    second = prepare_quran_foundation_native_pages(
        mushaf,
        render_version="test-1.0.0",
        renderer=renderer,
        first_page=1,
        limit=2,
        widths=(320, 640),
        uploader=uploader,
        work_root=tmp_path,
    )

    assert first.rendered_pages == 2
    assert first.publication.prepared_pages == 2
    assert first.publication.assets_count == 4
    assert second.rendered_pages == 0
    assert second.resumed_pages == 2
    assert renderer.rendered_pages == [1, 2]
    assert len(uploader.specs) == 4
    assert all(key.startswith("quran/quran-foundation/native/") for key in uploader.keys)
    assert all(".." not in key.split("/") for key in uploader.keys)


@pytest.mark.django_db
@override_settings(QURAN_QF_ENV="production", PUBLIC_MEDIA_BASE_URL="https://media.example.test")
def test_complete_publication_enables_catalog_and_page_assets(
    api_client: APIClient,
    tmp_path: Path,
) -> None:
    mushaf = _create_mushaf()
    renderer = FakeRenderer()
    prepare_quran_foundation_native_pages(
        mushaf,
        render_version="test-1.0.0",
        renderer=renderer,
        first_page=1,
        limit=2,
        widths=(320, 640),
        uploader=FakeUploader(),
        work_root=tmp_path,
    )

    result = publish_quran_foundation_native_pages(mushaf, render_version="test-1.0.0")
    catalog = api_client.get("/api/v1/quran/foundation/mushafs")
    page = api_client.get("/api/v1/quran/foundation/mushafs/1/pages/1")

    assert result.publication.status == QuranFoundationNativePublicationStatus.PUBLISHED
    assert result.publication.is_active is True
    assert len(result.publication.manifest_checksum_sha256) == 64
    assert catalog.json()[0]["native_rendering"] == {
        "available": True,
        "status": "ready",
        "render_version": "test-1.0.0",
        "source_checksum_sha256": SOURCE_CHECKSUM,
        "manifest_checksum_sha256": result.publication.manifest_checksum_sha256,
        "page_count": 2,
        "assets": [
            {"format": "webp", "content_type": "image/webp", "width": 320},
            {"format": "webp", "content_type": "image/webp", "width": 640},
        ],
    }
    assert [asset["width"] for asset in page.json()["native_assets"]] == [320, 640]
    assert all(
        asset["url"].startswith("https://media.example.test/quran/")
        for asset in page.json()["native_assets"]
    )
    assert renderer.rendered_pages == [1, 2]


@pytest.mark.django_db
@override_settings(QURAN_QF_ENV="production")
def test_incomplete_publication_is_fail_closed(
    api_client: APIClient,
    tmp_path: Path,
) -> None:
    mushaf = _create_mushaf()
    prepare_quran_foundation_native_pages(
        mushaf,
        render_version="test-1.0.0",
        renderer=FakeRenderer(),
        first_page=1,
        limit=1,
        widths=(320,),
        uploader=FakeUploader(),
        work_root=tmp_path,
    )

    with pytest.raises(QuranFoundationNativeError, match="incomplete"):
        publish_quran_foundation_native_pages(mushaf, render_version="test-1.0.0")

    assert (
        api_client.get("/api/v1/quran/foundation/mushafs").json()[0]["native_rendering"]["status"]
        == "not_ready"
    )
    assert (
        api_client.get("/api/v1/quran/foundation/mushafs/1/pages/1").json()["native_assets"] == []
    )


@pytest.mark.django_db
def test_source_checksum_change_invalidates_prepared_and_published_assets(tmp_path: Path) -> None:
    mushaf = _create_mushaf()
    prepare_quran_foundation_native_pages(
        mushaf,
        render_version="test-1.0.0",
        renderer=FakeRenderer(),
        first_page=1,
        limit=2,
        widths=(320,),
        uploader=FakeUploader(),
        work_root=tmp_path,
    )
    publication = publish_quran_foundation_native_pages(
        mushaf,
        render_version="test-1.0.0",
    ).publication
    assert native_rendering_catalog(mushaf)["status"] == "ready"

    mushaf.source_checksum_sha256 = "b" * 64
    mushaf.save(update_fields=["source_checksum_sha256", "updated_at"])
    mushaf.refresh_from_db()

    assert native_rendering_catalog(mushaf) == {
        "available": False,
        "status": "not_ready",
        "reason": "source_changed",
        "assets": [],
    }
    with pytest.raises(QuranFoundationNativeError, match="source changed"):
        publish_quran_foundation_native_pages(
            mushaf,
            render_version=publication.render_version,
            activate_existing=True,
        )


@pytest.mark.django_db
def test_resource_11_remains_fail_closed(tmp_path: Path) -> None:
    mushaf = _create_mushaf(source_id=11)

    assert native_rendering_catalog(mushaf)["reason"] == "official_asset_base_url_unavailable"
    with pytest.raises(QuranFoundationNativeError, match="official asset base URL"):
        prepare_quran_foundation_native_pages(
            mushaf,
            render_version="test-1.0.0",
            renderer=FakeRenderer(),
            first_page=1,
            limit=1,
            widths=(320,),
            uploader=FakeUploader(),
            work_root=tmp_path,
        )


@pytest.mark.django_db
def test_render_version_cannot_escape_storage_prefix(tmp_path: Path) -> None:
    mushaf = _create_mushaf()

    with pytest.raises(QuranFoundationNativeError, match="safe lowercase"):
        prepare_quran_foundation_native_pages(
            mushaf,
            render_version="../../escape",
            renderer=FakeRenderer(),
            first_page=1,
            limit=1,
            widths=(320,),
            uploader=FakeUploader(),
            work_root=tmp_path,
        )


@pytest.mark.django_db
def test_missing_published_asset_immediately_fails_closed(tmp_path: Path) -> None:
    mushaf = _create_mushaf()
    result = prepare_quran_foundation_native_pages(
        mushaf,
        render_version="test-1.0.0",
        renderer=FakeRenderer(),
        first_page=1,
        limit=2,
        widths=(320,),
        uploader=FakeUploader(),
        work_root=tmp_path,
    )
    publication = publish_quran_foundation_native_pages(
        mushaf,
        render_version="test-1.0.0",
    ).publication
    assert native_rendering_catalog(mushaf)["status"] == "ready"

    result.publication.page_assets.filter(page_number=2).delete()

    assert native_rendering_catalog(mushaf) == {
        "available": False,
        "status": "not_ready",
        "reason": "incomplete_publication",
        "assets": [],
    }
    assert publication.is_active is True


@pytest.mark.django_db
def test_rollback_reactivates_previous_immutable_publication(tmp_path: Path) -> None:
    mushaf = _create_mushaf()
    for render_version in ("test-1.0.0", "test-2.0.0"):
        prepare_quran_foundation_native_pages(
            mushaf,
            render_version=render_version,
            renderer=FakeRenderer(),
            first_page=1,
            limit=2,
            widths=(320,),
            uploader=FakeUploader(),
            work_root=tmp_path,
        )
        publish_quran_foundation_native_pages(mushaf, render_version=render_version)

    assert native_rendering_catalog(mushaf)["render_version"] == "test-2.0.0"

    rollback = publish_quran_foundation_native_pages(
        mushaf,
        render_version="test-1.0.0",
        activate_existing=True,
    )

    assert rollback.activated is True
    assert native_rendering_catalog(mushaf)["render_version"] == "test-1.0.0"
    assert mushaf.native_publications.filter(is_active=True).count() == 1
