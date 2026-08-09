from __future__ import annotations

from typing import Any, cast

from drf_spectacular.generators import SchemaGenerator

from quran_backend.modules.reading.serializers import (
    FullResyncResponseSerializer,
    SyncChangeOutputSerializer,
    SyncOperationResultSerializer,
)


def test_openapi_contract_is_31_and_matches_bookmark_concurrency_api() -> None:
    schema = cast(
        dict[str, Any],
        SchemaGenerator().get_schema(public=True),  # type: ignore[no-untyped-call]
    )

    assert schema["openapi"] == "3.1.0"
    bookmark_detail = schema["paths"]["/api/v1/me/bookmarks/{bookmark_id}"]
    assert set(bookmark_detail["delete"]["responses"]) == {"200"}
    update_schema = schema["components"]["schemas"]["BookmarkUpdateRequest"]
    assert set(update_schema["required"]) >= {"base_revision", "client_updated_at"}
    sync_union = schema["components"]["schemas"]["SyncPullOrFullResyncResponse"]
    assert sync_union["discriminator"]["mapping"] == {
        "incremental": "#/components/schemas/SyncPullResponse",
        "full_resync": "#/components/schemas/FullResyncResponse",
    }
    assert "mode" in schema["components"]["schemas"]["SyncPullResponse"]["required"]
    assert "mode" in schema["components"]["schemas"]["FullResyncResponse"]["required"]
    assert schema["components"]["schemas"]["SyncPullResponseModeEnum"]["enum"] == ["incremental"]
    assert schema["components"]["schemas"]["FullResyncResponseModeEnum"]["enum"] == ["full_resync"]
    full_resync_entities = schema["components"]["schemas"]["FullResyncResponse"]["properties"][
        "entities"
    ]
    assert full_resync_entities["type"] == "array"
    assert full_resync_entities["items"]["allOf"][0]["$ref"] == (
        "#/components/schemas/ReadingSyncEntity"
    )
    assert schema["components"]["schemas"]["ReadingSyncEntity"]["discriminator"]["mapping"] == {
        "reading_position": "#/components/schemas/ReadingPositionOutput",
        "bookmark": "#/components/schemas/BookmarkOutput",
    }
    bookmark_parameters = {
        parameter["name"]: parameter
        for parameter in schema["paths"]["/api/v1/me/bookmarks"]["get"]["parameters"]
    }
    assert bookmark_parameters["page_size"]["schema"] == {
        "type": "integer",
        "maximum": 200,
        "minimum": 1,
        "default": 50,
    }
    sync_parameters = {
        parameter["name"]: parameter
        for parameter in schema["paths"]["/api/v1/sync/pull"]["get"]["parameters"]
    }
    assert sync_parameters["limit"]["schema"]["minimum"] == 1
    assert sync_parameters["limit"]["schema"]["maximum"] == 200
    assert sync_parameters["page_token"]["schema"]["maxLength"] == 2048
    delete_parameters = {
        parameter["name"]: parameter for parameter in bookmark_detail["delete"]["parameters"]
    }
    assert delete_parameters["base_revision"]["schema"]["minimum"] == 1
    assert delete_parameters["client_updated_at"]["schema"]["format"] == "date-time"


def test_polymorphic_sync_output_fields_are_safe_at_runtime() -> None:
    entity = {"id": "019fe4be-0000-7000-8000-000000000001", "entity_type": "bookmark"}
    full_resync = FullResyncResponseSerializer(
        {
            "mode": "full_resync",
            "entities": [entity],
            "snapshot_cursor": 7,
            "next_page_token": None,
            "has_more": False,
        }
    ).data
    change = SyncChangeOutputSerializer(
        {
            "cursor": 7,
            "entity_type": "bookmark",
            "entity_id": entity["id"],
            "action": "upsert",
            "revision": 1,
            "entity": entity,
            "server_updated_at": "2026-08-09T00:00:00Z",
        }
    ).data
    operation = SyncOperationResultSerializer(
        {
            "operation_id": "019fe4be-0000-7000-8000-000000000002",
            "outcome": "accepted",
            "replayed": False,
            "entity": entity,
            "cursor": 7,
        }
    ).data

    assert full_resync["entities"] == [entity]
    assert change["entity"] == entity
    assert operation["entity"] == entity
