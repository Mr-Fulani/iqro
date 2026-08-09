from __future__ import annotations

import uuid
from collections.abc import Mapping
from typing import Any

from drf_spectacular.extensions import OpenApiSerializerExtension
from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers

UUIDV7_PATTERN = (
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-7[0-9a-fA-F]{3}-"
    r"[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
)


class StrictFieldsSerializer(serializers.Serializer[Any]):
    """Reject silently ignored input keys at every request nesting level."""

    def to_internal_value(self, data: Any) -> dict[str, Any]:
        if isinstance(data, Mapping):
            unknown = sorted(str(key) for key in data if key not in self.fields)
            if unknown:
                raise serializers.ValidationError(
                    {key: ["Unknown field."] for key in unknown},
                    code="unknown_field",
                )
        return dict(super().to_internal_value(data))


@extend_schema_field(
    {
        "type": "string",
        "format": "uuid",
        "pattern": UUIDV7_PATTERN,
        "description": "Client-generated UUIDv7.",
    }
)
class UUIDv7Field(serializers.UUIDField):
    def to_internal_value(self, data: Any) -> uuid.UUID:
        value = super().to_internal_value(data)
        if value.version != 7:
            raise serializers.ValidationError("A UUIDv7 value is required.", code="invalid")
        return value


class StrictFieldsSerializerSchema(  # type: ignore[no-untyped-call]
    OpenApiSerializerExtension
):
    """Make the generated JSON Schema match strict runtime validation."""

    target_class = StrictFieldsSerializer
    match_subclasses = True

    def map_serializer(self, auto_schema: Any, direction: Any) -> dict[str, Any]:
        schema: dict[str, Any] = auto_schema._map_serializer(
            self.target,
            direction,
            bypass_extensions=True,
        )
        schema["additionalProperties"] = False
        return schema
