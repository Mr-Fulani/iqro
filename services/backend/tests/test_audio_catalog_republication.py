from __future__ import annotations

import io
import json
from typing import Any

import pytest
from django.core.exceptions import ValidationError
from django.core.management import call_command
from django.utils import timezone

from quran_backend.modules.audio.catalog_republication import republish_audio_catalog
from quran_backend.modules.audio.models import (
    AudioRendition,
    AudioTimingVersion,
    AudioTrack,
    AyahAudioSegment,
    RecitationEdition,
    Reciter,
)
from quran_backend.modules.audio.selectors import public_recitation_base, public_reciters
from quran_backend.modules.quran.models import Ayah, QuranEditionVersion, Surah


@pytest.fixture
def catalog(quran_dataset: dict[str, Any]) -> dict[str, Any]:
    source = quran_dataset["version"]
    reciter = Reciter.objects.create(
        code="preserved-reciter",
        name_en="Preserved Reciter",
        name_ar="قارئ",
        name_ru="Чтец",
        portrait_object_key="audio/reciters/preserved.webp",
    )
    recitation = RecitationEdition.objects.create(
        code="qf-7-murattal-000000000001",
        version="source-release",
        reciter=reciter,
        quran_edition_version=source,
        source_name="Approved existing source",
        source_version="v1",
        source_checksum_sha256="a" * 64,
        rights_holder="Existing rights holder",
        license_name="Existing terms",
        stream_allowed=True,
        offline_download_allowed=False,
    )
    timing = AudioTimingVersion.objects.create(
        recitation_edition=recitation,
        version="timing-v1",
        source_name="Verified source",
        source_version="v1",
        source_checksum_sha256="b" * 64,
        verified_at=timezone.now(),
    )
    tracks = AudioTrack.objects.bulk_create(
        [
            AudioTrack(
                recitation_edition=recitation,
                timing_version=timing,
                scope="surah",
                surah_number=n,
                duration_ms=10000,
            )
            for n in range(1, 115)
        ]
    )
    AudioRendition.objects.bulk_create(
        [
            AudioRendition(
                track=t,
                quality="standard",
                is_default=True,
                codec="mp3",
                content_type="audio/mpeg",
                bitrate_kbps=128,
                size_bytes=100000,
                object_key=None,
                external_url=f"https://audio.example.test/{t.surah_number}.mp3",
            )
            for t in tracks
        ]
    )
    AyahAudioSegment.objects.bulk_create(
        [
            AyahAudioSegment(
                track=tracks[0], ayah=quran_dataset["first_ayah"], start_ms=0, end_ms=5000
            ),
            AyahAudioSegment(
                track=tracks[0], ayah=quran_dataset["second_ayah"], start_ms=5000, end_ms=10000
            ),
        ]
    )
    recitation.publish()
    recitation.save()
    target = QuranEditionVersion.objects.create(
        edition=source.edition,
        version="1.0.1",
        checksum_sha256="c" * 64,
        status="published",
        published_at=timezone.now(),
    )
    surah = Surah.objects.create(
        edition_version=target,
        number=1,
        name_ar="الفاتحة",
        name_en="Al-Fatihah",
        name_ru="Аль-Фатиха",
        revelation_type="meccan",
        ayah_count=2,
    )
    for ayah in (quran_dataset["first_ayah"], quran_dataset["second_ayah"]):
        Ayah.objects.create(
            surah=surah,
            number=ayah.number,
            text_uthmani=ayah.text_uthmani,
            text_search=ayah.text_search,
            juz_number=ayah.juz_number,
            hizb_number=ayah.hizb_number,
            rub_el_hizb_number=ayah.rub_el_hizb_number,
        )
    edition = source.edition
    edition.active_version = target
    edition.save(update_fields=["active_version"])
    return {
        "source": source,
        "target": target,
        "recitation": recitation,
        "reciter": reciter,
        "timing": timing,
    }


def _run(*, apply: bool = False) -> dict[str, int]:
    return republish_audio_catalog(
        edition_code="madani-hafs",
        source_version="1.0.0",
        target_version="1.0.1",
        source_release="source-release",
        release_version="restored-release",
        apply=apply,
    )


@pytest.mark.django_db
def test_dry_run_and_command_do_not_change_catalog(catalog: dict[str, Any]) -> None:
    assert public_recitation_base().count() == 0
    assert _run() == {
        "ayahs_verified": 2,
        "recitations": 1,
        "created": 0,
        "existing": 0,
        "tracks": 114,
        "segments": 2,
    }
    output = io.StringIO()
    call_command(
        "republish_audio_catalog",
        edition="madani-hafs",
        source_version="1.0.0",
        target_version="1.0.1",
        source_release="source-release",
        release_version="restored-release",
        stdout=output,
    )
    assert json.loads(output.getvalue())["applied"] is False
    assert RecitationEdition.objects.count() == 1
    assert AudioTrack.objects.count() == 114
    assert catalog["reciter"].portrait_object_key == "audio/reciters/preserved.webp"


@pytest.mark.django_db
def test_republication_preserves_originals_media_portraits_and_remaps_timings(
    catalog: dict[str, Any],
) -> None:
    assert _run(apply=True)["created"] == 1
    published = public_recitation_base().get()
    assert public_reciters().get().pk == catalog["reciter"].pk
    assert published.quran_edition_version_id == catalog["target"].pk
    assert published.stream_allowed is True
    assert published.offline_download_allowed is False
    old = RecitationEdition.objects.get(pk=catalog["recitation"].pk)
    assert old.quran_edition_version_id == catalog["source"].pk
    assert old.status == "published"
    assert set(
        AudioRendition.objects.filter(track__recitation_edition=old).values_list(
            "external_url", flat=True
        )
    ) == set(
        AudioRendition.objects.filter(track__recitation_edition=published).values_list(
            "external_url", flat=True
        )
    )
    assert list(
        AyahAudioSegment.objects.filter(track__recitation_edition=published)
        .order_by("start_ms")
        .values_list("ayah__surah__edition_version_id", "ayah__number", "start_ms", "end_ms")
    ) == [(catalog["target"].pk, 1, 0, 5000), (catalog["target"].pk, 2, 5000, 10000)]
    assert published.timing_versions.get().verified_at == catalog["timing"].verified_at
    assert _run(apply=True)["existing"] == 1
    assert RecitationEdition.objects.count() == 2
    assert AudioTrack.objects.count() == 228
    assert Reciter.objects.count() == 1


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("field", "value"), [("text_uthmani", "different"), ("number", 3), ("juz_number", 2)]
)
def test_changed_corpus_is_rejected_before_any_writes(
    catalog: dict[str, Any], field: str, value: Any
) -> None:
    Ayah.objects.filter(surah__edition_version=catalog["target"], number=1).update(**{field: value})
    with pytest.raises(ValidationError, match="differ"):
        _run(apply=True)
    assert RecitationEdition.objects.count() == 1


@pytest.mark.django_db
def test_invalid_source_timings_cannot_be_republished(catalog: dict[str, Any]) -> None:
    AyahAudioSegment.objects.filter(
        track__recitation_edition=catalog["recitation"], start_ms=5000
    ).update(end_ms=11000)
    with pytest.raises(ValidationError, match="timelines"):
        _run(apply=True)
    assert RecitationEdition.objects.count() == 1
    assert AudioTimingVersion.objects.count() == 1


@pytest.mark.django_db
def test_target_must_still_be_active(catalog: dict[str, Any]) -> None:
    edition = catalog["source"].edition
    edition.active_version = catalog["source"]
    edition.save(update_fields=["active_version"])
    with pytest.raises(ValidationError, match="active"):
        _run(apply=True)
    assert RecitationEdition.objects.count() == 1


@pytest.mark.django_db
def test_failure_after_copying_rolls_back_new_catalog(
    catalog: dict[str, Any], monkeypatch: pytest.MonkeyPatch
) -> None:
    def fail_publish(self: RecitationEdition) -> None:
        raise ValidationError("simulated publication failure")

    monkeypatch.setattr(RecitationEdition, "publish", fail_publish)
    with pytest.raises(ValidationError, match="simulated"):
        _run(apply=True)
    assert RecitationEdition.objects.count() == 1
    assert AudioTrack.objects.count() == 114
    assert AyahAudioSegment.objects.count() == 2
    assert Reciter.objects.get().pk == catalog["reciter"].pk
