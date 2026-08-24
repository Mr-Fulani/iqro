from __future__ import annotations

from prometheus_client import CONTENT_TYPE_LATEST, CollectorRegistry, Gauge, generate_latest

from quran_backend.modules.audio.models import AudioTrack
from quran_backend.modules.audio.operations import QuranFoundationOperationalSummary
from quran_backend.modules.audio.selectors import public_recitation_base
from quran_backend.modules.core.runtime_metrics import register_runtime_collectors
from quran_backend.modules.quran.models import (
    Ayah,
    MushafPage,
    PublicationStatus,
    QuranEdition,
)


def render_platform_metrics(
    summary: QuranFoundationOperationalSummary,
    *,
    app_version: str,
) -> tuple[bytes, str]:
    """Render bounded, process-independent metrics from durable database state."""

    registry = CollectorRegistry()
    register_runtime_collectors(registry)
    build_info = Gauge(
        "quran_platform_build_info",
        "Static build information for the Quran Platform backend.",
        labelnames=("version",),
        registry=registry,
    )
    build_info.labels(version=app_version).set(1)

    catalog_items = Gauge(
        "quran_platform_catalog_items",
        "Published items currently available from public catalog APIs.",
        labelnames=("kind",),
        registry=registry,
    )
    active_editions = QuranEdition.objects.filter(
        active_version__status=PublicationStatus.PUBLISHED
    )
    public_recitations = public_recitation_base()
    catalog_items.labels(kind="quran_editions").set(active_editions.count())
    catalog_items.labels(kind="mushaf_pages").set(
        MushafPage.objects.filter(edition_version__active_for_editions__isnull=False).count()
    )
    catalog_items.labels(kind="ayahs").set(
        Ayah.objects.filter(surah__edition_version__active_for_editions__isnull=False).count()
    )
    catalog_items.labels(kind="audio_recitations").set(public_recitations.count())
    catalog_items.labels(kind="audio_tracks").set(
        AudioTrack.objects.filter(recitation_edition__in=public_recitations).count()
    )

    sync_enabled = Gauge(
        "quran_foundation_audio_sync_enabled",
        "Whether scheduled Quran.Foundation audio synchronization is enabled.",
        registry=registry,
    )
    sync_enabled.set(int(summary.enabled))
    sync_states = Gauge(
        "quran_foundation_audio_sync_states",
        "Current Quran.Foundation recitation state grouped by health classification.",
        labelnames=("environment", "status"),
        registry=registry,
    )
    for status, value in (
        ("healthy", summary.healthy),
        ("stale", summary.stale),
        ("failing", summary.failing),
        ("never_synced", summary.never_synced),
    ):
        sync_states.labels(environment=summary.environment, status=status).set(value)

    oldest_success = Gauge(
        "quran_foundation_audio_sync_oldest_success_timestamp_seconds",
        "Oldest successful refresh timestamp among tracked Quran.Foundation recitations.",
        labelnames=("environment",),
        registry=registry,
    )
    oldest_success.labels(environment=summary.environment).set(
        summary.oldest_success_at.timestamp() if summary.oldest_success_at else 0
    )
    max_failures = Gauge(
        "quran_foundation_audio_sync_max_consecutive_failures",
        "Maximum consecutive refresh failures among tracked Quran.Foundation recitations.",
        labelnames=("environment",),
        registry=registry,
    )
    max_failures.labels(environment=summary.environment).set(summary.max_consecutive_failures)

    return generate_latest(registry), CONTENT_TYPE_LATEST
