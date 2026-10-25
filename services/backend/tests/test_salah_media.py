"""Media of the prayer-learning course's lessons (docs/salah/lesson-media.md)."""

from __future__ import annotations

import copy
from collections.abc import Iterator
from pathlib import Path
from typing import Any
from unittest.mock import patch

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import Client, override_settings
from django.urls import reverse

from quran_backend.modules.accounts.models import User
from quran_backend.modules.salah import editor
from quran_backend.modules.salah.importer import (
    copy_salah_version,
    import_salah_snapshot,
    mark_salah_watched,
    new_videos,
    publish_salah_version,
    sign_salah_version,
)
from quran_backend.modules.salah.models import SalahCompiledDocument, SalahCourseVersion
from quran_backend.modules.salah.snapshot import SalahSnapshotError, validate_snapshot
from tests.test_courses_video import KeepingUploader, media, storage  # noqa: F401 - fixtures
from tests.test_salah import FakeResolver, FakeUploader, _example_snapshot, _write_media
from tests.test_tajweed_media import SLIDES, picture, video

MEDIA = "https://media.iqro.forum"
# The example's one lesson is a prayer: its steps come from a template, the media are its own.
LESSON = "fajr"
RESOLVER = "quran_backend.modules.salah.importer.FormulaResolver"


def with_media(snapshot: dict[str, Any], blocks: list[dict[str, Any]]) -> dict[str, Any]:
    result = copy.deepcopy(snapshot)
    next(lesson for lesson in result["lessons"] if lesson["slug"] == LESSON)["media"] = blocks
    return result


def _lesson(version: SalahCourseVersion) -> dict[str, Any]:
    return next(item for item in version.snapshot["lessons"] if item["slug"] == LESSON)


def _shown(version: SalahCourseVersion, language: str) -> dict[str, Any]:
    payload = SalahCompiledDocument.objects.get(version=version, language=language).payload
    return next(item for item in payload["lessons"] if item["slug"] == LESSON)


def _import(tmp_path: Path, snapshot: dict[str, Any]) -> SalahCourseVersion:
    _write_media(tmp_path, snapshot)
    with patch(RESOLVER, FakeResolver):
        return import_salah_snapshot(snapshot, data_dir=tmp_path, uploader=FakeUploader())


@pytest.fixture
def draft(tmp_path: Path) -> SalahCourseVersion:
    return _import(tmp_path, _example_snapshot())


@pytest.fixture
def owner(db: None) -> User:
    return User.objects.create_user(
        email="salah-owner@example.test", status="active", is_staff=True, is_superuser=True
    )


def _publish(version: SalahCourseVersion, owner: User) -> SalahCourseVersion:
    with (
        patch(RESOLVER, FakeResolver),
        patch("quran_backend.modules.salah.importer.enqueue_salah_content_change"),
    ):
        for sha256 in new_videos(version):
            mark_salah_watched(version, sha256=sha256, watched=True)
        version.refresh_from_db()
        sign_salah_version(version, owner)
        publish_salah_version(version)
    version.refresh_from_db()
    return version


# Snapshot and documents ------------------------------------------------------


@pytest.mark.django_db
@override_settings(PUBLIC_AUDIO_BASE_URL=MEDIA)
def test_documents_show_the_lesson_media_on_each_language(tmp_path: Path) -> None:
    version = _import(
        tmp_path,
        with_media(
            _example_snapshot(), [{"id": "video", "type": "video", "video": video()}, SLIDES]
        ),
    )

    russian, arabic, english = _shown(version, "ru"), _shown(version, "ar"), _shown(version, "en")
    assert [block["type"] for block in russian["media"]] == ["video", "slides"]
    assert russian["media"][0]["video"]["url"] == f"{MEDIA}/courses/videos/{'a' * 20}.mp4"
    # The English document gets the English dub, the Arabic one its own picture.
    assert english["media"][0]["video"]["url"].endswith("-en-eeeeeeeeeeee.mp4")
    assert english["media"][0]["video"]["spoken_language"] == "en"
    assert arabic["media"][1]["slides"][0]["image"]["url"] == f"{MEDIA}/courses/slides/ar.webp"
    assert arabic["media"][1]["slides"][0]["dir"] == "rtl"
    # The steps and the course's own pictures stay as they were.
    payload = SalahCompiledDocument.objects.get(version=version, language="ru").payload
    assert "courses/" not in str(payload["media"])
    assert russian["steps"]


@pytest.mark.django_db
def test_a_lesson_without_media_has_no_key(draft: SalahCourseVersion) -> None:
    assert "media" not in _shown(draft, "ru")
    # A place for a video not yet uploaded shows nothing either.
    assert "media" not in _lesson(draft)


def test_snapshot_refuses_odd_media() -> None:
    snapshot = _example_snapshot()
    validate_snapshot(with_media(snapshot, [SLIDES, {"id": "video", "type": "video"}]))
    for blocks in (
        [{"id": "x", "type": "gallery"}],
        [{"id": "video", "type": "video"}, {"id": "video", "type": "video"}],
        [{"id": "x", "type": "slides"}],
        "slides",
    ):
        with pytest.raises(SalahSnapshotError, match="media"):
            validate_snapshot(with_media(snapshot, blocks))  # type: ignore[arg-type]


@pytest.mark.django_db
def test_a_new_draft_copies_the_media(draft: SalahCourseVersion) -> None:
    draft.snapshot = with_media(
        draft.snapshot, [{"id": "video", "type": "video", "video": video()}, SLIDES]
    )
    draft.save(update_fields=["snapshot"])
    with patch(RESOLVER, FakeResolver):
        copied = copy_salah_version(draft, "2026-11-01")
    assert _lesson(copied)["media"] == _lesson(draft)["media"]
    assert _shown(copied, "ru")["media"][1]["slides"][0]["caption"] == "Горловые буквы"


# Watched marks and sign-off ----------------------------------------------------------


@pytest.mark.django_db
def test_sign_off_needs_every_new_video_and_dub_watched(tmp_path: Path, owner: User) -> None:
    version = _import(
        tmp_path,
        with_media(_example_snapshot(), [{"id": "video", "type": "video", "video": video()}]),
    )
    assert new_videos(version) == {"a" * 64, "e" * 64}
    with pytest.raises(SalahSnapshotError, match="Просмотрено"):
        sign_salah_version(version, owner)
    mark_salah_watched(version, sha256="a" * 64, watched=True)
    with pytest.raises(SalahSnapshotError, match="нет среди новых"):
        mark_salah_watched(version, sha256="f" * 64, watched=True)
    version.refresh_from_db()
    with pytest.raises(SalahSnapshotError, match="Просмотрено"):
        sign_salah_version(version, owner)
    published = _publish(version, owner)
    assert published.status == "published"
    with pytest.raises(SalahSnapshotError, match="неподписанный"):
        mark_salah_watched(published, sha256="a" * 64, watched=False)

    # The next draft shows the same files: nothing new to watch, a new dub is.
    with patch(RESOLVER, FakeResolver):
        later = copy_salah_version(published, "2026-11-01")
    assert new_videos(later) == set()
    changed = video()
    changed["dubs"]["tr"] = {**changed["dubs"]["en"], "sha256": "d" * 64}
    later.snapshot = with_media(
        later.snapshot, [{"id": "video", "type": "video", "video": changed}]
    )
    later.save(update_fields=["snapshot"])
    assert new_videos(later) == {"d" * 64}


# Admin -------------------------------------------------------------------------


def _client(user: User) -> Client:
    client = Client()
    client.force_login(user)
    return client


def _url(name: str, version: SalahCourseVersion, *args: str) -> str:
    return reverse(f"admin:salah_salahcourseversion_{name}", args=[version.pk, *args])


def _editor(version: SalahCourseVersion, node: str = f"lesson:{LESSON}") -> str:
    return _url("editor", version) + f"?node={node}"


@pytest.fixture
def stored() -> Iterator[list[str]]:
    names: list[str] = []

    def fake(uploaded: Any, *, kind: str, prefix: str) -> dict[str, Any]:
        names.append(f"{prefix}/{kind}/{uploaded.name}")
        return picture(Path(uploaded.name).stem)

    with (
        patch("quran_backend.modules.courses.lesson_media_admin.store_media_image", fake),
        patch(RESOLVER, FakeResolver),
    ):
        yield names


def _file(name: str) -> SimpleUploadedFile:
    return SimpleUploadedFile(name, b"\x89PNG\r\n\x1a\n", content_type="image/png")


@pytest.mark.django_db
@override_settings(PUBLIC_AUDIO_BASE_URL=MEDIA)
def test_editor_adds_slides_and_a_banner_to_a_draft_lesson(
    draft: SalahCourseVersion, owner: User, stored: list[str]
) -> None:
    client = _client(owner)
    page = client.get(_editor(draft)).content.decode()
    assert "Медиа пока нет." in page
    assert "data-media-add" in page
    assert "lesson_media/admin/media.js" in page
    # A step has no media block: its own picture and recordings are enough.
    step = client.get(_editor(draft, "step:fajr.r1.ruku")).content.decode()
    assert "lesson_media/admin/media.js" not in step

    # The texts form and the tree, opened before the media changed, still save.
    form_revision = editor.node_revision(
        draft.snapshot, editor.find_node(draft.snapshot, f"lesson:{LESSON}")
    )
    tree_revision = editor.structure_revision(draft.snapshot)

    address = _url("lesson_media", draft, LESSON)
    added = client.post(
        address, {"action": "add", "kind": "slides", "file": [_file("one.png"), _file("two.png")]}
    )
    assert added.status_code == 200, added.content
    assert "Слайд 2" in added.json()["html"]
    banner = client.post(address, {"action": "add", "kind": "banner", "file": _file("wide.png")})
    assert banner.status_code == 200, banner.content
    assert stored == [
        "courses/slides/one.png",
        "courses/slides/two.png",
        "courses/banner/wide.png",
    ]
    draft.refresh_from_db()
    slides, wide = _lesson(draft)["media"]
    texts = client.post(
        address,
        {"action": "texts", "block": slides["id"], "slide": slides["slides"][0]["id"],
         "language": "ru", "caption": "Такбир", "alt": ""},
    )  # fmt: skip
    assert texts.json() == {"ok": True}
    shown = _shown(draft, "ru")["media"]
    assert [block["type"] for block in shown] == ["slides", "banner"]
    assert shown[0]["slides"][0]["caption"] == "Такбир"
    assert shown[1]["image"]["url"] == f"{MEDIA}/courses/slides/wide.webp"

    draft.refresh_from_db()
    node = editor.find_node(draft.snapshot, f"lesson:{LESSON}")
    assert editor.node_revision(draft.snapshot, node) == form_revision
    assert editor.structure_revision(draft.snapshot) == tree_revision

    # The lesson's texts saved from the form keep the media.
    form: dict[str, Any] = {"node_revision": form_revision}
    for field in node.fields:
        for language, text in (node.data.get(field.name) or {}).items():
            form[f"text-{field.name}-{language}"] = text
    form["text-title-ru"] = "Фаджр"
    saved = client.post(_editor(draft), form)
    assert saved.status_code == 302, saved.content.decode()[:500]
    draft.refresh_from_db()
    assert _lesson(draft)["title"]["ru"] == "Фаджр"
    assert _lesson(draft)["media"][0]["slides"][0]["caption"] == {"ru": "Такбир"}

    order = client.post(address, {"action": "order", "order": [wide["id"], slides["id"]]})
    assert order.status_code == 200
    removed = client.post(address, {"action": "remove", "block": slides["id"]})
    assert removed.status_code == 200
    draft.refresh_from_db()
    assert [block["type"] for block in _lesson(draft)["media"]] == ["banner"]


@pytest.mark.django_db
def test_signed_and_published_versions_keep_their_media(
    draft: SalahCourseVersion, owner: User, stored: list[str]
) -> None:
    published = _publish(draft, owner)
    client = _client(owner)
    answer = client.post(
        _url("lesson_media", published, LESSON),
        {"action": "add", "kind": "slides", "file": _file("a.png")},
    )
    assert answer.status_code == 403
    assert stored == []
    assert client.post(_url("lesson_media", published, "no-such-lesson")).status_code == 404
    page = client.get(_editor(published)).content.decode()
    assert "Медиа пока нет." in page
    assert "data-media-add" not in page


@pytest.mark.django_db
@override_settings(PUBLIC_AUDIO_BASE_URL=MEDIA)
def test_editor_uploads_a_video_and_a_dub_into_the_draft(
    media: dict[str, Path],  # noqa: F811 - the fixture of the video tests
    storage: KeepingUploader,  # noqa: F811
    draft: SalahCourseVersion,
    owner: User,
) -> None:
    client = _client(owner)
    with patch(RESOLVER, FakeResolver):
        with media["handbrake"].open("rb") as file:
            uploaded = client.post(
                _url("lesson_video", draft, LESSON, "upload"),
                {"file": file, "spoken_language": "ru"},
            )
        assert uploaded.status_code == 200, uploaded.content
        assert "Язык речи" in uploaded.json()["html"]
        draft.refresh_from_db()
        stored_video = _lesson(draft)["media"][0]["video"]
        assert stored_video["object_key"].startswith("courses/videos/")
        assert stored_video["original_name"] == "lecture.mp4"

        with media["dub_mp3"].open("rb") as file:
            dubbed = client.post(
                _url("lesson_dub", draft, LESSON, "en", "upload"),
                {"file": file, "video": stored_video["sha256"]},
            )
        assert dubbed.status_code == 200, dubbed.content
        stale = client.post(
            _url("lesson_video", draft, LESSON, "language"),
            {"video": "0" * 64, "spoken_language": "ar"},
        )
        assert stale.status_code == 409

    draft.refresh_from_db()
    assert set(_lesson(draft)["media"][0]["video"]["dubs"]) == {"en"}
    english = _shown(draft, "en")["media"][0]["video"]
    assert english["spoken_language"] == "en"
    assert _shown(draft, "ru")["media"][0]["video"]["spoken_language"] == "ru"

    # Both files wait for «Просмотрено» before the sign-off.
    new = new_videos(draft)
    assert len(new) == 2
    page = client.get(_editor(draft)).content.decode()
    assert "Новые видео и озвучки" in page
    first = sorted(new)[0]
    marked = client.post(_url("watched", draft, first), {"node": f"lesson:{LESSON}"})
    assert marked.status_code == 302
    assert marked["Location"].endswith(f"?node=lesson%3A{LESSON}#videos")
    draft.refresh_from_db()
    assert draft.watched_videos == [first]
    with patch(RESOLVER, FakeResolver):
        client.post(_url("review", draft), {"action": "sign"})
    draft.refresh_from_db()
    assert not draft.is_signed

    with patch(RESOLVER, FakeResolver):
        removed = client.post(
            _url("lesson_video", draft, LESSON, "remove"), {"video": stored_video["sha256"]}
        )
    assert removed.status_code == 200
    draft.refresh_from_db()
    assert new_videos(draft) == set()
    assert "media" not in _shown(draft, "ru")
