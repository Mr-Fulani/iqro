"""Step pictures of the prayer course: replaced in the editor or on the illustrations page."""

from __future__ import annotations

# Russian interface strings intentionally contain characters that resemble Latin glyphs.
# ruff: noqa: RUF001
import shutil
import subprocess
from pathlib import Path
from typing import Any
from unittest.mock import patch

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import Client

from quran_backend.modules.accounts.models import User
from quran_backend.modules.salah import editor
from quran_backend.modules.salah.importer import import_salah_snapshot
from quran_backend.modules.salah.media_upload import (
    SalahMediaUploadError,
    image_kind,
    upload_salah_image,
)
from quran_backend.modules.salah.models import SalahCourseVersion, SalahPublicationStatus
from quran_backend.modules.salah.snapshot import snapshot_checksum, validate_snapshot
from tests.test_salah import FakeResolver, FakeUploader, _example_snapshot, _write_media
from tests.test_salah_editor import (
    RESOLVER,
    RUKU,
    UPLOADER,
    _editor_url,
    _form,
    _post,
    _snapshot_with_variants,
)

FFMPEG = shutil.which("ffmpeg") or "ffmpeg"
needs_ffmpeg = pytest.mark.skipif(shutil.which("ffmpeg") is None, reason="ffmpeg is not installed")
needs_rsvg = pytest.mark.skipif(
    shutil.which("ffmpeg") is None or shutil.which("rsvg-convert") is None,
    reason="ffmpeg and rsvg-convert are not installed",
)
SVG = (
    b'<?xml version="1.0"?>\n<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300">'
    b'<rect width="400" height="300" fill="#0a7"/><circle cx="200" cy="150" r="90" fill="#fff"/>'
    b"</svg>"
)


def _import(tmp_path: Path, snapshot: dict[str, Any]) -> SalahCourseVersion:
    _write_media(tmp_path, snapshot)
    with patch(RESOLVER, FakeResolver):
        return import_salah_snapshot(snapshot, data_dir=tmp_path, uploader=FakeUploader())


@pytest.fixture
def draft(tmp_path: Path) -> SalahCourseVersion:
    return _import(tmp_path, _example_snapshot())


@pytest.fixture
def owner_client() -> Client:
    owner = User.objects.create_user(
        email="owner@example.test", status="active", is_staff=True, is_superuser=True
    )
    client = Client()
    client.force_login(owner)
    return client


def _png(tmp_path: Path, name: str = "pose.png", color: str = "teal") -> SimpleUploadedFile:
    path = tmp_path / name
    subprocess.run(  # noqa: S603 - test fixture, fixed arguments
        [
            FFMPEG, "-nostdin", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", f"color=c={color}:s=900x700", "-frames:v", "1", str(path),
        ],
        check=True,
    )  # fmt: skip
    return SimpleUploadedFile(name, path.read_bytes(), content_type="image/png")


def _props(version: SalahCourseVersion, node_id: str) -> dict[str, Any]:
    """The step's properties as the editor sends them unchanged."""
    data = editor.find_node(version.snapshot, node_id).data
    return {
        "prop-kind": data["kind"],
        "prop-ruling": data.get("ruling") or "",
        "prop-media": data.get("media") or "",
        "prop-formula": list(data.get("formulas", [])),
        "prop-repeat": data.get("repeat") or "",
    }


def _save_picture(
    client: Client, version: SalahCourseVersion, upload: SimpleUploadedFile, **extra: str
) -> Any:
    form = {**_form(version, RUKU), **_props(version, RUKU), "prop-image": upload, **extra}
    with patch(UPLOADER, return_value=FakeUploader()):
        return _post(client, version, RUKU, form)


def _scene(version: SalahCourseVersion, key: str) -> Any:
    return next(asset for asset in version.snapshot["media"] if asset["key"] == key).get("scene")


def test_the_file_itself_says_what_picture_it_is() -> None:
    assert image_kind(b"\x89PNG\r\n\x1a\n....") == "png"
    assert image_kind(b"\xff\xd8\xff\xe0....") == "jpeg"
    assert image_kind(b"RIFF\x10\x00\x00\x00WEBPVP8 ") == "webp"
    assert image_kind(SVG) == "svg"
    assert image_kind(b"\xef\xbb\xbf<svg xmlns='http://www.w3.org/2000/svg'/>") == "svg"
    assert image_kind(b"GIF89a....") is None
    assert image_kind(b"<html><body>not a picture</body></html>") is None
    assert image_kind(b"<?xml version='1.0'?><note/>") is None


@needs_ffmpeg
@pytest.mark.django_db
def test_the_step_page_shows_its_picture_and_where_else_it_is(
    draft: SalahCourseVersion, owner_client: Client
) -> None:
    page = owner_client.get(_editor_url(draft, RUKU))

    picture = page.context["properties"]["picture"]
    stored = draft.media.get(key="position-ruku")
    assert picture["url"].endswith(stored.object_key)
    assert picture["steps"] == 1
    assert picture["scene"] is True
    content = page.content.decode()
    assert 'name="prop-image"' in content
    assert "поверх играет 3D-анимация позы" in content
    assert "Оставить 3D-анимацию поверх новой картинки" in content
    assert "PNG, JPEG, WebP или SVG" in content


@needs_ffmpeg
@pytest.mark.django_db
def test_a_new_picture_replaces_the_pose_everywhere_and_stops_the_3d_scene(
    draft: SalahCourseVersion, owner_client: Client, tmp_path: Path
) -> None:
    old = draft.media.get(key="position-ruku")

    response = _save_picture(owner_client, draft, _png(tmp_path))

    assert response.status_code == 302
    draft.refresh_from_db()
    new = draft.media.get(key="position-ruku")
    assert (new.width, new.height, new.content_type) == (720, 720, "image/webp")
    assert new.bytes <= 60 * 1024
    assert new.object_key != old.object_key
    assert new.object_key.startswith("salah/hanbali-umdah/2026-10-18/position-ruku-")
    assert _scene(draft, "position-ruku") is None
    assert draft.checksum_sha256 == snapshot_checksum(draft.snapshot)
    for document in draft.documents.all():
        media = document.payload["media"]["position-ruku"]
        assert media["url"].endswith(new.object_key)
        assert media["sha256"] == new.sha256
        assert "scene" not in media
    # Other poses keep their scene.
    assert _scene(draft, "position-takbir") == {"pose": "takbir", "view": "full"}
    validate_snapshot(draft.snapshot)


@needs_ffmpeg
@pytest.mark.django_db
def test_the_3d_scene_can_stay_over_a_new_still(
    draft: SalahCourseVersion, owner_client: Client, tmp_path: Path
) -> None:
    response = _save_picture(owner_client, draft, _png(tmp_path), **{"prop-image-scene": "on"})

    assert response.status_code == 302
    draft.refresh_from_db()
    assert _scene(draft, "position-ruku") == {"pose": "ruku", "view": "full"}
    ru = draft.documents.get(language="ru").payload
    assert ru["media"]["position-ruku"]["scene"] == {"pose": "ruku", "view": "full"}


@needs_ffmpeg
@pytest.mark.django_db
def test_a_picture_of_one_step_alone_leaves_the_shared_one(
    owner_client: Client, tmp_path: Path
) -> None:
    version = _import(tmp_path, _snapshot_with_variants())
    shared = version.media.get(key="position-ruku")
    page = owner_client.get(_editor_url(version, RUKU))
    # Ruku' of rak'ah 1, of rak'ahs 2+ and of the second template.
    assert page.context["properties"]["picture"]["steps"] == 3

    response = _save_picture(
        owner_client,
        version,
        _png(tmp_path),
        **{"prop-image-scope": "step", "sync_variants": "on"},
    )

    assert response.status_code == 302
    version.refresh_from_db()
    fard, nafl = version.snapshot["templates"]
    own_key = fard["steps"][1]["media"]
    assert own_key.startswith("image-step-fajr-r1-ruku-")
    # The variant with the same words takes it; the one with other words keeps the shared one.
    assert fard["steps"][2]["media"] == own_key
    assert nafl["steps"][1]["media"] == "position-ruku"
    entry = next(asset for asset in version.snapshot["media"] if asset["key"] == own_key)
    assert entry["file"] == f"media/{own_key}.webp"
    assert entry["alt"] == next(
        asset["alt"] for asset in version.snapshot["media"] if asset["key"] == "position-ruku"
    )
    assert "scene" not in entry
    assert version.media.get(key="position-ruku").object_key == shared.object_key
    assert _scene(version, "position-ruku") == {"pose": "ruku", "view": "full"}
    ru = version.documents.get(language="ru").payload
    assert ru["media"][own_key]["width"] == 720
    assert ru["lessons"][0]["steps"][1]["media"] == own_key
    validate_snapshot(version.snapshot)


@needs_ffmpeg
@pytest.mark.django_db
def test_a_file_that_is_not_a_picture_is_refused_and_nothing_is_saved(
    draft: SalahCourseVersion, owner_client: Client, tmp_path: Path
) -> None:
    checksum = draft.checksum_sha256
    object_key = draft.media.get(key="position-ruku").object_key

    def refused(upload: SimpleUploadedFile) -> str:
        form = {
            **_form(draft, RUKU),
            **_props(draft, RUKU),
            "text-title-ru": "Не потеряется",
            "prop-image": upload,
        }
        with patch(UPLOADER, return_value=FakeUploader()):
            response = _post(owner_client, draft, RUKU, form)
        assert response.status_code == 400
        assert response.context["properties"]["errors"]["image"]
        content = response.content.decode()
        assert "Не потеряется" in content
        return content

    assert "Файл не похож на картинку. Загрузите PNG, JPEG, WebP или SVG." in refused(
        SimpleUploadedFile("pose.png", b"<html>not a picture</html>")
    )
    assert "Файл не похож на картинку." in refused(SimpleUploadedFile("pose.gif", b"GIF89a" * 9))
    assert "Выбранный файл пуст." in refused(SimpleUploadedFile("pose.png", b""))
    with patch("quran_backend.modules.salah.media_upload.MAX_SOURCE_MIB", 0.001):
        assert "Файл должен быть не больше" in refused(_png(tmp_path))
    assert "Файл не удалось обработать." in refused(
        SimpleUploadedFile("pose.png", b"\x89PNG\r\n\x1a\n" + b"broken" * 20)
    )
    draft.refresh_from_db()
    assert draft.checksum_sha256 == checksum
    assert draft.media.get(key="position-ruku").object_key == object_key


@needs_rsvg
@pytest.mark.django_db
def test_an_svg_is_drawn_and_stored_as_a_square_webp(
    draft: SalahCourseVersion, owner_client: Client
) -> None:
    response = _save_picture(
        owner_client, draft, SimpleUploadedFile("pose.svg", SVG, content_type="image/svg+xml")
    )

    assert response.status_code == 302
    draft.refresh_from_db()
    asset = draft.media.get(key="position-ruku")
    assert (asset.width, asset.height, asset.content_type) == (720, 720, "image/webp")
    assert asset.object_key.endswith(".webp")


@pytest.mark.django_db
def test_without_rsvg_an_svg_asks_for_a_png(draft: SalahCourseVersion) -> None:
    upload = SimpleUploadedFile("pose.svg", SVG, content_type="image/svg+xml")
    with (
        patch("quran_backend.modules.salah.media_upload.shutil.which", return_value=None),
        pytest.raises(SalahMediaUploadError, match="Сохраните картинку как PNG"),
    ):
        upload_salah_image(draft, "position-ruku", upload, uploader=FakeUploader())


@needs_ffmpeg
@pytest.mark.django_db
def test_the_illustrations_page_replaces_a_pose_and_can_keep_its_scene(
    draft: SalahCourseVersion, admin_client: Any, tmp_path: Path
) -> None:
    url = f"/admin/salah/salahcourseversion/{draft.pk}/media/"
    content = admin_client.get(url).content.decode()
    assert "оставить 3D-анимацию" in content
    assert "image/svg+xml" in content

    with (
        patch(
            "quran_backend.modules.salah.media_upload.player_background_uploader",
            return_value=FakeUploader(),
        ),
        patch(RESOLVER, FakeResolver),
    ):
        admin_client.post(url, {"key": "position-takbir", "file": _png(tmp_path, "a.png")})
        admin_client.post(
            url, {"key": "position-ruku", "file": _png(tmp_path, "b.png"), "keep_scene": "on"}
        )
    draft.refresh_from_db()
    assert _scene(draft, "position-takbir") is None
    assert _scene(draft, "position-ruku") == {"pose": "ruku", "view": "full"}
    assert draft.checksum_sha256 == snapshot_checksum(draft.snapshot)


@needs_ffmpeg
@pytest.mark.django_db
def test_a_replaced_picture_reaches_the_api_after_sign_off_and_publication(
    draft: SalahCourseVersion, owner_client: Client, api_client: Any, tmp_path: Path
) -> None:
    assert _save_picture(owner_client, draft, _png(tmp_path, color="orange")).status_code == 302
    draft.refresh_from_db()
    new = draft.media.get(key="position-ruku")

    review = f"/admin/salah/salahcourseversion/{draft.pk}/review/"
    with (
        patch(RESOLVER, FakeResolver),
        patch("quran_backend.modules.salah.importer.enqueue_salah_content_change") as revalidate,
    ):
        owner_client.post(review, {"action": "sign", "node": RUKU})
        owner_client.post(review, {"action": "publish"})
    draft.refresh_from_db()
    assert draft.status == SalahPublicationStatus.PUBLISHED
    revalidate.assert_called_once()

    for language in ("ru", "ar"):
        payload = api_client.get(f"/api/v1/salah/courses/hanbali-umdah?language={language}").json()
        media = payload["media"]["position-ruku"]
        assert media["url"].endswith(new.object_key)
        assert media["sha256"] == new.sha256
        assert "scene" not in media
    manifest = api_client.get(
        "/api/v1/salah/courses/hanbali-umdah/offline-manifest?language=ru"
    ).json()
    item = next(item for item in manifest["items"] if item["key"] == "position-ruku")
    assert item["asset"]["sha256"] == new.sha256
    assert item["asset"]["url"].endswith(new.object_key)
