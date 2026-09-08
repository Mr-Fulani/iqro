from __future__ import annotations

import hashlib
import json
from io import StringIO
from pathlib import Path
from typing import Any
from unittest.mock import Mock

import pytest
from django.conf import settings
from django.contrib import admin
from django.core.management import call_command
from django.core.management.base import CommandError
from django.db.backends.postgresql.base import DatabaseWrapper
from django.test import override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from quran_backend.modules.core.object_storage import ImmutableObjectSpec, ObjectStorageError
from quran_backend.modules.quran import rendition_publication as publication
from quran_backend.modules.quran.models import (
    MushafRendition,
    MushafRenditionPage,
    MushafRenditionRelease,
    PublicationStatus,
    QuranFoundationMushaf,
    QuranFoundationMushafPage,
)
from quran_backend.modules.quran.rendition_api import visible_releases
from quran_backend.modules.quran.serializers import OfflineMushafManifestSerializer


def test_source_checksum_subquery_compares_text_on_postgresql() -> None:
    # SQLite accepts JSON/string comparison; PostgreSQL rejects jsonb = varchar.
    # Compile using the real PostgreSQL backend without connecting to a database.
    postgres = DatabaseWrapper({"NAME": "compile_only"}, alias="compile_only")
    sql, params = visible_releases().query.get_compiler(connection=postgres).as_sql()
    assert '"source_metadata" ->> %s' in sql
    assert "source_checksum_sha256" in params


@pytest.fixture
def rendition(quran_dataset: dict[str, Any]) -> MushafRenditionRelease:
    visual = MushafRendition.objects.create(code="qcf-v2-hafs", names={"en": "QCF V2"})
    release = MushafRenditionRelease.objects.create(
        rendition=visual,
        version="test-v1",
        canonical_version=quran_dataset["version"],
        checksum_sha256="c" * 64,
        source_commit=publication.SOURCE_COMMIT,
        source_url="https://github.com/JMApps/mymushaf",
        renderer="test",
        widths=[720],
        page_count=1,
        published_at=timezone.now(),
        staging_only=True,
    )
    MushafRenditionPage.objects.create(release=release, **page_fields(quran_dataset))
    visual.active_release = release
    visual.save(update_fields=["active_release"])
    return release


def page_fields(dataset: dict[str, Any]) -> dict[str, Any]:
    return {
        "number": 1,
        "image_width": 1000,
        "image_height": 1600,
        "checksum_sha256": "d" * 64,
        "assets": [
            {
                "path": "quran/rendition/page-001.webp",
                "format": "webp",
                "width": 720,
                "height": 1152,
                "sha256": "e" * 64,
                "bytes": 123,
            }
        ],
        "regions": [
            {
                "id": "region-1",
                "reading_order": 0,
                "polygon": [],
                "x": "0.02000000",
                "y": "0.05000000",
                "width": "0.90000000",
                "height": "0.10000000",
                "ayah": {"id": str(dataset["first_ayah"].pk), "surah": 1, "number": 1},
            }
        ],
    }


@pytest.mark.django_db
def test_previews_are_hidden_in_production(
    api_client: APIClient, rendition: MushafRenditionRelease
) -> None:
    with override_settings(MUSHAF_STAGING_PREVIEWS=False):
        assert api_client.get(reverse("quran:rendition-list")).json() == []
        for name, kwargs in (
            ("rendition-page", {"code": "qcf-v2-hafs", "page": 1}),
            ("rendition-offline", {"code": "qcf-v2-hafs"}),
        ):
            assert api_client.get(reverse(f"quran:{name}", kwargs=kwargs)).status_code == 404


@pytest.mark.django_db
@override_settings(
    MUSHAF_STAGING_PREVIEWS=True,
    PUBLIC_MEDIA_BASE_URL="https://media.example.test",
    ALLOWED_HOSTS=["testserver", "localhost"],
)
def test_rendition_uses_canonical_ayahs_and_stable_offline_checksum(
    api_client: APIClient,
    rendition: MushafRenditionRelease,
    quran_dataset: dict[str, Any],
) -> None:
    catalog = api_client.get(reverse("quran:rendition-list")).json()
    assert catalog[0]["code"] == "qcf-v2-hafs"
    assert catalog[0]["canonical_edition"] == "madani-hafs"
    assert catalog[0]["staging_only"] is True
    page = api_client.get(
        reverse("quran:rendition-page", kwargs={"code": "qcf-v2-hafs", "page": 1})
    ).json()
    assert page["edition_code"] == "qcf-v2-hafs"
    assert page["regions"][0]["ayah"]["id"] == str(quran_dataset["first_ayah"].pk)
    assert page["assets"][0]["url"].startswith("https://media.example.test/")
    assert "path" not in page["assets"][0]
    url = reverse("quran:rendition-offline", kwargs={"code": "qcf-v2-hafs"})
    response = api_client.get(url, HTTP_HOST="localhost")
    assert response.status_code == 200
    manifest = response.json()
    serializer = OfflineMushafManifestSerializer(data=manifest)
    assert serializer.is_valid(), serializer.errors
    assert manifest["mushaf"]["edition_code"] == "qcf-v2-hafs"
    assert manifest["total_bytes"] == 123
    assert manifest["pages"][0]["metadata"]["regions"] == page["regions"]
    with override_settings(PUBLIC_MEDIA_BASE_URL="https://different.example.test"):
        other = api_client.get(url).json()
    assert other["package_checksum_sha256"] == manifest["package_checksum_sha256"]
    assert other["pages"][0]["asset"]["url"] != manifest["pages"][0]["asset"]["url"]
    assert api_client.get(url, {"width": "bad"}).status_code == 400
    assert api_client.get(url, {"width": 1440}).status_code == 404


@pytest.mark.django_db
@override_settings(MUSHAF_STAGING_PREVIEWS=True)
@pytest.mark.parametrize(
    "change", ["unpublished", "canonical_draft", "canonical_removed", "inactive"]
)
def test_only_active_compatible_publications_are_visible(
    api_client: APIClient,
    rendition: MushafRenditionRelease,
    change: str,
) -> None:
    if change == "unpublished":
        rendition.published_at = None
        rendition.save()
    elif change == "canonical_draft":
        rendition.canonical_version.status = PublicationStatus.DRAFT
        rendition.canonical_version.save()
    elif change == "canonical_removed":
        edition = rendition.canonical_version.edition
        edition.active_version = None
        edition.save()
    else:
        rendition.rendition.active_release = None
        rendition.rendition.save()
    assert api_client.get(reverse("quran:rendition-list")).json() == []


@pytest.mark.django_db
@override_settings(MUSHAF_STAGING_PREVIEWS=True)
def test_incomplete_offline_publication_fails_closed(
    api_client: APIClient,
    rendition: MushafRenditionRelease,
) -> None:
    rendition.page_count = 604
    rendition.save()
    url = reverse("quran:rendition-offline", kwargs={"code": "qcf-v2-hafs"})
    assert api_client.get(url).status_code == 404


@pytest.mark.django_db
def test_publication_activates_only_after_upload_and_is_idempotent(
    quran_dataset: dict[str, Any],
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    bundle = publication.PreparedRendition(
        manifest={"edition": "qcf-v2-hafs", "version": "v1", "renderer": "test", "widths": [720]},
        checksum="a" * 64,
        canonical=quran_dataset["version"],
        pages=[page_fields(quran_dataset)],
        uploads=[(tmp_path / "page.webp", ImmutableObjectSpec("test", "image/webp", 1, "a" * 64))],
    )
    monkeypatch.setattr(publication, "prepare_rendition", lambda _: bundle)
    uploader = Mock()
    uploader.upload_path.side_effect = ObjectStorageError("failed transfer")
    with pytest.raises(ObjectStorageError):
        publication.publish_rendition(tmp_path / "manifest.json", uploader=uploader)
    assert not MushafRendition.objects.exists()
    uploader.upload_path.side_effect = None
    first = publication.publish_rendition(tmp_path / "manifest.json", uploader=uploader)
    second = publication.publish_rendition(tmp_path / "manifest.json", uploader=uploader)
    assert first is not None
    assert second is not None
    assert first.pk == second.pk
    assert MushafRendition.objects.get().active_release_id == first.pk
    assert MushafRenditionPage.objects.count() == 1
    quran_dataset["edition"].refresh_from_db()
    assert quran_dataset["edition"].active_version_id == quran_dataset["version"].pk
    # Validation mode must not even invoke the storage adapter.
    uploader.reset_mock()
    assert (
        publication.publish_rendition(
            tmp_path / "manifest.json", uploader=uploader, validate_only=True
        )
        is None
    )
    uploader.upload_path.assert_not_called()


@pytest.mark.django_db
def test_canonical_change_during_transfer_prevents_activation(
    quran_dataset: dict[str, Any],
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    bundle = publication.PreparedRendition(
        {"edition": "qcf-v2-hafs", "version": "v1"},
        "a" * 64,
        quran_dataset["version"],
        [],
        [(tmp_path / "page.webp", ImmutableObjectSpec("test", "image/webp", 1, "a" * 64))],
    )
    monkeypatch.setattr(publication, "prepare_rendition", lambda _: bundle)

    def change_version(*args: Any) -> None:
        edition = quran_dataset["edition"]
        edition.active_version = None
        edition.save()

    uploader = Mock()
    uploader.upload_path.side_effect = change_version
    with pytest.raises(ValueError, match="Canonical version changed"):
        publication.publish_rendition(tmp_path / "manifest.json", uploader=uploader)
    assert not MushafRendition.objects.exists()


def test_manifest_gate_checks_complete_edition_and_source_before_database(tmp_path: Path) -> None:
    manifest = tmp_path / "manifest.json"
    with (
        override_settings(MUSHAF_STAGING_PREVIEWS=False),
        pytest.raises(ValueError, match="production publication"),
    ):
        publication.load_manifest(manifest)
    payload = {
        "schema_version": 1,
        "status": "prepared",
        "publication_scope": "staging",
        "source_commit": publication.SOURCE_COMMIT,
        "canonical_edition": "madani-hafs",
        "edition": "qcf-v2-hafs",
        "page_count": 604,
        "widths": [720, 1440, 2160],
        "version": "v1",
        "pages": [{"page": n} for n in range(1, 605)],
    }
    with override_settings(MUSHAF_STAGING_PREVIEWS=True):
        for change, error in (
            ({}, None),
            ({"page_count": 1}, "Unsupported"),
            ({"source_commit": "f" * 40}, "Unsupported"),
            ({"version": "../../unsafe"}, "Invalid version"),
            ({"pages": [{"page": 1}]}, "Incomplete"),
        ):
            data = json.dumps({**payload, **change}).encode()
            manifest.write_bytes(data)
            (tmp_path / "manifest.sha256").write_text(
                f"{hashlib.sha256(data).hexdigest()}  manifest.json\n"
            )
            if error is None:
                assert publication.load_manifest(manifest)[0] == payload
            else:
                with pytest.raises(ValueError, match=error):
                    publication.load_manifest(manifest)


def test_bundle_files_and_lossless_container_fail_closed(tmp_path: Path) -> None:
    file = tmp_path / "page.webp"
    # Minimal container header, intentionally not a decoder fixture.
    bits = (719 | (1151 << 14)).to_bytes(4, "little")
    chunk = b"VP8L" + (5).to_bytes(4, "little") + b"\x2f" + bits + b"\x00"
    data = b"RIFF" + (len(chunk) + 4).to_bytes(4, "little") + b"WEBP" + chunk
    file.write_bytes(data)
    spec = {"path": file.name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
    assert publication.checked_file(tmp_path, spec) == file
    assert publication.webp_dimensions(data) == (720, 1152)
    for damaged in (data[:-1], data.replace(b"VP8L", b"VP8 "), b"not-webp"):
        with pytest.raises(ValueError, match="WebP"):
            publication.webp_dimensions(damaged)
    for wrong in ({"path": "../page.webp"}, {"sha256": "a" * 64}, {"bytes": 999}):
        with pytest.raises(ValueError, match=r"[Bb]undle"):
            publication.checked_file(tmp_path, {**spec, **wrong})


@pytest.mark.django_db
def test_admin_cannot_manually_mutate_rendition_content(rendition: MushafRenditionRelease) -> None:
    request = Mock()
    for model in (MushafRendition, MushafRenditionRelease, MushafRenditionPage):
        view = admin.site._registry[model]
        assert not view.has_add_permission(request)
        assert not view.has_change_permission(request)
        assert not view.has_delete_permission(request)


def kfgqpc_source() -> dict[str, Any]:
    return {
        "kind": "quran-foundation",
        "source_id": 5,
        "edition": "kfgqpc-hafs",
        "source_checksum_sha256": publication.KFGQPC_SOURCE_SHA,
        "snapshot_sha256": publication.KFGQPC_SNAPSHOT_SHA,
        "font_sha256": publication.KFGQPC_FONT_SHA,
    }


def create_qf_source() -> QuranFoundationMushaf:
    return QuranFoundationMushaf.objects.create(
        environment=settings.QURAN_QF_ENV,
        source_id=5,
        name="KFGQPC HAFS",
        qirat_name="Hafs",
        pages_count=604,
        lines_per_page=15,
        schema_version="1",
        sync_sequence=1,
        source_checksum_sha256=publication.KFGQPC_SOURCE_SHA,
        last_synced_at=timezone.now(),
    )


def tajweed_source() -> dict[str, Any]:
    lock = json.loads(
        (Path(__file__).parent / "fixtures/mushaf/tajweed.source.lock.json").read_bytes()
    )
    return {
        "kind": "quran-foundation",
        "edition": "qcf-v4-tajweed-hafs",
        **lock,
        "decoration_font_sha256": publication.KFGQPC_FONT_SHA,
    }


@pytest.mark.parametrize(
    "field", ["source_id", "palette_index", "files", "snapshot_sha256", "decoration_font_sha256"]
)
def test_tajweed_requires_exact_color_fonts_snapshot_and_palette(field: str) -> None:
    source = tajweed_source()
    manifest = {"edition": "qcf-v4-tajweed-hafs", "source": source}
    assert publication.validate_source(manifest)
    source[field] = "wrong"
    assert not publication.validate_source(manifest)


@pytest.mark.django_db
@override_settings(MUSHAF_STAGING_PREVIEWS=True)
def test_tajweed_visibility_and_offline_provenance_are_source_specific(
    api_client: APIClient,
    rendition: MushafRenditionRelease,
) -> None:
    source = create_qf_source()
    source.source_id = 19
    source.source_checksum_sha256 = publication.TAJWEED_SOURCE_SHA
    source.save()
    rendition.source_metadata = tajweed_source()
    rendition.source_commit = ""
    rendition.save()
    visual = rendition.rendition
    visual.code = "qcf-v4-tajweed-hafs"
    visual.names = publication.RENDITION_NAMES[visual.code]
    visual.save()
    catalog_url = reverse("quran:rendition-list")
    assert api_client.get(catalog_url).json()[0]["code"] == visual.code
    payload = api_client.get(
        reverse("quran:rendition-offline", kwargs={"code": visual.code})
    ).json()
    assert payload["mushaf"]["source_id"] == 19
    assert payload["mushaf"]["name"] == "QCF V4 · Tajweed"
    assert "Quran.Foundation" in payload["source"]["name"]
    assert "JMApps" not in payload["rights"]["attribution"]
    # An identical checksum on a DIFFERENT source cannot authorize this release.
    source.source_id = 5
    source.save()
    assert api_client.get(catalog_url).json() == []


@pytest.mark.parametrize(
    "field", ["source_id", "font_sha256", "snapshot_sha256", "source_checksum_sha256", "kind"]
)
def test_kfgqpc_requires_the_matching_font_and_snapshot(field: str) -> None:
    source = kfgqpc_source()
    manifest = {"edition": "kfgqpc-hafs", "source": source}
    assert publication.validate_source(manifest)
    source[field] = "wrong"
    assert not publication.validate_source(manifest)
    assert not publication.validate_source({"edition": "unknown", "source": {}})


@pytest.mark.django_db
@override_settings(MUSHAF_STAGING_PREVIEWS=True)
def test_qf_snapshot_change_hides_only_derived_rendition(
    api_client: APIClient, rendition: MushafRenditionRelease
) -> None:
    source = create_qf_source()
    rendition.source_metadata = kfgqpc_source()
    rendition.source_commit = ""
    rendition.save()
    url = reverse("quran:rendition-list")
    assert len(api_client.get(url).json()) == 1
    source.source_checksum_sha256 = "b" * 64
    source.save()
    assert api_client.get(url).json() == []
    assert rendition.pages.count() == 1  # No content deletion.
    rendition.source_metadata = {}
    rendition.save()
    assert len(api_client.get(url).json()) == 1  # Existing JMApps unchanged.


@pytest.mark.django_db
def test_kfgqpc_publication_preserves_api_provenance_without_fake_git_commit(
    quran_dataset: dict[str, Any], monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    create_qf_source()
    manifest = {
        "edition": "kfgqpc-hafs",
        "version": "v1",
        "renderer": "test",
        "widths": [720],
        "source": kfgqpc_source(),
    }
    bundle = publication.PreparedRendition(
        manifest, "a" * 64, quran_dataset["version"], [page_fields(quran_dataset)], []
    )
    monkeypatch.setattr(publication, "prepare_rendition", lambda _: bundle)
    release = publication.publish_rendition(tmp_path / "manifest.json", uploader=Mock())
    assert release is not None
    assert release.source_commit == ""
    assert release.source_metadata == kfgqpc_source()
    assert release.rendition.names["ru"] == "KFGQPC HAFS"
    assert release.staging_only is True


@pytest.mark.django_db
def test_qf_change_during_upload_prevents_activation(
    quran_dataset: dict[str, Any], monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    source = create_qf_source()
    manifest = {"edition": "kfgqpc-hafs", "version": "v1", "source": kfgqpc_source()}
    bundle = publication.PreparedRendition(
        manifest,
        "a" * 64,
        quran_dataset["version"],
        [],
        [(tmp_path / "page.webp", ImmutableObjectSpec("test", "image/webp", 1, "a" * 64))],
    )
    monkeypatch.setattr(publication, "prepare_rendition", lambda _: bundle)

    def update_source(*args: Any) -> None:
        source.source_checksum_sha256 = "b" * 64
        source.save()

    uploader = Mock()
    uploader.upload_path.side_effect = update_source
    with pytest.raises(ValueError, match="source changed"):
        publication.publish_rendition(tmp_path / "manifest.json", uploader=uploader)
    assert not MushafRenditionRelease.objects.exists()


@pytest.mark.django_db
def test_export_source_is_public_content_only_and_rejects_partial_snapshot(
    quran_dataset: dict[str, Any],
) -> None:
    source = create_qf_source()
    output = StringIO()
    with pytest.raises(CommandError, match="Incomplete source"):
        call_command("export_qf_mushaf_source", mushaf=5, stdout=output)
    assert output.getvalue() == ""
    source.pages_count = 1
    source.save()
    QuranFoundationMushafPage.objects.create(
        mushaf=source,
        source_id=1,
        page_number=1,
        verse_mapping={"1": "1-2"},
        verses_count=2,
        words=[{"id": 1, "text": "بِسْمِ"}],
    )
    call_command("export_qf_mushaf_source", mushaf=5, stdout=output)
    exported = json.loads(output.getvalue())
    assert exported["source_checksum_sha256"] == publication.KFGQPC_SOURCE_SHA
    assert exported["surahs"][0]["number"] == 1
    assert set(exported["pages"][0]) == {"page_number", "verse_mapping", "words"}
    assert "environment" not in exported
    assert "settings" not in exported
    assert source.cached_pages.count() == 1


def test_bounded_parallel_uploads_finish_before_returning(tmp_path: Path) -> None:
    uploads = [
        (tmp_path / f"{n}.webp", ImmutableObjectSpec(str(n), "image/webp", 1, "a" * 64))
        for n in range(30)
    ]
    uploader = Mock()
    publication.upload_files(uploads, uploader, workers=4)
    assert uploader.upload_path.call_count == 30
    assert {call.args[1].key for call in uploader.upload_path.call_args_list} == {
        str(n) for n in range(30)
    }
    uploader.upload_path.side_effect = ObjectStorageError("failed")
    with pytest.raises(ObjectStorageError):
        publication.upload_files(uploads, uploader, workers=4)
    with pytest.raises(ValueError, match="workers"):
        publication.upload_files(uploads, uploader, workers=100)
