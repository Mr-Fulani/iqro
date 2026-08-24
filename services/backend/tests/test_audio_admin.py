from __future__ import annotations

from typing import Any

import pytest
from django.contrib import admin
from django.test import RequestFactory
from django.utils import timezone

from quran_backend.modules.accounts.models import User
from quran_backend.modules.audio.admin import (
    AudioRenditionAdmin,
    AudioTimingVersionAdmin,
    AudioTrackAdmin,
    AyahAudioSegmentAdmin,
    RecitationEditionAdmin,
)
from quran_backend.modules.audio.models import (
    AudioCodec,
    AudioRendition,
    AudioRenditionQuality,
    AudioTimingVersion,
    AudioTrack,
    AudioTrackScope,
    AyahAudioSegment,
    RecitationEdition,
    Reciter,
)


def _create_audio_aggregate(
    quran_dataset: dict[str, Any],
    *,
    suffix: str,
    publish: bool,
) -> tuple[
    RecitationEdition,
    AudioTimingVersion,
    AudioTrack,
    AudioRendition,
    AyahAudioSegment,
]:
    reciter = Reciter.objects.create(
        code=f"admin-reciter-{suffix}",
        name_ar="قارئ الإدارة",
        name_en=f"Admin Reciter {suffix}",
        name_ru=f"Админ-чтец {suffix}",
    )
    recitation = RecitationEdition.objects.create(
        code=f"admin-recitation-{suffix}",
        version="1.0.0",
        reciter=reciter,
        quran_edition_version=quran_dataset["version"],
        source_name="Synthetic admin source",
        source_version="1.0.0",
        source_checksum_sha256="a" * 64,
        rights_holder="Synthetic rights holder",
        license_name="Synthetic test license",
    )
    timing = AudioTimingVersion.objects.create(
        recitation_edition=recitation,
        version="1.0.0",
        source_name="Synthetic timing source",
        source_version="1.0.0",
        source_checksum_sha256="b" * 64,
        verified_at=timezone.now(),
    )
    track = AudioTrack.objects.create(
        recitation_edition=recitation,
        timing_version=timing,
        scope=AudioTrackScope.SURAH,
        surah_number=1,
        duration_ms=10_000,
    )
    rendition = AudioRendition.objects.create(
        track=track,
        quality=AudioRenditionQuality.STANDARD,
        is_default=True,
        codec=AudioCodec.MP3,
        bitrate_kbps=128,
        size_bytes=160_000,
        checksum_sha256="c" * 64,
        object_key=f"audio/admin/{suffix}/001.mp3",
        origin_etag='"origin-admin-etag"',
        etag='"edge-admin-etag"',
        cdn_contract_verified_at=timezone.now(),
    )
    segment = AyahAudioSegment.objects.create(
        track=track,
        ayah=quran_dataset["first_ayah"],
        start_ms=0,
        end_ms=1000,
    )
    if publish:
        recitation.stream_allowed = True
        recitation.offline_download_allowed = True
        recitation.publish()
        recitation.save()
    return recitation, timing, track, rendition, segment


@pytest.mark.django_db
def test_audio_admin_disables_bulk_delete_and_protects_published_aggregate(
    quran_dataset: dict[str, Any],
) -> None:
    published = _create_audio_aggregate(quran_dataset, suffix="published", publish=True)
    operator = User.objects.create_user(
        email="audio-admin@example.test",
        status="active",
        is_staff=True,
        is_superuser=True,
    )
    request = RequestFactory().get("/admin/audio/")
    request.user = operator

    admin_objects = (
        RecitationEditionAdmin(RecitationEdition, admin.site),
        AudioTimingVersionAdmin(AudioTimingVersion, admin.site),
        AudioTrackAdmin(AudioTrack, admin.site),
        AudioRenditionAdmin(AudioRendition, admin.site),
        AyahAudioSegmentAdmin(AyahAudioSegment, admin.site),
    )
    for model_admin, obj in zip(admin_objects, published, strict=True):
        assert "delete_selected" not in model_admin.get_actions(request)
        assert model_admin.has_delete_permission(request, None) is False
        assert model_admin.has_delete_permission(request, obj) is False


@pytest.mark.django_db
def test_audio_admin_allows_individual_draft_cleanup_and_preloads_display_relations(
    quran_dataset: dict[str, Any],
) -> None:
    draft = _create_audio_aggregate(quran_dataset, suffix="draft", publish=False)
    operator = User.objects.create_user(
        email="audio-draft-admin@example.test",
        status="active",
        is_staff=True,
        is_superuser=True,
    )
    request = RequestFactory().get("/admin/audio/")
    request.user = operator
    admin_objects = (
        RecitationEditionAdmin(RecitationEdition, admin.site),
        AudioTimingVersionAdmin(AudioTimingVersion, admin.site),
        AudioTrackAdmin(AudioTrack, admin.site),
        AudioRenditionAdmin(AudioRendition, admin.site),
        AyahAudioSegmentAdmin(AyahAudioSegment, admin.site),
    )

    for model_admin, obj in zip(admin_objects, draft, strict=True):
        assert model_admin.has_delete_permission(request, obj) is True

    assert "quran_edition_version__edition" in admin_objects[0].list_select_related
    assert "timing_version__recitation_edition" in admin_objects[2].list_select_related
    assert "track__recitation_edition" in admin_objects[3].list_select_related
    assert "origin_etag" in admin_objects[3].get_readonly_fields(request, draft[3])
    assert "etag" in admin_objects[3].get_readonly_fields(request, draft[3])
    assert "cdn_contract_verified_at" in admin_objects[3].get_readonly_fields(request, draft[3])
    assert "ayah__surah__edition_version__edition" in admin_objects[4].list_select_related
