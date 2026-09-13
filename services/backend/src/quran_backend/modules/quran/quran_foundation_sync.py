from __future__ import annotations

import hashlib
import json
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Protocol

from django.db import transaction
from django.utils import timezone

from quran_backend.modules.audio.quran_foundation import (
    QuranFoundationClient,
    QuranFoundationEnvironment,
    QuranFoundationError,
    QuranFoundationMushafSyncResult,
)
from quran_backend.modules.quran.models import (
    QuranFoundationMushaf,
    QuranFoundationMushafPage,
    QuranFoundationMushafSyncState,
)

MUSHAF_RESOURCES_FILTER = "mushafs:*"
RELOAD_MUTATIONS = {
    "RESOURCE_CREATE",
    "RESOURCE_INVALIDATE",
    "RESOURCE_UPDATE",
    "ROW_CREATE",
    "ROW_UPDATE",
    "ROW_DELETE",
}


class QuranFoundationMushafSource(Protocol):
    environment: QuranFoundationEnvironment

    def sync_mushaf_catalog(
        self,
        *,
        sync_token: str = "",
        resource_ids: tuple[int, ...] | None = None,
    ) -> QuranFoundationMushafSyncResult: ...

    def get_mushaf_snapshot(self, resource_id: int) -> dict[str, Any]: ...


@dataclass(frozen=True, slots=True)
class MushafCatalogSyncSummary:
    resources: int
    pages: int
    words: int
    removed: int
    changed: bool
    sync_sequence: int


def sync_quran_foundation_mushafs(
    *,
    client: QuranFoundationMushafSource | None = None,
    force: bool = False,
    now: datetime | None = None,
    resource_ids: tuple[int, ...] | None = None,
) -> MushafCatalogSyncSummary:
    if resource_ids is not None and (
        not resource_ids or any(type(value) is not int or value <= 0 for value in resource_ids)
    ):
        raise QuranFoundationError("Mushaf resource IDs must be positive.")
    resources_filter = (
        MUSHAF_RESOURCES_FILTER
        if resource_ids is None
        else ("mushafs:" + ",".join(map(str, sorted(set(resource_ids)))))
    )
    sync_client = client or QuranFoundationClient.from_environment()
    current = now or timezone.now()
    state, _ = QuranFoundationMushafSyncState.objects.get_or_create(
        environment=sync_client.environment.name,
        resources_filter=resources_filter,
    )
    state.last_attempt_at = current
    state.save(update_fields=["last_attempt_at", "updated_at"])

    try:
        result = sync_client.sync_mushaf_catalog(
            sync_token="" if force else state.sync_token,
            **({"resource_ids": resource_ids} if resource_ids is not None else {}),
        )
        reload_ids, deleted_ids = _catalog_actions(result.mutations)
        if resource_ids is not None and not (reload_ids | deleted_ids) <= set(resource_ids):
            raise QuranFoundationError("Quran.Foundation returned an unrequested Mushaf.")
        snapshots = {
            resource_id: sync_client.get_mushaf_snapshot(resource_id)
            for resource_id in sorted(reload_ids)
        }
        resources, pages, words = _apply_catalog(
            environment=sync_client.environment.name,
            snapshots=snapshots,
            deleted_ids=deleted_ids,
            result=result,
            current=current,
            resources_filter=resources_filter,
        )
    except QuranFoundationError:
        state.consecutive_failures += 1
        state.last_error_code = "quran_foundation_error"
        state.save(
            update_fields=[
                "consecutive_failures",
                "last_error_code",
                "updated_at",
            ]
        )
        raise
    return MushafCatalogSyncSummary(
        resources=resources,
        pages=pages,
        words=words,
        removed=len(deleted_ids),
        changed=bool(snapshots or deleted_ids),
        sync_sequence=result.sync_until_sequence,
    )


def _catalog_actions(
    mutations: tuple[dict[str, Any], ...],
) -> tuple[set[int], set[int]]:
    reload_ids: set[int] = set()
    deleted_ids: set[int] = set()
    for mutation in mutations:
        resource_id = _positive_int(mutation.get("resource_id"), "mutation resource ID")
        mutation_type = str(mutation.get("type", ""))
        if mutation_type == "RESOURCE_DELETE":
            deleted_ids.add(resource_id)
            reload_ids.discard(resource_id)
        elif mutation_type in RELOAD_MUTATIONS:
            reload_ids.add(resource_id)
            deleted_ids.discard(resource_id)
    return reload_ids, deleted_ids


@transaction.atomic
def _apply_catalog(  # noqa: PLR0913
    *,
    environment: str,
    snapshots: dict[int, dict[str, Any]],
    deleted_ids: set[int],
    result: QuranFoundationMushafSyncResult,
    current: datetime,
    resources_filter: str = MUSHAF_RESOURCES_FILTER,
) -> tuple[int, int, int]:
    QuranFoundationMushaf.objects.filter(
        environment=environment,
        source_id__in=deleted_ids,
    ).delete()

    page_count = 0
    word_count = 0
    for resource_id, snapshot in snapshots.items():
        pages, words = _replace_snapshot(
            environment=environment,
            resource_id=resource_id,
            snapshot=snapshot,
            current=current,
        )
        page_count += pages
        word_count += words

    state = QuranFoundationMushafSyncState.objects.select_for_update().get(
        environment=environment,
        resources_filter=resources_filter,
    )
    state.sync_token = result.next_sync_token
    state.last_sync_sequence = result.sync_until_sequence
    state.last_success_at = current
    state.consecutive_failures = 0
    state.last_error_code = ""
    state.save(
        update_fields=[
            "sync_token",
            "last_sync_sequence",
            "last_success_at",
            "consecutive_failures",
            "last_error_code",
            "updated_at",
        ]
    )
    resources = QuranFoundationMushaf.objects.filter(
        environment=environment,
        is_available=True,
    ).count()
    return resources, page_count, word_count


def _replace_snapshot(  # noqa: PLR0912
    *,
    environment: str,
    resource_id: int,
    snapshot: dict[str, Any],
    current: datetime,
) -> tuple[int, int]:
    records = snapshot.get("records")
    if not isinstance(records, list):
        raise QuranFoundationError("Quran.Foundation Mushaf snapshot has no records.")
    metadata_rows = [
        row for row in records if isinstance(row, dict) and row.get("record_type") == "mushaf"
    ]
    if len(metadata_rows) != 1:
        raise QuranFoundationError("Quran.Foundation Mushaf snapshot has invalid metadata.")
    metadata = metadata_rows[0]
    if _positive_int(metadata.get("id"), "Mushaf ID") != resource_id:
        raise QuranFoundationError("Quran.Foundation Mushaf snapshot ID does not match.")

    pages_count = _positive_int(metadata.get("pages_count"), "Mushaf page count")
    page_rows = [
        row for row in records if isinstance(row, dict) and row.get("record_type") == "mushaf_page"
    ]
    pages_by_number: dict[int, dict[str, Any]] = {}
    for row in page_rows:
        page_number = _positive_int(row.get("page_number"), "Mushaf page number")
        if page_number in pages_by_number:
            raise QuranFoundationError("Quran.Foundation returned a duplicate Mushaf page.")
        pages_by_number[page_number] = row
    if set(pages_by_number) != set(range(1, pages_count + 1)):
        raise QuranFoundationError(
            f"Quran.Foundation Mushaf {resource_id} has incomplete pages: "
            f"expected {pages_count}, received {len(pages_by_number)}."
        )

    words_by_page: defaultdict[int, list[dict[str, Any]]] = defaultdict(list)
    for row in records:
        if not isinstance(row, dict) or row.get("record_type") != "mushaf_word":
            continue
        word = _normalize_word(row)
        page_number = int(word["page_number"])
        if page_number not in pages_by_number:
            raise QuranFoundationError("Quran.Foundation word references an unknown page.")
        words_by_page[page_number].append(word)
    if set(words_by_page) != set(pages_by_number):
        raise QuranFoundationError("Quran.Foundation Mushaf snapshot has pages without words.")
    for words in words_by_page.values():
        words.sort(key=lambda row: (int(row["position_in_page"]), int(row["id"])))

    qirat = metadata.get("qirat")
    if not isinstance(qirat, dict):
        raise QuranFoundationError("Quran.Foundation Mushaf snapshot has no qira'ah metadata.")
    qirat_name = _required_string(qirat.get("name"), "Mushaf qira'ah")
    checksum = hashlib.sha256(
        json.dumps(
            snapshot,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode()
    ).hexdigest()
    mushaf, _ = QuranFoundationMushaf.objects.update_or_create(
        environment=environment,
        source_id=resource_id,
        defaults={
            "resource_content_id": _optional_int(snapshot.get("resource_content_id")),
            "name": _required_string(metadata.get("name"), "Mushaf name"),
            "description": str(metadata.get("description") or ""),
            "qirat_id": _optional_int(qirat.get("id")),
            "qirat_name": qirat_name,
            "pages_count": pages_count,
            "lines_per_page": _positive_int(
                metadata.get("lines_per_page"),
                "Mushaf lines per page",
            ),
            "default_font_name": _required_string(
                metadata.get("default_font_name"),
                "Mushaf default font",
            ),
            "mapping_mode": _required_string(
                metadata.get("mapping_mode"),
                "Mushaf mapping mode",
            ),
            "schema_version": str(snapshot.get("schema_version", "")),
            "sync_sequence": _non_negative_int(
                snapshot.get("sync_sequence"),
                "Mushaf sync sequence",
            ),
            "source_checksum_sha256": checksum,
            "is_available": True,
            "last_synced_at": current,
        },
    )
    mushaf.cached_pages.all().delete()
    cached_pages = []
    for page_number, page in sorted(pages_by_number.items()):
        cached_pages.append(
            QuranFoundationMushafPage(
                mushaf=mushaf,
                source_id=_positive_int(page.get("id"), "Mushaf page ID"),
                page_number=page_number,
                verse_mapping=_mapping(page.get("verse_mapping"), "verse mapping"),
                first_verse_id=_optional_int(page.get("first_verse_id")),
                last_verse_id=_optional_int(page.get("last_verse_id")),
                first_word_id=_optional_int(page.get("first_word_id")),
                last_word_id=_optional_int(page.get("last_word_id")),
                verses_count=_positive_int(page.get("verses_count"), "page verse count"),
                words=words_by_page[page_number],
            )
        )
    QuranFoundationMushafPage.objects.bulk_create(cached_pages, batch_size=100)
    return len(cached_pages), sum(len(words) for words in words_by_page.values())


def _normalize_word(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": _positive_int(row.get("id"), "Mushaf word ID"),
        "word_id": _optional_int(row.get("word_id")),
        "verse_id": _optional_int(row.get("verse_id")),
        "page_number": _positive_int(row.get("page_number"), "word page number"),
        "line_number": _positive_int(row.get("line_number"), "word line number"),
        "position_in_line": _positive_int(
            row.get("position_in_line"),
            "word line position",
        ),
        "position_in_page": _positive_int(
            row.get("position_in_page"),
            "word page position",
        ),
        "position_in_verse": _optional_int(row.get("position_in_verse")),
        "char_type_id": _optional_int(row.get("char_type_id")),
        "char_type_name": _required_string(row.get("char_type_name"), "word type"),
        "text": _required_string(row.get("text"), "word text"),
        "css_class": str(row.get("css_class") or ""),
        "css_style": str(row.get("css_style") or ""),
    }


def _mapping(value: object, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise QuranFoundationError(f"Quran.Foundation returned an invalid {label}.")
    return dict(value)


def _required_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise QuranFoundationError(f"Quran.Foundation returned an invalid {label}.")
    return value.strip()


def _optional_int(value: object) -> int | None:
    if value is None or value == "":
        return None
    if isinstance(value, bool) or not isinstance(value, (int, str)):
        raise QuranFoundationError("Quran.Foundation returned an invalid integer.")
    try:
        parsed = int(value)
    except (TypeError, ValueError) as exc:
        raise QuranFoundationError("Quran.Foundation returned an invalid integer.") from exc
    if parsed < 0:
        raise QuranFoundationError("Quran.Foundation returned a negative integer.")
    return parsed


def _positive_int(value: object, label: str) -> int:
    parsed = _optional_int(value)
    if parsed is None or parsed <= 0:
        raise QuranFoundationError(f"Quran.Foundation returned an invalid {label}.")
    return parsed


def _non_negative_int(value: object, label: str) -> int:
    parsed = _optional_int(value)
    if parsed is None:
        raise QuranFoundationError(f"Quran.Foundation returned an invalid {label}.")
    return parsed
