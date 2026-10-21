from __future__ import annotations

import copy
import json
import shutil
import struct
import subprocess
from pathlib import Path
from typing import Any
from unittest.mock import patch

import pytest
from django.contrib import admin
from django.core.files.uploadedfile import SimpleUploadedFile

from quran_backend.modules.accounts.models import User
from quran_backend.modules.core.object_storage import ImmutableObjectSpec, StoredObject
from quran_backend.modules.salah.admin import SalahCourseVersionAdmin
from quran_backend.modules.salah.compiler import compile_document
from quran_backend.modules.salah.importer import (
    MAX_AUDIO_BYTES,
    MAX_IMAGE_BYTES,
    import_salah_snapshot,
    publish_salah_version,
    webp_size,
)
from quran_backend.modules.salah.media_upload import SalahMediaUploadError, upload_salah_image
from quran_backend.modules.salah.models import (
    SalahCompiledDocument,
    SalahCourseVersion,
    SalahPublicationStatus,
)
from quran_backend.modules.salah.resolvers import FormulaResolver, clean_note
from quran_backend.modules.salah.snapshot import (
    SCENE_POSES,
    SalahSnapshotError,
    expand_lesson_steps,
    load_snapshot,
    validate_snapshot,
)

DOCS = Path(__file__).resolve().parents[3] / "docs" / "salah"
COURSE_SNAPSHOT = (
    Path(__file__).resolve().parents[1]
    / "src/quran_backend/modules/salah/data/hanbali-umdah-v1.json"
)
LANGUAGES = ("ru", "en", "ar", "tr")
FFMPEG = shutil.which("ffmpeg") or "ffmpeg"
needs_ffmpeg = pytest.mark.skipif(shutil.which("ffmpeg") is None, reason="ffmpeg is not installed")


def _all(text: str) -> dict[str, str]:
    return {language: f"{text} [{language}]" for language in LANGUAGES}


def _example_snapshot() -> dict[str, Any]:
    return json.loads((DOCS / "course-snapshot.example.json").read_text(encoding="utf-8"))


def _step(slug: str, **extra: Any) -> dict[str, Any]:
    return {
        "slug": slug,
        "kind": "recitation",
        "title": _all(slug),
        "instruction": _all(f"do {slug}"),
        "formulas": [],
        **extra,
    }


PRAYER_TEMPLATE = {
    "id": "fard-prayer",
    "steps": [
        _step("takbir", when={"first_rakat": True}),
        _step("fatiha-aloud", when={"recitation": "jahr"}),
        _step("fatiha-silent", when={"recitation": "sirr"}),
        _step("surah", when={"surah_after_fatiha": True}),
        _step("ruku"),
        _step("qunut", when={"qunut": True}),
        _step("sujud"),
        _step("tashahhud", when={"sitting": ["middle_tashahhud", "final_tashahhud"]}),
        _step("stand-up", when={"sitting": "middle_tashahhud"}),
        _step("salawat", when={"sitting": "final_tashahhud"}),
        _step("taslim", when={"last_rakat": True}),
    ],
}


def _rule(
    rakat: int, recitation: str, surah: bool, sitting: str, qunut: bool = False
) -> dict[str, Any]:
    return {
        "rakat": rakat,
        "recitation": recitation,
        "surah_after_fatiha": surah,
        "sitting": sitting,
        "qunut": qunut,
    }


def _prayer(slug: str, kind: str, rules: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "slug": slug,
        "kind": "prayer",
        "title": _all(slug),
        "summary": _all(slug),
        "minutes": 5,
        "prayer": {"code": slug, "kind": kind, "template": "fard-prayer", "rakat_rules": rules},
    }


def _unrolled(lesson: dict[str, Any]) -> list[str]:
    return [step["slug"] for step in expand_lesson_steps(lesson, {"fard-prayer": PRAYER_TEMPLATE})]


def test_example_snapshot_validates_and_unrolls_fajr() -> None:
    snapshot = _example_snapshot()
    validate_snapshot(snapshot)

    fajr = snapshot["lessons"][0]
    templates = {template["id"]: template for template in snapshot["templates"]}
    assert [step["slug"] for step in expand_lesson_steps(fajr, templates)] == [
        "fajr.r1.takbir",
        "fajr.r1.ruku",
        "fajr.r2.ruku",
        "fajr.r2.tashahhud",
    ]


def test_course_snapshot_marks_the_prayer_intention_as_a_condition() -> None:
    snapshot = load_snapshot(COURSE_SNAPSHOT)
    validate_snapshot(snapshot)

    assert {template["steps"][0]["slug"] for template in snapshot["templates"]} == {"intention"}
    assert {template["steps"][0]["ruling"] for template in snapshot["templates"]} == {"shart"}


def test_course_snapshot_ships_the_recordings_its_formulas_point_to() -> None:
    snapshot = load_snapshot(COURSE_SNAPSHOT)
    media = {asset["key"]: asset for asset in snapshot["media"]}
    recorded = {
        formula["id"]: formula["source"]["audio_media"]
        for formula in snapshot["formulas"]
        if formula["source"].get("audio_media")
    }

    assert recorded == {"takbir": "audio-takbir", "taawwudh": "audio-taawwudh"}
    for key in recorded.values():
        recording = COURSE_SNAPSHOT.parent / media[key]["file"]
        assert 0 < recording.stat().st_size <= MAX_AUDIO_BYTES


def test_course_illustrations_in_git_are_square_webp_within_the_limit() -> None:
    snapshot = load_snapshot(COURSE_SNAPSHOT)
    shipped = [
        COURSE_SNAPSHOT.parent / asset["file"]
        for asset in snapshot["media"]
        if asset["file"].endswith(".webp") and (COURSE_SNAPSHOT.parent / asset["file"]).exists()
    ]

    assert len(shipped) >= 17
    for image in shipped:
        data = image.read_bytes()
        assert webp_size(data) == (720, 720), image.name
        assert len(data) <= MAX_IMAGE_BYTES, image.name


def test_course_pose_illustrations_are_stills_of_the_3d_scene() -> None:
    # Rendered by services/web/scripts/salah3d-frames.ts (docs/salah/salah-3d.md).
    snapshot = load_snapshot(COURSE_SNAPSHOT)
    scenes = {asset["key"]: asset["scene"] for asset in snapshot["media"] if "scene" in asset}

    assert {key: scene["pose"] for key, scene in scenes.items()} == {
        "position-takbir": "takbir", "position-qiyam": "qiyam", "position-ruku": "ruku",
        "position-itidal": "itidal", "position-sujud": "sujud", "position-jalsa": "jalsa",
        "position-tashahhud": "tashahhud", "position-taslim": "salam",
    }  # fmt: skip
    assert {scene["view"] for scene in scenes.values()} == {"full"}
    assert {scene["pose"] for scene in scenes.values()} <= SCENE_POSES
    for key in scenes:
        still = (COURSE_SNAPSHOT.parent / f"media/{key}.webp").read_bytes()
        assert webp_size(still) == (720, 720), key
        assert len(still) <= 60 * 1024, key
    # The poses the scene has no figure for keep their drawings.
    pictures = {asset["key"] for asset in snapshot["media"] if asset["file"].endswith(".webp")}
    assert {key for key in pictures - set(scenes) if key.startswith("position-")} == {
        "position-qunut",
        "position-tawarruk",
    }


def test_a_scene_names_a_pose_and_a_view_of_the_scene() -> None:
    broken = _example_snapshot()
    media = {asset["key"]: asset for asset in broken["media"]}
    media["position-takbir"]["scene"] = {"pose": "flying", "view": "full"}
    media["position-ruku"]["scene"] = {"pose": "ruku", "view": "aerial"}
    media["position-tashahhud"]["scene"] = {"pose": "tashahhud"}
    media["audio-takbir"]["scene"] = {"pose": "takbir", "view": "full"}

    with pytest.raises(SalahSnapshotError) as error:
        validate_snapshot(broken)

    problems = "\n".join(error.value.problems)
    assert "Медиа «position-takbir».scene: в сцене нет позы «flying»" in problems
    assert "Медиа «position-ruku».scene: в сцене нет вида «aerial»" in problems
    assert "Медиа «position-tashahhud».scene: ожидается {pose, view}" in problems
    assert "Медиа «audio-takbir».scene: сцену задают только картинке" in problems


def test_prayer_kinds_come_from_the_course_and_compile_with_their_title() -> None:
    snapshot = _example_snapshot()
    unknown = copy.deepcopy(snapshot)
    unknown["lessons"][0]["prayer"]["kind"] = "eid"
    with pytest.raises(SalahSnapshotError) as error:
        validate_snapshot(unknown)
    assert "неизвестный вид молитвы «eid»" in "\n".join(error.value.problems)

    unknown["prayer_kinds"].append(
        {"code": "eid", "title": {"ru": "Праздничный", "en": "Eid", "ar": "عيد", "tr": "Bayram"}}
    )
    validate_snapshot(unknown)
    document = compile_document(
        unknown,
        language="tr",
        course_meta={"slug": "hanbali-umdah", "version": "v", "methodology": "hanbali"},
        formulas=_fake_formulas(unknown),
        media=_fake_media(unknown),
    )
    assert document["lessons"][0]["prayer"]["kind_title"] == "Bayram"


def test_funeral_prayer_unrolls_once_without_a_rakat_counter() -> None:
    snapshot = load_snapshot(COURSE_SNAPSHOT)
    templates = {template["id"]: template for template in snapshot["templates"]}
    janazah = next(lesson for lesson in snapshot["lessons"] if lesson["slug"] == "janazah-prayer")

    steps = expand_lesson_steps(janazah, templates)

    assert [step["slug"] for step in steps] == [
        "janazah-prayer.intention",
        "janazah-prayer.takbir-1",
        "janazah-prayer.fatiha",
        "janazah-prayer.takbir-2",
        "janazah-prayer.takbir-3",
        "janazah-prayer.takbir-4",
        "janazah-prayer.taslim",
    ]
    assert all("rakat" not in step for step in steps)
    two_rules = copy.deepcopy(janazah)
    two_rules["prayer"]["rakat_rules"].append({"rakat": 2, "recitation": "sirr", "sitting": "none"})
    broken = {**snapshot, "lessons": [*snapshot["lessons"], {**two_rules, "slug": "janazah-twice"}]}
    broken["sections"] = [
        *snapshot["sections"],
        {**snapshot["sections"][0], "lessons": ["janazah-twice"]},
    ]
    with pytest.raises(SalahSnapshotError) as error:
        validate_snapshot(broken)
    assert "в молитве без ракаатов нужно ровно одно правило" in "\n".join(error.value.problems)


def test_eid_prayer_has_six_and_five_extra_takbirs() -> None:
    snapshot = load_snapshot(COURSE_SNAPSHOT)
    templates = {template["id"]: template for template in snapshot["templates"]}
    eid = next(lesson for lesson in snapshot["lessons"] if lesson["slug"] == "eid-prayer")

    extra = {
        step["slug"]: step["repeat"]
        for step in expand_lesson_steps(eid, templates)
        if step["slug"].endswith("extra-takbirs")
    }

    assert extra == {"eid-prayer.r1.extra-takbirs": 6, "eid-prayer.r2.extra-takbirs": 5}


def test_four_rakat_prayer_unrolls_with_a_middle_tashahhud() -> None:
    dhuhr = _prayer(
        "dhuhr",
        "fard",
        [
            _rule(1, "sirr", True, "none"),
            _rule(2, "sirr", True, "middle_tashahhud"),
            _rule(3, "sirr", False, "none"),
            _rule(4, "sirr", False, "final_tashahhud"),
        ],
    )

    assert _unrolled(dhuhr) == [
        "dhuhr.r1.takbir", "dhuhr.r1.fatiha-silent", "dhuhr.r1.surah",
        "dhuhr.r1.ruku", "dhuhr.r1.sujud",
        "dhuhr.r2.fatiha-silent", "dhuhr.r2.surah", "dhuhr.r2.ruku", "dhuhr.r2.sujud",
        "dhuhr.r2.tashahhud", "dhuhr.r2.stand-up",
        "dhuhr.r3.fatiha-silent", "dhuhr.r3.ruku", "dhuhr.r3.sujud",
        "dhuhr.r4.fatiha-silent", "dhuhr.r4.ruku", "dhuhr.r4.sujud",
        "dhuhr.r4.tashahhud", "dhuhr.r4.salawat", "dhuhr.r4.taslim",
    ]  # fmt: skip


def test_witr_of_one_rakat_has_qunut_after_ruku() -> None:
    witr = _prayer("witr", "witr", [_rule(1, "jahr", True, "final_tashahhud", qunut=True)])

    assert _unrolled(witr) == [
        "witr.r1.takbir", "witr.r1.fatiha-aloud", "witr.r1.surah", "witr.r1.ruku", "witr.r1.qunut",
        "witr.r1.sujud", "witr.r1.tashahhud", "witr.r1.salawat", "witr.r1.taslim",
    ]  # fmt: skip


def test_validation_lists_every_problem_at_once() -> None:
    snapshot = _example_snapshot()
    broken = copy.deepcopy(snapshot)
    del broken["lessons"][0]["title"]["tr"]
    broken["templates"][0]["steps"][1]["formulas"] = ["missing-formula"]
    broken["templates"][0]["steps"][1]["media"] = "missing-media"
    broken["sections"][0]["lessons"].append("nowhere")

    with pytest.raises(SalahSnapshotError) as error:
        validate_snapshot(broken)

    problems = "\n".join(error.value.problems)
    assert "Урок «fajr».title: нет текста на «tr»" in problems
    assert "нет формулы «missing-formula»" in problems
    assert "нет медиа «missing-media»" in problems
    assert "нет урока «nowhere»" in problems


def _keys(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: _keys(item) for key, item in value.items()}
    if isinstance(value, list) and value and isinstance(value[0], dict):
        merged: dict[str, Any] = {}
        for item in value:
            merged.update(_keys(item))
        return [merged]
    return None


def _fake_formulas(snapshot: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {
        formula["id"]: {
            "arabic": "ٱللَّهُ",
            "translation": "…",
            "repetitions": 1,
            "audio": {"url": "https://media.iqro.forum/a.m4a"},
            "source": {"kind": formula["source"]["kind"]},
        }
        for formula in snapshot["formulas"]
    }


def _fake_media(snapshot: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {
        asset["key"]: {
            "url": f"https://media.iqro.forum/salah/{asset['key']}.webp",
            "width": 720,
            "height": 720,
            "bytes": 1,
            "sha256": "0" * 64,
            "alt": "…",
        }
        for asset in snapshot["media"]
    }


def test_compiled_document_follows_the_published_contract() -> None:
    snapshot = _example_snapshot()
    document = compile_document(
        snapshot,
        language="ru",
        course_meta={"slug": "hanbali-umdah", "version": "v", "methodology": "hanbali"},
        formulas=_fake_formulas(snapshot),
        media=_fake_media(snapshot),
    )
    contract = json.loads((DOCS / "course-document.example.json").read_text(encoding="utf-8"))

    assert set(document) == set(contract)
    assert set(document["sections"][0]) == set(contract["sections"][0])
    lesson_keys = set(_keys(contract["lessons"])[0])
    assert set(document["lessons"][0]) <= lesson_keys
    step_keys = set(_keys(contract["lessons"])[0]["steps"][0])
    for step in document["lessons"][0]["steps"]:
        assert set(step) <= step_keys
        assert isinstance(step["title"], str)
    contract_fajr = next(lesson for lesson in contract["lessons"] if lesson["slug"] == "fajr")
    assert document["lessons"][0]["prayer"] == contract_fajr["prayer"]
    assert document["lessons"][0]["steps"][0]["rakat"] == 1
    assert set(document["formulas"]) == {"takbir", "ruku-tasbih", "tashahhud"}


def test_webp_size_reads_the_extended_header() -> None:
    vp8x = b"RIFF" + struct.pack("<I", 22) + b"WEBPVP8X" + struct.pack("<I", 10) + b"\0" * 4
    vp8x += (719).to_bytes(3, "little") + (539).to_bytes(3, "little")
    assert webp_size(vp8x) == (720, 540)
    assert webp_size(b"not a webp file at all, really") is None


class FakeUploader:
    def __init__(self) -> None:
        self.calls: list[ImmutableObjectSpec] = []

    def upload_path(self, _source_path: Path, spec: ImmutableObjectSpec) -> StoredObject:
        self.calls.append(spec)
        return StoredObject(key=spec.key, etag='"e"', created=True)


class FakeResolver:
    def __init__(self, formulas: list[dict[str, Any]], _media: dict[str, Any]) -> None:
        self.formulas = formulas

    def resolve(self, language: str) -> dict[str, dict[str, Any]]:
        return {
            formula["id"]: {
                "arabic": "ٱللَّهُ",
                "translation": f"[{language}]",
                "repetitions": 1,
                "source": {"kind": formula["source"]["kind"]},
            }
            for formula in self.formulas
        }


def _write_media(directory: Path, snapshot: dict[str, Any]) -> None:
    webp = b"RIFF" + struct.pack("<I", 22) + b"WEBPVP8X" + struct.pack("<I", 10) + b"\0" * 4
    webp += (719).to_bytes(3, "little") + (719).to_bytes(3, "little")
    for asset in snapshot["media"]:
        path = directory / asset["file"]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(webp if path.suffix == ".webp" else b"audio")


@pytest.fixture
def imported(tmp_path: Path) -> tuple[SalahCourseVersion, FakeUploader]:
    snapshot = _example_snapshot()
    _write_media(tmp_path, snapshot)
    uploader = FakeUploader()
    with patch("quran_backend.modules.salah.importer.FormulaResolver", FakeResolver):
        version = import_salah_snapshot(snapshot, data_dir=tmp_path, uploader=uploader)
    return version, uploader


@pytest.mark.django_db
def test_import_creates_a_draft_with_documents_and_immutable_media(
    imported: tuple[SalahCourseVersion, FakeUploader], tmp_path: Path
) -> None:
    version, uploader = imported

    assert version.status == SalahPublicationStatus.DRAFT
    assert sorted(version.documents.values_list("language", flat=True)) == ["ar", "en", "ru", "tr"]
    assert {spec.key.split("/")[-1].rsplit("-", 1)[0] for spec in uploader.calls} == {
        "position-takbir", "position-ruku", "position-tashahhud", "audio-takbir", "audio-ruku-ru",
    }  # fmt: skip
    ruku = version.media.get(key="position-ruku")
    assert (ruku.width, ruku.height) == (720, 720)
    assert ruku.object_key.startswith("salah/hanbali-umdah/2026-10-18/position-ruku-")
    # A still of the 3D scene says which pose it shows.
    media = version.documents.get(language="ar").payload["media"]
    assert {key: entry["scene"] for key, entry in media.items()} == {
        "position-takbir": {"pose": "takbir", "view": "full"},
        "position-ruku": {"pose": "ruku", "view": "full"},
        "position-tashahhud": {"pose": "tashahhud", "view": "full"},
    }

    # The same content again is a no-op; changed content must be a new version.
    snapshot = _example_snapshot()
    with patch("quran_backend.modules.salah.importer.FormulaResolver", FakeResolver):
        assert import_salah_snapshot(snapshot, data_dir=tmp_path, uploader=uploader) == version
        snapshot["lessons"][0]["minutes"] = 7
        with pytest.raises(SalahSnapshotError, match=r"Поднимите course\.version"):
            import_salah_snapshot(snapshot, data_dir=tmp_path, uploader=uploader)


@pytest.mark.django_db
def test_publication_needs_a_sign_off_and_then_serves_the_document(
    imported: tuple[SalahCourseVersion, FakeUploader], api_client: Any
) -> None:
    version, _ = imported
    assert api_client.get("/api/v1/salah/courses/hanbali-umdah?language=ru").status_code == 404

    with pytest.raises(SalahSnapshotError, match="подписать"):
        publish_salah_version(version)

    owner = User.objects.create_user(email="owner@example.test", password="x" * 16, status="active")
    with (
        patch("quran_backend.modules.salah.importer.FormulaResolver", FakeResolver),
        patch("quran_backend.modules.salah.importer.enqueue_salah_content_change") as revalidate,
    ):
        version.sign(owner)
        publish_salah_version(version)
    revalidate.assert_called_once_with(
        action="activated", course="hanbali-umdah", version="2026-10-18"
    )

    response = api_client.get("/api/v1/salah/courses/hanbali-umdah?language=tr")
    assert response.status_code == 200
    payload = response.json()
    assert payload["course"]["language"] == "tr"
    assert payload["course"]["reviewed_by"] == "IQRO"
    assert payload["course"]["published_at"]
    assert payload["lessons"][0]["title"] == "Sabah"
    assert payload["formulas"]["takbir"]["translation"] == "[tr]"
    assert payload["media"]["position-ruku"]["width"] == 720
    etag = response["ETag"]
    assert (
        api_client.get(
            "/api/v1/salah/courses/hanbali-umdah?language=tr", HTTP_IF_NONE_MATCH=etag
        ).status_code
        == 304
    )
    assert api_client.get("/api/v1/salah/courses/hanbali-umdah?language=de").status_code == 400

    courses = api_client.get("/api/v1/salah/courses").json()
    assert [course["slug"] for course in courses] == ["hanbali-umdah"]
    manifest = api_client.get(
        "/api/v1/salah/courses/hanbali-umdah/offline-manifest?language=ru"
    ).json()
    assert manifest["package_type"] == "salah_course"
    assert {item["key"] for item in manifest["items"]} == {
        "position-takbir", "position-ruku", "position-tashahhud",
    }  # fmt: skip
    assert manifest["total_bytes"] == sum(item["asset"]["bytes"] for item in manifest["items"])


@pytest.mark.django_db
def test_published_versions_are_read_only_in_the_admin(
    imported: tuple[SalahCourseVersion, FakeUploader],
) -> None:
    version, _ = imported
    model_admin = admin.site._registry[SalahCourseVersion]
    assert isinstance(model_admin, SalahCourseVersionAdmin)
    assert not model_admin.has_add_permission(None)  # type: ignore[arg-type]
    assert not model_admin.has_change_permission(None, version)  # type: ignore[arg-type]
    assert model_admin.has_delete_permission(None, version)  # type: ignore[arg-type]
    version.status = SalahPublicationStatus.WITHDRAWN
    assert not model_admin.has_delete_permission(None, version)  # type: ignore[arg-type]
    assert "Начальный такбир" in model_admin.review_preview(version)
    assert SalahCompiledDocument.objects.filter(version=version).count() == 4


@pytest.mark.django_db
def test_import_without_media_files_leaves_illustrations_for_the_admin(tmp_path: Path) -> None:
    uploader = FakeUploader()
    with patch("quran_backend.modules.salah.importer.FormulaResolver", FakeResolver):
        version = import_salah_snapshot(_example_snapshot(), data_dir=tmp_path, uploader=uploader)

    assert uploader.calls == []
    assert not version.media.exists()
    assert version.documents.get(language="ru").payload["media"] == {}


def _source_image(tmp_path: Path) -> SimpleUploadedFile:
    source = tmp_path / "source.png"
    subprocess.run(  # noqa: S603 - test fixture, fixed arguments
        [
            FFMPEG, "-nostdin", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "color=c=gray:s=1000x800", "-frames:v", "1", str(source),
        ],
        check=True,
    )  # fmt: skip
    return SimpleUploadedFile("qiyam.png", source.read_bytes(), content_type="image/png")


@needs_ffmpeg
@pytest.mark.django_db
def test_admin_upload_converts_to_a_square_webp_and_recompiles(
    imported: tuple[SalahCourseVersion, FakeUploader], tmp_path: Path
) -> None:
    version, uploader = imported
    old = version.media.get(key="position-ruku")

    with patch("quran_backend.modules.salah.importer.FormulaResolver", FakeResolver):
        asset = upload_salah_image(
            version, "position-ruku", _source_image(tmp_path), uploader=uploader
        )

    assert asset.pk == old.pk
    assert (asset.width, asset.height) == (720, 720)
    assert asset.content_type == "image/webp"
    assert asset.bytes <= 60 * 1024
    assert asset.object_key != old.object_key
    payload = version.documents.get(language="ru").payload
    assert payload["media"]["position-ruku"]["sha256"] == asset.sha256

    with pytest.raises(SalahMediaUploadError, match="нет в снимке"):
        upload_salah_image(version, "audio-takbir", _source_image(tmp_path), uploader=uploader)
    version.status = SalahPublicationStatus.PUBLISHED
    with pytest.raises(SalahMediaUploadError, match="только в черновике"):
        upload_salah_image(version, "position-ruku", _source_image(tmp_path), uploader=uploader)


@needs_ffmpeg
@pytest.mark.django_db
def test_admin_media_page_lists_and_uploads_illustrations(
    imported: tuple[SalahCourseVersion, FakeUploader], tmp_path: Path, admin_client: Any
) -> None:
    version, uploader = imported
    url = f"/admin/salah/salahcourseversion/{version.pk}/media/"

    page = admin_client.get(url)
    assert page.status_code == 200
    content = page.content.decode()
    assert "position-tashahhud" in content
    assert "audio-takbir" not in content

    with (
        patch(
            "quran_backend.modules.salah.media_upload.player_background_uploader",
            return_value=uploader,
        ),
        patch("quran_backend.modules.salah.importer.FormulaResolver", FakeResolver),
    ):
        response = admin_client.post(
            url, {"key": "position-takbir", "file": _source_image(tmp_path)}
        )
    assert response.status_code == 302
    assert version.media.get(key="position-takbir").width == 720


@pytest.mark.django_db
def test_formulas_resolve_from_the_published_hisn_al_muslim() -> None:
    resolver = FormulaResolver(
        [
            {
                "id": "ruku",
                "source": {"kind": "dua", "collection": "hisn-al-muslim", "source_number": 33},
            },
            {
                "id": "takbir",
                "source": {
                    "kind": "inline",
                    "arabic": "اللَّهُ أَكْبَرُ",
                    "translations": {
                        "ru": {"meaning": "Аллах велик", "transliteration": "Аллаху акбар"}
                    },
                },
            },
            {
                "id": "ruku-own",
                "source": {
                    "kind": "dua",
                    "collection": "hisn-al-muslim",
                    "source_number": 33,
                    "audio_media": "audio-own",
                    "audio_media_languages": {"en": "audio-own-en"},
                },
            },
        ],
        {
            "audio-own": {"url": "https://media.iqro.forum/salah/own.m4a"},
            "audio-own-en": {"url": "https://media.iqro.forum/salah/own-en.mp3"},
        },
    )

    ru = resolver.resolve("ru")
    # Hisn's ((…)) and «three times» notes are dropped; the counter shows the count.
    assert ru["ruku"]["arabic"].startswith("سُبْحانَ")
    assert "((" not in ru["ruku"]["arabic"]
    assert "مرَّاتٍ" not in ru["ruku"]["arabic"]
    assert ru["ruku"]["translation"] == "Слава моему Великому Господу!"
    assert ru["ruku"]["repetitions"] == 3
    assert ru["ruku"]["source"] == {
        "kind": "dua",
        "collection": "hisn-al-muslim",
        "source_number": 33,
    }
    assert ru["ruku"]["audio"]["url"].endswith("/33.mp3")
    assert ru["takbir"] == {
        "arabic": "اللَّهُ أَكْبَرُ",
        "translation": "Аллах велик",
        "transliteration": "Аллаху акбар",
        "repetitions": 1,
        "source": {"kind": "inline"},
    }
    # The course's own recording replaces Hisn's; a language may have its own voice.
    assert ru["ruku-own"]["audio"] == {"url": "https://media.iqro.forum/salah/own.m4a"}
    assert resolver.resolve("en")["ruku-own"]["audio"] == {
        "url": "https://media.iqro.forum/salah/own-en.mp3"
    }


@pytest.mark.parametrize(
    ("raw", "clean"),
    [
        ("Субхана Рабби-ль-'Азыми!\" - 3 раза", "Субхана Рабби-ль-'Азыми!"),
        (
            "How perfect my Lord is, The Supreme.’(three times)",  # noqa: RUF001
            "How perfect my Lord is, The Supreme",
        ),
        ("(Subhana rabbiyal-aAAla. (three times)))", "Subhana rabbiyal-aAAla"),
        ("Господь мой, прости меня!", "Господь мой, прости меня!"),
    ],
)
def test_count_notes_are_trimmed_from_formula_texts(raw: str, clean: str) -> None:
    assert clean_note(raw) == clean
