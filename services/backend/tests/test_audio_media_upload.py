from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

import pytest
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import override_settings
from django.utils import timezone

from quran_backend.modules.audio.media_contract import (
    AudioMediaContractError,
    record_audio_media_contract,
)
from quran_backend.modules.audio.media_upload import (
    AudioMediaUploadError,
    upload_audio_rendition,
)
from quran_backend.modules.audio.models import (
    AudioCodec,
    AudioContentType,
    AudioRendition,
    AudioRenditionQuality,
    AudioTrack,
    AudioTrackScope,
    RecitationEdition,
    RecitationPublicationStatus,
    RecitationStyle,
    Reciter,
)
from quran_backend.modules.core.object_storage import ImmutableObjectSpec, StoredObject
from quran_backend.modules.quran.models import QuranEdition, QuranEditionVersion


class FakeUploader:
    def __init__(self, *, etag: str = '"uploaded-etag"') -> None:
        self.etag = etag
        self.calls: list[tuple[Path, ImmutableObjectSpec]] = []

    def upload_path(self, source_path: Path, spec: ImmutableObjectSpec) -> StoredObject:
        self.calls.append((source_path, spec))
        return StoredObject(key=spec.key, etag=self.etag, created=True)


@pytest.fixture
def managed_rendition(db: Any, tmp_path: Path) -> tuple[AudioRendition, Path]:
    quran_edition = QuranEdition.objects.create(
        code="media-upload-hafs",
        name_ar="حفص",
        name_en="Hafs",
        name_ru="Хафс",
        riwayah="Hafs 'an Asim",
        source_name="Test",
        source_url="https://example.test/quran",
        license_name="Test license",
        license_url="https://example.test/license",
    )
    version = QuranEditionVersion.objects.create(
        edition=quran_edition,
        version="1.0.0",
        checksum_sha256="a" * 64,
        page_count=604,
        surah_count=114,
        juz_count=30,
    )
    reciter = Reciter.objects.create(
        code="media-upload-reciter",
        name_ar="قارئ",
        name_en="Reciter",
        name_ru="Чтец",
    )
    recitation = RecitationEdition.objects.create(
        reciter=reciter,
        quran_edition_version=version,
        code="media-upload-recitation",
        version="1.0.0",
        style=RecitationStyle.MURATTAL,
        source_name="Test",
        source_version="2026-08-24",
        source_checksum_sha256="b" * 64,
        source_url="https://example.test/audio",
        rights_holder="Test rights holder",
        license_name="Test license",
        license_url="https://example.test/license",
        status=RecitationPublicationStatus.DRAFT,
    )
    track = AudioTrack.objects.create(
        recitation_edition=recitation,
        scope=AudioTrackScope.SURAH,
        surah_number=1,
        duration_ms=10_000,
    )
    payload = b"managed-audio-rendition"
    source = tmp_path / "surah-001.mp3"
    source.write_bytes(payload)
    rendition = AudioRendition.objects.create(
        track=track,
        quality=AudioRenditionQuality.STANDARD,
        is_default=True,
        codec=AudioCodec.MP3,
        content_type=AudioContentType.MPEG,
        bitrate_kbps=128,
        size_bytes=len(payload),
        checksum_sha256=hashlib.sha256(payload).hexdigest(),
        object_key="audio/media-upload/1.0.0/surah-001-standard.mp3",
    )
    return rendition, source


@pytest.mark.django_db
def test_upload_audio_rendition_records_observed_etag(
    managed_rendition: tuple[AudioRendition, Path],
) -> None:
    rendition, source = managed_rendition
    uploader = FakeUploader()

    result = upload_audio_rendition(rendition.id, source, uploader=uploader)

    rendition.refresh_from_db()
    assert rendition.origin_etag == '"uploaded-etag"'
    assert rendition.etag == ""
    assert result.created is True
    assert uploader.calls[0][1].checksum_sha256 == rendition.checksum_sha256


@pytest.mark.django_db
def test_upload_audio_rendition_rejects_external_provider(
    managed_rendition: tuple[AudioRendition, Path],
) -> None:
    rendition, source = managed_rendition
    rendition.object_key = None
    rendition.external_url = "https://audio.example.test/surah-001.mp3"
    rendition.checksum_sha256 = ""
    rendition.save()
    uploader = FakeUploader()

    with pytest.raises(AudioMediaUploadError, match="managed"):
        upload_audio_rendition(rendition.id, source, uploader=uploader)

    assert uploader.calls == []


@pytest.mark.django_db
def test_upload_audio_rendition_rejects_published_parent(
    managed_rendition: tuple[AudioRendition, Path],
) -> None:
    rendition, source = managed_rendition
    RecitationEdition.objects.filter(pk=rendition.track.recitation_edition_id).update(
        status=RecitationPublicationStatus.PUBLISHED,
        published_at=timezone.now(),
        stream_allowed=True,
        offline_download_allowed=False,
    )

    with pytest.raises(AudioMediaUploadError, match="draft"):
        upload_audio_rendition(rendition.id, source, uploader=FakeUploader())


@pytest.mark.django_db
def test_upload_audio_rendition_command_reports_configuration_error(
    managed_rendition: tuple[AudioRendition, Path],
) -> None:
    rendition, source = managed_rendition

    with pytest.raises(CommandError, match="MEDIA_OBJECT_STORAGE_ENABLED"):
        call_command("upload_audio_rendition", rendition.id, source)


def _write_contract_report(
    path: Path,
    rendition: AudioRendition,
    *,
    origins: list[str] | None = None,
) -> Path:
    report = {
        "schema_version": 1,
        "generated_at": timezone.now().isoformat(),
        "manifest": {"name": "audio-release", "version": 1},
        "origins": origins or ["https://www.example.test", "https://mini.example.test"],
        "min_cache_seconds": 31_536_000,
        "passed": True,
        "assets": [
            {
                "name": f"audio-rendition:{rendition.id}",
                "url": (f"https://media.example.test/{rendition.object_key}"),
                "passed": True,
                "failures": [],
                "observed_etag": '"edge-etag"',
                "observed_bytes": rendition.size_bytes,
                "observed_content_type": rendition.content_type,
            }
        ],
    }
    path.write_text(json.dumps(report), encoding="utf-8")
    return path


@pytest.mark.django_db
@override_settings(
    PUBLIC_AUDIO_BASE_URL="https://media.example.test/",
    MEDIA_CDN_REQUIRED_ORIGINS=[
        "https://www.example.test",
        "https://mini.example.test",
    ],
)
def test_record_audio_media_contract_records_edge_evidence(
    managed_rendition: tuple[AudioRendition, Path],
    tmp_path: Path,
) -> None:
    rendition, source = managed_rendition
    upload_audio_rendition(rendition.id, source, uploader=FakeUploader())
    report = _write_contract_report(tmp_path / "report.json", rendition)

    result = record_audio_media_contract(report)

    rendition.refresh_from_db()
    assert result.verified == 1
    assert rendition.origin_etag == '"uploaded-etag"'
    assert rendition.etag == '"edge-etag"'
    assert rendition.cdn_contract_verified_at is not None


@pytest.mark.django_db
@override_settings(
    PUBLIC_AUDIO_BASE_URL="https://media.example.test/",
    MEDIA_CDN_REQUIRED_ORIGINS=["https://www.example.test"],
)
def test_record_audio_media_contract_requires_origin_upload_first(
    managed_rendition: tuple[AudioRendition, Path],
    tmp_path: Path,
) -> None:
    rendition, _source = managed_rendition
    report = _write_contract_report(tmp_path / "report.json", rendition)

    with pytest.raises(AudioMediaContractError, match="origin-verified"):
        record_audio_media_contract(report)


@pytest.mark.django_db
@override_settings(
    PUBLIC_AUDIO_BASE_URL="https://media.example.test/",
    MEDIA_CDN_REQUIRED_ORIGINS=["https://mini.example.test"],
)
def test_record_audio_media_contract_requires_every_client_origin(
    managed_rendition: tuple[AudioRendition, Path],
    tmp_path: Path,
) -> None:
    rendition, source = managed_rendition
    upload_audio_rendition(rendition.id, source, uploader=FakeUploader())
    report = _write_contract_report(
        tmp_path / "report.json",
        rendition,
        origins=["https://www.example.test"],
    )

    with pytest.raises(AudioMediaContractError, match="REQUIRED_ORIGINS"):
        record_audio_media_contract(report)
