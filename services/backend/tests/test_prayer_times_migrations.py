from __future__ import annotations

import importlib
from collections.abc import Iterator
from datetime import UTC, datetime

import pytest
from django.db import connection
from django.db.migrations.executor import MigrationExecutor

from quran_backend.modules.prayer_times.models import (
    PrayerConfigRelease,
    PrayerConfigReleaseStatus,
    PrayerProfile,
)

PREVIOUS_MIGRATION = "0005_load_prayer_cities"
RELEASE_MIGRATION = "0006_release_tzdb_2026e"


def _targets(executor: MigrationExecutor, migration: str) -> list[tuple[str, str]]:
    return [
        *((app, name) for app, name in executor.loader.graph.leaf_nodes() if app != "prayer_times"),
        ("prayer_times", migration),
    ]


def _migrate(migration: str) -> MigrationExecutor:
    executor = MigrationExecutor(connection)
    executor.migrate(_targets(executor, migration))
    return MigrationExecutor(connection)


def _held(release: PrayerConfigRelease) -> dict[str, tuple[str, str]]:
    return {
        item.method.code: (str(item.id), item.checksum_sha256)
        for item in release.method_configurations.select_related("method")
    }


@pytest.fixture
def back_to_latest() -> Iterator[None]:
    yield
    # Later transactional tests expect every app at its latest migration.
    executor = MigrationExecutor(connection)
    executor.migrate(executor.loader.graph.leaf_nodes())


@pytest.mark.django_db(transaction=True)
@pytest.mark.usefixtures("back_to_latest")
def test_release_2026_2_takes_over_the_configuration_ids_clients_hold() -> None:
    executor = _migrate(PREVIOUS_MIGRATION)
    old_apps = executor.loader.project_state(_targets(executor, PREVIOUS_MIGRATION)).apps
    if not old_apps.get_model("prayer_times", "PrayerConfigRelease").objects.exists():
        # Earlier transactional tests flush the rows that 0002 seeded.
        reference = importlib.import_module(
            "quran_backend.modules.prayer_times.migrations.0002_reference_release"
        )
        reference.seed_reference_release(old_apps, None)
    held = {
        item.method.code: (str(item.id), item.checksum_sha256)
        for item in old_apps.get_model("prayer_times", "PrayerMethodConfig")
        .objects.filter(release__version="2026.1")
        .select_related("method")
    }
    assert len(held) == 9
    user = old_apps.get_model("accounts", "User").objects.create()
    profile = old_apps.get_model("prayer_times", "PrayerProfile").objects.create(
        user=user,
        method_config_id=held["dubai"][0],
        high_latitude_rule="middle_of_night",
        polar_resolution="unresolved",
        revision=3,
        client_updated_at=datetime(2026, 11, 20, 8, tzinfo=UTC),
    )

    _migrate(RELEASE_MIGRATION)

    release = PrayerConfigRelease.objects.get(
        status=PrayerConfigReleaseStatus.PUBLISHED,
        is_default=True,
    )
    assert (release.version, release.timezone_database_version) == ("2026.2", "2026.5")
    assert _held(release) == held
    release.full_clean()
    assert release.manifest_checksum_sha256 == release.calculate_manifest_checksum()
    for configuration in release.method_configurations.all():
        assert configuration.checksum_sha256 == configuration.calculate_checksum()
    previous = PrayerConfigRelease.objects.get(version="2026.1")
    assert (previous.status, previous.is_default) == (PrayerConfigReleaseStatus.PUBLISHED, False)
    copies = _held(previous)
    assert {code: checksum for code, (_, checksum) in copies.items()} == {
        code: checksum for code, (_, checksum) in held.items()
    }
    assert not {item_id for item_id, _ in copies.values()} & {
        item_id for item_id, _ in held.values()
    }
    previous.full_clean()
    unchanged = PrayerProfile.objects.get(pk=profile.pk)
    assert (str(unchanged.method_config_id), unchanged.revision) == (held["dubai"][0], 3)

    _migrate(PREVIOUS_MIGRATION)

    assert not PrayerConfigRelease.objects.filter(version="2026.2").exists()
    restored = PrayerConfigRelease.objects.get(version="2026.1")
    assert (restored.status, restored.is_default) == (PrayerConfigReleaseStatus.PUBLISHED, True)
    assert _held(restored) == held
    assert PrayerProfile.objects.get(pk=profile.pk).revision == 3
