# Russian interface strings intentionally contain Cyrillic letters.
# ruff: noqa: RUF001
"""The admin of lesson media kept in a version's snapshot (snapshot_media.py).

The tajweed and the prayer-learning course editors show the «Медиа» block of
thematic courses on a lesson of a draft and the list of new videos and dubs to
watch before signing. The module gives its URLs, its lock (`DraftLesson`) and
its log; the views here answer the block's buttons with JSON, as on a lesson of
a thematic course.
"""

from __future__ import annotations

import logging
from collections.abc import Callable, Iterable, Mapping, Sequence
from typing import Any

from django.core.exceptions import ImproperlyConfigured
from django.http import Http404, HttpRequest, HttpResponse, HttpResponseNotAllowed, JsonResponse
from django.template.loader import render_to_string

from quran_backend.modules.audio.serializers import public_audio_url
from quran_backend.modules.core.object_storage import ObjectStorageError
from quran_backend.modules.courses.admin import (
    TAB_LABELS,
    VIDEO_INSTRUCTION_URL,
    _received_file,
    clock,
    megabytes,
)
from quran_backend.modules.courses.document import LANGUAGE_NAMES, video_payload
from quran_backend.modules.courses.lesson_media import LessonMediaError
from quran_backend.modules.courses.lesson_media_admin import (
    Change,
    MediaPage,
    render_media,
    run_media_action,
)
from quran_backend.modules.courses.models import SPOKEN_LANGUAGES
from quran_backend.modules.courses.snapshot_media import (
    DraftLesson,
    delete_dub,
    lesson_video,
    remove_video,
    set_poster,
    set_spoken_language,
    upload_dub,
    upload_video,
)
from quran_backend.modules.courses.video import (
    MAX_DUB_MIB,
    MAX_VIDEO_MIB,
    SPEECH_NAMES,
    CourseVideoError,
)

logger = logging.getLogger(__name__)

VIDEO_TEMPLATE = "admin/courses/courselesson/video.html"

# Draws the video block; `operation` is "upload", "poster", "language" or "remove".
VideoUrl = Callable[[str], str]
# The same for a dub: (language, "upload" | "delete").
DubUrl = Callable[[str, str], str]


def video_block(
    lesson: Mapping[str, Any],
    *,
    editable: bool,
    languages: Sequence[str],
    video_url: VideoUrl,
    dub_url: DubUrl,
) -> dict[str, Any]:
    """The lesson's video for the video block of thematic courses, which reads these names."""
    block: dict[str, Any] = {
        "instruction_url": VIDEO_INSTRUCTION_URL,
        "languages": SPOKEN_LANGUAGES,
        "max_video_mib": MAX_VIDEO_MIB,
        "max_dub_mib": MAX_DUB_MIB,
        "can_upload": editable,
        "upload_url": video_url("upload"),
        "video": None,
    }
    video = lesson_video(lesson)
    if video is None:
        return block
    poster = video["poster"]
    dubs = video["dubs"]
    block.update(
        {
            "video": {
                **video,
                "pk": video["sha256"],
                "poster_width": poster["width"],
                "poster_height": poster["height"],
            },
            "url": public_audio_url(video["object_key"]),
            "poster_url": public_audio_url(poster["small_object_key"]),
            "duration": clock(video["duration_ms"]),
            "size": megabytes(video["bytes"]),
            "fps": f"{video['fps']:g}".replace(".", ","),
            "speech": SPEECH_NAMES[video["spoken_language"]],
            "poster_second": min(3, video["duration_ms"] // 10_000),
            "last_second": max(0, video["duration_ms"] // 1000 - 1),
            "can_edit": editable,
            "can_remove": editable,
            "can_dub": editable,
            "can_delete_dub": editable,
            "poster_url_action": video_url("poster"),
            "language_url": video_url("language"),
            "remove_url": video_url("remove"),
            "dubs": [
                {
                    "code": code,
                    "label": LANGUAGE_NAMES[code],
                    "tab": TAB_LABELS[code],
                    "dub": dubs.get(code),
                    "url": public_audio_url(dubs[code]["object_key"]) if code in dubs else "",
                    "duration": clock(dubs[code]["duration_ms"]) if code in dubs else "",
                    "size": megabytes(dubs[code]["bytes"]) if code in dubs else "",
                    "upload_url": dub_url(code, "upload"),
                    "delete_url": dub_url(code, "delete"),
                }
                for code in languages
                if code != video["spoken_language"]
            ],
        }
    )
    return block


def render_video(block: dict[str, Any], request: HttpRequest) -> str:
    return render_to_string(VIDEO_TEMPLATE, {"block": block}, request=request)


def video_operation(
    request: HttpRequest, draft: DraftLesson, operation: str, language: str
) -> Callable[[], str]:
    """What a button of the video block does, as a change that names itself for the log."""
    post = request.POST
    video_id = post.get("video")

    def upload() -> str:
        with _received_file(request, MAX_VIDEO_MIB) as (uploaded, source):
            video = upload_video(
                draft,
                source,
                spoken_language=str(post.get("spoken_language", "ru")),
                original_name=uploaded.name or "",
            )
        return f"видео «{video['original_name']}», {clock(video['duration_ms'])}"

    def poster() -> str:
        image = request.FILES.get("image")
        raw = str(post.get("second", "")).replace(",", ".").strip()
        try:
            second = float(raw) if raw else None
        except ValueError:
            second = None
        set_poster(draft, video_id, second=second, image=image)
        return f"обложка из картинки «{image.name}»" if image else f"обложка — кадр на {raw} с"

    def speech() -> str:
        spoken = str(post.get("spoken_language", ""))
        set_spoken_language(draft, video_id, spoken)
        return f"язык речи — {SPEECH_NAMES.get(spoken, spoken)}"

    def remove() -> str:
        remove_video(draft, video_id)
        return "видео убрано"

    def dub() -> str:
        with _received_file(request, MAX_DUB_MIB) as (uploaded, source):
            upload_dub(draft, video_id, language, source, original_name=uploaded.name or "")
        return f"озвучка ({language})"

    def undub() -> str:
        delete_dub(draft, video_id, language)
        return f"удалена озвучка ({language})"

    operations: dict[str, Callable[[], str]] = (
        {"upload": dub, "delete": undub}
        if language
        else {"upload": upload, "poster": poster, "language": speech, "remove": remove}
    )
    if operation not in operations:
        raise Http404
    return operations[operation]


def _answer(run: Callable[[], str], log: Callable[[str], object]) -> HttpResponse | None:
    """Runs the change and logs it; an error is the answer, success gives None."""
    try:
        message = run()
    except (LessonMediaError, CourseVideoError) as error:
        return JsonResponse({"error": str(error)}, status=error.status)
    except ImproperlyConfigured, ObjectStorageError, OSError:
        logger.exception("Lesson media operation failed")
        return JsonResponse({"error": "Хранилище недоступно, повторите."}, status=502)
    log(message)
    return None


def _keep() -> None:
    """Nothing to do apart: the video lives in its block, which goes with it."""


def media_view(
    request: HttpRequest,
    *,
    draft: DraftLesson,
    page: Callable[[], MediaPage],
    log: Callable[[str], object],
) -> HttpResponse:
    """The «Медиа» block's buttons; `page` reads the version again for each answer."""
    if request.method != "POST":
        return HttpResponseNotAllowed(["POST"])

    def update(change: Change) -> None:
        draft.change(lambda item: item.__setitem__("media", change(list(item.get("media") or []))))

    response = _answer(
        lambda: run_media_action(request, page(), update=update, remove_video=_keep), log
    )
    if response is not None:
        return response
    if request.POST.get("action") == "texts":
        return JsonResponse({"ok": True})
    return JsonResponse({"html": render_media(page(), request)})


def video_view(  # noqa: PLR0913 - the button and what to draw after it
    request: HttpRequest,
    *,
    draft: DraftLesson,
    operation: str,
    language: str,
    block: Callable[[], dict[str, Any]],
    log: Callable[[str], object],
) -> HttpResponse:
    """The video block's buttons: upload, poster, language of speech, dubs."""
    if request.method != "POST":
        return HttpResponseNotAllowed(["POST"])
    response = _answer(video_operation(request, draft, operation, language), log)
    if response is not None:
        return response
    return JsonResponse({"html": render_video(block(), request)})


def review_videos(
    lessons: Iterable[tuple[str, Mapping[str, Any]]],
    *,
    new: set[str],
    watched: set[str],
    mark_url: Callable[[str], str],
    node: str,
) -> list[dict[str, Any]]:
    """Every new video and dub of a draft, each with its own «Просмотрено».

    `lessons` are (name, lesson) in the course's order; `node` is where the editor returns.
    """
    found = []
    for name, lesson in lessons:
        video = lesson_video(lesson)
        if video is None:
            continue
        files = [(video["sha256"], f"основное видео, {SPEECH_NAMES[video['spoken_language']]}", "")]
        files += [
            (dub["sha256"], f"озвучка, {LANGUAGE_NAMES[code]}", code)
            for code, dub in sorted(video["dubs"].items())
        ]
        for sha256, label, code in files:
            if sha256 not in new:
                continue
            payload = video_payload(video, code)
            assert payload is not None
            found.append(
                {
                    "name": f"{name}: {label}",
                    "sha256": sha256,
                    "url": payload["url"],
                    "poster_url": payload["poster"]["small_url"],
                    "duration": clock(payload["duration_ms"]),
                    "size": megabytes(payload["bytes"]),
                    "watched": sha256 in watched,
                    "mark_url": mark_url(sha256),
                    "node": node,
                }
            )
    return found
