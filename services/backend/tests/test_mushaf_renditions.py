from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any
from unittest.mock import Mock

import pytest
from django.contrib import admin
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
)
from quran_backend.modules.quran.serializers import OfflineMushafManifestSerializer


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
