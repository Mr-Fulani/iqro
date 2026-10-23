"""The teaching reciter: one default for the Mushaf, Memorization and the courses."""

from __future__ import annotations

from typing import Any

import pytest
from django.contrib import admin
from django.test import RequestFactory, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from quran_backend.modules.audio.admin import AudioCatalogSettingsAdmin
from quran_backend.modules.audio.models import (
    AudioCatalogSettings,
    AudioTimingVersion,
    AyahAudioSegment,
    RecitationEdition,
    Reciter,
)
from quran_backend.modules.audio.selectors import teaching_recitation, timed_recitation_candidates
from quran_backend.modules.salah.resolvers import FormulaResolver
from tests.test_audio_api import (  # noqa: F401 - the fixture is used by name
    _complete_surah_catalog,
    _create_recitation,
    _create_second_public_recitation,
    _create_track,
    _publish,
    published_audio_dataset,
)


def _timed_recitation(
    quran_dataset: dict[str, Any],
    *,
    code: str,
    version: str = "1.0.0",
    ayahs: tuple[str, ...] = ("first_ayah", "second_ayah"),
    publish: bool = True,
) -> RecitationEdition:
    reciter, _ = Reciter.objects.get_or_create(
        code=f"{code}-reciter",
        defaults={
            "name_ar": "قارئ",
            "name_en": code.replace("-", " ").title(),
            "name_ru": "Чтец",
            "country_code": "EG",
        },
    )
    recitation = _create_recitation(reciter, quran_dataset["version"], code=code, version=version)
    timing_version = AudioTimingVersion.objects.create(
        recitation_edition=recitation,
        version=version,
        source_name="Verified synthetic timings",
        source_version="2026-10-23",
        source_checksum_sha256="e" * 64,
        verified_at=timezone.now(),
    )
    track = _create_track(
        recitation,
        timing_version=timing_version,
        object_key=f"audio/{code}/{version}/surah-001.mp3",
    )
    _complete_surah_catalog(recitation)
    start_ms = 0
    for key in ayahs:
        AyahAudioSegment.objects.create(
            track=track, ayah=quran_dataset[key], start_ms=start_ms, end_ms=start_ms + 5_000
        )
        start_ms += 5_000
    if publish:
        _publish(recitation)
    return recitation


def _teaching_flags(client: APIClient) -> dict[str, bool]:
    response = client.get(reverse("audio:recitation-list"))
    assert response.status_code == 200
    return {item["code"]: item["teaching_default"] for item in response.json()["results"]}


@pytest.mark.django_db
@pytest.mark.usefixtures("published_audio_dataset")
@override_settings(QURAN_TEACHING_RECITATION_CODE="x-husary-muallim")
def test_the_catalog_marks_the_configured_teaching_recitation(
    api_client: APIClient, quran_dataset: dict[str, Any]
) -> None:
    older = _timed_recitation(quran_dataset, code="x-husary-muallim", version="1.0.0")
    newer = _timed_recitation(quran_dataset, code="x-husary-muallim", version="2.0.0")

    # The newest published version of the configured code teaches.
    assert teaching_recitation() == newer
    flags = api_client.get(reverse("audio:recitation-list")).json()["results"]
    assert {item["version"]: item["teaching_default"] for item in flags} == {
        "1.0.0": False,
        "2.0.0": True,
    }
    assert _teaching_flags(api_client)["test-recitation"] is False
    detail = api_client.get(reverse("audio:recitation-detail", kwargs={"recitation_id": newer.id}))
    assert detail.json()["teaching_default"] is True
    detail = api_client.get(reverse("audio:recitation-detail", kwargs={"recitation_id": older.id}))
    assert detail.json()["teaching_default"] is False


@pytest.mark.django_db
@pytest.mark.usefixtures("published_audio_dataset")
@override_settings(QURAN_TEACHING_RECITATION_CODE="x-husary-muallim")
def test_the_admin_choice_wins_and_the_code_is_the_fallback(
    api_client: APIClient, quran_dataset: dict[str, Any]
) -> None:
    husary = _timed_recitation(quran_dataset, code="x-husary-muallim")
    chosen = RecitationEdition.objects.get(code="test-recitation")
    AudioCatalogSettings.objects.create(teaching_recitation=chosen)

    assert teaching_recitation() == chosen
    assert _teaching_flags(api_client) == {"test-recitation": True, "x-husary-muallim": False}

    # A withdrawn choice no longer teaches: the configured code does.
    chosen.withdraw()
    chosen.save()
    assert teaching_recitation() == husary

    # Without a choice and without a code, nothing is marked: clients keep their own rules.
    AudioCatalogSettings.objects.update(teaching_recitation=None)
    with override_settings(QURAN_TEACHING_RECITATION_CODE=""):
        assert teaching_recitation() is None
        assert _teaching_flags(api_client) == {"x-husary-muallim": False}


@pytest.mark.django_db
@pytest.mark.usefixtures("published_audio_dataset")
def test_the_admin_offers_only_published_timed_recitations(
    quran_dataset: dict[str, Any],
) -> None:
    timed = RecitationEdition.objects.get(code="test-recitation")
    untimed = _create_second_public_recitation(quran_dataset)
    draft = _timed_recitation(quran_dataset, code="x-draft-muallim", publish=False)
    listening_only = _timed_recitation(quran_dataset, code="x-listening-muallim", publish=False)
    listening_only.listening_only = True
    _publish(listening_only)

    assert list(timed_recitation_candidates()) == [timed]
    assert untimed not in timed_recitation_candidates()
    assert draft not in timed_recitation_candidates()

    model_admin = admin.site._registry[AudioCatalogSettings]
    assert isinstance(model_admin, AudioCatalogSettingsAdmin)
    request = RequestFactory().get("/admin/")
    field = model_admin.formfield_for_foreignkey(
        AudioCatalogSettings._meta.get_field("teaching_recitation"), request
    )
    assert list(field.queryset) == [timed]
    assert not model_admin.has_delete_permission(request)
    assert AudioCatalogSettings.objects.count() == 0
    AudioCatalogSettings.objects.create(teaching_recitation=timed)
    request.user = type("Superuser", (), {"has_perm": lambda *_: True, "is_active": True})()
    assert not model_admin.has_add_permission(request)


@pytest.mark.django_db
@pytest.mark.usefixtures("published_audio_dataset")
def test_salah_course_audio_prefers_the_teaching_recitation(
    quran_dataset: dict[str, Any],
) -> None:
    # Sorts after «test-recitation», so the catalog order alone would not pick it.
    _timed_recitation(quran_dataset, code="x-husary-muallim", ayahs=("first_ayah",))

    def audio(start: int, end: int) -> dict[str, Any] | None:
        resolver = FormulaResolver(
            [
                {
                    "id": "fatiha",
                    "source": {"kind": "quran", "surah": 1, "ayah_from": start, "ayah_to": end},
                }
            ],
            {},
        )
        return resolver.resolve("ru")["fatiha"].get("audio")

    with override_settings(QURAN_TEACHING_RECITATION_CODE="x-husary-muallim"):
        whole = audio(1, 2)
        first = audio(1, 1)
    with override_settings(QURAN_TEACHING_RECITATION_CODE=""):
        unconfigured = audio(1, 1)

    # The teaching reciter has timings for the first ayah only: the whole passage
    # silently comes from the first recitation that has them all.
    assert first is not None
    assert "x-husary-muallim" in first["url"]
    assert first["segments"] == [{"ayah": 1, "start_ms": 0, "end_ms": 5_000}]
    assert whole is not None
    assert "test-recitation" in whole["url"]
    assert [segment["ayah"] for segment in whole["segments"]] == [1, 2]
    assert unconfigured is not None
    assert "test-recitation" in unconfigured["url"]
