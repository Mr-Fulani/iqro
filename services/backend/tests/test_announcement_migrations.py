from __future__ import annotations

from collections.abc import Iterator
from datetime import UTC, datetime

import pytest
from django.db import connection
from django.db.migrations.executor import MigrationExecutor

PREVIOUS_MIGRATION = "0002_announcement_groups"
WAVES_MIGRATION = "0003_announcement_edits_and_waves"


def _targets(executor: MigrationExecutor, migration: str) -> list[tuple[str, str]]:
    return [
        *(
            (app, name)
            for app, name in executor.loader.graph.leaf_nodes()
            if app != "announcements"
        ),
        ("announcements", migration),
    ]


@pytest.fixture
def back_to_latest() -> Iterator[None]:
    yield
    # Later transactional tests expect every app at its latest migration.
    executor = MigrationExecutor(connection)
    executor.migrate(executor.loader.graph.leaf_nodes())


@pytest.mark.django_db(transaction=True)
@pytest.mark.usefixtures("back_to_latest")
def test_announcements_published_before_waves_get_their_first_wave() -> None:
    executor = MigrationExecutor(connection)
    previous = _targets(executor, PREVIOUS_MIGRATION)
    executor.migrate(previous)
    old_apps = executor.loader.project_state(previous).apps
    announcement_model = old_apps.get_model("announcements", "Announcement")
    published_at = datetime(2026, 10, 21, 9, 30, tzinfo=UTC)
    published = announcement_model.objects.create(
        kind="general",
        starts_at=published_at,
        published_at=published_at,
    )
    draft = announcement_model.objects.create(kind="general", starts_at=published_at)

    executor = MigrationExecutor(connection)
    latest = _targets(executor, WAVES_MIGRATION)
    executor.migrate(latest)
    new_apps = executor.loader.project_state(latest).apps
    wave_model = new_apps.get_model("announcements", "AnnouncementWave")

    wave = wave_model.objects.get()
    assert wave.announcement_id == published.id
    assert (wave.number, wave.reason, wave.revision) == (1, "published", 1)
    assert wave.created_at == published_at
    assert not wave_model.objects.filter(announcement_id=draft.id).exists()
    assert (
        new_apps.get_model("announcements", "Announcement").objects.get(pk=published.pk).wave == 1
    )
