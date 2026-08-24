from __future__ import annotations

import hmac
import uuid
from dataclasses import dataclass
from pathlib import Path

from django.db import transaction

from quran_backend.modules.audio.models import (
    AudioRendition,
    RecitationPublicationStatus,
)
from quran_backend.modules.core.object_storage import (
    ImmutableObjectSpec,
    ObjectUploader,
    configured_object_uploader,
)


class AudioMediaUploadError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class AudioRenditionUploadResult:
    rendition_id: uuid.UUID
    object_key: str
    etag: str
    created: bool


@dataclass(frozen=True, slots=True)
class _UploadIntent:
    track_id: uuid.UUID
    object_key: str
    content_type: str
    size_bytes: int
    checksum_sha256: str
    existing_origin_etag: str

    @classmethod
    def from_rendition(cls, rendition: AudioRendition) -> _UploadIntent:
        if rendition.track.recitation_edition.status != RecitationPublicationStatus.DRAFT:
            raise AudioMediaUploadError("Only draft recitation renditions can be uploaded")
        if rendition.object_key is None or rendition.external_url:
            raise AudioMediaUploadError("Only managed object-key renditions can be uploaded")
        if not rendition.checksum_sha256:
            raise AudioMediaUploadError("Managed rendition has no SHA-256 checksum")
        return cls(
            track_id=rendition.track_id,
            object_key=rendition.object_key,
            content_type=rendition.content_type,
            size_bytes=rendition.size_bytes,
            checksum_sha256=rendition.checksum_sha256,
            existing_origin_etag=rendition.origin_etag,
        )

    def matches(self, rendition: AudioRendition) -> bool:
        return (
            rendition.track_id == self.track_id
            and rendition.object_key == self.object_key
            and rendition.content_type == self.content_type
            and rendition.size_bytes == self.size_bytes
            and hmac.compare_digest(rendition.checksum_sha256, self.checksum_sha256)
            and rendition.origin_etag == self.existing_origin_etag
        )


def upload_audio_rendition(
    rendition_id: uuid.UUID,
    source_path: Path,
    *,
    uploader: ObjectUploader | None = None,
) -> AudioRenditionUploadResult:
    try:
        rendition = AudioRendition.objects.select_related("track__recitation_edition").get(
            pk=rendition_id
        )
    except AudioRendition.DoesNotExist as exc:
        raise AudioMediaUploadError("Audio rendition does not exist") from exc

    intent = _UploadIntent.from_rendition(rendition)
    actual_uploader = uploader or configured_object_uploader()
    stored = actual_uploader.upload_path(
        source_path,
        ImmutableObjectSpec(
            key=intent.object_key,
            content_type=intent.content_type,
            size_bytes=intent.size_bytes,
            checksum_sha256=intent.checksum_sha256,
        ),
    )

    with transaction.atomic():
        locked = (
            AudioRendition.objects.select_for_update()
            .select_related("track__recitation_edition")
            .get(pk=rendition_id)
        )
        recitation = locked.track.recitation_edition
        type(recitation).objects.select_for_update().get(pk=recitation.pk)
        if recitation.status != RecitationPublicationStatus.DRAFT:
            raise AudioMediaUploadError(
                "Recitation was published while the rendition upload was running"
            )
        if not intent.matches(locked):
            raise AudioMediaUploadError(
                "Rendition metadata changed while the object upload was running"
            )
        if intent.existing_origin_etag and not hmac.compare_digest(
            intent.existing_origin_etag,
            stored.etag,
        ):
            raise AudioMediaUploadError("Stored object ETag differs from the recorded ETag")
        if not locked.origin_etag:
            locked.origin_etag = stored.etag
            locked.save(update_fields=["origin_etag", "updated_at"])

    return AudioRenditionUploadResult(
        rendition_id=locked.id,
        object_key=intent.object_key,
        etag=stored.etag,
        created=stored.created,
    )
