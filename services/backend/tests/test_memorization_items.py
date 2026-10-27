from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import pytest
from django.db import IntegrityError, connection, transaction
from django.db.migrations.executor import MigrationExecutor
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from quran_backend.modules.accounts.merge import merge_guest_into_account
from quran_backend.modules.accounts.models import (
    AuthIdentity,
    IdentityProvider,
    User,
    UserStatus,
)
from quran_backend.modules.memorization.models import (
    MemorizationItem,
    MemorizationItemStatus,
    MemorizationPlan,
    MemorizationSession,
)
from quran_backend.modules.memorization.services import (
    record_memorization_session,
    set_memorization_plan,
)
from quran_backend.modules.quran.models import Ayah, RevelationType, Surah


def _client(user: User) -> APIClient:
    client = APIClient()
    client.force_authenticate(user=user)
    return client


@pytest.fixture
def long_quran(quran_dataset: dict[str, Any]) -> dict[str, Any]:
    """Add surah 2 (20 ayahs) and surah 3 (5 ayahs) to the test edition."""
    version = quran_dataset["first_ayah"].surah.edition_version
    for number, ayah_count in ((2, 20), (3, 5)):
        surah = Surah.objects.create(
            edition_version=version,
            number=number,
            name_ar=f"سورة {number}",
            name_en=f"Surah {number}",
            name_ru=f"Sura {number}",
            revelation_type=RevelationType.MEDINAN,
            ayah_count=ayah_count,
        )
        Ayah.objects.bulk_create(
            Ayah(
                surah=surah,
                number=ayah,
                text_uthmani=f"آية {ayah}",
                text_search=f"اية {ayah}",
                juz_number=1,
                hizb_number=1,
                rub_el_hizb_number=1,
            )
            for ayah in range(1, ayah_count + 1)
        )
    return quran_dataset


def _add(
    client: APIClient,
    start: tuple[int, int],
    end: tuple[int, int] | None = None,
    *,
    mode: str = "queue",
    revision: int | None = None,
) -> Any:
    end = end or start
    if revision is None:
        revision = client.get(reverse("memorization:dashboard")).json()["revision"]
    return client.post(
        reverse("memorization:item-list"),
        {
            "start_surah": start[0],
            "start_ayah": start[1],
            "end_surah": end[0],
            "end_ayah": end[1],
            "mode": mode,
            "timezone_name": "UTC",
            "base_revision": revision,
            "client_updated_at": timezone.now().isoformat(),
        },
        format="json",
    )


def _preview(client: APIClient, start: tuple[int, int], end: tuple[int, int] | None = None) -> Any:
    end = end or start
    return client.get(
        reverse("memorization:item-preview"),
        {
            "start_surah": start[0],
            "start_ayah": start[1],
            "end_surah": end[0],
            "end_ayah": end[1],
        },
    ).json()


def _ranges(payload: dict[str, Any], status: str) -> list[tuple[int, int, int]]:
    return [
        (
            item["start_ayah"]["surah_number"],
            item["start_ayah"]["ayah_number"],
            item["end_ayah"]["ayah_number"],
        )
        for item in payload["items"]
        if item["status"] == status
    ]


@pytest.mark.django_db
def test_first_selection_becomes_the_active_plan_range(long_quran: dict[str, Any]) -> None:
    user = User.objects.create_user(timezone="UTC")
    client = _client(user)

    assert _preview(client, (2, 3), (2, 5))["state"] == "empty"
    response = _add(client, (2, 3), (2, 5), mode="queue")
    dashboard = client.get(reverse("memorization:dashboard")).json()

    assert response.status_code == 201
    assert response.json()["result"] == "started"
    assert _ranges(dashboard, "active") == [(2, 3, 5)]
    assert dashboard["plan"]["start_ayah"]["ayah_number"] == 3
    assert dashboard["plan"]["end_ayah"]["ayah_number"] == 5
    assert dashboard["plan"]["daily_repetitions"] == 5
    assert dashboard["revision"] == dashboard["plan"]["revision"] == 1
    assert MemorizationItem.objects.get(user=user).source == "mushaf"


@pytest.mark.django_db
def test_duplicate_selection_reports_the_item_that_holds_it(long_quran: dict[str, Any]) -> None:
    client = _client(User.objects.create_user(timezone="UTC"))
    active = _add(client, (2, 1), (2, 5)).json()["item"]
    queued = _add(client, (2, 10), (2, 12)).json()["item"]

    inside_active = _add(client, (2, 2), (2, 4))
    inside_queue = _add(client, (2, 11))
    preview = _preview(client, (2, 11))

    assert inside_active.status_code == 200
    assert inside_active.json()["result"] == "duplicate"
    assert inside_active.json()["item"]["id"] == active["id"]
    assert inside_queue.json()["item"]["id"] == queued["id"]
    assert preview["state"] == "duplicate"
    assert preview["item"]["id"] == queued["id"]
    assert MemorizationItem.objects.count() == 2


@pytest.mark.django_db
def test_queue_glues_overlapping_and_neighbouring_ranges(long_quran: dict[str, Any]) -> None:
    client = _client(User.objects.create_user(timezone="UTC"))
    _add(client, (1, 1))
    _add(client, (2, 10), (2, 12))
    _add(client, (2, 16), (2, 18))

    neighbour = _add(client, (2, 13), (2, 15)).json()
    overlap = _add(client, (2, 17), (2, 20)).json()
    other_surah = _add(client, (3, 1), (3, 2)).json()

    assert neighbour["result"] == "merged"
    assert overlap["result"] == "merged"
    assert _ranges(overlap, "queued") == [(2, 10, 20)]
    assert _ranges(other_surah, "queued") == [(2, 10, 20), (3, 1, 2)]
    assert [item["position"] for item in other_surah["items"][1:]] == [0, 1]


@pytest.mark.django_db
def test_learn_now_moves_the_current_range_first_in_the_queue(
    long_quran: dict[str, Any],
) -> None:
    user = User.objects.create_user(timezone="UTC")
    client = _client(user)
    plan = _add(client, (2, 1), (2, 3)).json()["plan"]
    _add(client, (2, 10), (2, 12))
    now = timezone.now()
    session, _created = record_memorization_session(
        user=user,
        session_id=uuid.uuid7(),
        plan_id=uuid.UUID(plan["id"]),
        completed_repetitions=3,
        assessment="repeat",
        duration_seconds=30,
        timezone_name="UTC",
        local_date=now.date(),
        client_updated_at=now,
    )

    response = _add(client, (3, 1), (3, 4), mode="now").json()
    session.refresh_from_db()

    assert response["result"] == "now"
    assert _ranges(response, "active") == [(3, 1, 4)]
    assert _ranges(response, "queued") == [(2, 1, 3), (2, 10, 12)]
    assert response["plan"]["start_ayah"]["surah_number"] == 3
    assert response["plan"]["id"] == plan["id"]
    assert (session.start_ayah.number, session.end_ayah.number) == (1, 3)
    assert MemorizationSession.objects.filter(plan_id=plan["id"]).count() == 1


@pytest.mark.django_db
def test_extend_widens_the_active_range_when_selection_follows_it(
    long_quran: dict[str, Any],
) -> None:
    client = _client(User.objects.create_user(timezone="UTC"))
    _add(client, (2, 1), (2, 5))

    preview = _preview(client, (2, 4), (2, 8))
    extended = _add(client, (2, 4), (2, 8), mode="extend")
    not_next = _add(client, (2, 12), mode="extend")

    assert preview["state"] == "extendable"
    assert preview["extend_to"] == {
        "surah_number": 2,
        "start_ayah_number": 1,
        "end_ayah_number": 8,
    }
    assert extended.json()["result"] == "extended"
    assert _ranges(extended.json(), "active") == [(2, 1, 8)]
    assert extended.json()["plan"]["end_ayah"]["ayah_number"] == 8
    assert not_next.status_code == 400
    assert _preview(client, (2, 12))["state"] == "choose"


@pytest.mark.django_db
def test_ayahs_added_one_by_one_grow_the_current_range_and_the_queue(
    long_quran: dict[str, Any],
) -> None:
    client = _client(User.objects.create_user(timezone="UTC"))
    _add(client, (2, 1))
    for ayah in (2, 3):
        assert _preview(client, (2, ayah))["state"] == "extendable"
        assert _add(client, (2, ayah), mode="extend").json()["result"] == "extended"
    for ayah in (10, 11, 12):
        _add(client, (2, ayah))

    dashboard = client.get(reverse("memorization:dashboard")).json()

    assert _ranges(dashboard, "active") == [(2, 1, 3)]
    assert _ranges(dashboard, "queued") == [(2, 10, 12)]
    assert dashboard["plan"]["end_ayah"]["ayah_number"] == 3


@pytest.mark.django_db
def test_selection_across_surahs_is_split_into_items(long_quran: dict[str, Any]) -> None:
    client = _client(User.objects.create_user(timezone="UTC"))

    response = _add(client, (2, 18), (3, 2), mode="now").json()

    assert _ranges(response, "active") == [(2, 18, 20)]
    assert _ranges(response, "queued") == [(3, 1, 2)]


@pytest.mark.django_db
def test_list_changes_require_the_current_revision(long_quran: dict[str, Any]) -> None:
    client = _client(User.objects.create_user(timezone="UTC"))
    first = _add(client, (2, 1), (2, 3)).json()

    stale = _add(client, (2, 10), revision=0)
    fresh = _add(client, (2, 10), revision=first["revision"])

    assert stale.status_code == 409
    assert stale.json()["code"] == "memorization_plan_revision_conflict"
    assert fresh.status_code == 201
    assert fresh.json()["revision"] == first["revision"] + 1


@pytest.mark.django_db
def test_marking_memorized_suggests_the_next_item_and_starting_it(
    long_quran: dict[str, Any],
) -> None:
    client = _client(User.objects.create_user(timezone="UTC"))
    active = _add(client, (2, 1), (2, 3)).json()["item"]
    queued = _add(client, (2, 10), (2, 12)).json()

    memorized = client.patch(
        reverse("memorization:item-detail", args=[active["id"]]),
        {
            "status": "memorized",
            "base_revision": queued["revision"],
            "client_updated_at": timezone.now().isoformat(),
        },
        format="json",
    ).json()
    started = client.patch(
        reverse("memorization:item-detail", args=[memorized["next"]["id"]]),
        {
            "status": "active",
            "base_revision": memorized["revision"],
            "client_updated_at": timezone.now().isoformat(),
        },
        format="json",
    ).json()

    assert memorized["result"] == "memorized"
    assert memorized["next"]["id"] == queued["item"]["id"]
    assert memorized["memorized_ayah_count"] == 3
    assert started["result"] == "started"
    assert started["next"] is None
    assert _ranges(started, "active") == [(2, 10, 12)]
    assert _ranges(started, "memorized") == [(2, 1, 3)]
    assert started["plan"]["start_ayah"]["ayah_number"] == 10
    assert _preview(client, (2, 2))["state"] == "duplicate"


@pytest.mark.django_db
def test_queued_item_can_be_removed_but_not_the_active_one(long_quran: dict[str, Any]) -> None:
    client = _client(User.objects.create_user(timezone="UTC"))
    active = _add(client, (2, 1)).json()["item"]
    queued = _add(client, (2, 10)).json()

    removed = client.delete(
        reverse("memorization:item-detail", args=[queued["item"]["id"]])
        + f"?base_revision={queued['revision']}"
    )
    refused = client.delete(
        reverse("memorization:item-detail", args=[active["id"]])
        + f"?base_revision={removed.json()['revision']}"
    )

    assert removed.status_code == 200
    assert _ranges(removed.json(), "queued") == []
    assert refused.status_code == 400


@pytest.mark.django_db
def test_only_one_active_item_per_user(long_quran: dict[str, Any]) -> None:
    user = User.objects.create_user(timezone="UTC")
    _add(_client(user), (2, 1))
    ayah = Ayah.objects.get(surah__number=2, number=5)

    with pytest.raises(IntegrityError), transaction.atomic():
        MemorizationItem.objects.create(
            user=user,
            start_ayah=ayah,
            end_ayah=ayah,
            status=MemorizationItemStatus.ACTIVE,
        )
    MemorizationItem.objects.create(
        user=user,
        start_ayah=ayah,
        end_ayah=ayah,
        status=MemorizationItemStatus.QUEUED,
    )


@pytest.mark.django_db
def test_plan_form_keeps_the_active_item_in_step(long_quran: dict[str, Any]) -> None:
    user = User.objects.create_user(timezone="UTC")
    now = timezone.now()
    first, second = (Ayah.objects.get(surah__number=2, number=n) for n in (4, 9))
    plan, _created = set_memorization_plan(
        user=user,
        start_ayah_id=long_quran["first_ayah"].id,
        end_ayah_id=long_quran["second_ayah"].id,
        recitation_id=None,
        daily_repetitions=5,
        pause_seconds=2,
        timezone_name="UTC",
        base_revision=0,
        client_updated_at=now,
    )
    set_memorization_plan(
        user=user,
        start_ayah_id=first.id,
        end_ayah_id=second.id,
        recitation_id=None,
        daily_repetitions=5,
        pause_seconds=2,
        timezone_name="UTC",
        base_revision=plan.revision,
        client_updated_at=now,
    )

    item = MemorizationItem.objects.get(user=user)
    assert item.status == MemorizationItemStatus.ACTIVE
    assert (item.start_ayah_id, item.end_ayah_id) == (first.id, second.id)


@pytest.mark.django_db
def test_guest_list_merges_behind_the_newer_plan(long_quran: dict[str, Any]) -> None:
    guest = User.objects.create_user(timezone="UTC")
    target = User.objects.create_user(
        email="list@example.com",
        status=UserStatus.ACTIVE,
        timezone="UTC",
    )
    identity = AuthIdentity.objects.create(
        user=target,
        provider=IdentityProvider.EMAIL,
        provider_subject="list@example.com",
        email_at_provider="list@example.com",
        email_verified=True,
    )
    _add(_client(target), (2, 1), (2, 2))
    _add(_client(target), (3, 1))
    _add(_client(guest), (2, 10), (2, 11))
    _add(_client(guest), (3, 1))

    result = merge_guest_into_account(
        source_user=guest,
        target_user=target,
        trigger_identity=identity,
        idempotency_key=uuid.uuid4(),
    )
    dashboard = _client(target).get(reverse("memorization:dashboard")).json()

    assert result.moved_counts["memorization_items"] == 1
    assert _ranges(dashboard, "active") == [(2, 10, 11)]
    assert sorted(_ranges(dashboard, "queued")) == [(2, 1, 2), (3, 1, 1)]
    assert dashboard["plan"]["start_ayah"]["ayah_number"] == 10
    assert not MemorizationItem.objects.filter(user=guest).exists()


PLAN_ONLY_MIGRATION = "0001_initial"
ITEMS_MIGRATION = "0003_plan_ranges_to_items"


def _targets(executor: MigrationExecutor, migration: str) -> list[tuple[str, str]]:
    return [
        *((app, name) for app, name in executor.loader.graph.leaf_nodes() if app != "memorization"),
        ("memorization", migration),
    ]


@pytest.fixture
def back_to_latest() -> Iterator[None]:
    yield
    executor = MigrationExecutor(connection)
    executor.migrate(executor.loader.graph.leaf_nodes())


@pytest.mark.django_db(transaction=True)
@pytest.mark.usefixtures("back_to_latest")
def test_migration_turns_each_plan_range_into_an_active_item(
    quran_dataset: dict[str, Any],
) -> None:
    users = [User.objects.create_user(timezone="UTC") for _ in range(2)]
    executor = MigrationExecutor(connection)
    previous = _targets(executor, PLAN_ONLY_MIGRATION)
    executor.migrate(previous)
    old_plan = executor.loader.project_state(previous).apps.get_model(
        "memorization", "MemorizationPlan"
    )
    ranges = [
        (quran_dataset["first_ayah"].id, quran_dataset["second_ayah"].id),
        (quran_dataset["second_ayah"].id, quran_dataset["second_ayah"].id),
    ]
    for user, (start_id, end_id) in zip(users, ranges, strict=True):
        old_plan.objects.create(
            user_id=user.id,
            start_ayah_id=start_id,
            end_ayah_id=end_id,
            daily_repetitions=7,
            pause_seconds=3,
            timezone_name="UTC",
            client_updated_at=timezone.now(),
        )

    executor = MigrationExecutor(connection)
    executor.migrate(_targets(executor, ITEMS_MIGRATION))

    for user, (start_id, end_id) in zip(users, ranges, strict=True):
        item = MemorizationItem.objects.get(user=user)
        assert item.status == MemorizationItemStatus.ACTIVE
        assert (item.start_ayah_id, item.end_ayah_id) == (start_id, end_id)
        assert MemorizationPlan.objects.get(user=user).daily_repetitions == 7
