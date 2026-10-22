from __future__ import annotations

import hashlib
import json
from typing import Any

from rest_framework import serializers

from quran_backend.modules.announcements.models import (
    PLATFORMS,
    ActionType,
    Announcement,
    AnnouncementKind,
    AnnouncementPriority,
    StatEvent,
    StatSurface,
)
from quran_backend.modules.announcements.routes import action_target
from quran_backend.modules.audio.serializers import public_audio_url

MAX_EVENTS_PER_BATCH = 50


def announcement_payload(announcement: Announcement, locale: str) -> dict[str, Any]:
    """The audience-facing announcement in one language, identical for site and app."""
    translation = next(item for item in announcement.translations.all() if item.language == locale)
    reciter = announcement.reciter
    image_key = announcement.image_object_key or (reciter.portrait_object_key if reciter else "")
    image = None
    if image_key:
        image = {
            "url": public_audio_url(image_key),
            "thumb_url": (
                public_audio_url(announcement.thumb_object_key)
                if announcement.thumb_object_key
                else None
            ),
            "width": announcement.image_width if announcement.image_object_key else None,
            "height": announcement.image_height if announcement.image_object_key else None,
            "alt": translation.image_alt,
        }
    illustrations = {step.order: step for step in announcement.step_images.all()}
    steps = []
    for order, step in enumerate(translation.steps or [], start=1):
        illustration = illustrations.get(order)
        steps.append(
            {
                "title": step["title"],
                "text": step["text"],
                "image_url": public_audio_url(illustration.image_object_key)
                if illustration
                else None,
                "width": illustration.image_width if illustration else None,
                "height": illustration.image_height if illustration else None,
            }
        )
    target = action_target(announcement, locale)
    payload: dict[str, Any] = {
        "id": str(announcement.id),
        # Raised by each published edit; lets clients decide whether to show it again.
        "revision": announcement.revision,
        # Raised by «Показать снова»: a mark from an earlier wave no longer hides it.
        "wave": announcement.wave,
        "kind": announcement.kind,
        "priority": announcement.priority,
        "pinned": announcement.pinned,
        "starts_at": announcement.starts_at,
        "ends_at": announcement.display_until,
        "surfaces": {
            "bubble": announcement.channel_bubble,
            "home_card": announcement.channel_home_card,
            "modal": announcement.channel_modal,
        },
        "bubble": {
            "icon": announcement.effective_bubble_icon,
            "frequency": announcement.bubble_frequency,
            "max_impressions": announcement.bubble_max_impressions,
        },
        "audience": {"auth": announcement.audience_auth},
        "title": translation.title,
        "summary": translation.summary,
        "body": translation.body,
        "image": image,
        "steps": steps,
        "action": {
            "type": announcement.action_type,
            "label": translation.cta_label,
            "web_path": target.web_path,
            "app_route": target.app_route,
            "external_url": target.external_url,
        },
    }
    payload["version"] = hashlib.sha256(
        json.dumps(payload, sort_keys=True, default=str, ensure_ascii=False).encode()
    ).hexdigest()[:16]
    return payload


class AnnouncementQuerySerializer(serializers.Serializer[Any]):
    platform = serializers.ChoiceField(choices=PLATFORMS)
    locale = serializers.ChoiceField(choices=("ru", "en", "ar", "tr"))
    app_version = serializers.RegexField(
        r"^\d{1,4}(\.\d{1,4}){0,2}$",
        required=False,
        help_text="Installed app version; ignored for the web.",
    )


class AnnouncementFeedQuerySerializer(AnnouncementQuerySerializer):
    kind = serializers.ChoiceField(choices=AnnouncementKind.choices, required=False)
    cursor = serializers.CharField(required=False, max_length=200)


class AnnouncementImageSerializer(serializers.Serializer[Any]):
    url = serializers.URLField()
    thumb_url = serializers.URLField(allow_null=True)
    width = serializers.IntegerField(allow_null=True)
    height = serializers.IntegerField(allow_null=True)
    alt = serializers.CharField(allow_blank=True)


class AnnouncementStepSerializer(serializers.Serializer[Any]):
    title = serializers.CharField()
    text = serializers.CharField(allow_blank=True)
    image_url = serializers.URLField(allow_null=True)
    width = serializers.IntegerField(allow_null=True)
    height = serializers.IntegerField(allow_null=True)


class AnnouncementActionSerializer(serializers.Serializer[Any]):
    type = serializers.ChoiceField(choices=ActionType.choices)
    label = serializers.CharField(allow_blank=True)  # type: ignore[assignment]
    web_path = serializers.CharField(allow_null=True)
    app_route = serializers.CharField(allow_null=True)
    external_url = serializers.CharField(allow_null=True)


class AnnouncementSurfacesSerializer(serializers.Serializer[Any]):
    bubble = serializers.BooleanField()
    home_card = serializers.BooleanField()
    modal = serializers.BooleanField()


class AnnouncementBubbleSerializer(serializers.Serializer[Any]):
    icon = serializers.CharField()
    frequency = serializers.CharField()
    max_impressions = serializers.IntegerField()


class AnnouncementAudienceSerializer(serializers.Serializer[Any]):
    auth = serializers.ChoiceField(choices=("all", "guests", "signed_in"))


class AnnouncementSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    revision = serializers.IntegerField(min_value=1)
    wave = serializers.IntegerField(min_value=1)
    kind = serializers.ChoiceField(choices=AnnouncementKind.choices)
    priority = serializers.ChoiceField(choices=AnnouncementPriority.choices)
    pinned = serializers.BooleanField()
    starts_at = serializers.DateTimeField()
    ends_at = serializers.DateTimeField()
    surfaces = AnnouncementSurfacesSerializer()
    bubble = AnnouncementBubbleSerializer()
    audience = AnnouncementAudienceSerializer()
    title = serializers.CharField()
    summary = serializers.CharField()
    body = serializers.CharField(allow_blank=True)
    image = AnnouncementImageSerializer(allow_null=True)
    steps = AnnouncementStepSerializer(many=True)
    action = AnnouncementActionSerializer()
    version = serializers.CharField()


class ActiveAnnouncementsSerializer(serializers.Serializer[Any]):
    enabled = serializers.BooleanField()
    results = AnnouncementSerializer(many=True)


class AnnouncementFeedSerializer(serializers.Serializer[Any]):
    next_cursor = serializers.CharField(allow_null=True)
    results = AnnouncementSerializer(many=True)


class AnnouncementReceiptSerializer(serializers.Serializer[Any]):
    announcement_id = serializers.UUIDField()
    read_at = serializers.DateTimeField(allow_null=True)
    dismissed_at = serializers.DateTimeField(allow_null=True)
    wave = serializers.IntegerField(min_value=1)


class AnnouncementReceiptListSerializer(serializers.Serializer[Any]):
    results = AnnouncementReceiptSerializer(many=True)


class AnnouncementReceiptWriteSerializer(serializers.Serializer[Any]):
    read = serializers.BooleanField(default=False)
    dismissed = serializers.BooleanField(default=False)
    wave = serializers.IntegerField(min_value=1, required=False)


class AnnouncementEventSerializer(serializers.Serializer[Any]):
    id = serializers.UUIDField()
    surface = serializers.ChoiceField(choices=StatSurface.choices)
    event = serializers.ChoiceField(choices=StatEvent.choices)
    wave = serializers.IntegerField(min_value=1, required=False)


class AnnouncementEventBatchSerializer(serializers.Serializer[Any]):
    platform = serializers.ChoiceField(choices=PLATFORMS)
    events = AnnouncementEventSerializer(many=True, allow_empty=False)

    def validate_events(self, value: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if len(value) > MAX_EVENTS_PER_BATCH:
            raise serializers.ValidationError(f"Send at most {MAX_EVENTS_PER_BATCH} events.")
        return value


class AnnouncementEventResultSerializer(serializers.Serializer[Any]):
    accepted = serializers.IntegerField()
