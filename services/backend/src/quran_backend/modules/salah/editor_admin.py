"""The course editor in the admin: texts by language, «?» and «!» notes, recordings.

A mixin of SalahCourseVersionAdmin. One page shows one place of the course
(`editor.py`): the course tree on the side, the place's form and, for a step,
a live preview. Only an unsigned draft is editable; any version can be copied
into a new draft. A save never loses what was typed: a problem keeps the form
as it was sent and names the field, a form older than the draft is refused.
"""

from __future__ import annotations

# Russian interface strings intentionally contain characters that resemble Latin glyphs.
# ruff: noqa: RUF001
import copy
import json
import logging
import re
from contextlib import ExitStack
from typing import Any

from django.conf import settings
from django.contrib import messages
from django.contrib.admin.utils import unquote
from django.core.exceptions import ImproperlyConfigured, PermissionDenied
from django.db import transaction
from django.http import (
    Http404,
    HttpRequest,
    HttpResponse,
    HttpResponseNotAllowed,
    HttpResponseRedirect,
)
from django.template.response import TemplateResponse
from django.urls import path, reverse
from django.utils import timezone
from django.utils.http import urlencode

from quran_backend.modules.audio.player_background_upload import player_background_uploader
from quran_backend.modules.audio.serializers import public_audio_url
from quran_backend.modules.core.object_storage import ObjectStorageError
from quran_backend.modules.salah import editor
from quran_backend.modules.salah.importer import (
    compile_version,
    copy_salah_version,
    publish_salah_version,
    sign_salah_version,
    store_media,
)
from quran_backend.modules.salah.media_upload import (
    MAX_AUDIO_SECONDS,
    CheckedAudio,
    SalahMediaUploadError,
    checked_audio,
)
from quran_backend.modules.salah.models import (
    SALAH_LANGUAGES,
    SalahCourseVersion,
    SalahMediaAsset,
    SalahPublicationStatus,
)
from quran_backend.modules.salah.resolvers import SalahFormulaError
from quran_backend.modules.salah.snapshot import SalahSnapshotError, snapshot_checksum

logger = logging.getLogger(__name__)

VERSION_NAME = re.compile(r"^[0-9A-Za-z][0-9A-Za-z._-]{0,63}$")
RULING_LABELS = {
    "shart": "Условие (шарт)",
    "rukn": "Столп (рукн)",
    "wajib": "Обязательно (ваджиб)",
    "sunnah": "Сунна",
}
KIND_LABELS = {
    "course": "Курс",
    "section": "Раздел",
    "lesson": "Урок",
    "step": "Шаг",
    "formula": "Формула",
}
# Problems of a sign-off shown at once; the rest is counted.
SHOWN_PROBLEMS = 12


class _SaveRefusedError(Exception):
    """The draft cannot take this form; the message says why and what to do."""


def editor_editable(user: Any, version: SalahCourseVersion) -> bool:
    return (
        version.status == SalahPublicationStatus.DRAFT
        and not version.is_signed
        and user.has_perm("salah.change_salahcourseversion")
    )


def readonly_reason(user: Any, version: SalahCourseVersion) -> str:
    if version.status == SalahPublicationStatus.PUBLISHED:
        return (
            "Версия опубликована: её показывают приложение и сайт, поэтому она не меняется. "
            "Чтобы что-то поправить, создайте из неё черновик."
        )
    if version.status == SalahPublicationStatus.WITHDRAWN:
        return (
            "Версия отозвана: её заменила более новая. Её можно только читать "
            "или сделать из неё новый черновик."
        )
    if version.is_signed:
        return (
            "Черновик подписан и ждёт публикации: подписанный текст не меняется. "
            "Чтобы поправить, создайте из него новый черновик и подпишите его заново."
        )
    if not user.has_perm("salah.change_salahcourseversion"):
        return "У вас право только на просмотр курса."
    return ""


def free_version_name(version: SalahCourseVersion, base: str) -> str:
    taken = set(version.course.versions.values_list("version", flat=True))
    if base not in taken:
        return base
    number = 2
    while f"{base}-{number}" in taken:
        number += 1
    return f"{base}-{number}"


def _language_names() -> dict[str, str]:
    return {code: str(name) for code, name in settings.LANGUAGES}


def _kib(size: int) -> int:
    return max(1, round(size / 1024))


def _duration(milliseconds: int | None) -> str:
    if not milliseconds:
        return ""
    seconds = round(milliseconds / 1000)
    return f"{seconds // 60}:{seconds % 60:02d}"


class SalahEditorAdminMixin:
    """Views of the editor; `self` is the SalahCourseVersion ModelAdmin."""

    admin_site: Any
    model: type[SalahCourseVersion]

    def editor_urls(self) -> list[Any]:
        view = self.admin_site.admin_view
        return [
            path(
                "<path:object_id>/editor/",
                view(self.editor_view),
                name="salah_salahcourseversion_editor",
            ),
            path(
                "<path:object_id>/new-draft/",
                view(self.new_draft_view),
                name="salah_salahcourseversion_new_draft",
            ),
            path(
                "<path:object_id>/snapshot.json",
                view(self.snapshot_view),
                name="salah_salahcourseversion_snapshot",
            ),
            path(
                "<path:object_id>/review/",
                view(self.review_view),
                name="salah_salahcourseversion_review",
            ),
        ]

    # Access -------------------------------------------------------------

    def _version(self, request: HttpRequest, object_id: str) -> SalahCourseVersion:
        version: SalahCourseVersion | None = self.get_object(request, unquote(object_id))  # type: ignore[attr-defined]
        if version is None:
            raise Http404
        if not request.user.has_perm("salah.view_salahcourseversion"):
            raise PermissionDenied
        return version

    @staticmethod
    def _editor_url(version: SalahCourseVersion, node_id: str = "course") -> str:
        url = reverse("admin:salah_salahcourseversion_editor", args=[version.pk])
        return f"{url}?{urlencode({'node': node_id})}"

    # Editor page --------------------------------------------------------

    def editor_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        version = self._version(request, object_id)
        languages = editor.editor_languages(SALAH_LANGUAGES)
        node_id = request.GET.get("node") or "course"
        snapshot = copy.deepcopy(version.snapshot)
        try:
            node = editor.find_node(snapshot, node_id)
        except editor.EditorNodeNotFoundError:
            messages.warning(request, "Такого места в этой версии курса нет: открыт обзор курса.")
            return HttpResponseRedirect(self._editor_url(version))
        if request.method == "POST":
            if not editor_editable(request.user, version):
                raise PermissionDenied
            return self._save(request, version, node_id, languages)
        return self._render(request, version, snapshot, node, languages)

    def _render(  # noqa: PLR0913 - the page shows what the save refused, when it refused
        self,
        request: HttpRequest,
        version: SalahCourseVersion,
        snapshot: dict[str, Any],
        node: editor.EditorNode,
        languages: list[str],
        *,
        posted: Any = None,
        errors: dict[str, str] | None = None,
        revision: str | None = None,
    ) -> TemplateResponse:
        errors = errors or {}
        names = _language_names()
        editable = editor_editable(request.user, version)
        tree = editor.editor_tree(snapshot, languages)
        ids = editor.flat_ids(tree)
        position = ids.index(node.id) if node.id in ids else 0
        missing_ids = editor.missing_ids(tree)
        next_missing = next(
            (node_id for node_id in missing_ids if ids.index(node_id) > position),
            missing_ids[0] if missing_ids else None,
        )
        node_missing = editor.node_missing(node, languages)
        course_missing = editor.course_missing(snapshot, languages)
        assets = {asset.key: asset for asset in version.media.all()}
        language_rows = [
            {
                "code": code,
                "name": names.get(code, code),
                "dir": "rtl" if code == "ar" else "ltr",
                "missing": node_missing.get(code, 0),
                "course_missing": course_missing.get(code, 0),
            }
            for code in languages
        ]
        context = {
            **self.admin_site.each_context(request),
            "is_nav_sidebar_enabled": False,
            "opts": self.model._meta,
            "original": version,
            "title": f"Редактор курса: {version}",
            "editable": editable,
            "readonly_reason": readonly_reason(request.user, version),
            "can_copy": request.user.has_perm("salah.add_salahcourseversion"),
            "can_review": request.user.has_perm("salah.change_salahcourseversion")
            and version.status == SalahPublicationStatus.DRAFT,
            "languages": language_rows,
            "course_missing_total": sum(course_missing.values()),
            "tree": tree,
            "open_ids": self._open_ids(snapshot, node),
            "node": node,
            "node_kind": KIND_LABELS[node.kind],
            "node_path": self._path(snapshot, node),
            "revision": revision or editor.node_revision(snapshot, node),
            "fields": self._fields(node, languages, names, posted, errors),
            "notes": self._notes(node, languages, names, posted, errors),
            "note_kinds": list(editor.NOTE_KIND_LABELS.items()),
            "audio_groups": self._audio_groups(
                snapshot, node, languages, names=names, assets=assets, errors=errors
            ),
            "template_usage": editor.template_step_usage(snapshot, node)
            if node.template_id
            else [],
            "template_label": editor.template_label(snapshot, node.template_id)
            if node.template_id
            else "",
            "when": editor.describe_when(node.data.get("when", {})) if node.template_id else "",
            "variants": editor.variant_descriptions(snapshot, node),
            "sync_variants": posted is None or posted.get("sync_variants") == "on",
            "formula": self._formula_info(snapshot, version, node, languages, names),
            "lesson_steps": self._lesson_steps(snapshot, node),
            "prev_id": ids[position - 1] if position > 0 else None,
            "next_id": ids[position + 1] if position + 1 < len(ids) else None,
            "next_missing_id": next_missing if next_missing != node.id else None,
            "preview": self._preview(snapshot, version, node, languages, assets),
            "max_audio_seconds": MAX_AUDIO_SECONDS,
            "status_label": self._status_label(version),
        }
        return TemplateResponse(request, "admin/salah/salahcourseversion/editor.html", context)

    @staticmethod
    def _status_label(version: SalahCourseVersion) -> str:
        if version.status == SalahPublicationStatus.DRAFT:
            return "Черновик, подписан" if version.is_signed else "Черновик"
        return str(SalahPublicationStatus(version.status).label)

    @staticmethod
    def _open_ids(snapshot: dict[str, Any], node: editor.EditorNode) -> set[str]:
        """The tree opens at the place being edited."""
        opened = set()
        lesson = node.lesson
        if lesson is not None:
            opened.add(f"lesson:{lesson['slug']}")
            for section in snapshot.get("sections", []):
                if lesson["slug"] in section.get("lessons", []):
                    opened.add(f"section:{section['slug']}")
        if node.kind == "section":
            opened.add(node.id)
        if node.kind == "formula":
            opened.add("formulas")
        return opened

    @staticmethod
    def _path(snapshot: dict[str, Any], node: editor.EditorNode) -> list[tuple[str, str]]:
        """Breadcrumbs inside the course: (label, node id)."""
        trail: list[tuple[str, str]] = []
        lesson = node.lesson
        if lesson is None:
            return trail
        for section in snapshot.get("sections", []):
            if lesson["slug"] in section.get("lessons", []):
                trail.append(
                    (editor.localized_title(section.get("title"), section["slug"]),
                     f"section:{section['slug']}")
                )  # fmt: skip
                break
        if node.kind == "step":
            trail.append(
                (editor.localized_title(lesson.get("title"), lesson["slug"]),
                 f"lesson:{lesson['slug']}")
            )  # fmt: skip
        return trail

    @staticmethod
    def _fields(
        node: editor.EditorNode,
        languages: list[str],
        names: dict[str, str],
        posted: Any,
        errors: dict[str, str],
    ) -> list[dict[str, Any]]:
        rows = []
        for text_field in node.fields:
            stored = node.data.get(text_field.name) or {}
            values = []
            for code in languages:
                name = f"text-{text_field.name}-{code}"
                value = posted.get(name, "") if posted is not None else stored.get(code, "")
                values.append(
                    {
                        "name": name,
                        "code": code,
                        "language": names.get(code, code),
                        "dir": "rtl" if code == "ar" else "ltr",
                        "value": value,
                        "error": errors.get(name, ""),
                    }
                )
            filled = [bool(str(item["value"]).strip()) for item in values]
            for item, has_text in zip(values, filled, strict=True):
                item["missing"] = not has_text and (text_field.required or any(filled))
            rows.append({"field": text_field, "values": values})
        return rows

    @staticmethod
    def _notes(
        node: editor.EditorNode,
        languages: list[str],
        names: dict[str, str],
        posted: Any,
        errors: dict[str, str],
    ) -> list[dict[str, Any]] | None:
        if not node.has_notes:
            return None
        if posted is not None:
            order = [uid for uid in str(posted.get("notes_order", "")).split(",") if uid.strip()]
            notes = [
                {
                    "uid": uid,
                    "kind": posted.get(f"note-{uid}-kind", ""),
                    "text": {code: posted.get(f"note-{uid}-text-{code}", "") for code in languages},
                }
                for uid in order
            ]
        else:
            notes = [
                {"uid": f"n{number}", "kind": note.get("kind"), "text": note.get("text") or {}}
                for number, note in enumerate(node.data.get("notes", []), start=1)
            ]
        rows = []
        for note in notes:
            prefix = f"note-{note['uid']}"
            values = [
                {
                    "name": f"{prefix}-text-{code}",
                    "code": code,
                    "language": names.get(code, code),
                    "dir": "rtl" if code == "ar" else "ltr",
                    "value": note["text"].get(code, ""),
                    "missing": not str(note["text"].get(code, "")).strip(),
                    "error": errors.get(f"{prefix}-text-{code}", ""),
                }
                for code in languages
            ]
            rows.append(
                {
                    "uid": note["uid"],
                    "kind": note["kind"],
                    "kind_error": errors.get(f"{prefix}-kind", ""),
                    "values": values,
                }
            )
        return rows

    @staticmethod
    def _audio_owners(
        snapshot: dict[str, Any], node: editor.EditorNode
    ) -> list[tuple[str, editor.EditorNode, str, str]]:
        """Who on this page takes a recording: (form key, node, title, help)."""
        owners: list[tuple[str, editor.EditorNode, str, str]] = []
        if node.kind == "step":
            owners.append(
                (
                    "step",
                    node,
                    "Озвучка шага",
                    "Голос, который читает или объясняет шаг. Обычно это запись на языке "
                    "урока: загрузите её в строку своего языка.",
                )
            )
            for formula_id in node.data.get("formulas", []):
                try:
                    formula = editor.find_node(snapshot, f"formula:{formula_id}")
                except editor.EditorNodeNotFoundError:
                    continue
                owners.append(
                    (
                        f"formula.{formula_id}",
                        formula,
                        f"Формула «{formula_id}»",
                        "Запись формулы общая: она звучит во всех шагах с этой формулой "
                        "и заменяет запись из источника.",
                    )
                )
        elif node.kind == "formula":
            owners.append(
                (
                    f"formula.{node.title}",
                    node,
                    "Своя запись формулы",
                    "Заменяет запись из «Хисн аль-Муслим» или Корана во всех шагах с этой "
                    "формулой. Без своей записи звучит запись источника.",
                )
            )
        return owners

    def _audio_groups(  # noqa: PLR0913 - one form block per recording owner
        self,
        snapshot: dict[str, Any],
        node: editor.EditorNode,
        languages: list[str],
        *,
        names: dict[str, str],
        assets: dict[str, SalahMediaAsset],
        errors: dict[str, str],
    ) -> list[dict[str, Any]]:
        groups = []
        for owner_key, owner, title, help_text in self._audio_owners(snapshot, node):
            slots = []
            target = owner.audio_owner or {}
            for slot, key in editor.audio_slots(target, languages).items():
                asset = assets.get(key) if key else None
                field = f"audio__{owner_key}__{slot}"
                slots.append(
                    {
                        "slot": slot,
                        "label": "Для всех языков"
                        if slot == editor.AUDIO_ALL
                        else f"{names.get(slot, slot)} ({slot})",
                        "key": key or "",
                        "url": public_audio_url(asset.object_key) if asset else "",
                        "kib": _kib(asset.bytes) if asset else None,
                        "duration": _duration(asset.duration_ms) if asset else "",
                        "field": field,
                        "delete_field": f"audio_delete__{owner_key}__{slot}",
                        "error": errors.get(field, ""),
                        "stored_missing": bool(key) and asset is None,
                    }
                )
            groups.append(
                {
                    "owner": owner_key,
                    "title": title,
                    "help": help_text,
                    "link": owner.id if owner is not node else "",
                    "slots": slots,
                }
            )
        return groups

    @staticmethod
    def _formula_info(
        snapshot: dict[str, Any],
        version: SalahCourseVersion,
        node: editor.EditorNode,
        languages: list[str],
        names: dict[str, str],
    ) -> dict[str, Any] | None:
        if node.kind != "formula":
            return None
        source = node.data.get("source") or {}
        kind = source.get("kind")
        if kind == "dua":
            origin = f"«Хисн аль-Муслим», № {source.get('source_number')}"
        elif kind == "quran":
            origin = (
                f"Коран, сура {source.get('surah')}, аяты {source.get('ayah_from')}–"
                f"{source.get('ayah_to')}"
            )
        else:
            origin = "Своя формула курса"
        documents = {document.language: document.payload for document in version.documents.all()}
        compiled = {
            code: (documents.get(code) or {}).get("formulas", {}).get(node.title) or {}
            for code in languages
        }
        first = next((value for value in compiled.values() if value), {})
        return {
            "origin": origin,
            "arabic": first.get("arabic", ""),
            "audio_url": (first.get("audio") or {}).get("url", ""),
            "translations": [
                {
                    "code": code,
                    "language": names.get(code, code),
                    "dir": "rtl" if code == "ar" else "ltr",
                    "text": compiled[code].get("translation", ""),
                }
                for code in languages
            ],
            "steps": [
                (step.id, f"{step.lesson['slug'] if step.lesson else ''}: {step.title}")
                for step in editor.formula_steps(snapshot, node.title)
            ],
        }

    @staticmethod
    def _lesson_steps(snapshot: dict[str, Any], node: editor.EditorNode) -> list[tuple[str, str]]:
        """A lesson page lists its steps, so the owner sees what the lesson holds."""
        if node.kind != "lesson":
            return []
        return [
            (step.id, f"Р{step.rakat} · {step.title}" if step.rakat is not None else step.title)
            for step in editor.lesson_steps(snapshot, node.data)
        ]

    @staticmethod
    def _preview(
        snapshot: dict[str, Any],
        version: SalahCourseVersion,
        node: editor.EditorNode,
        languages: list[str],
        assets: dict[str, SalahMediaAsset],
    ) -> dict[str, Any] | None:
        """What the live preview needs besides the form: picture, formulas, recordings."""
        if node.kind != "step":
            return None
        documents = {document.language: document.payload for document in version.documents.all()}
        media = {asset.get("key"): asset for asset in snapshot.get("media", [])}
        image = None
        picture = assets.get(node.data.get("media") or "")
        if picture is not None:
            alt = media.get(picture.key, {}).get("alt") or {}
            image = {"url": public_audio_url(picture.object_key), "alt": alt}
        formulas = []
        for formula_id in node.data.get("formulas", []):
            by_language = {
                code: (documents.get(code) or {}).get("formulas", {}).get(formula_id) or {}
                for code in languages
            }
            first = next((value for value in by_language.values() if value), {})
            formulas.append(
                {
                    "id": formula_id,
                    "arabic": first.get("arabic", ""),
                    "repetitions": first.get("repetitions", 1),
                    "texts": {
                        code: {
                            "translation": value.get("translation", ""),
                            "transliteration": value.get("transliteration", ""),
                        }
                        for code, value in by_language.items()
                    },
                }
            )
        audio = {}
        for slot, key in editor.audio_slots(node.data, languages).items():
            asset = assets.get(key or "")
            if asset is not None:
                audio[slot] = public_audio_url(asset.object_key)
        return {
            "ruling": RULING_LABELS.get(node.data.get("ruling") or "", ""),
            "rakat": node.rakat,
            "image": image,
            "formulas": formulas,
            "audio": audio,
        }

    # Saving -------------------------------------------------------------

    def _save(
        self,
        request: HttpRequest,
        version: SalahCourseVersion,
        node_id: str,
        languages: list[str],
    ) -> HttpResponse:
        snapshot = copy.deepcopy(version.snapshot)
        node = editor.find_node(snapshot, node_id)
        edit = editor.parse_node_form(node, request.POST, languages)
        errors = dict(edit.errors)
        owners = {owner_key for owner_key, *_ in self._audio_owners(snapshot, node)}
        uploads = {
            name: uploaded
            for name, uploaded in request.FILES.items()
            if name.startswith("audio__") and self._audio_field(name, owners, languages)
        }
        deletes = {
            name.removeprefix("audio_delete__")
            for name in request.POST
            if name.startswith("audio_delete__")
            and self._audio_field(name.replace("audio_delete__", "audio__", 1), owners, languages)
        }
        with ExitStack() as stack:
            checked: dict[str, CheckedAudio] = {}
            for name, uploaded in uploads.items():
                try:
                    checked[name.removeprefix("audio__")] = stack.enter_context(
                        checked_audio(uploaded)
                    )
                except SalahMediaUploadError as error:
                    errors[name] = f"{uploaded.name}: {error}"
            if errors:
                messages.error(
                    request,
                    "Ничего не сохранено: исправьте отмеченные поля. Введённый текст остался "
                    "в форме, файлы записей выберите заново.",
                )
                return self._refuse(request, version, node_id, languages, errors, status=400)
            try:
                saved, synced = self._write(
                    request,
                    version,
                    node_id,
                    edit=edit,
                    checked=checked,
                    deletes=deletes,
                    languages=languages,
                )
            except _SaveRefusedError as refusal:
                messages.error(request, str(refusal))
                return self._refuse(request, version, node_id, languages, errors, status=409)
            except ImproperlyConfigured, ObjectStorageError, OSError:
                logger.exception("Salah editor: storing a recording failed")
                messages.error(
                    request,
                    "Не удалось сохранить запись в хранилище, поэтому ничего не сохранено. "
                    "Повторите через минуту: введённый текст остался в форме.",
                )
                return self._refuse(request, version, node_id, languages, errors, status=503)
        try:
            compile_version(saved)
        except SalahFormulaError as error:
            messages.warning(request, f"Сохранено, но документы курса не пересобраны: {error}")
        node = editor.find_node(saved.snapshot, node_id)
        self.log_change(request, saved, f"Редактор курса: {KIND_LABELS[node.kind]} «{node.title}».")  # type: ignore[attr-defined]
        summary = "Сохранено."
        if synced:
            summary += (
                f" Те же правки внесены ещё в варианты этого шага с таким же текстом "
                f"(другие ракааты и молитвы): {synced}."
            )
        missing = sum(editor.node_missing(node, languages).values())
        if missing:
            summary += f" Здесь не переведено полей: {missing}."
        messages.success(request, summary)
        target = node_id
        if "save_next" in request.POST:
            ids = editor.flat_ids(editor.editor_tree(saved.snapshot, languages))
            position = ids.index(node_id) if node_id in ids else -1
            target = ids[position + 1] if 0 <= position < len(ids) - 1 else node_id
        return HttpResponseRedirect(self._editor_url(saved, target))

    @staticmethod
    def _audio_field(name: str, owners: set[str], languages: list[str]) -> bool:
        _, owner, slot = [*name.split("__", 2), "", ""][:3]
        return owner in owners and (slot == editor.AUDIO_ALL or slot in languages)

    def _refuse(  # noqa: PLR0913 - the page again, as the save found it
        self,
        request: HttpRequest,
        version: SalahCourseVersion,
        node_id: str,
        languages: list[str],
        errors: dict[str, str],
        *,
        status: int,
    ) -> TemplateResponse:
        """The page again with the form as it was sent."""
        version.refresh_from_db()
        snapshot = copy.deepcopy(version.snapshot)
        node = editor.find_node(snapshot, node_id)
        response = self._render(
            request,
            version,
            snapshot,
            node,
            languages,
            posted=request.POST,
            errors=errors,
            revision=request.POST.get("node_revision"),
        )
        response.status_code = status
        return response

    @transaction.atomic
    def _write(  # noqa: PLR0913 - one save of one form
        self,
        request: HttpRequest,
        version: SalahCourseVersion,
        node_id: str,
        *,
        edit: editor.NodeEdit,
        checked: dict[str, CheckedAudio],
        deletes: set[str],
        languages: list[str],
    ) -> tuple[SalahCourseVersion, int]:
        locked = SalahCourseVersion.objects.select_for_update().get(pk=version.pk)
        if not editor_editable(request.user, locked):
            raise _SaveRefusedError(
                "Ничего не сохранено: версию уже подписали или опубликовали. "
                "Скопируйте свои правки из формы и внесите их в новый черновик."
            )
        snapshot = copy.deepcopy(locked.snapshot)
        node = editor.find_node(snapshot, node_id)
        if editor.node_revision(snapshot, node) != request.POST.get("node_revision"):
            raise _SaveRefusedError(
                "Ничего не сохранено: пока форма была открыта, это место курса изменили "
                "(в другой вкладке или другой человек). Ваш текст остался в форме — "
                "скопируйте его, откройте страницу заново и внесите правки ещё раз."
            )
        sync = request.POST.get("sync_variants") == "on"
        synced = editor.apply_node_edit(snapshot, node, edit, languages, sync_variants=sync)
        self._write_audio(
            locked, snapshot, node, checked=checked, deletes=deletes, languages=languages, sync=sync
        )
        locked.snapshot = snapshot
        locked.checksum_sha256 = snapshot_checksum(snapshot)
        update_fields = ["snapshot", "checksum_sha256", "updated_at"]
        if node.kind == "course":
            locked.source_title = dict(snapshot["course"].get("source_title") or {})
            update_fields.append("source_title")
        locked.save(update_fields=update_fields)
        return locked, synced

    @staticmethod
    def _write_audio(  # noqa: PLR0913 - the recordings of one form
        version: SalahCourseVersion,
        snapshot: dict[str, Any],
        node: editor.EditorNode,
        *,
        checked: dict[str, CheckedAudio],
        deletes: set[str],
        languages: list[str],
        sync: bool,
    ) -> None:
        replaced: set[str] = set()
        uploader = None
        for slot_id in sorted(set(checked) | deletes):
            owner_key, slot = slot_id.split("__", 1)
            owner = (
                node
                if owner_key == "step"
                else editor.find_node(snapshot, f"formula:{owner_key.removeprefix('formula.')}")
            )
            target = owner.audio_owner
            if target is None:
                continue
            old_key = editor.audio_slot(target, slot)
            new_key = None
            recording = checked.get(slot_id)
            if recording is not None:
                new_key = editor.new_audio_key(owner, slot)
                uploader = uploader or player_background_uploader()
                store_media(
                    version, new_key, recording.path, uploader, duration_ms=recording.duration_ms
                )
                editor.add_audio_media(snapshot, new_key, recording.path.suffix)
            elif old_key is None:
                continue
            variants = (
                editor.audio_variants(snapshot, owner, slot, old_key, languages)
                if sync and owner.kind == "step"
                else []
            )
            for each in [target, *variants]:
                editor.set_audio_slot(each, slot, new_key)
            if old_key:
                replaced.add(old_key)
        dropped = editor.drop_unused_audio(snapshot, replaced)
        SalahMediaAsset.objects.filter(version=version, key__in=dropped).delete()

    # New draft, download, review ---------------------------------------

    def new_draft_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        source = self._version(request, object_id)
        if not request.user.has_perm("salah.add_salahcourseversion"):
            raise PermissionDenied
        name = free_version_name(source, timezone.localdate().isoformat())
        error = ""
        if request.method == "POST":
            name = str(request.POST.get("version", "")).strip()
            if not VERSION_NAME.match(name):
                error = "Имя версии: латинские буквы, цифры, точка, дефис, до 64 знаков."
            elif source.course.versions.filter(version=name).exists():
                error = f"Версия «{name}» уже есть. Выберите другое имя."
            else:
                try:
                    draft = copy_salah_version(source, name)
                except SalahFormulaError as formula_error:
                    error = f"Черновик не создан: {formula_error}"
                else:
                    self.log_addition(request, draft, f"Черновик из версии {source.version}.")  # type: ignore[attr-defined]
                    messages.success(
                        request,
                        f"Создан черновик {draft}: копия версии {source.version}. "
                        "Исходная версия не изменилась.",
                    )
                    return HttpResponseRedirect(self._editor_url(draft))
        return TemplateResponse(
            request,
            "admin/salah/salahcourseversion/new_draft.html",
            {
                **self.admin_site.each_context(request),
                "opts": self.model._meta,
                "original": source,
                "title": f"Новый черновик из версии {source.version}",
                "name": name,
                "error": error,
            },
            status=400 if error else 200,
        )

    def snapshot_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        """The snapshot as JSON, to keep it in git like `hanbali-umdah-v1.json`."""
        version = self._version(request, object_id)
        body = json.dumps(version.snapshot, ensure_ascii=False, indent=2) + "\n"
        response = HttpResponse(body, content_type="application/json; charset=utf-8")
        filename = f"{version.course.slug}-{version.version}.json"
        response["Content-Disposition"] = f'attachment; filename="{filename}"'
        return response

    def review_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        """Sign-off and publication from the editor's status bar."""
        if request.method != "POST":
            return HttpResponseNotAllowed(["POST"])
        version = self._version(request, object_id)
        if not request.user.has_perm("salah.change_salahcourseversion"):
            raise PermissionDenied
        action = request.POST.get("action")
        back = HttpResponseRedirect(self._editor_url(version, request.POST.get("node") or "course"))
        if action == "sign":
            self._sign(request, version)
        elif action == "publish":
            try:
                publish_salah_version(version)
            except (SalahSnapshotError, SalahFormulaError) as error:
                messages.error(request, f"Не опубликовано: {error}")
            else:
                self.log_change(request, version, "Опубликована из редактора.")  # type: ignore[attr-defined]
                messages.success(
                    request,
                    f"{version} опубликована: приложение и сайт покажут её "
                    "в течение нескольких минут.",
                )
        return back

    def _sign(self, request: HttpRequest, version: SalahCourseVersion) -> None:
        if not editor_editable(request.user, version):
            messages.error(request, "Подписать можно только неподписанный черновик.")
            return
        languages = editor.editor_languages(SALAH_LANGUAGES)
        missing = editor.course_missing(version.snapshot, languages)
        if any(missing.values()):
            counts = ", ".join(f"{code}: {count}" for code, count in missing.items() if count)
            messages.error(
                request,
                f"Подписать пока нельзя: есть непереведённые тексты ({counts}). "
                "Кнопка «Следующий непереведённый» открывает их по очереди.",
            )
            return
        try:
            sign_salah_version(version, request.user)
        except SalahSnapshotError as error:
            problems = list(dict.fromkeys(error.problems))
            shown = "; ".join(problems[:SHOWN_PROBLEMS])
            more = (
                f" И ещё {len(problems) - SHOWN_PROBLEMS}."
                if len(problems) > SHOWN_PROBLEMS
                else ""
            )
            messages.error(request, f"Подписать нельзя: {shown}.{more}")
        except SalahFormulaError as error:
            messages.error(request, f"Подписано, но документы не пересобраны: {error}")
        else:
            self.log_change(request, version, "Подписана из редактора.")  # type: ignore[attr-defined]
            messages.success(
                request,
                "Подписано: религиозная проверка отмечена, текст версии закреплён. "
                "Теперь её можно опубликовать.",
            )
