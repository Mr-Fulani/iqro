# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""The «Медиа» block of a lesson page in the admin, for any module with lesson media.

The module gives the stored list, whether the lesson has a video, the URL of
its media view and its own video block drawn as HTML; it saves the list in
`update`, under the lock of its row. Pictures are processed before that, so the
row is not locked while ffmpeg works.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass
from typing import Any

from django.http import HttpRequest
from django.template.loader import render_to_string
from django.utils.html import format_html
from django.utils.safestring import SafeString

from quran_backend.modules.audio.serializers import public_audio_url
from quran_backend.modules.courses.lesson_media import (
    BANNER,
    IMAGE_ACCEPT,
    MAX_SLIDES,
    SLIDES,
    VIDEO,
    LessonMediaError,
    add_block,
    add_images,
    editor_blocks,
    find_block,
    find_slide,
    move_blocks,
    move_slides,
    remove_block,
    remove_slide,
    set_language_image,
    set_texts,
    store_media_image,
)

TAB_LABELS = {"ru": "RU", "en": "EN", "ar": "العربية", "tr": "TR"}
LANGUAGE_NAMES = {"ru": "русского", "en": "английского", "ar": "арабского", "tr": "турецкого"}
KIND_LABELS = {VIDEO: "Видео", SLIDES: "Слайды", BANNER: "Баннер"}
MEDIA_INSTRUCTION_URL = "https://github.com/Mr-Fulani/iqro/blob/main/docs/courses/video.md"
MAX_FILES = MAX_SLIDES
OPEN_LESSON_HINT = "Видео, слайды и баннер добавляются в уроке: выберите его в списке слева."
MAKE_DRAFT_HINT = (
    "Видео, слайды и баннер добавляются только в черновике. Создайте его из этой версии, "
    "откройте урок и выберите, что добавить. Ученики увидят медиа после подписи и публикации."
)
NO_DRAFT_HINT = (
    "Видео, слайды и баннер добавляются только в черновике, а его создаёт сотрудник "
    "с правом на добавление версий курса."
)
NEW_LESSON_HINT = (
    "Видео, слайды и баннер можно добавить после сохранения темы: "
    "нажмите «Сохранить и продолжить редактирование»."
)

Change = Callable[[list[dict[str, Any]]], list[dict[str, Any]]]


@dataclass(frozen=True, slots=True)
class MediaPage:
    media: Sequence[dict[str, Any]]
    has_video: bool
    # The editor's order, Russian first.
    languages: Sequence[str]
    action_url: str
    can_edit: bool
    # The module's video block, shown in the video's place.
    video_html: str
    # The first part of the keys in R2: "courses", "tajweed".
    prefix: str
    # Why the buttons are missing and where to get them: see `media_hint`.
    hint: str = ""
    draft_url: str = ""


def media_hint(*, on_lesson: bool, editable: bool, draft_url: str) -> str:
    """The way to the buttons from a place of a version's editor that has none."""
    if editable:
        return "" if on_lesson else OPEN_LESSON_HINT
    return MAKE_DRAFT_HINT if draft_url else NO_DRAFT_HINT


def render_media_hint(hint: str, draft_url: str, request: HttpRequest) -> str:
    """The block in place of «Медиа» on a part of a course that is not a lesson."""
    return format_html(
        '<section class="cp cmedia" role="note"><h2>Медиа</h2>{}</section>',
        render_to_string(
            "admin/lesson_media/hint.html",
            {"hint": hint, "draft_url": draft_url},
            request=request,
        ),
    )


def render_media(page: MediaPage, request: HttpRequest) -> str:
    return render_to_string(
        "admin/lesson_media/media.html", {"media": media_context(page)}, request=request
    )


def media_context(page: MediaPage) -> dict[str, Any]:
    blocks = editor_blocks(page.media, has_video=page.has_video)
    return {
        "action_url": page.action_url,
        "can_edit": page.can_edit,
        "can_add_video": not any(block["type"] == VIDEO for block in blocks),
        "hint": page.hint,
        "draft_url": page.draft_url,
        "instruction_url": MEDIA_INSTRUCTION_URL,
        "accept": IMAGE_ACCEPT,
        "max_slides": MAX_SLIDES,
        "languages": [{"code": code, "tab": TAB_LABELS[code]} for code in page.languages],
        "blocks": [_block_context(block, page) for block in blocks],
    }


def _block_context(block: dict[str, Any], page: MediaPage) -> dict[str, Any]:
    context: dict[str, Any] = {
        "id": block["id"],
        "type": block["type"],
        "label": KIND_LABELS[block["type"]],
    }
    if block["type"] == VIDEO:
        context["video_html"] = SafeString(page.video_html)
        context["confirm"] = (
            "Убрать видео из темы вместе с озвучками? Файлы останутся в хранилище."
            if page.has_video
            else "Убрать место для видео?"
        )
        return context
    slides = block["slides"]
    if block["type"] == SLIDES:
        context["count"] = f"{len(slides)} из {MAX_SLIDES}" if slides else "пока нет слайдов"
    context["confirm"] = (
        f"Удалить блок «{context['label']}»"
        + (f" ({len(slides)} шт.)" if block["type"] == SLIDES and slides else "")
        + "? Картинки останутся в хранилище."
    )
    context["slides"] = [
        {
            "id": slide["id"],
            "number": number,
            "languages": [
                _language_context(slide, code, page.languages[0]) for code in page.languages
            ],
        }
        for number, slide in enumerate(slides, start=1)
    ]
    return context


def _language_context(slide: dict[str, Any], code: str, first: str) -> dict[str, Any]:
    own = slide.get("images", {}).get(code)
    image = own or slide["image"]
    return {
        "code": code,
        "tab": TAB_LABELS[code],
        "name": LANGUAGE_NAMES[code],
        "first": code == first,
        "own": own is not None,
        "url": public_audio_url(image["small_object_key"]),
        "width": image["width"],
        "height": image["height"],
        "caption": slide.get("caption", {}).get(code, ""),
        "alt": slide.get("alt", {}).get(code, ""),
    }


def run_media_action(
    request: HttpRequest,
    page: MediaPage,
    *,
    update: Callable[[Change], None],
    remove_video: Callable[[], None],
) -> str:
    """Does what the button asked for and says it for the change log."""
    handler = _ACTIONS.get(str(request.POST.get("action", "")))
    if handler is None:
        raise LessonMediaError("Неизвестное действие.")
    return handler(_Action(request, page, update, remove_video))


@dataclass(frozen=True, slots=True)
class _Action:
    request: HttpRequest
    page: MediaPage
    update: Callable[[Change], None]
    remove_video: Callable[[], None]

    @property
    def has_video(self) -> bool:
        return self.page.has_video

    @property
    def block_id(self) -> str:
        return str(self.request.POST.get("block", ""))

    @property
    def slide_id(self) -> str:
        return str(self.request.POST.get("slide", ""))

    def block(self) -> dict[str, Any]:
        """The block as the page showed it: the list is read again under the lock."""
        return find_block(editor_blocks(self.page.media, has_video=self.has_video), self.block_id)

    def language(self, *, common: bool = False) -> str:
        """A language of the editor; "" is the common picture where `common` allows it."""
        language = str(self.request.POST.get("language", ""))
        if language not in self.page.languages and not (common and language == ""):
            raise LessonMediaError("Неизвестный язык.")
        return language

    def pictures(self, kind: str, *, single: bool = False) -> list[dict[str, Any]]:
        files = self.request.FILES.getlist("file")
        if not files:
            raise LessonMediaError("Выберите картинку.")
        if single and len(files) > 1:
            raise LessonMediaError("Выберите одну картинку.")
        if len(files) > MAX_FILES:
            raise LessonMediaError(f"За один раз — не больше {MAX_FILES} картинок.")
        return [store_media_image(file, kind=kind, prefix=self.page.prefix) for file in files]


def _add(action: _Action) -> str:
    kind = str(action.request.POST.get("kind", ""))
    has_video = action.has_video
    if kind == VIDEO:
        action.update(lambda media: add_block(media, VIDEO, has_video=has_video)[0])
        return "Медиа: добавлено место для видео"
    if kind not in (SLIDES, BANNER):
        raise LessonMediaError("Неизвестный вид медиа.")
    images = action.pictures(kind, single=kind == BANNER)

    def add(media: list[dict[str, Any]]) -> list[dict[str, Any]]:
        blocks, block = add_block(media, kind, has_video=has_video)
        return add_images(blocks, block["id"], images, has_video=has_video)

    action.update(add)
    return f"Медиа: добавлены слайды ({len(images)})" if kind == SLIDES else "Медиа: баннер"


def _order(action: _Action) -> str:
    order = action.request.POST.getlist("order")
    action.update(lambda media: move_blocks(media, order, has_video=action.has_video))
    return "Медиа: изменён порядок"


def _remove(action: _Action) -> str:
    block = action.block()
    if block["type"] == VIDEO and action.has_video:
        action.remove_video()
    action.update(lambda media: remove_block(media, block["id"], has_video=action.has_video)[0])
    return f"Медиа: удалён блок «{KIND_LABELS[block['type']]}»"


def _images(action: _Action) -> str:
    block = action.block()
    if block["type"] == VIDEO:
        raise LessonMediaError("В блок видео картинки не добавляются.")
    images = action.pictures(block["type"], single=block["type"] == BANNER)
    action.update(lambda media: add_images(media, block["id"], images, has_video=action.has_video))
    return f"Медиа: картинки ({len(images)}) в блок «{KIND_LABELS[block['type']]}»"


def _slide_order(action: _Action) -> str:
    order = action.request.POST.getlist("order")
    block_id = action.block_id
    action.update(lambda media: move_slides(media, block_id, order, has_video=action.has_video))
    return "Медиа: изменён порядок слайдов"


def _slide_remove(action: _Action) -> str:
    block_id, slide_id = action.block_id, action.slide_id
    action.update(lambda media: remove_slide(media, block_id, slide_id, has_video=action.has_video))
    return "Медиа: удалён слайд"


def _texts(action: _Action) -> str:
    language = action.language()
    block_id, slide_id = action.block_id, action.slide_id
    caption = str(action.request.POST.get("caption", ""))
    alt = str(action.request.POST.get("alt", ""))
    action.update(
        lambda media: set_texts(
            media,
            block_id,
            slide_id,
            language,
            caption=caption,
            alt=alt,
            has_video=action.has_video,
        )
    )
    return f"Медиа: подпись слайда ({language})"


def _language_image(action: _Action) -> str:
    language = action.language(common=True)
    block = action.block()
    slide_id = action.slide_id
    find_slide(block, slide_id)
    (image,) = action.pictures(block["type"], single=True)
    action.update(
        lambda media: set_language_image(
            media, block["id"], slide_id, language, image, has_video=action.has_video
        )
    )
    return f"Медиа: картинка слайда ({language or 'общая'})"


def _language_image_remove(action: _Action) -> str:
    language = action.language()
    block_id, slide_id = action.block_id, action.slide_id
    action.update(
        lambda media: set_language_image(
            media, block_id, slide_id, language, None, has_video=action.has_video
        )
    )
    return f"Медиа: слайд снова с общей картинкой ({language})"


_ACTIONS: dict[str, Callable[[_Action], str]] = {
    "add": _add,
    "order": _order,
    "remove": _remove,
    "images": _images,
    "slide_order": _slide_order,
    "slide_remove": _slide_remove,
    "texts": _texts,
    "language_image": _language_image,
    "language_image_remove": _language_image_remove,
}
