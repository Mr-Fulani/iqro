from __future__ import annotations

from typing import Any

import pytest
from django.db import connection
from django.db.migrations.executor import MigrationExecutor

PREVIOUS_MIGRATION = "0003_quranfoundationsyncstate"
RENDITION_MIGRATION = "0004_audio_rendition"
LATEST_MIGRATION = "0005_audio_rendition_origin_etag"


def _executor() -> MigrationExecutor:
    return MigrationExecutor(connection)


def _targets(executor: MigrationExecutor, audio_migration: str) -> list[tuple[str, str]]:
    return [
        *((app, name) for app, name in executor.loader.graph.leaf_nodes() if app != "audio"),
        ("audio", audio_migration),
    ]


@pytest.mark.django_db(transaction=True)
def test_audio_rendition_migration_backfills_and_reverses_default_asset() -> None:
    executor = _executor()
    previous_targets = _targets(executor, PREVIOUS_MIGRATION)
    executor.migrate(previous_targets)
    old_apps = executor.loader.project_state(previous_targets).apps
    quran_edition = old_apps.get_model("quran", "QuranEdition").objects.create(
        code="migration-hafs",
        name_ar="حفص",
        name_en="Migration Hafs",
        name_ru="Migration Hafs",
        riwayah="hafs",
        source_name="Migration fixture",
        license_name="Migration fixture",
    )
    quran_version = old_apps.get_model("quran", "QuranEditionVersion").objects.create(
        edition_id=quran_edition.id,
        version="1.0.0",
        checksum_sha256="a" * 64,
    )
    reciter = old_apps.get_model("audio", "Reciter").objects.create(
        code="migration-reciter",
        name_ar="قارئ",
        name_en="Migration Reciter",
        name_ru="Migration Reciter",
    )
    recitation = old_apps.get_model("audio", "RecitationEdition").objects.create(
        code="migration-recitation",
        version="1.0.0",
        reciter_id=reciter.id,
        quran_edition_version_id=quran_version.id,
        source_name="Migration fixture",
        source_version="1",
        source_checksum_sha256="b" * 64,
        rights_holder="Migration fixture",
        license_name="Migration fixture",
    )
    track = old_apps.get_model("audio", "AudioTrack").objects.create(
        recitation_edition_id=recitation.id,
        scope="surah",
        surah_number=1,
        duration_ms=10_000,
        codec="mp3",
        content_type="audio/mpeg",
        bitrate_kbps=128,
        size_bytes=160_000,
        checksum_sha256="c" * 64,
        object_key="audio/migration/1.0.0/surah-001.mp3",
        external_url="",
    )

    try:
        executor = _executor()
        rendition_targets = _targets(executor, RENDITION_MIGRATION)
        executor.migrate(rendition_targets)
        new_apps = executor.loader.project_state(rendition_targets).apps
        rendition: Any = new_apps.get_model("audio", "AudioRendition").objects.get(
            track_id=track.id
        )
        assert rendition.quality == "standard"
        assert rendition.is_default is True
        assert rendition.codec == "mp3"
        assert rendition.bitrate_kbps == 128
        assert rendition.object_key == "audio/migration/1.0.0/surah-001.mp3"

        executor = _executor()
        previous_targets = _targets(executor, PREVIOUS_MIGRATION)
        executor.migrate(previous_targets)
        restored_apps = executor.loader.project_state(previous_targets).apps
        restored: Any = restored_apps.get_model("audio", "AudioTrack").objects.get(pk=track.id)
        assert restored.codec == "mp3"
        assert restored.bitrate_kbps == 128
        assert restored.checksum_sha256 == "c" * 64
        assert restored.object_key == "audio/migration/1.0.0/surah-001.mp3"
    finally:
        executor = _executor()
        executor.migrate(_targets(executor, LATEST_MIGRATION))
