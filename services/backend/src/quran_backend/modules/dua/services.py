from __future__ import annotations

from typing import Any

from django.db import transaction

from quran_backend.modules.accounts.models import User
from quran_backend.modules.dua.models import (
    DuaCollection,
    DuaEntry,
    DuaFavorite,
    DuaPublicationStatus,
)


class DuaFavoriteTargetNotFoundError(LookupError):
    pass


def favorite_snapshot(
    *,
    collection_slug: str,
    source_number: int,
    favorite: DuaFavorite | None,
) -> dict[str, Any]:
    return {
        "id": favorite.id if favorite else None,
        "collection": collection_slug,
        "source_number": source_number,
        "is_favorite": favorite is not None,
        "created_at": favorite.created_at if favorite else None,
    }


def list_dua_favorites(user: User) -> dict[str, list[dict[str, Any]]]:
    favorites = DuaFavorite.objects.filter(user=user).select_related("collection")
    return {
        "results": [
            favorite_snapshot(
                collection_slug=favorite.collection.slug,
                source_number=favorite.source_number,
                favorite=favorite,
            )
            for favorite in favorites
        ]
    }


@transaction.atomic
def set_dua_favorite(
    *,
    user: User,
    collection_slug: str,
    source_number: int,
    is_favorite: bool,
) -> dict[str, Any]:
    collection = (
        DuaCollection.objects.select_for_update()
        .filter(
            slug=collection_slug,
            active_version__status=DuaPublicationStatus.PUBLISHED,
        )
        .first()
    )
    if (
        collection is None
        or not DuaEntry.objects.filter(
            collection_version_id=collection.active_version_id,
            source_number=source_number,
        ).exists()
    ):
        raise DuaFavoriteTargetNotFoundError

    favorite = (
        DuaFavorite.objects.select_for_update()
        .filter(
            user=user,
            collection=collection,
            source_number=source_number,
        )
        .first()
    )
    if is_favorite:
        if favorite is None:
            favorite = DuaFavorite.objects.create(
                user=user,
                collection=collection,
                source_number=source_number,
            )
    elif favorite is not None:
        favorite.delete()
        favorite = None

    return favorite_snapshot(
        collection_slug=collection.slug,
        source_number=source_number,
        favorite=favorite,
    )
