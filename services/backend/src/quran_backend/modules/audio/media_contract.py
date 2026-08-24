from __future__ import annotations

import json
import re
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone

from quran_backend.modules.audio.models import AudioRendition, RecitationPublicationStatus
from quran_backend.modules.audio.validators import validate_strong_etag

MAX_REPORT_BYTES = 2 * 1024 * 1024
MAX_REPORT_ASSETS = 100
MIN_IMMUTABLE_CACHE_SECONDS = 31_536_000
REPORT_NAME_PATTERN = re.compile(
    r"audio-rendition:(?P<id>[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-"
    r"[0-9a-f]{4}-[0-9a-f]{12})\Z"
)


class AudioMediaContractError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class AudioMediaContractResult:
    verified: int
    generated_at: datetime


@dataclass(frozen=True, slots=True)
class _Evidence:
    rendition_id: uuid.UUID
    url: str
    etag: str
    size_bytes: int
    content_type: str


def record_audio_media_contract(report_path: Path) -> AudioMediaContractResult:
    report = _load_report(report_path)
    generated_at = _generated_at(report)
    _validate_report_envelope(report)
    evidence = _parse_evidence(report)
    rendition_ids = [item.rendition_id for item in evidence]

    with transaction.atomic():
        renditions = {
            rendition.id: rendition
            for rendition in AudioRendition.objects.select_for_update()
            .select_related("track__recitation_edition")
            .filter(pk__in=rendition_ids)
        }
        if len(renditions) != len(rendition_ids):
            raise AudioMediaContractError("Report references an unknown audio rendition")

        for item in evidence:
            rendition = renditions[item.rendition_id]
            _validate_evidence(item, rendition, generated_at)

        for item in evidence:
            rendition = renditions[item.rendition_id]
            rendition.etag = item.etag
            rendition.cdn_contract_verified_at = generated_at
            rendition.save(update_fields=["etag", "cdn_contract_verified_at", "updated_at"])

    return AudioMediaContractResult(verified=len(evidence), generated_at=generated_at)


def _load_report(path: Path) -> dict[str, Any]:
    try:
        if path.stat().st_size > MAX_REPORT_BYTES:
            raise AudioMediaContractError("Media contract report is too large")
        raw = json.loads(path.read_text(encoding="utf-8"))
    except AudioMediaContractError:
        raise
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise AudioMediaContractError("Media contract report cannot be read") from exc
    if not isinstance(raw, dict):
        raise AudioMediaContractError("Media contract report root must be an object")
    return raw


def _generated_at(report: dict[str, Any]) -> datetime:
    raw = report.get("generated_at")
    if not isinstance(raw, str):
        raise AudioMediaContractError("Media contract generated_at is missing")
    try:
        generated_at = datetime.fromisoformat(raw)
    except ValueError as exc:
        raise AudioMediaContractError("Media contract generated_at is invalid") from exc
    if generated_at.utcoffset() is None:
        raise AudioMediaContractError("Media contract generated_at must include a timezone")
    if generated_at > timezone.now() + timedelta(minutes=5):
        raise AudioMediaContractError("Media contract report is dated in the future")
    return generated_at


def _validate_report_envelope(report: dict[str, Any]) -> None:
    if report.get("schema_version") != 1 or report.get("passed") is not True:
        raise AudioMediaContractError("Only a successful schema-version 1 report is accepted")
    min_cache_seconds = report.get("min_cache_seconds")
    if (
        isinstance(min_cache_seconds, bool)
        or not isinstance(min_cache_seconds, int)
        or min_cache_seconds < MIN_IMMUTABLE_CACHE_SECONDS
    ):
        raise AudioMediaContractError("Report does not prove the one-year immutable cache policy")
    origins = report.get("origins")
    if not isinstance(origins, list) or not all(isinstance(item, str) for item in origins):
        raise AudioMediaContractError("Report origins are invalid")
    required_origins = set(getattr(settings, "MEDIA_CDN_REQUIRED_ORIGINS", []))
    if not required_origins or not required_origins.issubset(origins):
        raise AudioMediaContractError("Report does not cover all MEDIA_CDN_REQUIRED_ORIGINS")


def _parse_evidence(report: dict[str, Any]) -> list[_Evidence]:
    rows = report.get("assets")
    if not isinstance(rows, list) or not 1 <= len(rows) <= MAX_REPORT_ASSETS:
        raise AudioMediaContractError(
            f"Report must contain between 1 and {MAX_REPORT_ASSETS} assets"
        )
    evidence: list[_Evidence] = []
    ids: set[uuid.UUID] = set()
    for row in rows:
        if not isinstance(row, dict):
            raise AudioMediaContractError("Report asset is malformed")
        name = row.get("name")
        match = REPORT_NAME_PATTERN.fullmatch(name) if isinstance(name, str) else None
        if match is None:
            raise AudioMediaContractError("Asset name must be audio-rendition:<uuid>")
        rendition_id = uuid.UUID(match.group("id"))
        if rendition_id in ids:
            raise AudioMediaContractError("Report contains a duplicate audio rendition")
        ids.add(rendition_id)
        etag = row.get("observed_etag")
        if not isinstance(etag, str):
            raise AudioMediaContractError("Report asset ETag is not strong")
        try:
            validate_strong_etag(etag)
        except ValidationError as exc:
            raise AudioMediaContractError("Report asset ETag is not strong") from exc
        size_bytes = row.get("observed_bytes")
        if isinstance(size_bytes, bool) or not isinstance(size_bytes, int):
            raise AudioMediaContractError("Report asset size is invalid")
        content_type = row.get("observed_content_type")
        url = row.get("url")
        if (
            row.get("passed") is not True
            or row.get("failures") not in ([], ())
            or not isinstance(url, str)
            or not isinstance(content_type, str)
        ):
            raise AudioMediaContractError("Report asset did not pass the complete contract")
        evidence.append(
            _Evidence(
                rendition_id=rendition_id,
                url=url,
                etag=etag,
                size_bytes=size_bytes,
                content_type=content_type,
            )
        )
    return evidence


def _validate_evidence(
    evidence: _Evidence,
    rendition: AudioRendition,
    generated_at: datetime,
) -> None:
    recitation = rendition.track.recitation_edition
    if recitation.status != RecitationPublicationStatus.DRAFT:
        raise AudioMediaContractError("Only draft recitation renditions can be verified")
    if rendition.object_key is None or rendition.external_url:
        raise AudioMediaContractError("CDN evidence can only target managed renditions")
    if not rendition.origin_etag:
        raise AudioMediaContractError("Rendition must be uploaded and origin-verified first")
    expected_url = (
        f"{settings.PUBLIC_AUDIO_BASE_URL.rstrip('/')}/{rendition.object_key.lstrip('/')}"
    )
    if (
        evidence.url != expected_url
        or evidence.size_bytes != rendition.size_bytes
        or evidence.content_type != rendition.content_type
    ):
        raise AudioMediaContractError("CDN evidence does not match rendition metadata")
    if (
        rendition.cdn_contract_verified_at is not None
        and generated_at < rendition.cdn_contract_verified_at
    ):
        raise AudioMediaContractError("CDN evidence is older than the recorded verification")
