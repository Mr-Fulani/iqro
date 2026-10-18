from __future__ import annotations

import json
import shutil
import subprocess
from email.message import Message
from pathlib import Path
from typing import Any
from unittest.mock import MagicMock, patch
from urllib.error import HTTPError

import pytest
from django.contrib import admin
from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import Client
from django.urls import reverse
from django.utils import timezone
from rest_framework.exceptions import ValidationError as DRFValidationError

from quran_backend.modules.accounts.models import User
from quran_backend.modules.audio.admin import (
    RecitationEditionAdmin,
    RecitationEditionAdminForm,
    ReciterAdminForm,
)
from quran_backend.modules.audio.models import (
    AudioCodec,
    AudioContentType,
    AudioRendition,
    AudioRenditionQuality,
    AudioTimingVersion,
    AudioTrack,
    AudioTrackScope,
    AyahAudioSegment,
    RecitationEdition,
    RecitationPublicationStatus,
    RecitationStyle,
    Reciter,
)
from quran_backend.modules.audio.selectors import public_recitation_base, public_reciters
from quran_backend.modules.audio.surah_upload import (
    SurahUploadError,
    surah_number_from_filename,
    upload_surah_audio,
    verify_public_audio_object,
)
from quran_backend.modules.audio.variant_resolver import (
    AudioVariantResolver,
    AudioVariantRole,
    AudioVariantRoleNotSupportedError,
)
from quran_backend.modules.core.object_storage import StoredObject
from quran_backend.modules.memorization.services import _published_recitation
from quran_backend.modules.quran.models import PublicationStatus, QuranEditionVersion

needs_ffmpeg = pytest.mark.skipif(
    shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None,
    reason="ffmpeg is not installed",
)


def _reciter(code: str = "listening-reciter") -> Reciter:
    return Reciter.objects.create(
        code=code,
        name_ar="قارئ",
        name_en="Listening Reciter",
        name_ru="Чтец для прослушивания",
    )


def _recitation(
    quran_dataset: dict[str, Any],
    *,
    reciter: Reciter | None = None,
    listening_only: bool = True,
    code: str = "listening-recitation",
) -> RecitationEdition:
    return RecitationEdition.objects.create(
        code=code,
        version="1",
        reciter=reciter or _reciter(),
        quran_edition_version=quran_dataset["version"],
        listening_only=listening_only,
        source_name="Studio upload",
        source_version="1",
        source_checksum_sha256="" if listening_only else "c" * 64,
        rights_holder="Studio",
        license_name="Written permission",
    )


def _add_surah(recitation: RecitationEdition, surah_number: int, **rendition: Any) -> AudioTrack:
    track = AudioTrack.objects.create(
        recitation_edition=recitation,
        scope=AudioTrackScope.SURAH,
        surah_number=surah_number,
        duration_ms=60_000,
    )
    values: dict[str, Any] = {
        "track": track,
        "quality": AudioRenditionQuality.STANDARD,
        "is_default": True,
        "codec": AudioCodec.MP3,
        "content_type": AudioContentType.MPEG,
        "bitrate_kbps": 128,
        "size_bytes": 960_000,
        "checksum_sha256": f"{surah_number:064x}",
        "object_key": f"audio/recitations/{recitation.code}/1/surah-{surah_number:03d}.mp3",
        "origin_etag": f'"origin-{surah_number}"',
        "etag": f'"edge-{surah_number}"',
        "cdn_contract_verified_at": timezone.now(),
    }
    values.update(rendition)
    AudioRendition.objects.create(**values)
    return track


def _publish(recitation: RecitationEdition) -> None:
    recitation.stream_allowed = True
    recitation.offline_download_allowed = False
    recitation.publish()
    recitation.save()


@pytest.fixture
def listening(quran_dataset: dict[str, Any]) -> RecitationEdition:
    recitation = _recitation(quran_dataset)
    _add_surah(recitation, 1)
    _add_surah(recitation, 112)
    _publish(recitation)
    return recitation


def test_partial_listening_recitation_is_public(listening: RecitationEdition) -> None:
    assert public_recitation_base().filter(pk=listening.pk).exists()
    assert public_reciters().filter(pk=listening.reciter_id).exists()


def test_partial_recitation_with_ayah_roles_stays_hidden(
    quran_dataset: dict[str, Any],
) -> None:
    recitation = _recitation(quran_dataset, listening_only=False, code="timed-partial")
    _add_surah(recitation, 1)
    _publish(recitation)

    assert not public_recitation_base().filter(pk=recitation.pk).exists()


def test_listening_recitation_survives_a_newer_quran_version(
    quran_dataset: dict[str, Any],
    listening: RecitationEdition,
) -> None:
    edition = quran_dataset["version"].edition
    newer = QuranEditionVersion.objects.create(
        edition=edition,
        version="2.0.0",
        checksum_sha256="b" * 64,
        status=PublicationStatus.PUBLISHED,
        page_count=604,
        surah_count=114,
        juz_count=30,
        hizb_count=1,
        rub_el_hizb_count=1,
        published_at=timezone.now(),
    )
    edition.active_version = newer
    edition.save(update_fields=["active_version", "updated_at"])

    assert public_recitation_base().filter(pk=listening.pk).exists()


def test_catalog_lists_surahs_and_keeps_listening_audio_out_of_ayah_roles(
    api_client: Any,
    quran_dataset: dict[str, Any],
) -> None:
    recitation = _recitation(quran_dataset)
    track = _add_surah(recitation, 1)
    timing = AudioTimingVersion.objects.create(
        recitation_edition=recitation,
        version="1",
        source_name="Timings",
        source_version="1",
        source_checksum_sha256="e" * 64,
        verified_at=timezone.now(),
    )
    track.timing_version = timing
    track.save()
    for ayah, start in ((quran_dataset["first_ayah"], 0), (quran_dataset["second_ayah"], 30_000)):
        AyahAudioSegment.objects.create(
            track=track, ayah=ayah, start_ms=start, end_ms=start + 30_000
        )
    _publish(recitation)

    body = api_client.get(reverse("audio:recitation-detail", args=[recitation.pk])).json()

    assert body["coverage"]["surah_numbers"] == [1]
    assert body["coverage"]["complete"] is False
    assert body["timings"]["complete"] is True
    assert body["capabilities"] == {
        "listen": True,
        "ayah_playback": False,
        "memorization": False,
        "offline": False,
    }
    with pytest.raises(AudioVariantRoleNotSupportedError):
        AudioVariantResolver().resolve(str(recitation.pk), role=AudioVariantRole.AYAH_PLAYBACK)
    with pytest.raises(DRFValidationError, match="public recitation"):
        _published_recitation(
            recitation.pk,
            edition_version_id=quran_dataset["version"].id,
            start_ayah=quran_dataset["first_ayah"],
            end_ayah=quran_dataset["second_ayah"],
        )


def test_published_listening_recitation_accepts_new_surahs(
    listening: RecitationEdition,
) -> None:
    _add_surah(listening, 113)

    assert sorted(listening.tracks.values_list("surah_number", flat=True)) == [1, 112, 113]


def test_new_surah_after_publication_needs_cdn_evidence(listening: RecitationEdition) -> None:
    with pytest.raises(ValidationError, match="CDN evidence"):
        _add_surah(listening, 113, etag="", cdn_contract_verified_at=None)


def test_published_surahs_stay_immutable(listening: RecitationEdition) -> None:
    track = listening.tracks.get(surah_number=1)
    track.duration_ms = 1
    with pytest.raises(ValidationError):
        track.save()
    with pytest.raises(ValidationError):
        track.delete()
    with pytest.raises(ValidationError, match="keep their renditions"):
        AudioRendition.objects.create(
            track=track,
            quality=AudioRenditionQuality.HIGH,
            codec=AudioCodec.MP3,
            content_type=AudioContentType.MPEG,
            bitrate_kbps=256,
            size_bytes=1_920_000,
            checksum_sha256="f" * 64,
            object_key="audio/recitations/listening-recitation/1/surah-001-high.mp3",
            origin_etag='"origin-high"',
            etag='"edge-high"',
            cdn_contract_verified_at=timezone.now(),
        )


def test_published_timed_recitation_accepts_no_new_surahs(
    quran_dataset: dict[str, Any],
) -> None:
    recitation = _recitation(quran_dataset, listening_only=False, code="timed")
    _add_surah(recitation, 1)
    _publish(recitation)

    with pytest.raises(ValidationError, match="immutable"):
        _add_surah(recitation, 2)


def test_withdrawn_listening_recitation_accepts_no_new_surahs(
    listening: RecitationEdition,
) -> None:
    listening.withdraw()
    listening.save()

    with pytest.raises(ValidationError, match="immutable"):
        _add_surah(listening, 113)


def test_timed_recitation_still_needs_a_source_checksum(quran_dataset: dict[str, Any]) -> None:
    with pytest.raises(ValidationError, match="source checksum"):
        RecitationEdition.objects.create(
            code="no-checksum",
            version="1",
            reciter=_reciter("no-checksum"),
            quran_edition_version=quran_dataset["version"],
            source_name="Studio",
            source_version="1",
            rights_holder="Studio",
            license_name="Permission",
        )


@pytest.mark.parametrize(
    ("name", "expected"),
    [
        ("001.mp3", 1),
        ("2.mp3", 2),
        ("112 Al-Ikhlas.mp3", 112),
        ("114-an-nas.mp3", 114),
        ("folder/018.mp3", 18),
        ("115.mp3", None),
        ("0.mp3", None),
        ("1234.mp3", None),
        ("Al-Fatiha.mp3", None),
    ],
)
def test_surah_number_is_read_from_the_file_name(name: str, expected: int | None) -> None:
    assert surah_number_from_filename(name) == expected


class _RecordingUploader:
    def __init__(self) -> None:
        self.keys: list[str] = []

    def upload_path(self, source_path: Path, spec: Any) -> StoredObject:
        assert source_path.stat().st_size == spec.size_bytes
        self.keys.append(spec.key)
        return StoredObject(key=spec.key, etag=f'"{spec.checksum_sha256}"', created=True)


def _mp3(tmp_path: Path, seconds: int = 2) -> Path:
    target = tmp_path / "surah.mp3"
    subprocess.run(  # noqa: S603 - fixed test command
        [
            shutil.which("ffmpeg") or "ffmpeg",
            "-nostdin",
            "-loglevel",
            "error",
            "-f",
            "lavfi",
            "-i",
            f"sine=frequency=440:duration={seconds}",
            "-c:a",
            "libmp3lame",
            "-b:a",
            "64k",
            str(target),
        ],
        check=True,
    )
    return target


@needs_ffmpeg
def test_upload_measures_stores_and_adds_a_surah(
    tmp_path: Path,
    listening: RecitationEdition,
    django_capture_on_commit_callbacks: Any,
) -> None:
    uploader = _RecordingUploader()
    checks: list[tuple[str, int, str]] = []

    def verify(url: str, size: int, content_type: str) -> str:
        checks.append((url, size, content_type))
        return '"edge"'

    with (
        patch("quran_backend.modules.audio.surah_upload.enqueue_audio_content_change") as announce,
        django_capture_on_commit_callbacks(execute=True),
    ):
        result = upload_surah_audio(
            listening.pk, 113, _mp3(tmp_path), uploader=uploader, verify_public=verify
        )

    rendition = AudioRendition.objects.get(track_id=result.track_id)
    assert result.surah_number == 113
    assert 1_900 <= result.duration_ms <= 2_200
    assert rendition.object_key == uploader.keys[0]
    assert rendition.object_key.startswith("audio/recitations/listening-recitation/1/surah-113-")
    assert rendition.etag == '"edge"'
    assert rendition.cdn_contract_verified_at is not None
    assert checks[0][0].endswith(rendition.object_key)
    announce.assert_called_once()
    assert public_recitation_base().filter(pk=listening.pk).exists()


@needs_ffmpeg
def test_upload_rejects_a_surah_that_is_already_there(
    tmp_path: Path,
    listening: RecitationEdition,
) -> None:
    with pytest.raises(SurahUploadError, match="уже есть"):
        upload_surah_audio(listening.pk, 1, _mp3(tmp_path), uploader=_RecordingUploader())


def test_upload_rejects_files_that_are_not_mp3(
    tmp_path: Path,
    listening: RecitationEdition,
) -> None:
    source = tmp_path / "notes.mp3"
    source.write_bytes(b"not audio at all")
    uploader = _RecordingUploader()

    with pytest.raises(SurahUploadError, match="MP3"):
        upload_surah_audio(listening.pk, 2, source, uploader=uploader)
    assert uploader.keys == []


def test_upload_rejects_a_published_timed_recitation(
    tmp_path: Path,
    quran_dataset: dict[str, Any],
) -> None:
    recitation = _recitation(quran_dataset, listening_only=False, code="timed-upload")
    _add_surah(recitation, 1)
    _publish(recitation)
    source = tmp_path / "surah.mp3"
    source.write_bytes(b"x")

    with pytest.raises(SurahUploadError, match="черновик"):
        upload_surah_audio(recitation.pk, 2, source, uploader=_RecordingUploader())


def _head_response(headers: dict[str, str], status: int = 200) -> MagicMock:
    message = Message()
    for key, value in headers.items():
        message[key] = value
    response = MagicMock()
    response.status = status
    response.headers = message
    response.__enter__.return_value = response
    return response


GOOD_HEADERS = {
    "Content-Length": "1000",
    "Content-Type": "audio/mpeg",
    "ETag": '"abc"',
    "Cache-Control": "public, max-age=31536000, immutable",
}


def test_cdn_check_returns_the_served_etag() -> None:
    with patch(
        "quran_backend.modules.audio.surah_upload.urlopen",
        return_value=_head_response(GOOD_HEADERS),
    ):
        etag = verify_public_audio_object("https://media.example/a.mp3", 1000, "audio/mpeg")

    assert etag == '"abc"'


@pytest.mark.parametrize(
    ("override", "problem"),
    [
        ({"Content-Length": "999"}, "размер"),
        ({"Content-Type": "text/html"}, "тип файла"),
        ({"ETag": 'W/"abc"'}, "ETag"),
        ({"Cache-Control": "public, max-age=60"}, "Cache-Control"),
    ],
)
def test_cdn_check_names_what_the_cdn_serves_wrong(override: dict[str, str], problem: str) -> None:
    with (
        patch(
            "quran_backend.modules.audio.surah_upload.urlopen",
            return_value=_head_response({**GOOD_HEADERS, **override}),
        ),
        pytest.raises(SurahUploadError, match=problem),
    ):
        verify_public_audio_object("https://media.example/a.mp3", 1000, "audio/mpeg")


def test_cdn_check_reports_missing_files_and_refuses_plain_http() -> None:
    missing = HTTPError("https://media.example/a.mp3", 404, "Not Found", Message(), None)
    with (
        patch("quran_backend.modules.audio.surah_upload.urlopen", side_effect=missing),
        pytest.raises(SurahUploadError, match="404"),
    ):
        verify_public_audio_object("https://media.example/a.mp3", 1000, "audio/mpeg")
    with pytest.raises(SurahUploadError, match="HTTPS"):
        verify_public_audio_object("http://media.example/a.mp3", 1000, "audio/mpeg")


def _staff(*, superuser: bool = True) -> User:
    return User.objects.create_user(
        email=f"editor-{superuser}@example.test",
        status="active",
        is_staff=True,
        is_superuser=superuser,
    )


def test_admin_form_names_and_versions_a_new_listening_recitation(
    quran_dataset: dict[str, Any],
) -> None:
    reciter = _reciter("saad-al-ghamdi")
    _recitation(quran_dataset, reciter=reciter, code="saad-al-ghamdi-murattal")
    data = {
        "reciter": str(reciter.pk),
        "style": RecitationStyle.MURATTAL,
        "listening_only": "on",
        "quran_edition_version": str(quran_dataset["version"].pk),
        "status": RecitationPublicationStatus.DRAFT,
        "rights_holder": "Studio",
        "license_name": "Written permission",
        "stream_allowed": "true",
        "offline_download_allowed": "false",
        "source_name": "Studio upload",
    }

    form = RecitationEditionAdminForm(data=data)

    assert form.is_valid(), form.errors
    recitation = form.save()
    assert recitation.code == "saad-al-ghamdi-murattal"
    assert recitation.version == "2"
    assert recitation.source_version == "2"
    assert recitation.listening_only is True


def test_admin_form_dates_the_publication_itself(listening: RecitationEdition) -> None:
    draft = RecitationEdition.objects.create(
        code="to-publish",
        version="1",
        reciter=listening.reciter,
        quran_edition_version=listening.quran_edition_version,
        style=RecitationStyle.MUJAWWAD,
        listening_only=True,
        source_name="Studio",
        source_version="1",
        rights_holder="Studio",
        license_name="Permission",
        stream_allowed=True,
        offline_download_allowed=False,
    )
    _add_surah(draft, 1)
    form = RecitationEditionAdminForm(
        instance=draft,
        data={
            "reciter": str(draft.reciter_id),
            "style": draft.style,
            "listening_only": "on",
            "quran_edition_version": str(draft.quran_edition_version_id),
            "status": RecitationPublicationStatus.PUBLISHED,
            "rights_holder": "Studio",
            "license_name": "Permission",
            "stream_allowed": "true",
            "offline_download_allowed": "false",
            "source_name": "Studio",
            "code": draft.code,
            "version": draft.version,
            "source_version": draft.version,
        },
    )

    assert form.is_valid(), form.errors
    published = form.save()
    assert published.status == RecitationPublicationStatus.PUBLISHED
    assert published.published_at is not None


@needs_ffmpeg
def test_admin_upload_view_adds_surahs_for_staff_only(
    tmp_path: Path,
    listening: RecitationEdition,
) -> None:
    url = reverse("admin:audio_recitationedition_upload_surah", args=[listening.pk])
    client = Client()
    client.force_login(_staff())
    mp3 = _mp3(tmp_path).read_bytes()

    assert client.get(url).status_code == 405
    with (
        patch(
            "quran_backend.modules.audio.surah_upload.surah_audio_uploader",
            return_value=_RecordingUploader(),
        ),
        patch(
            "quran_backend.modules.audio.surah_upload.verify_public_audio_object",
            return_value='"edge"',
        ),
    ):
        added = client.post(url, {"file": SimpleUploadedFile("018 Al-Kahf.mp3", mp3)})
        duplicate = client.post(
            url, {"surah_number": "18", "file": SimpleUploadedFile("x.mp3", mp3)}
        )

    assert added.status_code == 200, added.content
    assert json.loads(added.content)["surah_number"] == 18
    assert duplicate.status_code == 400
    assert "уже есть" in json.loads(duplicate.content)["error"]

    outsider = Client()
    outsider.force_login(_staff(superuser=False))
    assert outsider.post(url, {"file": SimpleUploadedFile("19.mp3", mp3)}).status_code == 403


def test_admin_shows_where_a_recitation_plays(listening: RecitationEdition) -> None:
    model_admin = RecitationEditionAdmin(RecitationEdition, admin.site)

    assert "«Аудио»" in model_admin.catalog_status(listening)
    coverage = model_admin.surah_coverage(listening)
    assert "2 из 114: 1, 112" in coverage
    assert "data-surah-upload" in coverage


def test_rejected_reciter_form_leaves_no_portrait_in_storage(db: None) -> None:
    _reciter("taken-code")
    portrait = SimpleUploadedFile("p.png", b"\x89PNG\r\n\x1a\n" + b"0" * 32)
    form = ReciterAdminForm(
        data={"code": "taken-code", "name_ar": "ق", "name_en": "Dup", "name_ru": "Дубль"},
        files={"portrait_upload": portrait},
    )

    with patch("quran_backend.modules.audio.admin.upload_reciter_portrait") as upload:
        assert not form.is_valid()

    upload.assert_not_called()


def test_admin_pages_for_adding_a_reciter_and_a_recording_render(
    listening: RecitationEdition,
) -> None:
    client = Client()
    client.force_login(_staff())

    reciter_add = client.get(reverse("admin:audio_reciter_add"))
    reciter_change = client.get(reverse("admin:audio_reciter_change", args=[listening.reciter_id]))
    recitation_add = client.get(
        reverse("admin:audio_recitationedition_add"),
        {"reciter": str(listening.reciter_id), "listening_only": "1"},
    )
    recitation_change = client.get(
        reverse("admin:audio_recitationedition_change", args=[listening.pk])
    )

    assert reciter_add.status_code == 200
    assert "Сохраните чтеца" in reciter_add.content.decode()
    assert reciter_change.status_code == 200
    assert "Добавить запись для прослушивания" in reciter_change.content.decode()
    assert recitation_add.status_code == 200
    assert recitation_change.status_code == 200
    assert "data-surah-upload" in recitation_change.content.decode()
    assert "audio/admin/surah_upload.js" in recitation_change.content.decode()
