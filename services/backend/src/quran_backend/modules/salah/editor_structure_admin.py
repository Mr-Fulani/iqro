"""The structure editor in the admin: add, remove and reorder sections, lessons and steps.

A mixin over SalahEditorAdminMixin. Adding opens a form with the texts in every
language and the kind; removing opens a page that says what goes with the
element and where it shows; reordering comes from the arrows and the drag of
the course tree. Every change is checked before it is saved: a draft may lack
translations, never a reference to something that is not there.
"""

from __future__ import annotations

# Russian interface strings intentionally contain characters that resemble Latin glyphs.
# ruff: noqa: RUF001
import copy
from collections.abc import Callable
from typing import Any

from django.contrib import messages
from django.core.exceptions import PermissionDenied
from django.db import transaction
from django.http import HttpRequest, HttpResponse, HttpResponseRedirect
from django.template.response import TemplateResponse
from django.urls import path

from quran_backend.modules.salah import editor
from quran_backend.modules.salah import editor_structure as structure
from quran_backend.modules.salah.editor_admin import (
    KIND_LABELS,
    SalahEditorAdminMixin,
    editor_editable,
    language_names,
)
from quran_backend.modules.salah.importer import compile_version
from quran_backend.modules.salah.models import (
    SALAH_LANGUAGES,
    SalahCourseVersion,
    SalahMediaAsset,
)
from quran_backend.modules.salah.resolvers import SalahFormulaError
from quran_backend.modules.salah.snapshot import integrity_problems, snapshot_checksum

# A change returns what to say and the recordings it may have orphaned.
Change = Callable[[dict[str, Any]], tuple[str, str, set[str]]]

_ADD_FIELDS = {
    "section": (editor.SECTION_FIELDS[0],),
    "lesson": editor.LESSON_FIELDS,
    "step": editor.STEP_FIELDS[:2],
}


class _StructureRefusedError(Exception):
    pass


class SalahStructureAdminMixin(SalahEditorAdminMixin):
    def structure_urls(self) -> list[Any]:
        return [
            path(
                "<path:object_id>/structure/",
                self.admin_site.admin_view(self.structure_view),
                name="salah_salahcourseversion_structure",
            )
        ]

    def structure_view(self, request: HttpRequest, object_id: str) -> HttpResponse:
        version = self._version(request, object_id)
        if not editor_editable(request.user, version):
            raise PermissionDenied
        action = _param(request, "action")
        if action.startswith("add-"):
            return self._add(request, version, action.removeprefix("add-"))
        if action == "delete":
            return self._delete(request, version)
        if request.method != "POST":
            return HttpResponseRedirect(self._editor_url(version))
        return self._reorder(request, version, action)

    # Saving -------------------------------------------------------------

    def _commit(
        self, request: HttpRequest, version: SalahCourseVersion, change: Change
    ) -> tuple[SalahCourseVersion, str, str]:
        """Applies one change to the latest draft, under a lock, once it is still valid."""
        with transaction.atomic():
            locked = SalahCourseVersion.objects.select_for_update().get(pk=version.pk)
            if not editor_editable(request.user, locked):
                raise _StructureRefusedError("Версию уже подписали или опубликовали.")
            if request.POST.get("revision") != editor.structure_revision(locked.snapshot):
                raise _StructureRefusedError(
                    "Пока страница была открыта, курс изменили (в другой вкладке или другой "
                    "человек). Откройте страницу заново и повторите."
                )
            snapshot = copy.deepcopy(locked.snapshot)
            try:
                summary, target, audio = change(snapshot)
            except structure.StructureError as error:
                raise _StructureRefusedError(str(error)) from error
            problems = integrity_problems(snapshot)
            if problems:
                raise _StructureRefusedError("Изменение сломало бы курс: " + "; ".join(problems))
            dropped = editor.drop_unused_audio(snapshot, audio)
            SalahMediaAsset.objects.filter(version=locked, key__in=dropped).delete()
            locked.snapshot = snapshot
            locked.checksum_sha256 = snapshot_checksum(snapshot)
            locked.save(update_fields=["snapshot", "checksum_sha256", "updated_at"])
        try:
            compile_version(locked)
        except SalahFormulaError as error:
            messages.warning(request, f"Сохранено, но документы курса не пересобраны: {error}")
        self.log_change(request, locked, f"Структура курса: {summary}")  # type: ignore[attr-defined]
        return locked, summary, target

    def _apply(
        self, request: HttpRequest, version: SalahCourseVersion, change: Change, back: str
    ) -> HttpResponse:
        try:
            saved, summary, target = self._commit(request, version, change)
        except _StructureRefusedError as refusal:
            messages.error(request, f"Не изменено: {refusal}")
            return HttpResponseRedirect(self._editor_url(version, back))
        messages.success(request, summary)
        return HttpResponseRedirect(self._editor_url(saved, target or back))

    # Reordering ---------------------------------------------------------

    def _reorder(
        self, request: HttpRequest, version: SalahCourseVersion, action: str
    ) -> HttpResponse:
        node_id = _param(request, "node")
        back = str(request.POST.get("return") or node_id or "course")

        def change(snapshot: dict[str, Any]) -> tuple[str, str, set[str]]:
            node = _node(snapshot, node_id)
            if action in {"up", "down"}:
                _move(snapshot, node, -1 if action == "up" else 1)
            elif action == "move":
                target = _node(snapshot, _param(request, "target"))
                _move_next_to(snapshot, node, target, after=_param(request, "position") == "after")
            elif action == "lesson-section" and node.kind == "lesson":
                structure.move_lesson_to_section(
                    snapshot, node.data["slug"], _param(request, "section")
                )
            else:
                raise structure.StructureError("Неизвестное действие.")
            return f"Порядок изменён: {KIND_LABELS[node.kind].lower()} «{node.title}».", "", set()

        return self._apply(request, version, change, back)

    # Adding -------------------------------------------------------------

    def _add(self, request: HttpRequest, version: SalahCourseVersion, kind: str) -> HttpResponse:
        if kind not in _ADD_FIELDS:
            return HttpResponseRedirect(self._editor_url(version))
        data = request.POST if request.method == "POST" else request.GET
        languages = editor.editor_languages(SALAH_LANGUAGES)
        snapshot = version.snapshot
        anchor_id = str(data.get("after") or "")
        anchor = _maybe_node(snapshot, anchor_id)
        lesson_slug = str(data.get("lesson") or "")
        if anchor is not None and anchor.lesson is not None:
            lesson_slug = anchor.lesson["slug"]
        errors: dict[str, str] = {}
        texts = _read_texts(_ADD_FIELDS[kind], data, languages, errors)
        if request.method == "POST" and not any(texts["title"].values()):
            errors[f"text-title-{languages[0]}"] = "Напишите название хотя бы на одном языке."
        if request.method == "POST" and not errors:
            response = self._create(
                request,
                version,
                kind,
                texts=texts,
                data=data,
                anchor_id=anchor_id,
                lesson_slug=lesson_slug,
            )
            if response is not None:
                return response
        return TemplateResponse(
            request,
            "admin/salah/salahcourseversion/structure_add.html",
            {
                **self.admin_site.each_context(request),
                "is_nav_sidebar_enabled": False,
                "opts": self.model._meta,
                "original": version,
                "title": _ADD_TITLES[kind],
                "kind": kind,
                "fields": _field_rows(_ADD_FIELDS[kind], texts, languages, errors),
                "section_choices": [
                    (s["slug"], editor.localized_title(s.get("title"), s["slug"]))
                    for s in snapshot.get("sections", [])
                ],
                "section": str(data.get("section") or ""),
                "lesson_kinds": list(structure.NEW_LESSON_KINDS.items()),
                "lesson_kind": str(data.get("kind") or "steps"),
                "step_kinds": list(editor.STEP_KIND_LABELS.items()),
                "step_kind": str(data.get("step_kind") or "action"),
                "slug": str(data.get("slug") or ""),
                "lesson": lesson_slug,
                "lesson_title": _lesson_title(snapshot, lesson_slug),
                "after": anchor_id,
                "after_title": anchor.title if anchor else "",
                "shared": _shared_note(snapshot, anchor),
                "revision": editor.structure_revision(version.snapshot),
                "back": _back(anchor_id, lesson_slug, str(data.get("section") or "")),
            },
            status=400 if request.method == "POST" else 200,
        )

    def _create(  # noqa: PLR0913 - one form of a new element
        self,
        request: HttpRequest,
        version: SalahCourseVersion,
        kind: str,
        *,
        texts: dict[str, dict[str, str]],
        data: Any,
        anchor_id: str,
        lesson_slug: str,
    ) -> HttpResponse | None:
        def change(snapshot: dict[str, Any]) -> tuple[str, str, set[str]]:
            if kind == "section":
                slug = structure.add_section(snapshot, texts["title"])
                return "Добавлен раздел. Теперь добавьте в него уроки.", f"section:{slug}", set()
            if kind == "lesson":
                slug = structure.add_lesson(
                    snapshot,
                    str(data.get("section") or ""),
                    kind=str(data.get("kind") or ""),
                    title=texts["title"],
                    summary=texts["summary"],
                    slug=str(data.get("slug") or "").strip(),
                )
                return "Добавлен урок. Добавьте в него шаги.", f"lesson:{slug}", set()
            after = _maybe_node(snapshot, anchor_id)
            node_id = structure.add_step(
                snapshot,
                lesson_slug,
                kind=str(data.get("step_kind") or ""),
                title=texts["title"],
                instruction=texts["instruction"],
                after=after,
            )
            return "Добавлен шаг. Заполните его тексты и свойства.", node_id, set()

        try:
            saved, summary, target = self._commit(request, version, change)
        except _StructureRefusedError as refusal:
            messages.error(request, f"Не добавлено: {refusal}")
            return None
        messages.success(request, summary)
        return HttpResponseRedirect(self._editor_url(saved, target))

    # Removing -----------------------------------------------------------

    def _delete(self, request: HttpRequest, version: SalahCourseVersion) -> HttpResponse:
        node_id = _param(request, "node")
        node = _maybe_node(copy.deepcopy(version.snapshot), node_id)
        if node is None or node.kind not in {"section", "lesson", "step"}:
            messages.error(request, "Удалить можно раздел, урок или шаг.")
            return HttpResponseRedirect(self._editor_url(version))
        if request.method == "POST":

            def change(snapshot: dict[str, Any]) -> tuple[str, str, set[str]]:
                current = _node(snapshot, node_id)
                removed = _remove(snapshot, current)
                parent = _parent_id(current)
                return (
                    f"Удалено: {KIND_LABELS[current.kind].lower()} «{current.title}».",
                    parent,
                    structure.removed_audio(removed),
                )

            return self._apply(request, version, change, node_id)
        snapshot = copy.deepcopy(version.snapshot)
        return TemplateResponse(
            request,
            "admin/salah/salahcourseversion/structure_delete.html",
            {
                **self.admin_site.each_context(request),
                "is_nav_sidebar_enabled": False,
                "opts": self.model._meta,
                "original": version,
                "title": f"Удалить: {KIND_LABELS[node.kind].lower()} «{node.title}»",
                "node": node,
                "kind_label": KIND_LABELS[node.kind],
                "notes": structure.deletion_notes(snapshot, node),
                "revision": editor.structure_revision(version.snapshot),
            },
        )


_ADD_TITLES = {
    "section": "Новый раздел",
    "lesson": "Новый урок",
    "step": "Новый шаг",
}


def _param(request: HttpRequest, name: str) -> str:
    """A form value, or the address's: the tree's buttons say what to do in their address."""
    return str(request.POST.get(name) or request.GET.get(name) or "")


def _node(snapshot: dict[str, Any], node_id: str) -> editor.EditorNode:
    try:
        return editor.find_node(snapshot, node_id)
    except editor.EditorNodeNotFoundError as error:
        raise structure.StructureError("Этого места в черновике уже нет.") from error


def _maybe_node(snapshot: dict[str, Any], node_id: str) -> editor.EditorNode | None:
    if not node_id:
        return None
    try:
        return editor.find_node(snapshot, node_id)
    except editor.EditorNodeNotFoundError:
        return None


def _move(snapshot: dict[str, Any], node: editor.EditorNode, delta: int) -> None:
    if node.kind == "section":
        structure.move_section(snapshot, node.data["slug"], delta)
    elif node.kind == "lesson":
        structure.move_lesson(snapshot, node.data["slug"], delta)
    elif node.kind == "step":
        structure.move_step(snapshot, node, delta)
    else:
        raise structure.StructureError("Это место не переставляется.")


def _move_next_to(
    snapshot: dict[str, Any], node: editor.EditorNode, target: editor.EditorNode, *, after: bool
) -> None:
    if node.kind != target.kind:
        raise structure.StructureError(
            "Перетащите элемент на другой элемент того же уровня: раздел на раздел, "
            "урок на урок, шаг на шаг."
        )
    if node.kind == "section":
        structure.move_section_next_to(
            snapshot, node.data["slug"], target.data["slug"], after=after
        )
    elif node.kind == "lesson":
        structure.move_lesson_next_to(snapshot, node.data["slug"], target.data["slug"], after=after)
    elif node.kind == "step":
        structure.move_step_next_to(snapshot, node, target, after=after)
    else:
        raise structure.StructureError("Это место не переставляется.")


def _remove(snapshot: dict[str, Any], node: editor.EditorNode) -> list[dict[str, Any]]:
    if node.kind == "section":
        return structure.delete_section(snapshot, node.data["slug"])
    if node.kind == "lesson":
        return structure.delete_lesson(snapshot, node.data["slug"])
    return structure.delete_step(snapshot, node)


def _parent_id(node: editor.EditorNode) -> str:
    if node.kind == "step" and node.lesson is not None:
        return f"lesson:{node.lesson['slug']}"
    return "course"


def _back(anchor_id: str, lesson_slug: str, section_slug: str) -> str:
    """Where «Cancel» returns: the place the owner came from."""
    if anchor_id:
        return anchor_id
    if lesson_slug:
        return f"lesson:{lesson_slug}"
    return f"section:{section_slug}" if section_slug else "course"


def _lesson_title(snapshot: dict[str, Any], slug: str) -> str:
    for lesson in snapshot.get("lessons", []):
        if lesson["slug"] == slug:
            return editor.localized_title(lesson.get("title"), slug)
    return ""


def _shared_note(snapshot: dict[str, Any], anchor: editor.EditorNode | None) -> str:
    if anchor is None or anchor.template_id is None:
        return ""
    usage = editor.template_step_usage(snapshot, anchor)
    places = "; ".join(f"{title} ({where})" if where else title for title, where in usage)
    return (
        f"Шаг встанет в шаблон «{editor.template_label(snapshot, anchor.template_id)}» сразу "
        f"после «{anchor.title}» и появится там же, где он: {places}."
    )


def _read_texts(
    fields: tuple[editor.TextField, ...],
    data: Any,
    languages: list[str],
    errors: dict[str, str],
) -> dict[str, dict[str, str]]:
    texts: dict[str, dict[str, str]] = {}
    for text_field in fields:
        values = {}
        for language in languages:
            name = f"text-{text_field.name}-{language}"
            text = editor.clean_text(str(data.get(name, "")))
            if len(text) > text_field.max_length:
                errors[name] = (
                    f"Слишком длинно: {len(text)} знаков, допустимо до {text_field.max_length}."
                )
            values[language] = text
        texts[text_field.name] = values
    return texts


def _field_rows(
    fields: tuple[editor.TextField, ...],
    texts: dict[str, dict[str, str]],
    languages: list[str],
    errors: dict[str, str],
) -> list[dict[str, Any]]:
    names = language_names()
    rows = []
    for text_field in fields:
        values = [
            {
                "name": f"text-{text_field.name}-{code}",
                "code": code,
                "language": names.get(code, code),
                "dir": "rtl" if code == "ar" else "ltr",
                "value": texts[text_field.name].get(code, ""),
                "missing": not texts[text_field.name].get(code, ""),
                "error": errors.get(f"text-{text_field.name}-{code}", ""),
            }
            for code in languages
        ]
        rows.append({"field": text_field, "values": values})
    return rows
