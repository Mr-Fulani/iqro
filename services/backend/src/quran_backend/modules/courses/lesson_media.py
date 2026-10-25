# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""Media of a lesson: a video, slides and banners above the notes, in the author's order.

docs/courses/README.md, «Медиа темы». The editor keeps the blocks as a JSON list:
on the lesson row in thematic courses, in the lesson of a course version in the
tajweed and the prayer-learning courses (snapshot_media.py). Nothing here knows
those models: the functions take the list and give back a new one, and the
module locks its row around them.

A video block only keeps the place of the lesson's video; the file and its dubs
stay the module's own. Slides and banners are WebP pictures in R2 under
immutable keys (ADR 0001), with a caption and an alt text per language and,
for a picture with text on it, an own picture per language.
"""

from __future__ import annotations

import copy
import hashlib
import shutil
import subprocess
import uuid
from collections.abc import Callable, Sequence
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any

from django.core.files.uploadedfile import UploadedFile

from quran_backend.modules.audio.player_background_upload import player_background_uploader
from quran_backend.modules.core.editorial.markup import direction
from quran_backend.modules.core.object_storage import ObjectUploader
from quran_backend.modules.core.webp import webp_size
from quran_backend.modules.courses.media import (
    FFMPEG_TIMEOUT_SECONDS,
    WEBP_QUALITIES,
    CourseCoverError,
    _is_image,
    _save_upload,
    _store,
)

VIDEO = "video"
SLIDES = "slides"
BANNER = "banner"
KINDS = (VIDEO, SLIDES, BANNER)
# The lesson has one video at most, so its block needs no id of its own.
VIDEO_BLOCK_ID = "video"
MAX_BLOCKS = 10
MAX_SLIDES = 30
MAX_TEXT_CHARS = 300
SLIDE_BOX = 1600
SLIDE_SMALL_BOX = 800
BANNER_SIZE = (1600, 900)
BANNER_SMALL_SIZE = (800, 450)
SLIDE_BYTES = 250 * 1024
SLIDE_SMALL_BYTES = 90 * 1024
BANNER_BYTES = 200 * 1024
BANNER_SMALL_BYTES = 70 * 1024
# A slide from 1:3 to 3:1: a narrower strip would be a line in the carousel.
MAX_RATIO = 3
IMAGE_ACCEPT = "image/jpeg,image/png,image/webp"
CONFLICT = "Медиа темы изменили в другой вкладке. Обновите страницу."


class LessonMediaError(ValueError):
    """A message for the author; `status` is the HTTP status of the admin's JSON answer."""

    def __init__(self, message: str, status: int = 400) -> None:
        super().__init__(message)
        self.status = status


# Pictures ----------------------------------------------------------------


def store_media_image(
    uploaded: UploadedFile,
    *,
    kind: str,
    prefix: str,
    uploader: ObjectUploader | None = None,
    ffmpeg: str | None = None,
) -> dict[str, Any]:
    """A slide keeps its proportions within 1600 and 800 px; a banner is cropped to 16:9."""
    program = ffmpeg or shutil.which("ffmpeg") or "ffmpeg"
    name = uploaded.name or "картинка"
    with TemporaryDirectory(prefix="iqro-lesson-media-") as directory:
        folder = Path(directory)
        source = folder / "source"
        try:
            _save_upload(uploaded, source)
        except CourseCoverError as exc:
            raise LessonMediaError(f"{name}: {exc}") from exc
        if not _is_image(source):
            raise LessonMediaError(f"{name}: нужна картинка JPEG, PNG или WebP.")
        if kind == BANNER:
            big = _encode(program, source, folder / "big.webp", _crop(BANNER_SIZE), BANNER_BYTES)
            small = _encode(
                program, source, folder / "small.webp", _crop(BANNER_SMALL_SIZE), BANNER_SMALL_BYTES
            )
        else:
            big = _encode(program, source, folder / "big.webp", _fit(SLIDE_BOX), SLIDE_BYTES)
            small = _encode(
                program, source, folder / "small.webp", _fit(SLIDE_SMALL_BOX), SLIDE_SMALL_BYTES
            )
        data = big.read_bytes()
        size = webp_size(data)
        if size is None or webp_size(small.read_bytes()) is None:
            raise LessonMediaError(f"{name}: картинку не удалось обработать.")
        width, height = size
        if kind != BANNER and not 1 / MAX_RATIO <= width / height <= MAX_RATIO:
            raise LessonMediaError(
                f"{name}: картинка {width}×{height} слишком вытянута, "
                "для слайда подходят пропорции от 1:3 до 3:1."
            )
        digest = hashlib.sha256(data).hexdigest()
        stem = f"{prefix}/{'banners' if kind == BANNER else 'slides'}/{digest[:20]}"
        actual_uploader = uploader or player_background_uploader()
        return {
            "object_key": _store(actual_uploader, big, f"{stem}.webp"),
            "small_object_key": _store(actual_uploader, small, f"{stem}-{SLIDE_SMALL_BOX}.webp"),
            "width": width,
            "height": height,
            "sha256": digest,
        }


def _fit(box: int) -> str:
    """Within the box, never enlarged: a small picture stays as sharp as it was."""
    return f"scale=w='min({box},iw)':h='min({box},ih)':force_original_aspect_ratio=decrease"


def _crop(size: tuple[int, int]) -> str:
    width, height = size
    return f"scale={width}:{height}:force_original_aspect_ratio=increase,crop={width}:{height}"


def _encode(ffmpeg: str, source: Path, target: Path, scale: str, limit: int) -> Path:
    """The lightest quality that still reads well: stops once under the limit."""
    for quality in WEBP_QUALITIES:
        try:
            subprocess.run(  # noqa: S603 - fixed program, no shell, paths we created
                [
                    ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                    "-i", str(source), "-vf", scale, "-frames:v", "1",
                    "-c:v", "libwebp", "-quality", str(quality), str(target),
                ],
                check=True,
                capture_output=True,
                timeout=FFMPEG_TIMEOUT_SECONDS,
            )  # fmt: skip
        except FileNotFoundError as exc:
            raise LessonMediaError(f"На сервере нет {ffmpeg}.", status=502) from exc
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
            raise LessonMediaError(
                "Картинку не удалось обработать. Загрузите JPEG, PNG или WebP."
            ) from exc
        if target.stat().st_size <= limit:
            break
    return target


# The editor's list ---------------------------------------------------------


def new_id() -> str:
    return uuid.uuid4().hex[:12]


def editor_blocks(media: Sequence[dict[str, Any]], *, has_video: bool) -> list[dict[str, Any]]:
    """A copy of the blocks; a video uploaded before there were blocks stands first."""
    blocks = [copy.deepcopy(block) for block in media if block.get("type") in KINDS]
    if has_video and not any(block["type"] == VIDEO for block in blocks):
        blocks.insert(0, {"id": VIDEO_BLOCK_ID, "type": VIDEO})
    return blocks


def add_block(
    media: Sequence[dict[str, Any]], kind: str, *, has_video: bool
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    blocks = editor_blocks(media, has_video=has_video)
    if kind not in KINDS:
        raise LessonMediaError("Неизвестный вид медиа.")
    if len(blocks) >= MAX_BLOCKS:
        raise LessonMediaError(f"В теме уже {MAX_BLOCKS} блоков медиа: больше не поместится.")
    if kind == VIDEO and any(block["type"] == VIDEO for block in blocks):
        raise LessonMediaError("В теме уже есть видео: у темы одно видео.")
    block: dict[str, Any] = {"id": VIDEO_BLOCK_ID if kind == VIDEO else new_id(), "type": kind}
    if kind != VIDEO:
        block["slides"] = []
    blocks.append(block)
    return blocks, block


def remove_block(
    media: Sequence[dict[str, Any]], block_id: str, *, has_video: bool
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    blocks = editor_blocks(media, has_video=has_video)
    block = find_block(blocks, block_id)
    return [item for item in blocks if item is not block], block


def move_blocks(
    media: Sequence[dict[str, Any]], order: Sequence[str], *, has_video: bool
) -> list[dict[str, Any]]:
    blocks = editor_blocks(media, has_video=has_video)
    return _reordered(blocks, order)


def add_images(
    media: Sequence[dict[str, Any]],
    block_id: str,
    images: Sequence[dict[str, Any]],
    *,
    has_video: bool,
) -> list[dict[str, Any]]:
    """New slides at the end; a banner gets its picture replaced, its texts stay."""
    blocks = editor_blocks(media, has_video=has_video)
    block = find_block(blocks, block_id)
    if block["type"] == VIDEO:
        raise LessonMediaError(CONFLICT, status=409)
    slides = block["slides"]
    if block["type"] == BANNER:
        if len(images) != 1:
            raise LessonMediaError("У баннера одна картинка.")
        if slides:
            slides[0]["image"] = dict(images[0])
        else:
            slides.append(_new_slide(images[0]))
        return blocks
    if len(slides) + len(images) > MAX_SLIDES:
        raise LessonMediaError(
            f"В блоке не больше {MAX_SLIDES} слайдов, сейчас {len(slides)}. "
            "Добавьте второй блок слайдов."
        )
    slides.extend(_new_slide(image) for image in images)
    return blocks


def remove_slide(
    media: Sequence[dict[str, Any]], block_id: str, slide_id: str, *, has_video: bool
) -> list[dict[str, Any]]:
    blocks = editor_blocks(media, has_video=has_video)
    block = find_block(blocks, block_id)
    slide = find_slide(block, slide_id)
    block["slides"] = [item for item in block["slides"] if item is not slide]
    return blocks


def move_slides(
    media: Sequence[dict[str, Any]], block_id: str, order: Sequence[str], *, has_video: bool
) -> list[dict[str, Any]]:
    blocks = editor_blocks(media, has_video=has_video)
    block = find_block(blocks, block_id)
    block["slides"] = _reordered(block["slides"], order)
    return blocks


def set_texts(  # noqa: PLR0913 - which slide, which language and both texts
    media: Sequence[dict[str, Any]],
    block_id: str,
    slide_id: str,
    language: str,
    *,
    caption: str,
    alt: str,
    has_video: bool,
) -> list[dict[str, Any]]:
    blocks = editor_blocks(media, has_video=has_video)
    slide = find_slide(find_block(blocks, block_id), slide_id)
    for field, raw, label in (("caption", caption, "Подпись"), ("alt", alt, "Описание")):
        value = raw.strip()
        if len(value) > MAX_TEXT_CHARS:
            raise LessonMediaError(f"{label} — не больше {MAX_TEXT_CHARS} знаков.")
        texts = slide.setdefault(field, {})
        if value:
            texts[language] = value
        else:
            texts.pop(language, None)
    return blocks


def set_language_image(  # noqa: PLR0913 - which slide, which language and the picture
    media: Sequence[dict[str, Any]],
    block_id: str,
    slide_id: str,
    language: str,
    image: dict[str, Any] | None,
    *,
    has_video: bool,
) -> list[dict[str, Any]]:
    """The picture of one language, for text on the picture; None goes back to the common one.

    The language "" is the common picture itself.
    """
    blocks = editor_blocks(media, has_video=has_video)
    slide = find_slide(find_block(blocks, block_id), slide_id)
    if not language:
        if image is None:
            raise LessonMediaError("Общая картинка нужна всегда: удалите слайд целиком.")
        slide["image"] = dict(image)
        return blocks
    images = slide.setdefault("images", {})
    if image is None:
        images.pop(language, None)
    else:
        images[language] = dict(image)
    return blocks


def find_block(blocks: Sequence[dict[str, Any]], block_id: str) -> dict[str, Any]:
    block = next((block for block in blocks if block["id"] == block_id), None)
    if block is None:
        raise LessonMediaError(CONFLICT, status=409)
    return block


def find_slide(block: dict[str, Any], slide_id: str) -> dict[str, Any]:
    slides: list[dict[str, Any]] = block.get("slides", [])
    slide = next((slide for slide in slides if slide["id"] == slide_id), None)
    if slide is None:
        raise LessonMediaError(CONFLICT, status=409)
    return slide


def _new_slide(image: dict[str, Any]) -> dict[str, Any]:
    return {"id": new_id(), "image": dict(image), "images": {}, "caption": {}, "alt": {}}


def _reordered(items: list[dict[str, Any]], order: Sequence[str]) -> list[dict[str, Any]]:
    by_id = {item["id"]: item for item in items}
    if sorted(order) != sorted(by_id):
        raise LessonMediaError(CONFLICT, status=409)
    return [by_id[item_id] for item_id in order]


# Snapshot, documents and changes -------------------------------------------


def media_snapshot(
    media: Sequence[dict[str, Any]], *, has_video: bool, languages: Sequence[str]
) -> list[dict[str, Any]]:
    """The blocks students see, every language: no empty block, no place of a missing video."""
    result: list[dict[str, Any]] = []
    for block in editor_blocks(media, has_video=has_video):
        if block["type"] == VIDEO:
            result.append({"id": VIDEO_BLOCK_ID, "type": VIDEO})
        elif block["slides"]:
            result.append(
                {
                    "id": block["id"],
                    "type": block["type"],
                    "slides": [_slide_snapshot(slide, languages) for slide in block["slides"]],
                }
            )
    return [block for block in result if block["type"] != VIDEO or has_video]


def default_media(*, has_video: bool) -> list[dict[str, Any]]:
    """What a lesson shows without blocks of its own, and what releases before media meant."""
    return [{"id": VIDEO_BLOCK_ID, "type": VIDEO}] if has_video else []


def _slide_snapshot(slide: dict[str, Any], languages: Sequence[str]) -> dict[str, Any]:
    return {
        "id": slide["id"],
        "image": _image(slide["image"]),
        "images": {
            language: _image(slide["images"][language])
            for language in languages
            if language in slide.get("images", {})
        },
        **{
            field: {language: slide.get(field, {}).get(language, "") for language in languages}
            for field in ("caption", "alt")
        },
    }


def _image(image: dict[str, Any]) -> dict[str, Any]:
    keys = ("object_key", "small_object_key", "width", "height", "sha256")
    return {key: image[key] for key in keys}


def media_payload(
    media: Sequence[dict[str, Any]],
    *,
    language: str,
    video: dict[str, Any] | None,
    public_url: Callable[[str], str],
) -> list[dict[str, Any]]:
    """The blocks of one language: its own picture where there is one, its caption and alt."""
    result: list[dict[str, Any]] = []
    for block in media:
        if block["type"] == VIDEO:
            if video is not None:
                result.append({"type": VIDEO, "video": video})
        elif block["type"] == SLIDES:
            result.append(
                {
                    "type": SLIDES,
                    "slides": [
                        _slide_payload(slide, language, public_url) for slide in block["slides"]
                    ],
                }
            )
        elif block["type"] == BANNER:
            result.append(
                {"type": BANNER, **_slide_payload(block["slides"][0], language, public_url)}
            )
    return result


def _slide_payload(
    slide: dict[str, Any], language: str, public_url: Callable[[str], str]
) -> dict[str, Any]:
    image = slide["images"].get(language) or slide["image"]
    caption = slide["caption"][language].strip()
    alt = slide["alt"][language].strip() or caption
    return {
        "image": {
            "url": public_url(image["object_key"]),
            "small_url": public_url(image["small_object_key"]),
            "width": image["width"],
            "height": image["height"],
        },
        "caption": caption,
        "alt": alt,
        "dir": direction([caption or alt]),
    }


def media_changes(
    old: Sequence[dict[str, Any]], new: Sequence[dict[str, Any]], languages: Sequence[str]
) -> list[str]:
    """«добавлены слайды (3)», «слайды: изменены подписи (ru, en)», «изменён порядок медиа»."""
    before = {block["id"]: block for block in old}
    found: list[str] = []
    for block in new:
        previous = before.get(block["id"])
        if block["type"] == VIDEO:
            continue  # the video's own changes name it
        if previous is None:
            count = len(block["slides"])
            found.append(
                f"добавлены слайды ({count})" if block["type"] == SLIDES else "добавлен баннер"
            )
        elif previous != block:
            details = _slide_changes(previous["slides"], block["slides"], languages)
            label = "слайды" if block["type"] == SLIDES else "баннер"
            found.append(f"{label}: {', '.join(details)}")
    new_ids = {block["id"] for block in new}
    found.extend(
        "удалены слайды" if block["type"] == SLIDES else "удалён баннер"
        for block in old
        if block["id"] not in new_ids and block["type"] != VIDEO
    )
    kept = [block["id"] for block in old if block["id"] in new_ids]
    if kept != [block["id"] for block in new if block["id"] in before]:
        found.append("изменён порядок медиа")
    return found


def _slide_changes(
    old: list[dict[str, Any]], new: list[dict[str, Any]], languages: Sequence[str]
) -> list[str]:
    before = {slide["id"]: slide for slide in old}
    new_ids = {slide["id"] for slide in new}
    kept = [slide for slide in new if slide["id"] in before]
    details = []
    added = len(new) - len(kept)
    removed = sum(1 for slide in old if slide["id"] not in new_ids)
    if added:
        details.append(f"добавлено слайдов: {added}")
    if removed:
        details.append(f"удалено слайдов: {removed}")
    if any(
        (slide["image"], slide["images"])
        != (before[slide["id"]]["image"], before[slide["id"]]["images"])
        for slide in kept
    ):
        details.append("заменены картинки")
    for field, label in (("caption", "изменены подписи"), ("alt", "изменены описания картинок")):
        changed = [
            language
            for language in languages
            if any(slide[field][language] != before[slide["id"]][field][language] for slide in kept)
        ]
        if changed:
            details.append(f"{label} ({', '.join(changed)})")
    if [slide["id"] for slide in old if slide["id"] in new_ids] != [slide["id"] for slide in kept]:
        details.append("изменён порядок слайдов")
    return details


def changed_blocks(
    old: Sequence[dict[str, Any]] | None, new: Sequence[dict[str, Any]]
) -> list[tuple[dict[str, Any], bool]]:
    """Slides and banners a reviewer should look at: each with «is it new»."""
    before = {block["id"]: block for block in old or ()}
    return [
        (block, block["id"] not in before)
        for block in new
        if block["type"] != VIDEO and before.get(block["id"]) != block
    ]
