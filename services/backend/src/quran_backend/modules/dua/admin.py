from __future__ import annotations

from typing import Any, cast

from django.contrib import admin
from django.http import HttpRequest

from quran_backend.modules.dua.models import (
    DuaAudioAsset,
    DuaCategory,
    DuaCategoryTranslation,
    DuaCollection,
    DuaCollectionVersion,
    DuaEntry,
    DuaEntryTranslation,
    DuaEvidence,
    DuaFavorite,
    DuaPublicationStatus,
    DuaSourceEdition,
)

BASE_READONLY_FIELDS = ("id", "created_at", "updated_at")


def _all_model_fields(obj: Any, *, editable: set[str] | None = None) -> tuple[str, ...]:
    editable = editable or set()
    return tuple(field.name for field in obj._meta.fields if field.name not in editable)


class DuaVersionBoundAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    """Allow catalog rows to be edited only while their version is a draft."""

    actions = None
    readonly_fields = BASE_READONLY_FIELDS
    version_path = "collection_version"
    draft_parent_field = "collection_version"
    draft_parent_status_lookup = "status"

    def _version(self, obj: Any) -> DuaCollectionVersion:
        related = obj
        for attribute in self.version_path.split("__"):
            related = getattr(related, attribute)
        return cast(DuaCollectionVersion, related)

    def get_readonly_fields(
        self,
        request: HttpRequest,
        obj: Any = None,
    ) -> tuple[str, ...]:
        fields = tuple(super().get_readonly_fields(request, obj))
        if obj is not None and self._version(obj).status != DuaPublicationStatus.DRAFT:
            return tuple(dict.fromkeys((*fields, *_all_model_fields(obj))))
        return fields

    def has_delete_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return bool(
            super().has_delete_permission(request, obj)
            and obj is not None
            and self._version(obj).status == DuaPublicationStatus.DRAFT
        )

    def formfield_for_foreignkey(
        self,
        db_field: Any,
        request: HttpRequest,
        **kwargs: Any,
    ) -> Any:
        if db_field.name == self.draft_parent_field:
            kwargs["queryset"] = db_field.remote_field.model._default_manager.filter(
                **{self.draft_parent_status_lookup: DuaPublicationStatus.DRAFT}
            )
        return super().formfield_for_foreignkey(db_field, request, **kwargs)


@admin.register(DuaCollection)
class DuaCollectionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    actions = None
    list_display = ("slug", "active_version", "updated_at")
    search_fields = ("slug",)
    readonly_fields = (*BASE_READONLY_FIELDS, "active_version")

    def get_readonly_fields(
        self,
        request: HttpRequest,
        obj: DuaCollection | None = None,
    ) -> tuple[str, ...]:
        fields = tuple(super().get_readonly_fields(request, obj))
        if obj is not None and obj.versions.exists():
            return tuple(dict.fromkeys((*fields, *_all_model_fields(obj))))
        return fields

    def has_delete_permission(
        self,
        request: HttpRequest,
        obj: DuaCollection | None = None,
    ) -> bool:
        return bool(
            super().has_delete_permission(request, obj)
            and obj is not None
            and not obj.versions.exists()
            and not obj.audio_assets.exists()
            and not obj.favorites.exists()
        )


@admin.register(DuaCollectionVersion)
class DuaCollectionVersionAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    actions = None
    list_display = (
        "collection",
        "version",
        "status",
        "category_count",
        "entry_count",
        "published_at",
    )
    list_filter = ("status", "schema_version")
    search_fields = ("collection__slug", "version", "checksum_sha256")
    list_select_related = ("collection",)
    readonly_fields = (*BASE_READONLY_FIELDS, "status", "published_at")

    def get_readonly_fields(
        self,
        request: HttpRequest,
        obj: DuaCollectionVersion | None = None,
    ) -> tuple[str, ...]:
        fields = tuple(super().get_readonly_fields(request, obj))
        if obj is not None and obj.status != DuaPublicationStatus.DRAFT:
            return tuple(dict.fromkeys((*fields, *_all_model_fields(obj))))
        return fields

    def has_delete_permission(
        self,
        request: HttpRequest,
        obj: DuaCollectionVersion | None = None,
    ) -> bool:
        return bool(
            super().has_delete_permission(request, obj)
            and obj is not None
            and obj.status == DuaPublicationStatus.DRAFT
        )


@admin.register(DuaSourceEdition)
class DuaSourceEditionAdmin(DuaVersionBoundAdmin):
    list_display = ("title", "language_code", "provider", "source_item_id")
    list_filter = ("language_code", "provider")
    search_fields = ("title", "author", "translator", "source_item_id")
    list_select_related = ("collection_version", "collection_version__collection")


@admin.register(DuaCategory)
class DuaCategoryAdmin(DuaVersionBoundAdmin):
    list_display = ("source_number", "slug", "collection_version", "sort_order")
    search_fields = ("slug", "translations__title")
    list_select_related = ("collection_version", "collection_version__collection")


@admin.register(DuaCategoryTranslation)
class DuaCategoryTranslationAdmin(DuaVersionBoundAdmin):
    version_path = "category__collection_version"
    draft_parent_field = "category"
    draft_parent_status_lookup = "collection_version__status"
    list_display = ("category", "language_code", "title")
    list_filter = ("language_code",)
    search_fields = ("title",)
    list_select_related = ("category", "category__collection_version")


@admin.register(DuaEntry)
class DuaEntryAdmin(DuaVersionBoundAdmin):
    list_display = (
        "source_number",
        "slug",
        "category",
        "repetitions",
        "repetition_label",
        "sort_order",
    )
    list_filter = ("collection_version", "category")
    search_fields = ("slug", "arabic_text", "translations__meaning_text")
    list_select_related = ("category", "collection_version", "collection_version__collection")


@admin.register(DuaEntryTranslation)
class DuaEntryTranslationAdmin(DuaVersionBoundAdmin):
    version_path = "entry__collection_version"
    draft_parent_field = "entry"
    draft_parent_status_lookup = "collection_version__status"
    list_display = ("entry", "language_code")
    list_filter = ("language_code",)
    search_fields = ("meaning_text", "transliteration")
    list_select_related = ("entry", "entry__collection_version")


@admin.register(DuaEvidence)
class DuaEvidenceAdmin(DuaVersionBoundAdmin):
    version_path = "entry__collection_version"
    draft_parent_field = "entry"
    draft_parent_status_lookup = "collection_version__status"
    list_display = (
        "entry",
        "kind",
        "source_reference",
        "verification_status",
    )
    list_filter = ("kind", "provider", "verification_status")
    search_fields = ("source_name", "source_reference", "external_id")
    list_select_related = ("entry", "entry__collection_version")


@admin.register(DuaAudioAsset)
class DuaAudioAssetAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    actions = None
    list_display = (
        "source_number",
        "collection_version",
        "delivery_mode",
        "reader_name",
        "provider",
        "is_active",
    )
    list_filter = (
        "collection_version__collection",
        "provider",
        "language_code",
        "is_active",
    )
    search_fields = ("reader_name", "reader_name_ar", "external_url", "object_key")
    list_select_related = ("collection_version", "collection_version__collection")
    readonly_fields = BASE_READONLY_FIELDS

    def get_readonly_fields(
        self,
        request: HttpRequest,
        obj: DuaAudioAsset | None = None,
    ) -> tuple[str, ...]:
        fields = tuple(super().get_readonly_fields(request, obj))
        if (
            obj is not None
            and obj.is_active
            and obj.collection_version.status == DuaPublicationStatus.PUBLISHED
        ):
            immutable = _all_model_fields(obj, editable={"is_active"})
            return tuple(dict.fromkeys((*fields, *immutable)))
        return fields

    def has_delete_permission(
        self,
        request: HttpRequest,
        obj: DuaAudioAsset | None = None,
    ) -> bool:
        return bool(
            super().has_delete_permission(request, obj) and obj is not None and not obj.is_active
        )


@admin.register(DuaFavorite)
class DuaFavoriteAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    list_display = ("user", "collection", "source_number", "created_at")
    list_filter = ("collection",)
    search_fields = ("user__email", "collection__slug")
