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
        "reminder": "#/components/schemas/ReminderSyncOutput",
    }
    assert schema["components"]["schemas"]["SyncEntityTypeEnum"]["enum"] == [
        "reading_position",
        "bookmark",
        "reminder",
    ]
    reminder_sync_schema = schema["components"]["schemas"]["ReminderSyncOutput"]
    assert "entity_type" in reminder_sync_schema["required"]
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


def test_sync_push_openapi_is_a_strict_discriminated_request_union() -> None:
    schema = cast(
        dict[str, Any],
        SchemaGenerator().get_schema(public=True),  # type: ignore[no-untyped-call]
    )

    sync_push_request = schema["components"]["schemas"]["SyncPushRequest"]
    assert sync_push_request["additionalProperties"] is False
    operation_items = sync_push_request["properties"]["operations"]["items"]
    operation_union = schema["components"]["schemas"][
        operation_items["$ref"].rsplit("/", maxsplit=1)[-1]
    ]
    assert len(operation_union["oneOf"]) == 3
    assert operation_union["discriminator"] == {
        "propertyName": "entity_type",
        "mapping": {
            "reading_position": "#/components/schemas/ReadingPositionSyncOperationRequest",
            "bookmark": "#/components/schemas/BookmarkSyncOperationRequest",
            "reminder": "#/components/schemas/ReminderSyncOperationRequest",
        },
    }
    reminder_operation = schema["components"]["schemas"]["ReminderSyncOperationRequest"]
    assert len(reminder_operation["oneOf"]) == 3
    reminder_variants = [
        schema["components"]["schemas"][item["$ref"].rsplit("/", maxsplit=1)[-1]]
        for item in reminder_operation["oneOf"]
    ]
    create_variant, patch_variant, delete_variant = reminder_variants
    assert create_variant["properties"]["base_revision"] == {
        "type": "integer",
        "maximum": 0,
        "minimum": 0,
    }
    assert create_variant["properties"]["payload"]["$ref"] == (
        "#/components/schemas/ReminderFunctionalRequest"
    )
    assert patch_variant["properties"]["base_revision"]["minimum"] == 1
    assert patch_variant["properties"]["payload"]["$ref"] == (
        "#/components/schemas/ReminderPatchFunctionalRequest"
    )
    assert "payload" not in patch_variant["required"]
    assert delete_variant["properties"]["base_revision"]["minimum"] == 1
    empty_payload_ref = delete_variant["properties"]["payload"]["$ref"]
    empty_payload = schema["components"]["schemas"][empty_payload_ref.rsplit("/", 1)[-1]]
    assert empty_payload == {
        "type": "object",
        "description": (
            "An empty JSON object. Omission is equivalent to ``{}`` for delete operations."
        ),
        "additionalProperties": False,
    }
    assert "payload" not in delete_variant["required"]
    assert "device_id" not in create_variant["properties"]
    assert "device_id" not in patch_variant["properties"]
    assert "device_id" not in delete_variant["properties"]


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

    reminder = {
        "id": "019fe4be-0000-7000-8000-000000000003",
        "entity_type": "reminder",
    }
    reminder_full_resync = FullResyncResponseSerializer(
        {
            "mode": "full_resync",
            "entities": [reminder],
            "snapshot_cursor": 8,
            "next_page_token": None,
            "has_more": False,
        }
    ).data
    assert reminder_full_resync["entities"] == [reminder]


def test_openapi_declares_public_audio_catalog_and_bounded_cursors() -> None:
    schema = cast(
        dict[str, Any],
        SchemaGenerator().get_schema(public=True),  # type: ignore[no-untyped-call]
    )

    paths = schema["paths"]
    expected_paths = {
        "/api/v1/reciters",
        "/api/v1/reciters/{reciter_id}",
        "/api/v1/recitations",
        "/api/v1/recitations/{recitation_id}",
        "/api/v1/recitations/{recitation_id}/tracks",
        "/api/v1/recitations/{recitation_id}/surahs/{surah}",
        "/api/v1/recitations/{recitation_id}/ayahs/{surah}/{ayah}",
    }
    assert expected_paths <= paths.keys()

    recitation_parameters = {
        parameter["name"]: parameter
        for parameter in paths["/api/v1/recitations"]["get"]["parameters"]
    }
    track_parameters = {
        parameter["name"]: parameter
        for parameter in paths["/api/v1/recitations/{recitation_id}/tracks"]["get"]["parameters"]
    }
    assert recitation_parameters["cursor"]["schema"]["maxLength"] == 2048
    assert recitation_parameters["page_size"]["schema"] == {
        "type": "integer",
        "maximum": 100,
        "minimum": 1,
    }
    assert track_parameters["page_size"]["schema"]["maximum"] == 114
    assert track_parameters["scope"]["schema"]["enum"] == ["surah", "juz", "full"]
    assert paths["/api/v1/reciters"]["get"]["security"] == [{}]
    public_responses = paths["/api/v1/reciters"]["get"]["responses"]
    assert set(public_responses["200"]["headers"]) == {"ETag", "Cache-Control"}
    assert set(public_responses["304"]["headers"]) == {"ETag", "Cache-Control"}
    assert "content" not in public_responses["304"]

    timing_schema = schema["components"]["schemas"]["AudioTrack"]["properties"]["timing_version"]
    assert timing_schema["oneOf"][1] == {"type": "null"}
    asset_properties = schema["components"]["schemas"]["AudioAsset"]["properties"]
    assert {"url", "content_type", "bytes", "sha256", "etag"} <= asset_properties.keys()


def test_openapi_declares_device_inventory_and_deletion_lifecycle() -> None:
    schema = cast(
        dict[str, Any],
        SchemaGenerator().get_schema(public=True),  # type: ignore[no-untyped-call]
    )

    paths = schema["paths"]
    assert set(paths["/api/v1/me"]) == {"get", "patch"}
    assert set(paths["/api/v1/me/devices"]) == {"get"}
    assert set(paths["/api/v1/me/devices/{device_id}"]) == {"delete"}
    assert set(paths["/api/v1/me/deletion-request"]) == {"post"}
    assert set(paths["/api/v1/me/deletion-cancel"]) == {"post"}
    assert set(paths["/api/v1/me/devices/{device_id}"]["delete"]["responses"]) == {"204"}
    assert set(paths["/api/v1/me/deletion-request"]["post"]["responses"]) == {"202"}
    assert set(paths["/api/v1/me/deletion-cancel"]["post"]["responses"]) == {"200"}
    inventory_schema = schema["components"]["schemas"]["DeviceInventory"]
    assert {
        "id",
        "platform",
        "locale",
        "app_version",
        "created_at",
        "last_seen_at",
        "active_session_count",
        "is_current",
    } <= set(inventory_schema["required"])
