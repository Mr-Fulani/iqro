# ruff: noqa: RUF001
from __future__ import annotations

import copy
import json
from typing import Any
from unittest.mock import patch

import pytest
from django.contrib.auth.models import Permission
from django.test import Client, override_settings
from django.urls import reverse
from rest_framework.test import APIClient

from quran_backend.modules.accounts.models import User
from quran_backend.modules.tajweed.course import (
    TajweedCourseError,
    load_course_snapshot,
    missing_texts,
    validate_course_snapshot,
)
from quran_backend.modules.tajweed.course_markers import occurrences, parse_course_words
from quran_backend.modules.tajweed.course_publication import (
    copy_tajweed_course,
    import_tajweed_course,
    publish_tajweed_course,
    sign_tajweed_course,
)
from quran_backend.modules.tajweed.markup import parse_tajweed_verse
from quran_backend.modules.tajweed.models import (
    TAJWEED_COURSE_LANGUAGES,
    TajweedCourse,
    TajweedCourseDocument,
    TajweedCourseProgress,
    TajweedCourseStatus,
    TajweedCourseVersion,
)
from quran_backend.modules.tajweed.progress import merge_lessons
from quran_backend.modules.tajweed.quran_foundation_sync import (
    VerseWords,
    sync_quran_foundation_tajweed,
)
from tests.test_tajweed import FakeTajweedClient

# Real Quran.Foundation `text_uthmani_tajweed` rows.
MARKUP = {
    "1:7": (
        "صِر<tajweed class=madda_normal>َٲ</tajweed>طَ <tajweed class=ham_wasl>ٱ</tajweed>"
        "لَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ <tajweed class=ham_wasl>ٱ</tajweed>لْمَغْضُوبِ "
        "عَلَيْهِمْ وَلَا <tajweed class=ham_wasl>ٱ</tajweed><tajweed class=laam_shamsiyah>ل"
        "</tajweed>ضّ<tajweed class=madda_necessary>َا</tajweed>ٓلّ"
        "<tajweed class=madda_permissible>ِي</tajweed>نَ <span class=end>٧</span>"
    ),
    "2:2": (
        "ذ<tajweed class=madda_normal>َٲ</tajweed>لِكَ <tajweed class=ham_wasl>ٱ</tajweed>لْكِتَ"
        "<tajweed class=madda_normal>ـٰ</tajweed>بُ لَا رَيْبَ‌ۛ فِيهِ‌ۛ هُ"
        "<tajweed class=idgham_wo_ghunnah>دًى ل</tajweed>ِّلْمُتَّق"
        "<tajweed class=madda_permissible>ِي</tajweed>نَ <span class=end>٢</span>"
    ),
    "106:4": (
        "ٱلَّذ<tajweed class=madda_obligatory>ِىٓ</tajweed> أَ<tajweed class=qalaqah>طْ</tajweed>"
        "عَمَه<tajweed class=idgham_shafawi>ُم م</tajweed>ِّ<tajweed class=ikhafa>ن ج</tajweed>ُو"
        "<tajweed class=idgham_ghunnah>عٍ و</tajweed>َءَامَنَه<tajweed class=idgham_shafawi>ُم م"
        "</tajweed>ِّنْ خ<tajweed class=madda_permissible>َو</tajweed>ْفِۭ <span class=end>٤</span>"
    ),
    "108:1": (
        "إِ<tajweed class=ghunnah>نّ</tajweed><tajweed class=madda_obligatory>َآ</tajweed> "
        "أَعْطَيْنَ<tajweed class=madda_normal>ـٰ</tajweed>كَ <tajweed class=ham_wasl>ٱ</tajweed>"
        "لْكَوْثَرَ <span class=end>١</span>"
    ),
    "109:1": (
        "قُلْ يَ<tajweed class=madda_obligatory>ـٰٓ</tajweed>أَيُّهَا <tajweed class=ham_wasl>ٱ"
        "</tajweed>لْكَ<tajweed class=madda_normal>ـٰ</tajweed>فِر"
        "<tajweed class=madda_permissible>ُو</tajweed>نَ <span class=end>١</span>"
    ),
    "110:1": (
        "إِذَا ج<tajweed class=madda_obligatory>َا</tajweed>ٓءَ نَصْرُ <tajweed class=ham_wasl>ٱ"
        "</tajweed>للَّهِ وَ<tajweed class=ham_wasl>ٱ</tajweed>لْفَتْحُ <span class=end>١</span>"
    ),
    "112:1": (
        "قُلْ هُوَ <tajweed class=ham_wasl>ٱ</tajweed>للَّهُ أَحَ<tajweed class=qalaqah>د"
        "</tajweed>ٌ <span class=end>١</span>"
    ),
    "112:4": (
        "وَلَمْ يَك<tajweed class=idgham_wo_ghunnah>ُن ل</tajweed>َّهُ"
        "<tajweed class=madda_normal>ۥ</tajweed> كُفُوًا أَحَ<tajweed class=qalaqah>د</tajweed>ُۢ "
        "<span class=end>٤</span>"
    ),
}
PAGES = {"1:7": 1, "2:2": 2, "106:4": 602, "108:1": 602, "109:1": 603, "110:1": 603}


def _words(verse_key: str) -> tuple[Any, ...]:
    words = parse_course_words(verse_key, MARKUP[verse_key], [])
    assert words is not None
    return words


def _found(verse_key: str, target: str) -> list[dict[str, Any]]:
    return [occurrence.as_dict() for occurrence in occurrences(_words(verse_key), target)]


def _texts(verse_key: str, target: str) -> list[str]:
    words = _words(verse_key)
    return [
        " ".join(words[part.position - 1].text[part.start : part.end] for part in occurrence.parts)
        for occurrence in occurrences(words, target)
    ]


# Targets -----------------------------------------------------------------


def test_quran_foundation_classes_are_places_and_a_joined_rule_is_one_place() -> None:
    assert _found("112:4", "idgham_wo_ghunnah") == [
        {"parts": [{"position": 2, "start": 3, "end": 5}, {"position": 3, "start": 0, "end": 1}]}
    ]
    assert _found("112:4", "madda_normal") == [
        {"parts": [{"position": 3, "start": 5, "end": 6}], "variant": "silah_sughra"}
    ]
    assert _found("112:4", "qalaqah")[0]["variant"] == "stop"


def test_izhar_is_noon_with_sukun_or_tanween_before_a_throat_letter() -> None:
    # «أَنْعَمْتَ»: noon and ʿayn in one word; «كُفُوًا أَحَدٌۢ»: tanween before hamza.
    assert _texts("1:7", "izhar") == ["نْعَ"]
    assert _texts("112:4", "izhar") == ["وً أَ"]
    assert _texts("106:4", "izhar") == ["نْ خَ"]
    assert _found("112:4", "izhar")[0]["parts"] == [
        {"position": 4, "start": 4, "end": 6},
        {"position": 5, "start": 0, "end": 2},
    ]
    # Idgham and ikhfa noons carry no sukun: they are QF classes, not izhar.
    assert _texts("2:2", "izhar") == []


def test_izhar_shafawi_and_lam_qamariyah_read_the_sukun() -> None:
    # «أَنْعَمْتَ», «عَلَيْهِمْ غَيْرِ», «عَلَيْهِمْ وَلَا»: before waw too (no idgham into it).
    assert _texts("1:7", "izhar_shafawi") == ["مْتَ", "مْ غَ", "مْ وَ"]
    assert _texts("108:1", "laam_qamariyah") == ["لْ"]
    assert _texts("1:7", "laam_qamariyah") == ["لْ"]
    # The article before a sun letter is QF laam_shamsiyah, never qamariyah.
    assert _found("1:7", "laam_shamsiyah")
    assert len(_found("1:7", "laam_qamariyah")) == 1


def test_obligatory_madd_is_split_by_where_the_hamza_is() -> None:
    assert _texts("110:1", "madd_muttasil") == ["َا"]
    assert _texts("110:1", "madd_munfasil") == []
    assert _texts("108:1", "madd_munfasil") == ["َآ"]
    # «يَـٰٓأَيُّهَا»: the vocative is written into the word, the madd is still separated.
    assert _texts("109:1", "madd_munfasil") == ["ـٰٓ"]
    assert _texts("106:4", "madd_munfasil") == ["ِىٓ"]


def test_an_ayah_that_no_longer_matches_its_stored_words_is_left_out() -> None:
    stored = [{"position": 2, "text": "يَكُن", "rules": [{"code": "ikhafa", "start": 0, "end": 1}]}]
    assert parse_course_words("112:4", MARKUP["112:4"], stored) is None
    assert parse_course_words("112:4", "<broken", []) is None


# Snapshot ----------------------------------------------------------------


def _snapshot() -> dict[str, Any]:
    return copy.deepcopy(load_course_snapshot())


def test_the_course_in_git_is_complete_and_covers_every_quran_foundation_class() -> None:
    snapshot = _snapshot()
    validate_course_snapshot(snapshot)
    assert missing_texts(snapshot) == {"ar": 0, "en": 0, "ru": 0, "tr": 0}
    targets = {lesson["target"] for lesson in snapshot["lessons"]}
    assert {"izhar", "izhar_shafawi", "laam_qamariyah", "madd_muttasil", "madd_munfasil"} < targets
    assert {
        "ikhafa",
        "idgham_ghunnah",
        "idgham_wo_ghunnah",
        "iqlab",
        "ikhafa_shafawi",
        "idgham_shafawi",
        "ghunnah",
        "qalaqah",
        "madda_necessary",
        "madda_permissible",
        "madda_normal",
        "idgham_mutajanisayn",
        "idgham_mutaqaribayn",
        "ham_wasl",
        "laam_shamsiyah",
        "slnt",
    } < targets
    assert snapshot["course"]["review_status"] == "pending_teacher_review"


def test_snapshot_problems_are_reported_together() -> None:
    snapshot = _snapshot()
    snapshot["lessons"][0]["target"] = "tafkhim"
    snapshot["lessons"][1]["title"]["tr"] = ""
    snapshot["lessons"][2]["examples"] = ["115:1"]
    snapshot["sections"][0]["lessons"].append(snapshot["lessons"][3]["slug"])
    with pytest.raises(TajweedCourseError) as error:
        validate_course_snapshot(snapshot)
    text = str(error.value)
    assert "неизвестная цель 'tafkhim'" in text
    assert "[tr]: нет текста" in text
    assert "examples" in text
    assert "ровно в одном разделе" in text
    # A draft may miss a translation, not structure.
    snapshot = _snapshot()
    snapshot["lessons"][1]["title"]["tr"] = ""
    validate_course_snapshot(snapshot, complete=False)


# Publication and public API ------------------------------------------------


def _sync_markup(keys: list[str]) -> None:
    verses = [{"verse_key": key, "text_uthmani_tajweed": MARKUP[key]} for key in keys]
    verse_words = {
        key: VerseWords(
            page_number=PAGES.get(key, 604),
            words=tuple(word.text for word in parse_tajweed_verse(key, MARKUP[key])),
        )
        for key in keys
    }
    sync_quran_foundation_tajweed(
        client=FakeTajweedClient(verses), verse_words=verse_words, mushaf_checksum="m" * 64
    )


@pytest.fixture
def owner(db: None) -> User:
    return User.objects.create_superuser(email="owner@example.com", password="pw-123456789")


@pytest.fixture
def published(owner: User) -> Any:
    with patch(
        "quran_backend.modules.tajweed.course_publication.enqueue_tajweed_content_change"
    ) as notify:
        version = import_tajweed_course(_snapshot())
        sign_tajweed_course(version, owner)
        publish_tajweed_course(version)
    notify.assert_called_once_with(action="activated", course="tajweed", version=version.version)
    version.refresh_from_db()
    return version


@pytest.mark.django_db
def test_import_compiles_a_document_per_language_and_reimport_is_a_no_op() -> None:
    version = import_tajweed_course(_snapshot())
    assert import_tajweed_course(_snapshot()) == version
    assert sorted(version.documents.values_list("language", flat=True)) == ["ar", "en", "ru", "tr"]
    document = TajweedCourseDocument.objects.get(version=version, language="ru").payload
    assert document["course"]["title"] == "Таджвид"
    assert document["course"]["review_status"] == "pending_teacher_review"
    lessons = {lesson["slug"]: lesson for lesson in document["lessons"]}
    assert lessons["idgham-without-ghunnah"]["target"] == "idgham_wo_ghunnah"
    assert document["targets"]["idgham_wo_ghunnah"] == {
        "name": "Идгам без гунны",
        "arabic_name": "الإدغام بغير غنة",
        "color": "#A3A5A5",
        "rule": "idgham_wo_ghunnah",
    }
    assert document["targets"]["madd_munfasil"]["rule"] == "madda_obligatory"
    assert [lesson["slug"] for lesson in document["lessons"]] == [
        slug for section in document["sections"] for slug in section["lessons"]
    ]
    changed = _snapshot()
    changed["course"]["summary"]["ru"] = "Другое"
    with pytest.raises(TajweedCourseError, match=r"Поднимите course\.version"):
        import_tajweed_course(changed)


@pytest.mark.django_db
def test_only_a_signed_draft_is_published_and_the_previous_version_is_withdrawn(
    owner: User,
) -> None:
    first = import_tajweed_course(_snapshot())
    with pytest.raises(TajweedCourseError, match="подписать"):
        publish_tajweed_course(first)
    sign_tajweed_course(first, owner)
    publish_tajweed_course(first)
    second = copy_tajweed_course(first, "2026-11-01")
    sign_tajweed_course(second, owner)
    publish_tajweed_course(second)
    first.refresh_from_db()
    second.refresh_from_db()
    assert first.status == TajweedCourseStatus.WITHDRAWN
    assert second.status == TajweedCourseStatus.PUBLISHED
    assert TajweedCourse.objects.get(slug="tajweed").active_version == second
    with pytest.raises(TajweedCourseError, match="только черновик"):
        publish_tajweed_course(second)


def test_course_list_and_document_show_only_the_published_version(
    api_client: APIClient, published: Any
) -> None:
    courses = api_client.get("/api/v1/tajweed/courses").json()
    assert [(course["slug"], course["version"]) for course in courses] == [
        ("tajweed", published.version)
    ]
    response = api_client.get("/api/v1/tajweed/courses/tajweed?language=ar")
    assert response.status_code == 200
    assert response["Cache-Control"].startswith("public")
    assert response.json()["course"]["language"] == "ar"
    assert response.json()["course"]["published_at"]
    assert api_client.get("/api/v1/tajweed/courses/tajweed?language=fr").status_code == 400
    assert api_client.get("/api/v1/tajweed/courses/other").status_code == 404


@pytest.mark.django_db
def test_an_unpublished_course_is_not_served(api_client: APIClient) -> None:
    import_tajweed_course(_snapshot())
    assert api_client.get("/api/v1/tajweed/courses").json() == []
    assert api_client.get("/api/v1/tajweed/courses/tajweed").status_code == 404


@override_settings(QURAN_QF_ENV="production")
def test_examples_come_from_the_markup_well_known_and_short_first(
    api_client: APIClient, published: Any
) -> None:
    _sync_markup(list(MARKUP))
    url = "/api/v1/tajweed/courses/tajweed/lessons/izhar/examples"
    first = api_client.get(url, {"limit": 2}).json()
    assert first["lesson"] == "izhar"
    assert first["target"] == "izhar"
    # Juz ʿAmma and al-Fatiha first, shortest first; 2:2 has no izhar.
    assert [example["verse_key"] for example in first["examples"]] == ["112:4", "106:4"]
    assert first["next_offset"] == 2
    example = first["examples"][0]
    assert example["words"][1] == {"position": 2, "text": "يَكُن"}
    assert example["page_number"] == 604
    assert example["occurrences"] == [
        {"parts": [{"position": 4, "start": 4, "end": 6}, {"position": 5, "start": 0, "end": 2}]}
    ]
    rest = api_client.get(url, {"offset": 2, "limit": 2}).json()
    assert [example["verse_key"] for example in rest["examples"]] == ["1:7"]
    assert rest["next_offset"] is None
    assert api_client.get(url, {"limit": 9}).status_code == 400
    missing = "/api/v1/tajweed/courses/tajweed/lessons/nope/examples"
    assert api_client.get(missing).status_code == 404


@override_settings(QURAN_QF_ENV="production")
def test_a_lesson_s_own_ayahs_come_first(api_client: APIClient, published: Any) -> None:
    _sync_markup(list(MARKUP))
    snapshot = copy.deepcopy(published.snapshot)
    lesson = next(item for item in snapshot["lessons"] if item["target"] == "madd_munfasil")
    lesson["examples"] = ["2:2", "106:4"]  # 2:2 has no separated madd: skipped
    published.snapshot = snapshot
    published.save(update_fields=["snapshot"])
    url = f"/api/v1/tajweed/courses/tajweed/lessons/{lesson['slug']}/examples"
    keys = [example["verse_key"] for example in api_client.get(url).json()["examples"]]
    assert keys == ["106:4", "108:1", "109:1"]


def test_examples_need_published_markup(api_client: APIClient, published: Any) -> None:
    assert published.status == TajweedCourseStatus.PUBLISHED
    url = "/api/v1/tajweed/courses/tajweed/lessons/izhar/examples"
    assert api_client.get(url).status_code == 404


# Progress -----------------------------------------------------------------


def _entry(status: str, step: str, at: str) -> dict[str, str]:
    return {"status": status, "step_slug": step, "content_version": "v1", "updated_at": at}


def test_merge_keeps_a_passed_lesson_passed_and_takes_the_later_record() -> None:
    stored = {
        "izhar": _entry("completed", "find", "2026-10-20T10:00:00.000Z"),
        "iqlab": _entry("in_progress", "how", "2026-10-21T10:00:00.000Z"),
    }
    incoming = {
        "izhar": _entry("in_progress", "example-2", "2026-10-22T10:00:00.000Z"),
        "iqlab": _entry("in_progress", "intro", "2026-10-20T10:00:00.000Z"),
        "ikhfa": _entry("in_progress", "intro", "2026-10-22T09:00:00.000Z"),
    }
    merged = merge_lessons(stored, incoming)
    assert merged["izhar"] == _entry("completed", "example-2", "2026-10-22T10:00:00.000Z")
    assert merged["iqlab"] == stored["iqlab"]
    assert merged["ikhfa"] == incoming["ikhfa"]
    assert merge_lessons(incoming, stored) == merged


@pytest.mark.django_db
def test_progress_is_private_and_merged_on_every_write(api_client: APIClient) -> None:
    url = reverse("tajweed-progress", args=["tajweed"])
    assert api_client.get(url).status_code in {401, 403}
    user = User.objects.create_user(timezone="UTC")
    api_client.force_authenticate(user)
    assert api_client.get(url).json() == {"course": "tajweed", "lessons": {}}
    first = api_client.put(
        url,
        {"lessons": {"izhar": _entry("completed", "find", "2026-10-22T10:00:00+03:00")}},
        format="json",
    )
    assert first.status_code == 200
    assert first["Cache-Control"].startswith("private")
    assert first.json()["lessons"]["izhar"]["updated_at"] == "2026-10-22T07:00:00.000Z"
    second = api_client.put(
        url,
        {"lessons": {"izhar": _entry("in_progress", "intro", "2026-10-22T08:00:00.000Z")}},
        format="json",
    ).json()
    assert second["lessons"]["izhar"]["status"] == "completed"
    assert second["lessons"]["izhar"]["step_slug"] == "intro"
    assert api_client.get(url).json() == second
    for bad in (
        {"lessons": []},
        {"lessons": {"Izhar!": _entry("completed", "find", "2026-10-22T08:00:00Z")}},
        {"lessons": {"izhar": _entry("passed", "find", "2026-10-22T08:00:00Z")}},
        {"lessons": {"izhar": _entry("completed", "find", "yesterday")}},
        {"lessons": {"izhar": _entry("completed", "find", "2026-10-22T08:00:00")}},
    ):
        assert api_client.put(url, bad, format="json").status_code == 400


@pytest.mark.django_db
def test_guest_progress_moves_to_the_account_and_is_deleted_with_it() -> None:
    from quran_backend.modules.accounts.merge import _merge_tajweed_progress  # noqa: PLC0415

    guest = User.objects.create_user(timezone="UTC")
    account = User.objects.create_user(timezone="UTC")
    TajweedCourseProgress.objects.create(
        user=guest,
        course="tajweed",
        lessons={"izhar": _entry("completed", "find", "2026-10-20T10:00:00.000Z")},
    )
    TajweedCourseProgress.objects.create(
        user=guest,
        course="other",
        lessons={"a": _entry("in_progress", "intro", "2026-10-20T10:00:00.000Z")},
    )
    TajweedCourseProgress.objects.create(
        user=account,
        course="tajweed",
        lessons={"izhar": _entry("in_progress", "how", "2026-10-21T10:00:00.000Z")},
    )
    counts: dict[str, int] = {}
    _merge_tajweed_progress(source=guest, target=account, counts=counts)
    assert counts == {"tajweed_progress": 2, "tajweed_practice_sessions": 0}
    assert not TajweedCourseProgress.objects.filter(user=guest).exists()
    merged = TajweedCourseProgress.objects.get(user=account, course="tajweed").lessons
    assert merged["izhar"]["status"] == "completed"
    assert TajweedCourseProgress.objects.filter(user=account).count() == 2


# Admin --------------------------------------------------------------------


@pytest.mark.django_db
def test_the_admin_edits_a_draft_signs_it_and_publishes(client: Any, owner: User) -> None:
    version = import_tajweed_course(_snapshot())
    client.force_login(owner)
    editor = reverse("admin:tajweed_tajweedcourseversion_editor", args=[version.pk])
    page = client.get(editor, {"node": "lesson:izhar"})
    assert page.status_code == 200
    assert "Объяснение правила" in page.content.decode()
    data = {
        "node": "lesson:izhar",
        "minutes": "6",
        "letters": "ء ه ع ح غ خ",
        "examples": "106:4, 112:4",
    }
    lesson = next(item for item in version.snapshot["lessons"] if item["slug"] == "izhar")
    for field in ("title", "summary", "explanation", "how"):
        for language, text in lesson[field].items():
            data[f"{field}__{language}"] = text
    data["title__ru"] = "Изхар (ясное чтение)"
    assert client.post(f"{editor}?node=lesson:izhar", data).status_code == 302
    version.refresh_from_db()
    lesson = next(item for item in version.snapshot["lessons"] if item["slug"] == "izhar")
    assert lesson["title"]["ru"] == "Изхар (ясное чтение)"
    assert lesson["minutes"] == 6
    assert lesson["examples"] == ["106:4", "112:4"]
    ru = version.documents.get(language="ru").payload
    assert next(item for item in ru["lessons"] if item["slug"] == "izhar")["title"] == (
        "Изхар (ясное чтение)"
    )
    refused = client.post(f"{editor}?node=lesson:izhar", {**data, "examples": "999:1"})
    assert refused.status_code == 400
    assert "Не сохранено" in refused.content.decode()

    review = reverse("admin:tajweed_tajweedcourseversion_review", args=[version.pk])
    with patch("quran_backend.modules.tajweed.course_publication.enqueue_tajweed_content_change"):
        client.post(review, {"action": "sign"})
        version.refresh_from_db()
        assert version.is_signed
        assert client.post(f"{editor}?node=lesson:izhar", data).status_code == 403
        client.post(review, {"action": "publish"})
    version.refresh_from_db()
    assert version.status == TajweedCourseStatus.PUBLISHED

    download = client.get(reverse("admin:tajweed_tajweedcourseversion_snapshot", args=[version.pk]))
    assert json.loads(download.content) == version.snapshot
    new_draft = reverse("admin:tajweed_tajweedcourseversion_new_draft", args=[version.pk])
    assert client.get(new_draft).status_code == 200
    assert client.post(new_draft, {"version": version.version}).status_code == 400
    assert client.post(new_draft, {"version": "2026-12-01"}).status_code == 302
    assert version.course.versions.filter(version="2026-12-01", status="draft").exists()
    change = reverse("admin:tajweed_tajweedcourseversion_change", args=[version.pk])
    assert "Создать черновик из этой версии" in client.get(change).content.decode()


VERSIONS = "/admin/tajweed/tajweedcourseversion/"
DOCUMENTS = "/admin/tajweed/tajweedcoursedocument/"
LIST_ACTIONS = ("sign_versions", "publish_versions", "recompile_versions")
NOTIFY = "quran_backend.modules.tajweed.course_publication.enqueue_tajweed_content_change"
COMPILE = "quran_backend.modules.tajweed.course_admin.compile_course_version"


def _staff(*codenames: str) -> Client:
    user = User.objects.create_user(
        email=f"staff-{'-'.join(codenames)}@example.com", status="active", is_staff=True
    )
    user.user_permissions.set(Permission.objects.filter(codename__in=codenames))
    client = Client()
    client.force_login(user)
    return client


def _action(client: Client, action: str, version: TajweedCourseVersion) -> Any:
    """The action as the version list sends it, for one selected version."""
    with patch(NOTIFY):
        return client.post(
            VERSIONS, {"action": action, "index": 0, "_selected_action": [version.pk]}
        )


@pytest.mark.django_db
def test_list_actions_need_the_change_permission() -> None:
    version = import_tajweed_course(_snapshot())
    reader = _staff("view_tajweedcourseversion")
    page = reader.get(VERSIONS).content.decode()
    assert not any(f'value="{action}"' in page for action in LIST_ACTIONS)
    with patch(COMPILE) as recompile:
        for action in LIST_ACTIONS:
            _action(reader, action, version)
    recompile.assert_not_called()
    version.refresh_from_db()
    assert not version.is_signed

    editor = _staff("view_tajweedcourseversion", "change_tajweedcourseversion")
    page = editor.get(VERSIONS).content.decode()
    assert all(f'value="{action}"' in page for action in LIST_ACTIONS)
    with patch(COMPILE) as recompile:
        _action(editor, "recompile_versions", version)
    recompile.assert_called_once()
    assert _action(editor, "sign_versions", version).status_code == 302
    version.refresh_from_db()
    assert version.reviewed_by == User.objects.get(
        email="staff-view_tajweedcourseversion-change_tajweedcourseversion@example.com"
    )
    _action(editor, "publish_versions", version)
    version.refresh_from_db()
    assert version.status == TajweedCourseStatus.PUBLISHED


@pytest.mark.django_db
def test_a_signed_draft_is_not_signed_again(client: Any, owner: User) -> None:
    version = import_tajweed_course(_snapshot())
    client.force_login(owner)
    _action(client, "sign_versions", version)
    version.refresh_from_db()
    signed_at = version.reviewed_at

    _action(
        _staff("view_tajweedcourseversion", "change_tajweedcourseversion"), "sign_versions", version
    )
    version.refresh_from_db()
    assert version.reviewed_by == owner
    assert version.reviewed_at == signed_at


@pytest.mark.django_db
def test_a_draft_is_deleted_only_with_the_delete_permission() -> None:
    version = import_tajweed_course(_snapshot())
    delete = reverse("admin:tajweed_tajweedcourseversion_delete", args=[version.pk])
    # The documents' delete permission alone does not delete their version.
    reader = _staff("view_tajweedcourseversion", "delete_tajweedcoursedocument")
    assert 'value="delete_selected"' not in reader.get(VERSIONS).content.decode()
    assert reader.post(delete, {"post": "yes"}).status_code == 403
    assert TajweedCourseVersion.objects.filter(pk=version.pk).exists()

    remover = _staff(
        "view_tajweedcourseversion", "delete_tajweedcourseversion", "delete_tajweedcoursedocument"
    )
    assert remover.post(delete, {"post": "yes"}).status_code == 302
    assert not TajweedCourseVersion.objects.filter(pk=version.pk).exists()


def test_documents_of_a_published_or_withdrawn_version_are_not_deleted(
    client: Any, owner: User, published: Any
) -> None:
    draft = copy_tajweed_course(published, "2026-11-01")
    client.force_login(owner)
    document = draft.documents.get(language="ru")
    delete = reverse("admin:tajweed_tajweedcoursedocument_delete", args=[document.pk])
    assert client.get(delete).status_code == 200

    _action(client, "sign_versions", draft)
    _action(client, "publish_versions", draft)
    published.refresh_from_db()
    assert published.status == TajweedCourseStatus.WITHDRAWN
    for version in (draft, published):
        document = version.documents.get(language="ru")
        delete = reverse("admin:tajweed_tajweedcoursedocument_delete", args=[document.pk])
        assert client.post(delete, {"post": "yes"}).status_code == 403
        selected = {"action": "delete_selected", "_selected_action": [document.pk], "post": "yes"}
        assert client.post(DOCUMENTS, selected).status_code == 403
        assert version.documents.count() == len(TAJWEED_COURSE_LANGUAGES)
