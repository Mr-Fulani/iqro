from __future__ import annotations

from typing import Any

import pytest
from django.test import override_settings

from quran_backend.modules.tajweed.models import AyahTajweed
from quran_backend.modules.tajweed.practice import (
    PracticeState,
    apply_session,
    parse_task_key,
    practice_state,
    practice_tasks,
    task_key,
)
from tests.test_tajweed_course import MARKUP, _sync_markup, owner, published  # noqa: F401


def _answer(key: str, correct: bool, at: str) -> dict[str, Any]:
    task_type, _, target = key.split("~")
    return {"key": key, "target": target, "type": task_type, "correct": correct, "at": at}


def _session(
    session_id: str, day: str, answers: list[dict[str, Any]], finished: str | None = None
) -> dict[str, Any]:
    return {
        "id": session_id,
        "course": "tajweed",
        "local_date": day,
        "finished_at": finished or f"{day}T12:00:00.000Z",
        "answers": answers,
    }


KEY = "find~112:4~izhar"


def test_score_counts_right_answers_and_the_streak_counts_days_in_a_row() -> None:
    state = PracticeState()
    apply_session(state, _session("a", "2026-10-20", [_answer(KEY, True, "2026-10-20T10:00:00Z")]))
    apply_session(state, _session("b", "2026-10-20", [_answer(KEY, False, "2026-10-20T11:00:00Z")]))
    apply_session(state, _session("c", "2026-10-21", []))
    assert (state.answers, state.correct, state.current_streak, state.best_streak) == (2, 1, 2, 2)
    apply_session(state, _session("d", "2026-10-25", []))
    assert (state.current_streak, state.best_streak) == (1, 2)
    payload = state.as_dict("tajweed")
    assert payload["score"] == 1
    assert payload["streak"] == {"current": 1, "best": 2, "last_date": "2026-10-25"}


def test_a_mistake_comes_back_after_one_then_three_days_until_it_is_learned() -> None:
    state = PracticeState()
    apply_session(state, _session("a", "2026-10-20", [_answer(KEY, False, "2026-10-20T10:00:00Z")]))
    assert state.review[KEY] == {
        "key": KEY,
        "target": "izhar",
        "type": "find",
        "box": 1,
        "due_at": "2026-10-20T10:00:00.000Z",
    }
    apply_session(state, _session("b", "2026-10-20", [_answer(KEY, True, "2026-10-20T11:00:00Z")]))
    assert (state.review[KEY]["box"], state.review[KEY]["due_at"]) == (
        2,
        "2026-10-21T11:00:00.000Z",
    )
    apply_session(state, _session("c", "2026-10-21", [_answer(KEY, True, "2026-10-21T11:00:00Z")]))
    assert (state.review[KEY]["box"], state.review[KEY]["due_at"]) == (
        3,
        "2026-10-24T11:00:00.000Z",
    )
    apply_session(state, _session("d", "2026-10-24", [_answer(KEY, True, "2026-10-24T11:00:00Z")]))
    assert KEY not in state.review
    # A right answer to a task that was never missed changes nothing.
    apply_session(state, _session("e", "2026-10-24", [_answer(KEY, True, "2026-10-24T12:00:00Z")]))
    assert state.review == {}


def test_the_state_does_not_depend_on_the_order_sessions_arrive_in() -> None:
    sessions = [
        _session("b", "2026-10-21", [_answer(KEY, True, "2026-10-21T10:00:00Z")]),
        _session("a", "2026-10-20", [_answer(KEY, False, "2026-10-20T10:00:00Z")]),
    ]
    assert practice_state(sessions).as_dict("t") == practice_state(sessions[::-1]).as_dict("t")
    assert practice_state(sessions).review[KEY]["box"] == 2


def test_task_keys() -> None:
    assert task_key("listen", "1:7", "izhar_shafawi") == "listen~1:7~izhar_shafawi"
    assert parse_task_key("listen~1:7~izhar_shafawi") == ("listen", "1:7", "izhar_shafawi")
    assert parse_task_key("guess~1:7~izhar") is None
    assert parse_task_key("find~1:7") is None


@pytest.mark.django_db
@override_settings(QURAN_QF_ENV="production")
def test_tasks_come_from_the_markup_of_passed_lessons_with_unambiguous_options() -> None:
    _sync_markup(list(MARKUP))
    from quran_backend.modules.tajweed.selectors import (  # noqa: PLC0415
        published_tajweed_ayahs,
        published_tajweed_edition,
    )

    edition = published_tajweed_edition("production")
    assert edition is not None
    ayahs = published_tajweed_ayahs(edition)
    targets = ["izhar", "qalaqah", "madda_normal", "laam_qamariyah"]
    tasks = practice_tasks(ayahs, targets=targets, count=8, seed=7, review=[])
    assert tasks == practice_tasks(ayahs, targets=targets, count=8, seed=7, review=[])
    assert len(tasks) == 8
    seen = set()
    for task in tasks:
        assert task["target"] in targets
        assert task["review"] is False
        assert task["key"] == task_key(task["type"], task["example"]["verse_key"], task["target"])
        assert (task["example"]["verse_key"], task["target"]) not in seen
        seen.add((task["example"]["verse_key"], task["target"]))
        assert 0 <= task["focus"] < len(task["example"]["occurrences"])
        if task["type"] == "find":
            assert "options" not in task
        else:
            assert task["target"] in task["options"]
            assert len(set(task["options"])) == len(task["options"]) <= 4
    assert {task["type"] for task in tasks} > {"find"}
    # With one passed lesson there is nothing to choose between: every task is «find».
    single = practice_tasks(ayahs, targets=["izhar"], count=3, seed=1, review=[])
    assert [task["type"] for task in single] == ["find", "find", "find"]


@pytest.mark.django_db
@override_settings(QURAN_QF_ENV="production")
def test_review_tasks_come_first_and_stale_keys_are_skipped() -> None:
    _sync_markup(list(MARKUP))
    ayahs = AyahTajweed.objects.all()
    tasks = practice_tasks(
        ayahs,
        targets=["izhar", "qalaqah"],
        count=3,
        seed=3,
        review=[
            "identify~112:4~izhar",
            "find~2:2~izhar",  # 2:2 has no izhar
            "find~112:4~ghunnah",  # not a passed lesson
            "listen~1:7~izhar",
        ],
    )
    assert [(task["key"], task["review"]) for task in tasks[:2]] == [
        ("identify~112:4~izhar", True),
        ("listen~1:7~izhar", True),
    ]
    assert tasks[2]["review"] is False
    # Options never offer a second target on the asked letters.
    identify = tasks[0]
    assert "qalaqah" in identify["options"]


# API -------------------------------------------------------------------------


@pytest.mark.usefixtures("published")
@override_settings(QURAN_QF_ENV="production")
def test_the_practice_api_builds_tasks_for_passed_lessons(api_client: Any) -> None:
    _sync_markup(list(MARKUP))
    url = "/api/v1/tajweed/courses/tajweed/practice"
    response = api_client.get(url, {"lessons": "izhar,qalqalah,nope", "count": 4, "seed": 11})
    assert response.status_code == 200
    assert response["Cache-Control"].startswith("public")
    body = response.json()
    assert body["seed"] == 11
    assert len(body["tasks"]) == 4
    assert {task["target"] for task in body["tasks"]} <= {"izhar", "qalaqah"}
    assert (
        body
        == api_client.get(url, {"lessons": "izhar,qalqalah,nope", "count": 4, "seed": 11}).json()
    )
    review = api_client.get(
        url, {"lessons": "izhar", "count": 2, "review": "find~1:7~izhar"}
    ).json()
    assert review["tasks"][0]["key"] == "find~1:7~izhar"
    assert review["tasks"][0]["review"] is True
    assert api_client.get(url, {"lessons": "nope"}).status_code == 400
    assert api_client.get(url, {"lessons": "izhar", "count": 13}).status_code == 400


def _body(session_id: str, *, correct: bool = False, day: str = "2026-10-22") -> dict[str, Any]:
    return {
        "id": session_id,
        "course": "tajweed",
        "local_date": day,
        "finished_at": f"{day}T10:05:00+03:00",
        "answers": [
            {
                "key": KEY,
                "target": "izhar",
                "type": "find",
                "correct": correct,
                "at": f"{day}T10:01:00Z",
            }
        ],
    }


@pytest.mark.django_db
def test_sessions_are_stored_once_and_the_state_follows_them(api_client: Any) -> None:
    from quran_backend.modules.accounts.models import User  # noqa: PLC0415

    url = "/api/v1/me/tajweed/practice-sessions"
    session_id = "019a0000-0000-7000-8000-000000000001"
    assert api_client.post(url, _body(session_id), format="json").status_code in {401, 403}
    user = User.objects.create_user(timezone="UTC")
    api_client.force_authenticate(user)
    created = api_client.post(url, _body(session_id), format="json")
    assert created.status_code == 201
    assert created["Cache-Control"].startswith("private")
    state = created.json()
    assert (state["sessions"], state["answers"], state["score"]) == (1, 1, 0)
    assert state["streak"] == {"current": 1, "best": 1, "last_date": "2026-10-22"}
    assert state["review"][0]["key"] == KEY
    assert api_client.post(url, _body(session_id), format="json").status_code == 200
    assert api_client.post(url, _body(session_id, correct=True), format="json").status_code == 409
    second = api_client.post(
        url,
        _body("019a0000-0000-7000-8000-000000000002", correct=True, day="2026-10-23"),
        format="json",
    ).json()
    assert second["score"] == 1
    assert second["streak"]["current"] == 2
    assert second["review"][0]["box"] == 2
    assert api_client.get("/api/v1/me/tajweed/practice/tajweed").json() == second
    for bad in (
        {**_body("not-a-uuid")},
        {**_body("019a0000-0000-7000-8000-000000000003"), "local_date": "22.10.2026"},
        {**_body("019a0000-0000-7000-8000-000000000003"), "answers": [{"key": "guess~1:1~izhar"}]},
        {
            **_body("019a0000-0000-7000-8000-000000000003"),
            "answers": [{**_body("x")["answers"][0], "target": "ghunnah"}],
        },
        {**_body("019a0000-0000-7000-8000-000000000003"), "finished_at": "2026-10-22T10:05:00"},
    ):
        assert api_client.post(url, bad, format="json").status_code == 400
    other = User.objects.create_user(timezone="UTC")
    api_client.force_authenticate(other)
    assert api_client.post(url, _body(session_id), format="json").status_code == 409


@pytest.mark.django_db
def test_guest_sessions_move_to_the_account_and_go_with_it() -> None:
    from quran_backend.modules.accounts.merge import _merge_tajweed_progress  # noqa: PLC0415
    from quran_backend.modules.accounts.models import User  # noqa: PLC0415
    from quran_backend.modules.tajweed.practice import (  # noqa: PLC0415
        record_practice_session,
        user_practice_state,
    )

    guest = User.objects.create_user(timezone="UTC")
    account = User.objects.create_user(timezone="UTC")
    record_practice_session(guest, _body("019a0000-0000-7000-8000-000000000011"))
    record_practice_session(account, _body("019a0000-0000-7000-8000-000000000012", correct=True))
    counts: dict[str, int] = {}
    _merge_tajweed_progress(source=guest, target=account, counts=counts)
    assert counts["tajweed_practice_sessions"] == 1
    assert user_practice_state(account, "tajweed")["sessions"] == 2
    assert user_practice_state(guest, "tajweed")["sessions"] == 0
