from __future__ import annotations

from typing import Any

from django.core.exceptions import ValidationError
from django.db import models, transaction
from django.db.models import Count

from quran_backend.modules.audio.models import (
    AudioRendition,
    AudioTimingVersion,
    AudioTrack,
    AyahAudioSegment,
    RecitationEdition,
    RecitationPublicationStatus,
)
from quran_backend.modules.core.content_revalidation import enqueue_audio_content_change
from quran_backend.modules.quran.models import Ayah, PublicationStatus, QuranEdition


def _fields(instance: models.Model, *excluded: str) -> dict[str, Any]:
    omit = {"id", "created_at", "updated_at", *excluded}
    return {
        field.attname: getattr(instance, field.attname)
        for field in instance._meta.concrete_fields
        if field.name not in omit
    }


def _ayah_mapping(source: Any, target: Any) -> dict[Any, Any]:
    columns = (
        "id",
        "surah__number",
        "number",
        "text_uthmani",
        "juz_number",
        "hizb_number",
        "rub_el_hizb_number",
    )
    old = list(
        Ayah.objects.filter(surah__edition_version=source)
        .order_by(
            "surah__number",
            "number",
        )
        .values_list(*columns)
    )
    new = list(
        Ayah.objects.filter(surah__edition_version=target)
        .order_by(
            "surah__number",
            "number",
        )
        .values_list(*columns)
    )
    if (
        not old
        or len(old) != len(new)
        or any(a[1:] != b[1:] for a, b in zip(old, new, strict=True))
    ):
        raise ValidationError(
            "Quran ayah text, numbering or divisions differ; timings cannot be reused."
        )
    return {a[0]: b[0] for a, b in zip(old, new, strict=True)}


def _target_code(source: RecitationEdition, target: Any) -> str:
    suffix = str(target.pk).replace("-", "")[:12]
    # Preserve QF's canonical code format so subsequent source refreshes reuse it.
    if source.code.startswith("qf-"):
        return f"{source.code.rsplit('-', 1)[0]}-{suffix}"
    return f"{source.code[:47]}-q-{suffix}"


@transaction.atomic
def republish_audio_catalog(  # noqa: PLR0913, PLR0915
    *,
    edition_code: str,
    source_version: str,
    target_version: str,
    source_release: str,
    release_version: str,
    apply: bool = False,
) -> dict[str, int]:
    """Append a verified external-audio release; never rewrite published rows/media.

    The entire catalog commits atomically. Dry-run performs only reads. Managed
    object keys are unique and require a separate media-reuse design, so this
    operation explicitly refuses them instead of copying or renaming files.
    """
    edition = QuranEdition.objects.select_for_update().get(code=edition_code)
    source = edition.versions.get(version=source_version)
    target = edition.versions.get(version=target_version)
    if source.pk == target.pk or target.pk != edition.active_version_id:
        raise ValidationError("Target must be the active, distinct Quran version.")
    if source.status != PublicationStatus.PUBLISHED or target.status != PublicationStatus.PUBLISHED:
        raise ValidationError("Both Quran versions must remain published.")
    mapping = _ayah_mapping(source, target)
    releases = list(
        RecitationEdition.objects.select_for_update()
        .filter(
            quran_edition_version=source,
            version=source_release,
            status=RecitationPublicationStatus.PUBLISHED,
            stream_allowed=True,
            reciter__is_active=True,
        )
        .order_by("code", "id")
    )
    if not releases:
        raise ValidationError("No published streaming recitations match the source release.")
    if AudioRendition.objects.filter(
        track__recitation_edition__in=releases, object_key__isnull=False
    ).exists():
        raise ValidationError("Managed audio is not supported by this external-catalog operation.")
    result = {
        "ayahs_verified": len(mapping),
        "recitations": len(releases),
        "created": 0,
        "existing": 0,
        "tracks": 0,
        "segments": 0,
    }
    for original in releases:
        original._validate_publishable_children()
        tracks = list(original.tracks.select_related("timing_version").order_by("id"))
        defaults = (
            AudioRendition.objects.filter(track__in=tracks, is_default=True)
            .values("track_id")
            .annotate(n=Count("id"))
        )
        if {t.surah_number for t in tracks if t.scope == "surah"} != set(range(1, 115)) or len(
            defaults
        ) != len(tracks):
            raise ValidationError(
                "Source must have a complete 114-surah catalog with default renditions."
            )
        segments = list(AyahAudioSegment.objects.filter(track__in=tracks).order_by("id"))
        if any(s.ayah_id not in mapping for s in segments):
            raise ValidationError("A source timing refers to a different Quran version.")
        result["tracks"] += len(tracks)
        result["segments"] += len(segments)
        values = _fields(
            original, "quran_edition_version", "code", "version", "status", "published_at"
        )
        values.update(
            quran_edition_version_id=target.pk,
            code=_target_code(original, target),
            version=release_version,
        )
        candidate = RecitationEdition(**values)
        existing = RecitationEdition.objects.filter(
            code=candidate.code, version=release_version
        ).first()
        if existing is not None:
            if (
                any(getattr(existing, name) != value for name, value in values.items())
                or existing.status != RecitationPublicationStatus.PUBLISHED
            ):
                raise ValidationError(
                    "Target release already exists with different metadata/status."
                )
            if existing.tracks.count() != len(tracks) or AyahAudioSegment.objects.filter(
                track__recitation_edition=existing
            ).count() != len(segments):
                raise ValidationError("Existing target catalog does not match source coverage.")
            existing.full_clean()
            result["existing"] += 1
            continue
        candidate.full_clean()
        if not apply:
            continue
        candidate.save()
        timing_map = {}
        for timing in original.timing_versions.all():
            cloned = AudioTimingVersion(
                **_fields(timing, "recitation_edition"), recitation_edition=candidate
            )
            cloned.save()
            timing_map[timing.pk] = cloned.pk
        cloned_tracks = [
            AudioTrack(
                **_fields(t, "recitation_edition", "timing_version"),
                recitation_edition=candidate,
                timing_version_id=(
                    timing_map[t.timing_version_id] if t.timing_version_id is not None else None
                ),
            )
            for t in tracks
        ]
        AudioTrack.objects.bulk_create(cloned_tracks, batch_size=200)
        track_map = {a.pk: b.pk for a, b in zip(tracks, cloned_tracks, strict=True)}
        AudioRendition.objects.bulk_create(
            [
                AudioRendition(**_fields(r, "track"), track_id=track_map[r.track_id])
                for r in AudioRendition.objects.filter(track__in=tracks)
            ],
            batch_size=200,
        )
        AyahAudioSegment.objects.bulk_create(
            [
                AyahAudioSegment(
                    track_id=track_map[s.track_id],
                    ayah_id=mapping[s.ayah_id],
                    start_ms=s.start_ms,
                    end_ms=s.end_ms,
                )
                for s in segments
            ],
            batch_size=1000,
        )
        # Validate all mapped timelines, provenance, rights and renditions using
        # the normal publication gate. Failure rolls back every new release.
        candidate.publish()
        candidate.save()
        enqueue_audio_content_change(
            action="published",
            recitation_id=candidate.pk,
            reciter_id=candidate.reciter_id,
            version=candidate.version,
        )
        result["created"] += 1
    return result
