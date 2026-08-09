from __future__ import annotations

import math
from collections.abc import Mapping
from decimal import Decimal
from typing import Any, cast

from drf_spectacular.extensions import OpenApiSerializerExtension
from drf_spectacular.utils import PolymorphicProxySerializer, extend_schema_field
from rest_framework import serializers

from quran_backend.modules.core.serializers import StrictFieldsSerializer, UUIDv7Field
from quran_backend.modules.reading.models import SyncAction, SyncEntityType, SyncOutcome
from quran_backend.modules.reminders.serializers import (
    ReminderFunctionalSerializer,
    ReminderPatchFunctionalSerializer,
    ReminderSyncOutputSerializer,
)

READING_ANCHOR_SCHEMA: dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "x_ratio": {"type": "number", "format": "double", "minimum": 0, "maximum": 1},
        "y_ratio": {"type": "number", "format": "double", "minimum": 0, "maximum": 1},
        "line_number": {"type": "integer", "minimum": 1, "maximum": 30},
    },
}


@extend_schema_field(READING_ANCHOR_SCHEMA)
class ReadingAnchorSerializer(serializers.Serializer[Any]):
    """A compact, forward-compatible position inside a rendered Mushaf page."""

    x_ratio = serializers.FloatField(min_value=0, max_value=1, required=False)
    y_ratio = serializers.FloatField(min_value=0, max_value=1, required=False)
    line_number = serializers.IntegerField(min_value=1, max_value=30, required=False)

    def to_internal_value(self, data: Any) -> dict[str, Any]:
        if not isinstance(data, Mapping):
            raise serializers.ValidationError("Expected an object.")
        unknown_fields = sorted(set(data) - set(self.fields))
        if unknown_fields:
            raise serializers.ValidationError(
                dict.fromkeys(unknown_fields, "Unknown anchor field.")
            )
        type_errors: dict[str, str] = {}
        for field in ("x_ratio", "y_ratio"):
            value = data.get(field)
            if field in data and (isinstance(value, bool) or not isinstance(value, (int, float))):
                type_errors[field] = "A JSON number is required."
        line_number = data.get("line_number")
        if "line_number" in data and (
            isinstance(line_number, bool) or not isinstance(line_number, int)
        ):
            type_errors["line_number"] = "A JSON integer is required."
        if type_errors:
            raise serializers.ValidationError(type_errors)
        return dict(super().to_internal_value(data))

    def validate_x_ratio(self, value: float) -> float:
        return self._validate_finite_ratio(value)

    def validate_y_ratio(self, value: float) -> float:
        return self._validate_finite_ratio(value)

    @staticmethod
    def _validate_finite_ratio(value: float) -> float:
        if not math.isfinite(value):
            raise serializers.ValidationError("A finite number is required.")
        return value


class ReadingPositionPayloadSerializer(serializers.Serializer[Any]):
    edition_code = serializers.SlugField(max_length=64)
    page_number = serializers.IntegerField(min_value=1, max_value=604)
    surah_number = serializers.IntegerField(min_value=1, max_value=114, required=False)
    ayah_number = serializers.IntegerField(min_value=1, required=False)
    intra_page_anchor = ReadingAnchorSerializer(required=False, default=dict)
    progress_percent = serializers.DecimalField(
        max_digits=5,
        decimal_places=2,
        min_value=0,
        max_value=100,
        required=False,
        default=Decimal("0"),
    )
    last_read_at = serializers.DateTimeField()

    def validate(self, attrs: dict[str, Any]) -> dict[str, Any]:
        surah_number = attrs.get("surah_number")
        ayah_number = attrs.get("ayah_number")
        if (surah_number is None) != (ayah_number is None):
            raise serializers.ValidationError(
                "surah_number and ayah_number must be provided together."
            )
        return attrs


class ReadingPositionWriteSerializer(ReadingPositionPayloadSerializer):
    base_revision = serializers.IntegerField(min_value=0)
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(required=False, allow_null=True)


class BookmarkPayloadSerializer(serializers.Serializer[Any]):
    edition_code = serializers.SlugField(max_length=64, required=False)
    page_number = serializers.IntegerField(
        min_value=1,
        max_value=604,
        required=False,
        allow_null=True,
    )
    surah_number = serializers.IntegerField(
        min_value=1,
        max_value=114,
        required=False,
        allow_null=True,
    )
    ayah_number = serializers.IntegerField(min_value=1, required=False, allow_null=True)
    label = serializers.CharField(  # type: ignore[assignment]
        max_length=120,
        required=False,
        allow_blank=True,
    )
    color_key = serializers.RegexField(
        regex=r"^[a-z0-9][a-z0-9_-]{0,31}$",
        required=False,
    )
    note = serializers.CharField(max_length=2000, required=False, allow_blank=True)

    def validate(self, attrs: dict[str, Any]) -> dict[str, Any]:
        has_surah = "surah_number" in attrs and attrs["surah_number"] is not None
        has_ayah = "ayah_number" in attrs and attrs["ayah_number"] is not None
        clears_surah = "surah_number" in attrs and attrs["surah_number"] is None
        clears_ayah = "ayah_number" in attrs and attrs["ayah_number"] is None
        if has_surah != has_ayah or clears_surah != clears_ayah:
            raise serializers.ValidationError(
                "surah_number and ayah_number must be set or cleared together."
            )
        return attrs


class BookmarkCreateSerializer(BookmarkPayloadSerializer):
    id = UUIDv7Field(
        help_text=(
            "Client-generated UUIDv7 used as the idempotent bookmark identity. "
            "A new unseen id must be inside the configured offline age window."
        )
    )
    edition_code = serializers.SlugField(max_length=64)
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(required=False, allow_null=True)

    def validate(self, attrs: dict[str, Any]) -> dict[str, Any]:
        attrs = super().validate(attrs)
        if "edition_code" not in attrs:
            raise serializers.ValidationError({"edition_code": "This field is required."})
        has_page = attrs.get("page_number") is not None
        has_ayah = attrs.get("ayah_number") is not None
        if not has_page and not has_ayah:
            raise serializers.ValidationError("A page or ayah target is required.")
        return attrs


class BookmarkUpdateSerializer(BookmarkPayloadSerializer):
    base_revision = serializers.IntegerField(min_value=1)
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(required=False, allow_null=True)


class BookmarkDeleteSerializer(serializers.Serializer[Any]):
    base_revision = serializers.IntegerField(min_value=1)
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(required=False, allow_null=True)


class SyncOperationInputSerializer(StrictFieldsSerializer):
    operation_id = serializers.UUIDField()
    entity_type = serializers.ChoiceField(choices=SyncEntityType.choices)
    entity_id = serializers.UUIDField(
        help_text=(
            "Bookmark and reminder entity_id values must be client-generated UUIDv7 identifiers."
        )
    )
    action = serializers.ChoiceField(choices=SyncAction.choices)
    base_revision = serializers.IntegerField(min_value=0)
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(required=False, allow_null=True)
    payload = serializers.JSONField(required=False, default=dict)

    def validate(self, attrs: dict[str, Any]) -> dict[str, Any]:  # noqa: PLR0912
        entity_type = attrs["entity_type"]
        action = attrs["action"]
        payload = attrs.get("payload", {})
        base_revision = attrs["base_revision"]

        if (
            entity_type in {SyncEntityType.BOOKMARK, SyncEntityType.REMINDER}
            and attrs["entity_id"].version != 7
        ):
            raise serializers.ValidationError(
                {
                    "entity_id": (
                        f"{entity_type.replace('_', ' ').title()} identifiers must use UUIDv7."
                    )
                }
            )

        if entity_type == SyncEntityType.READING_POSITION:
            if action != SyncAction.UPSERT:
                raise serializers.ValidationError(
                    {"action": "Reading positions support only upsert."}
                )
            payload_serializer: serializers.Serializer[Any] = ReadingPositionPayloadSerializer(
                data=payload
            )
        elif entity_type == SyncEntityType.BOOKMARK and action == SyncAction.DELETE:
            if payload:
                raise serializers.ValidationError(
                    {"payload": "Delete operations must have an empty payload."}
                )
            attrs["payload"] = {}
            return attrs
        elif entity_type == SyncEntityType.BOOKMARK:
            payload_serializer = BookmarkPayloadSerializer(
                data=payload,
                partial=base_revision > 0,
            )
        elif entity_type == SyncEntityType.REMINDER:
            if "device_id" in attrs:
                raise serializers.ValidationError(
                    {"device_id": "Reminder device provenance comes from the access token."}
                )
            if action == SyncAction.DELETE:
                if base_revision == 0:
                    raise serializers.ValidationError(
                        {"base_revision": "Reminder deletes require an existing revision."}
                    )
                if payload:
                    raise serializers.ValidationError(
                        {"payload": "Delete operations must have an empty payload."}
                    )
                attrs["payload"] = {}
                return attrs
            payload_serializer = (
                ReminderFunctionalSerializer(data=payload)
                if base_revision == 0
                else ReminderPatchFunctionalSerializer(data=payload)
            )
        else:  # pragma: no cover - ChoiceField rejects unknown values first.
            raise serializers.ValidationError({"entity_type": "Unsupported sync entity type."})

        payload_serializer.is_valid(raise_exception=True)
        validated_payload = dict(payload_serializer.validated_data)
        if entity_type == SyncEntityType.BOOKMARK and base_revision == 0:
            has_target = (
                validated_payload.get("page_number") is not None
                or validated_payload.get("ayah_number") is not None
            )
            if "edition_code" not in validated_payload or not has_target:
                raise serializers.ValidationError(
                    {"payload": "New bookmarks require edition_code and a page or ayah target."}
                )
        attrs["payload"] = validated_payload
        return attrs


class EmptySyncPayloadSerializer(StrictFieldsSerializer):
    """An empty JSON object. Omission is equivalent to ``{}`` for delete operations."""


class ReadingPositionSyncOperationSerializer(StrictFieldsSerializer):
    """Schema-only reading-position upsert contract."""

    operation_id = serializers.UUIDField()
    entity_type = serializers.ChoiceField(choices=[SyncEntityType.READING_POSITION])
    entity_id = serializers.UUIDField()
    action = serializers.ChoiceField(choices=[SyncAction.UPSERT])
    base_revision = serializers.IntegerField(
        min_value=0,
        help_text=(
            "Use 0 to create the position; otherwise send the exact current revision. "
            "A mismatch is returned as a per-operation conflict."
        ),
    )
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(required=False, allow_null=True)
    payload = ReadingPositionPayloadSerializer()


class BookmarkSyncCreatePayloadSerializer(BookmarkPayloadSerializer):
    """New-bookmark payload; a page or complete ayah target is also required."""

    edition_code = serializers.SlugField(max_length=64)


class BookmarkSyncCreateOperationSerializer(StrictFieldsSerializer):
    """Schema-only bookmark create contract (upsert at base revision 0)."""

    operation_id = serializers.UUIDField()
    entity_type = serializers.ChoiceField(choices=[SyncEntityType.BOOKMARK])
    entity_id = UUIDv7Field()
    action = serializers.ChoiceField(choices=[SyncAction.UPSERT])
    base_revision = serializers.IntegerField(min_value=0, max_value=0)
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(required=False, allow_null=True)
    payload = BookmarkSyncCreatePayloadSerializer(
        help_text="Requires edition_code and either page_number or an ayah-number pair."
    )


class BookmarkSyncPatchOperationSerializer(StrictFieldsSerializer):
    """Schema-only bookmark patch contract (upsert at an existing revision)."""

    operation_id = serializers.UUIDField()
    entity_type = serializers.ChoiceField(choices=[SyncEntityType.BOOKMARK])
    entity_id = UUIDv7Field()
    action = serializers.ChoiceField(choices=[SyncAction.UPSERT])
    base_revision = serializers.IntegerField(min_value=1)
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(required=False, allow_null=True)
    payload = BookmarkPayloadSerializer(required=False)


class BookmarkSyncDeleteOperationSerializer(StrictFieldsSerializer):
    """Schema-only bookmark delete contract."""

    operation_id = serializers.UUIDField()
    entity_type = serializers.ChoiceField(choices=[SyncEntityType.BOOKMARK])
    entity_id = UUIDv7Field()
    action = serializers.ChoiceField(choices=[SyncAction.DELETE])
    base_revision = serializers.IntegerField(
        min_value=0,
        help_text=(
            "Send the exact current revision. Persisted bookmarks start at revision 1; "
            "base_revision=0 is accepted syntactically and resolves as a conflict."
        ),
    )
    client_updated_at = serializers.DateTimeField()
    device_id = serializers.UUIDField(required=False, allow_null=True)
    payload = EmptySyncPayloadSerializer(required=False)


class ReminderSyncCreateOperationSerializer(StrictFieldsSerializer):
    """Create a reminder with a complete functional payload."""

    operation_id = serializers.UUIDField()
    entity_type = serializers.ChoiceField(choices=[SyncEntityType.REMINDER])
    entity_id = UUIDv7Field()
    action = serializers.ChoiceField(choices=[SyncAction.UPSERT])
    base_revision = serializers.IntegerField(min_value=0, max_value=0)
    client_updated_at = serializers.DateTimeField()
    payload = ReminderFunctionalSerializer()


class ReminderSyncPatchOperationSerializer(StrictFieldsSerializer):
    """Patch an existing reminder at its exact current revision."""

    operation_id = serializers.UUIDField()
    entity_type = serializers.ChoiceField(choices=[SyncEntityType.REMINDER])
    entity_id = UUIDv7Field()
    action = serializers.ChoiceField(choices=[SyncAction.UPSERT])
    base_revision = serializers.IntegerField(min_value=1)
    client_updated_at = serializers.DateTimeField()
    payload = ReminderPatchFunctionalSerializer(required=False)


class ReminderSyncDeleteOperationSerializer(StrictFieldsSerializer):
    """Delete an existing reminder; payload must be omitted or an empty object."""

    operation_id = serializers.UUIDField()
    entity_type = serializers.ChoiceField(choices=[SyncEntityType.REMINDER])
    entity_id = UUIDv7Field()
    action = serializers.ChoiceField(choices=[SyncAction.DELETE])
    base_revision = serializers.IntegerField(min_value=1)
    client_updated_at = serializers.DateTimeField()
    payload = EmptySyncPayloadSerializer(required=False)


def _sync_operation_openapi_proxy() -> PolymorphicProxySerializer:
    bookmark = PolymorphicProxySerializer(
        component_name="BookmarkSyncOperation",
        serializers=[
            BookmarkSyncCreateOperationSerializer,
            BookmarkSyncPatchOperationSerializer,
            BookmarkSyncDeleteOperationSerializer,
        ],
        resource_type_field_name=None,
        many=False,
    )
    reminder = PolymorphicProxySerializer(
        component_name="ReminderSyncOperation",
        serializers=[
            ReminderSyncCreateOperationSerializer,
            ReminderSyncPatchOperationSerializer,
            ReminderSyncDeleteOperationSerializer,
        ],
        resource_type_field_name=None,
        many=False,
    )
    return PolymorphicProxySerializer(
        component_name="SyncOperationInput",
        serializers={
            SyncEntityType.READING_POSITION.value: ReadingPositionSyncOperationSerializer,
            SyncEntityType.BOOKMARK.value: bookmark,
            SyncEntityType.REMINDER.value: reminder,
        },
        resource_type_field_name="entity_type",
        many=False,
    )


class SyncOperationInputSerializerSchema(OpenApiSerializerExtension):  # type: ignore[no-untyped-call]
    """Expose the strict discriminated request union while retaining one runtime validator."""

    target_class = SyncOperationInputSerializer
    priority = 1

    def map_serializer(self, auto_schema: Any, direction: Any) -> dict[str, Any]:
        return cast(
            dict[str, Any],
            auto_schema._map_serializer(_sync_operation_openapi_proxy(), direction),
        )


class SyncPushSerializer(StrictFieldsSerializer):
    operations = SyncOperationInputSerializer(many=True, allow_empty=False)

    def validate_operations(self, operations: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if len(operations) > 100:
            raise serializers.ValidationError("A sync batch cannot exceed 100 operations.")
        operation_ids = [operation["operation_id"] for operation in operations]
        if len(operation_ids) != len(set(operation_ids)):
            raise serializers.ValidationError("operation_id values must be unique within a batch.")
        return operations


class SyncPullQuerySerializer(serializers.Serializer[Any]):
    cursor = serializers.IntegerField(min_value=0, required=False)
    limit = serializers.IntegerField(min_value=1, max_value=200, required=False, default=100)
    full_resync = serializers.BooleanField(required=False, default=False)
    page_token = serializers.CharField(required=False, allow_blank=False, max_length=2048)

    def validate(self, attrs: dict[str, Any]) -> dict[str, Any]:
        full_resync = attrs.get("full_resync", False)
        if attrs.get("page_token") and not full_resync:
            raise serializers.ValidationError(
                {"page_token": "page_token is valid only when full_resync=true."}
            )
        if full_resync and "cursor" in attrs:
            raise serializers.ValidationError(
                {"cursor": "Do not send cursor during a full resync."}
            )
        return attrs


class AyahReferenceOutputSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    surah_number = serializers.IntegerField()
    ayah_number = serializers.IntegerField()


class ReadingPositionOutputSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    entity_type = serializers.ChoiceField(choices=["reading_position"], read_only=True)
    edition_code = serializers.CharField()
    page_number = serializers.IntegerField()
    ayah = AyahReferenceOutputSerializer(allow_null=True)
    intra_page_anchor = ReadingAnchorSerializer()
    progress_percent = serializers.DecimalField(max_digits=5, decimal_places=2)
    last_read_at = serializers.DateTimeField()
    client_updated_at = serializers.DateTimeField()
    revision = serializers.IntegerField()
    device_id = serializers.UUIDField(allow_null=True)
    created_at = serializers.DateTimeField()
    updated_at = serializers.DateTimeField()


class BookmarkOutputSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    entity_type = serializers.ChoiceField(choices=["bookmark"], read_only=True)
    edition_code = serializers.CharField()
    page_number = serializers.IntegerField(allow_null=True)
    ayah = AyahReferenceOutputSerializer(allow_null=True)
    label = serializers.CharField()  # type: ignore[assignment]
    color_key = serializers.CharField()
    note = serializers.CharField()
    client_updated_at = serializers.DateTimeField()
    revision = serializers.IntegerField()
    deleted_at = serializers.DateTimeField(allow_null=True)
    device_id = serializers.UUIDField(allow_null=True)
    created_at = serializers.DateTimeField()
    updated_at = serializers.DateTimeField()


class BookmarkPageOutputSerializer(serializers.Serializer[Any]):
    next = serializers.URLField(allow_null=True)
    previous = serializers.URLField(allow_null=True)
    results = BookmarkOutputSerializer(many=True)


class BookmarkListQuerySerializer(serializers.Serializer[Any]):
    cursor = serializers.CharField(required=False, allow_blank=False, max_length=2048)
    page_size = serializers.IntegerField(min_value=1, max_value=200, required=False, default=50)
    include_deleted = serializers.BooleanField(required=False, default=False)


@extend_schema_field(
    PolymorphicProxySerializer(
        component_name="ReadingSyncEntity",
        serializers={
            "reading_position": ReadingPositionOutputSerializer,
            "bookmark": BookmarkOutputSerializer,
            "reminder": ReminderSyncOutputSerializer,
        },
        resource_type_field_name="entity_type",
    )
)
class ReadingSyncEntityField(serializers.Field[Any, Any, Any, Any]):
    """Output-only pass-through field with a concrete polymorphic OpenAPI contract."""

    def to_representation(self, value: Any) -> Any:
        return value

    def to_internal_value(self, data: Any) -> Any:  # pragma: no cover - output-only field.
        raise NotImplementedError


class SyncOperationResultSerializer(serializers.Serializer[Any]):
    operation_id = serializers.UUIDField()
    outcome = serializers.ChoiceField(choices=SyncOutcome.choices)
    replayed = serializers.BooleanField()
    conflict_reason = serializers.CharField(required=False)
    entity = ReadingSyncEntityField(read_only=True, allow_null=True)
    cursor = serializers.IntegerField()


class SyncPushResponseSerializer(serializers.Serializer[Any]):
    results = SyncOperationResultSerializer(many=True)
    cursor = serializers.IntegerField()


class SyncChangeOutputSerializer(serializers.Serializer[Any]):
    cursor = serializers.IntegerField()
    entity_type = serializers.ChoiceField(choices=SyncEntityType.choices)
    entity_id = serializers.UUIDField()
    action = serializers.ChoiceField(choices=SyncAction.choices)
    revision = serializers.IntegerField()
    entity = ReadingSyncEntityField(read_only=True)
    server_updated_at = serializers.DateTimeField()


class SyncPullResponseSerializer(serializers.Serializer[Any]):
    mode = serializers.ChoiceField(choices=["incremental"], read_only=True)
    changes = SyncChangeOutputSerializer(many=True)
    next_cursor = serializers.IntegerField()
    has_more = serializers.BooleanField()


class FullResyncResponseSerializer(serializers.Serializer[Any]):
    mode = serializers.ChoiceField(choices=["full_resync"], read_only=True)
    entities = serializers.ListField(
        child=ReadingSyncEntityField(read_only=True),
        read_only=True,
    )
    snapshot_cursor = serializers.IntegerField()
    next_page_token = serializers.CharField(allow_null=True)
    has_more = serializers.BooleanField()


class SyncCursorExpiredResponseSerializer(serializers.Serializer[Any]):
    type = serializers.URLField()
    title = serializers.CharField()
    status = serializers.IntegerField()
    code = serializers.CharField()
    detail = serializers.CharField()
    instance = serializers.CharField()
    request_id = serializers.CharField()
    full_resync_required = serializers.BooleanField()
    minimum_valid_cursor = serializers.IntegerField()
    current_cursor = serializers.IntegerField()
