# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
"""Admin of the Names of Allah.

A version starts as a draft imported from a data file (`manage.py import_names`)
or copied from another version here. The owner edits the names of a draft, signs
off the religious content and publishes. Signed and published versions are
read-only: a correction is a new draft.
"""

from __future__ import annotations

from typing import Any

from django.contrib import admin, messages
from django.db.models import ForeignKey, QuerySet
from django.forms import ModelChoiceField
from django.http import HttpRequest, HttpResponse, HttpResponseRedirect
from django.urls import reverse
from django.utils import timezone
from django.utils.html import format_html, format_html_join

from quran_backend.modules.names.models import (
    NAMES_LANGUAGES,
    DivineName,
    NamesCollection,
    NamesDocument,
    NamesStatus,
    NamesVersion,
)
from quran_backend.modules.names.publication import (
    NamesError,
    copy_names_version,
    publish_names_version,
    sign_names_version,
    version_problems,
)

SOURCE_FIELDS = tuple(
    f"{field}_{language}"
    for field in ("list_source", "tafsir_source")
    for language in NAMES_LANGUAGES
)

VERSION_FIELDS = (
    "collection",
    "version",
    "status",
    "names_link",
    "problems",
    *SOURCE_FIELDS,
    "reviewed_by",
    "reviewed_at",
    "review_note",
    "published_at",
    "review_preview",
)


def _names_url(version: NamesVersion) -> str:
    return f"{reverse('admin:names_divinename_changelist')}?version__id__exact={version.pk}"


@admin.register(NamesCollection)
class NamesCollectionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("slug", "active_version")
    readonly_fields = ("slug", "active_version", "created_at", "updated_at")

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_delete_permission(self, _request: HttpRequest, _obj: Any = None) -> bool:
        return False


@admin.register(NamesVersion)
class NamesVersionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("__str__", "status", "signed", "published_at", "names_link")
    list_filter = ("status",)
    actions = ("sign_versions", "publish_versions", "copy_versions")
    fields = VERSION_FIELDS

    def get_readonly_fields(
        self, _request: HttpRequest, obj: NamesVersion | None = None
    ) -> tuple[str, ...]:
        editable = SOURCE_FIELDS if obj is not None and obj.is_editable else ()
        return tuple(field for field in VERSION_FIELDS if field not in editable)

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_delete_permission(self, request: HttpRequest, obj: NamesVersion | None = None) -> bool:
        return super().has_delete_permission(request, obj) and (
            obj is None or obj.status == NamesStatus.DRAFT
        )

    @admin.display(boolean=True, description="Подписана")
    def signed(self, obj: NamesVersion) -> bool:
        return obj.is_signed

    @admin.display(description="Имена")
    def names_link(self, obj: NamesVersion) -> str:
        return format_html(
            '<a href="{}">{}: {}</a>',
            _names_url(obj),
            "Править имена" if obj.is_editable else "Открыть имена",
            obj.names.count(),
        )

    @admin.display(description="Что осталось заполнить")
    def problems(self, obj: NamesVersion) -> str:
        if not obj.is_editable:
            return "—"
        found = version_problems(obj)
        if not found:
            return "Всё заполнено: версию можно подписать."
        return format_html(
            "<ul>{}</ul>", format_html_join("", "<li>{}</li>", ((line,) for line in found))
        )

    @admin.display(description="Список для проверки (русский)")
    def review_preview(self, obj: NamesVersion) -> str:
        """Every card as the reader sees it, for the religious sign-off."""
        return format_html(
            "<ol>{}</ol>",
            format_html_join(
                "",
                '<li value="{}"><span dir="rtl" lang="ar" style="font-size:22px">{}</span> '
                "<b>{}</b> — {}<br>{}<br><i>{}</i></li>",
                (
                    (
                        name.position,
                        name.arabic,
                        name.transliteration_ru,
                        name.meaning_ru,
                        name.tafsir_ru,
                        " · ".join(
                            part
                            for part in (
                                f"Коран {name.surah}:{name.ayah}" if name.surah else "",
                                f"слово {name.word_position}" if name.word_position else "",
                                name.tafsir_ref,
                            )
                            if part
                        ),
                    )
                    for name in obj.names.all()
                ),
            ),
        )

    # The actions change a version: they need the change permission.
    @admin.action(permissions=["change"], description="Подписать: религиозная проверка пройдена")
    def sign_versions(self, request: HttpRequest, queryset: QuerySet[NamesVersion]) -> None:
        for version in queryset.filter(status=NamesStatus.DRAFT, reviewed_at=None):
            try:
                sign_names_version(version, request.user)
            except NamesError as error:
                more = f" И ещё {len(error.problems) - 5}." if len(error.problems) > 5 else ""
                self.message_user(
                    request,
                    f"{version}: не подписана. {' '.join(error.problems[:5])}{more}",
                    messages.ERROR,
                )
            else:
                self.message_user(request, f"{version}: подписана.", messages.SUCCESS)

    @admin.action(permissions=["change"], description="Опубликовать")
    def publish_versions(self, request: HttpRequest, queryset: QuerySet[NamesVersion]) -> None:
        for version in queryset:
            try:
                publish_names_version(version)
            except NamesError as error:
                self.message_user(request, f"{version}: {error}", messages.ERROR)
            else:
                self.message_user(request, f"{version}: опубликована.", messages.SUCCESS)

    @admin.action(permissions=["change"], description="Создать черновик-копию для правок")
    def copy_versions(self, request: HttpRequest, queryset: QuerySet[NamesVersion]) -> None:
        for source in queryset.select_related("collection"):
            taken = set(source.collection.versions.values_list("version", flat=True))
            day = timezone.localdate().isoformat()
            name = next(
                candidate
                for candidate in (day, *(f"{day}-{number}" for number in range(2, 1000)))
                if candidate not in taken
            )
            draft = copy_names_version(source, name)
            self.log_addition(request, draft, f"Черновик из версии {source.version}.")
            self.message_user(
                request,
                f"Создан черновик {draft}: копия версии {source.version}. "
                "Исходная версия не изменилась.",
                messages.SUCCESS,
            )


@admin.register(DivineName)
class DivineNameAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = (
        "position",
        "arabic_name",
        "transliteration_ru",
        "meaning_ru",
        "quran",
        "version",
    )
    list_display_links = ("position", "arabic_name")
    list_filter = ("version",)
    search_fields = ("arabic", "transliteration_ru", "transliteration_en", "meaning_ru", "slug")
    ordering = ("version", "position")
    list_per_page = 120
    fieldsets = (
        (None, {"fields": ("version", "position", "slug", "arabic")}),
        ("Русский", {"fields": ("transliteration_ru", "meaning_ru", "tafsir_ru")}),
        ("Английский", {"fields": ("transliteration_en", "meaning_en", "tafsir_en")}),
        ("Турецкий", {"fields": ("transliteration_tr", "meaning_tr", "tafsir_tr")}),
        ("Арабский", {"fields": ("meaning_ar", "tafsir_ar")}),
        ("В Коране и звук", {"fields": ("surah", "ayah", "word_position", "tafsir_ref")}),
    )

    @admin.display(description="Имя", ordering="arabic")
    def arabic_name(self, obj: DivineName) -> str:
        return format_html('<span dir="rtl" lang="ar" style="font-size:20px">{}</span>', obj.arabic)

    @admin.display(description="В Коране")
    def quran(self, obj: DivineName) -> str:
        if not obj.surah:
            return "—"
        word = f", слово {obj.word_position}" if obj.word_position else ""
        return f"{obj.surah}:{obj.ayah}{word}"

    def changelist_view(
        self, request: HttpRequest, extra_context: dict[str, Any] | None = None
    ) -> HttpResponse:
        """Without a chosen version the list opens on the one being worked on."""
        if not request.GET:
            version = (
                NamesVersion.objects.filter(status=NamesStatus.DRAFT).first()
                or NamesVersion.objects.filter(status=NamesStatus.PUBLISHED).first()
            )
            if version is not None:
                return HttpResponseRedirect(_names_url(version))
        return super().changelist_view(request, extra_context)

    def get_readonly_fields(
        self, _request: HttpRequest, obj: DivineName | None = None
    ) -> tuple[str, ...]:
        # A name does not move to another version.
        return ("version",) if obj is not None else ()

    def formfield_for_foreignkey(
        self, db_field: ForeignKey[Any, Any], request: HttpRequest, **kwargs: Any
    ) -> ModelChoiceField[Any] | None:
        if db_field.name == "version":
            kwargs["queryset"] = NamesVersion.objects.filter(
                status=NamesStatus.DRAFT, reviewed_at=None
            )
        return super().formfield_for_foreignkey(db_field, request, **kwargs)

    def has_change_permission(self, request: HttpRequest, obj: DivineName | None = None) -> bool:
        return super().has_change_permission(request, obj) and (
            obj is None or obj.version.is_editable
        )

    def has_delete_permission(self, request: HttpRequest, obj: DivineName | None = None) -> bool:
        return super().has_delete_permission(request, obj) and (
            obj is None or obj.version.is_editable
        )


@admin.register(NamesDocument)
class NamesDocumentAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("version", "language", "bytes")
    list_filter = ("language",)
    readonly_fields = ("version", "language", "checksum_sha256", "bytes", "payload")

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_change_permission(self, request: HttpRequest, obj: NamesDocument | None = None) -> bool:
        return False if obj is not None else super().has_change_permission(request, obj)

    def has_delete_permission(self, request: HttpRequest, obj: NamesDocument | None = None) -> bool:
        """A published or withdrawn version keeps its documents: the API serves them."""
        return super().has_delete_permission(request, obj) and (
            obj is None or obj.version.status == NamesStatus.DRAFT
        )
