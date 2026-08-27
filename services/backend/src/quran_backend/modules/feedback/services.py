from __future__ import annotations

import hashlib
import json
import uuid
from datetime import datetime, timedelta
from typing import Any

from django.conf import settings
from django.db import transaction
from django.db.models import QuerySet
from django.utils import timezone

from quran_backend.modules.accounts.models import User
from quran_backend.modules.feedback.exceptions import (
    FeedbackConflict,
    FeedbackLimitReached,
    FeedbackTicketNotFound,
)
from quran_backend.modules.feedback.models import (
    FeedbackAudit,
    FeedbackAuditAction,
    FeedbackAuthorType,
    FeedbackCategory,
    FeedbackContext,
    FeedbackMessage,
    FeedbackPriority,
    FeedbackStatus,
    FeedbackTicket,
    FeedbackVisibility,
)
from quran_backend.modules.feedback.tasks import (
    send_feedback_operator_notification_task,
    send_feedback_reporter_notification_task,
)

TERMINAL_STATUSES = {
    FeedbackStatus.REJECTED,
    FeedbackStatus.DUPLICATE,
}
REOPENABLE_STATUSES = {FeedbackStatus.RESOLVED, FeedbackStatus.CLOSED}
ACTIVE_STATUSES = {
    FeedbackStatus.NEW,
    FeedbackStatus.TRIAGED,
    FeedbackStatus.IN_PROGRESS,
    FeedbackStatus.WAITING_FOR_USER,
}

OPERATOR_TRANSITIONS: dict[str, set[str]] = {
    FeedbackStatus.NEW: {
        FeedbackStatus.TRIAGED,
        FeedbackStatus.IN_PROGRESS,
        FeedbackStatus.REJECTED,
        FeedbackStatus.DUPLICATE,
        FeedbackStatus.CLOSED,
    },
    FeedbackStatus.TRIAGED: {
        FeedbackStatus.IN_PROGRESS,
        FeedbackStatus.WAITING_FOR_USER,
        FeedbackStatus.RESOLVED,
        FeedbackStatus.REJECTED,
        FeedbackStatus.DUPLICATE,
        FeedbackStatus.CLOSED,
    },
    FeedbackStatus.IN_PROGRESS: {
        FeedbackStatus.TRIAGED,
        FeedbackStatus.WAITING_FOR_USER,
        FeedbackStatus.RESOLVED,
        FeedbackStatus.REJECTED,
        FeedbackStatus.DUPLICATE,
        FeedbackStatus.CLOSED,
    },
    FeedbackStatus.WAITING_FOR_USER: {
        FeedbackStatus.IN_PROGRESS,
        FeedbackStatus.RESOLVED,
        FeedbackStatus.CLOSED,
    },
    FeedbackStatus.RESOLVED: {FeedbackStatus.CLOSED, FeedbackStatus.TRIAGED},
    FeedbackStatus.REJECTED: {FeedbackStatus.TRIAGED},
    FeedbackStatus.DUPLICATE: {FeedbackStatus.TRIAGED},
    FeedbackStatus.CLOSED: {FeedbackStatus.TRIAGED},
}


def _request_fingerprint(data: dict[str, Any], channel: str, locale: str) -> str:
    fingerprint_data = {
        "category": data["category"],
        "subject": data["subject"],
        "message": data["message"],
        "client_message_id": data["client_message_id"],
        "contact_email": data.get("contact_email"),
        "context": data.get("context", {}),
        "channel": channel,
        "locale": locale,
    }
    canonical = json.dumps(
        fingerprint_data,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        default=str,
    ).encode()
    return hashlib.sha256(canonical).hexdigest()


def feedback_routing(category: str) -> tuple[str, str]:
    if category == FeedbackCategory.RELIGIOUS_CONTENT:
        return FeedbackPriority.HIGH, "religious_editorial"
    if category in {FeedbackCategory.PAGE_LAYOUT, FeedbackCategory.AUDIO}:
        return FeedbackPriority.HIGH, "content_quality"
    if category == FeedbackCategory.ADVERTISEMENT:
        return FeedbackPriority.NORMAL, "advertising"
    if category == FeedbackCategory.ACCOUNT_SYNC:
        return FeedbackPriority.NORMAL, "support"
    if category == FeedbackCategory.TECHNICAL:
        return FeedbackPriority.NORMAL, "engineering_support"
    return FeedbackPriority.NORMAL, "general_support"


def sla_due_at(category: str, priority: str, *, now: datetime) -> datetime | None:
    if priority == FeedbackPriority.CRITICAL:
        return now + timedelta(hours=4)
    if priority == FeedbackPriority.HIGH:
        return now + timedelta(hours=24)
    if category in {FeedbackCategory.TECHNICAL, FeedbackCategory.ACCOUNT_SYNC}:
        return now + timedelta(hours=24)
    return None


def record_audit(  # noqa: PLR0913
    *,
    ticket: FeedbackTicket,
    actor: User | None,
    actor_type: str,
    action: str,
    old_values: dict[str, Any] | None = None,
    new_values: dict[str, Any] | None = None,
    reason: str = "",
) -> FeedbackAudit:
    return FeedbackAudit.objects.create(
        ticket=ticket,
        actor=actor,
        actor_type=actor_type,
        action=action,
        old_values=_json_safe(old_values or {}),
        new_values=_json_safe(new_values or {}),
        reason=reason,
    )


def _json_safe(values: dict[str, Any]) -> dict[str, Any]:
    return {
        key: (
            value.isoformat()
            if isinstance(value, datetime)
            else str(value)
            if isinstance(value, uuid.UUID)
            else value
        )
        for key, value in values.items()
    }


@transaction.atomic
def create_ticket(
    reporter: User,
    data: dict[str, Any],
    *,
    channel: str,
) -> tuple[FeedbackTicket, bool]:
    User.objects.select_for_update().only("id").get(pk=reporter.pk)
    locale = str(data.get("locale") or reporter.preferred_locale)
    fingerprint = _request_fingerprint(data, channel, locale)
    existing = FeedbackTicket.objects.filter(
        reporter=reporter,
        client_request_id=data["client_request_id"],
    ).first()
    if existing is not None:
        if existing.request_fingerprint != fingerprint:
            raise FeedbackConflict(
                "client_request_id was already used with different feedback content."
            )
        return existing, False

    max_open = int(getattr(settings, "FEEDBACK_MAX_OPEN_TICKETS_PER_USER", 20))
    active_count = FeedbackTicket.objects.filter(
        reporter=reporter,
        status__in=ACTIVE_STATUSES,
    ).count()
    if active_count >= max_open:
        raise FeedbackLimitReached(
            "Close an existing active feedback ticket before creating another one."
        )

    now = timezone.now()
    priority, team = feedback_routing(str(data["category"]))
    ticket = FeedbackTicket.objects.create(
        reporter=reporter,
        client_request_id=data["client_request_id"],
        request_fingerprint=fingerprint,
        category=data["category"],
        subject=data["subject"],
        priority=priority,
        locale=locale,
        channel=channel,
        contact_email=data.get("contact_email"),
        team=team,
        sla_response_due_at=sla_due_at(str(data["category"]), priority, now=now),
        last_public_message_at=now,
    )
    context = dict(data.get("context", {}))
    FeedbackContext.objects.create(ticket=ticket, **context)
    initial_message = FeedbackMessage.objects.create(
        ticket=ticket,
        client_message_id=data["client_message_id"],
        author=reporter,
        author_type=FeedbackAuthorType.REPORTER,
        visibility=FeedbackVisibility.PUBLIC,
        body=data["message"],
    )
    record_audit(
        ticket=ticket,
        actor=reporter,
        actor_type=FeedbackAuthorType.REPORTER,
        action=FeedbackAuditAction.CREATED,
        new_values={
            "status": ticket.status,
            "category": ticket.category,
            "priority": ticket.priority,
            "team": ticket.team,
            "initial_message_id": initial_message.id,
        },
    )
    _notify_operator_after_commit(ticket.id, initial_message.id, "created")
    return ticket, True


def list_tickets(reporter: User) -> QuerySet[FeedbackTicket]:
    return FeedbackTicket.objects.filter(reporter=reporter)


def get_ticket(reporter: User, public_id: str, *, for_update: bool = False) -> FeedbackTicket:
    queryset = FeedbackTicket.objects.filter(reporter=reporter)
    if for_update:
        queryset = queryset.select_for_update()
    ticket = queryset.filter(public_id=public_id).first()
    if ticket is None:
        raise FeedbackTicketNotFound
    return ticket


@transaction.atomic
def close_ticket(reporter: User, public_id: str, *, reason: str = "") -> FeedbackTicket:
    ticket = get_ticket(reporter, public_id, for_update=True)
    if ticket.status == FeedbackStatus.CLOSED:
        return ticket
    if ticket.status in TERMINAL_STATUSES:
        raise FeedbackConflict("Rejected or duplicate tickets cannot be closed by the reporter.")
    old_status = ticket.status
    now = timezone.now()
    ticket.status = FeedbackStatus.CLOSED
    ticket.closed_at = now
    ticket.save(update_fields=["status", "closed_at", "updated_at"])
    record_audit(
        ticket=ticket,
        actor=reporter,
        actor_type=FeedbackAuthorType.REPORTER,
        action=FeedbackAuditAction.STATUS_CHANGED,
        old_values={"status": old_status},
        new_values={"status": ticket.status},
        reason=reason,
    )
    return ticket


def _reopen_locked(ticket: FeedbackTicket, reporter: User, *, reason: str) -> None:
    old_status = ticket.status
    now = timezone.now()
    ticket.status = FeedbackStatus.NEW
    ticket.closed_at = None
    ticket.resolved_at = None
    ticket.reopened_at = now
    ticket.reopen_count += 1
    ticket.sla_response_due_at = sla_due_at(ticket.category, ticket.priority, now=now)
    ticket.save(
        update_fields=[
            "status",
            "closed_at",
            "resolved_at",
            "reopened_at",
            "reopen_count",
            "sla_response_due_at",
            "updated_at",
        ]
    )
    record_audit(
        ticket=ticket,
        actor=reporter,
        actor_type=FeedbackAuthorType.REPORTER,
        action=FeedbackAuditAction.REOPENED,
        old_values={"status": old_status},
        new_values={"status": ticket.status, "reopen_count": ticket.reopen_count},
        reason=reason,
    )


@transaction.atomic
def reopen_ticket(reporter: User, public_id: str, *, reason: str = "") -> FeedbackTicket:
    ticket = get_ticket(reporter, public_id, for_update=True)
    if ticket.status in REOPENABLE_STATUSES:
        _reopen_locked(ticket, reporter, reason=reason)
        return ticket
    if ticket.status == FeedbackStatus.NEW and ticket.reopened_at is not None:
        return ticket
    raise FeedbackConflict("Only a resolved or closed ticket can be reopened by the reporter.")


@transaction.atomic
def add_reporter_message(
    reporter: User,
    public_id: str,
    data: dict[str, Any],
) -> tuple[FeedbackTicket, FeedbackMessage, bool]:
    ticket = get_ticket(reporter, public_id, for_update=True)
    existing = FeedbackMessage.objects.filter(
        ticket=ticket,
        client_message_id=data["client_message_id"],
    ).first()
    if existing is not None:
        if (
            existing.author_id != reporter.id
            or existing.author_type != FeedbackAuthorType.REPORTER
            or existing.visibility != FeedbackVisibility.PUBLIC
            or existing.body != data["body"]
        ):
            raise FeedbackConflict(
                "client_message_id was already used with different message content."
            )
        return ticket, existing, False

    if ticket.status in TERMINAL_STATUSES:
        raise FeedbackConflict("Messages cannot be added to a rejected or duplicate ticket.")
    max_messages = int(getattr(settings, "FEEDBACK_MAX_MESSAGES_PER_TICKET", 100))
    if ticket.messages.count() >= max_messages:
        raise FeedbackLimitReached("This ticket has reached the message limit.")

    if ticket.status in REOPENABLE_STATUSES:
        _reopen_locked(ticket, reporter, reason="Reopened by a new reporter message.")
    elif ticket.status == FeedbackStatus.WAITING_FOR_USER:
        old_status = ticket.status
        ticket.status = FeedbackStatus.IN_PROGRESS
        ticket.save(update_fields=["status", "updated_at"])
        record_audit(
            ticket=ticket,
            actor=reporter,
            actor_type=FeedbackAuthorType.REPORTER,
            action=FeedbackAuditAction.STATUS_CHANGED,
            old_values={"status": old_status},
            new_values={"status": ticket.status},
            reason="Reporter replied.",
        )

    message = FeedbackMessage.objects.create(
        ticket=ticket,
        client_message_id=data["client_message_id"],
        author=reporter,
        author_type=FeedbackAuthorType.REPORTER,
        visibility=FeedbackVisibility.PUBLIC,
        body=data["body"],
    )
    ticket.last_public_message_at = message.created_at
    ticket.save(update_fields=["last_public_message_at", "updated_at"])
    record_audit(
        ticket=ticket,
        actor=reporter,
        actor_type=FeedbackAuthorType.REPORTER,
        action=FeedbackAuditAction.MESSAGE_ADDED,
        new_values={"message_id": message.id, "visibility": message.visibility},
    )
    _notify_operator_after_commit(ticket.id, message.id, "reporter_reply")
    return ticket, message, True


@transaction.atomic
def operator_update_ticket(
    ticket_id: uuid.UUID,
    actor: User,
    *,
    changes: dict[str, Any],
    reason: str,
) -> FeedbackTicket:
    ticket = FeedbackTicket.objects.select_for_update().get(pk=ticket_id)
    old_values: dict[str, Any] = {}
    new_values: dict[str, Any] = {}
    old_status = ticket.status
    new_status = str(changes.get("status", old_status))
    if new_status != old_status and new_status not in OPERATOR_TRANSITIONS.get(old_status, set()):
        raise FeedbackConflict(f"Operator transition {old_status} -> {new_status} is not allowed.")

    for field in ("status", "priority", "team", "assignee"):
        if field not in changes:
            continue
        old_value = (
            getattr(ticket, f"{field}_id") if field == "assignee" else getattr(ticket, field)
        )
        new_value = changes[field]
        new_comparable = (
            new_value.id if field == "assignee" and new_value is not None else new_value
        )
        if old_value == new_comparable:
            continue
        old_values[field] = old_value
        new_values[field] = new_comparable
        setattr(ticket, field, new_value)

    if not new_values:
        return ticket

    now = timezone.now()
    if "status" in new_values:
        if ticket.status == FeedbackStatus.RESOLVED:
            ticket.resolved_at = now
        elif old_status == FeedbackStatus.RESOLVED:
            ticket.resolved_at = None
        if ticket.status == FeedbackStatus.CLOSED:
            ticket.closed_at = now
        elif old_status == FeedbackStatus.CLOSED:
            ticket.closed_at = None
    if "priority" in new_values:
        ticket.sla_response_due_at = sla_due_at(ticket.category, ticket.priority, now=now)

    ticket.save()
    action = (
        FeedbackAuditAction.STATUS_CHANGED
        if "status" in new_values
        else FeedbackAuditAction.ROUTING_CHANGED
    )
    record_audit(
        ticket=ticket,
        actor=actor,
        actor_type=FeedbackAuthorType.OPERATOR,
        action=action,
        old_values=old_values,
        new_values=new_values,
        reason=reason,
    )
    return ticket


@transaction.atomic
def register_operator_message(message_id: uuid.UUID, actor: User) -> FeedbackMessage:
    message = FeedbackMessage.objects.select_related("ticket").get(pk=message_id)
    ticket = FeedbackTicket.objects.select_for_update().get(pk=message.ticket_id)
    now = message.created_at
    update_fields = ["updated_at"]
    if message.visibility == FeedbackVisibility.PUBLIC:
        ticket.last_public_message_at = now
        update_fields.append("last_public_message_at")
        if ticket.first_response_at is None:
            ticket.first_response_at = now
            update_fields.append("first_response_at")
    ticket.save(update_fields=update_fields)
    record_audit(
        ticket=ticket,
        actor=actor,
        actor_type=FeedbackAuthorType.OPERATOR,
        action=FeedbackAuditAction.MESSAGE_ADDED,
        new_values={"message_id": message.id, "visibility": message.visibility},
    )
    if message.visibility == FeedbackVisibility.PUBLIC:
        _notify_reporter_after_commit(message.id)
    return message


def _notify_operator_after_commit(
    ticket_id: uuid.UUID,
    message_id: uuid.UUID,
    event: str,
) -> None:
    transaction.on_commit(
        lambda: send_feedback_operator_notification_task.delay(
            str(ticket_id),
            str(message_id),
            event,
        ),
        robust=True,
    )


def _notify_reporter_after_commit(message_id: uuid.UUID) -> None:
    transaction.on_commit(
        lambda: send_feedback_reporter_notification_task.delay(str(message_id)),
        robust=True,
    )


def context_snapshot(context: FeedbackContext) -> dict[str, Any]:
    return {
        "edition_code": context.edition_code,
        "content_version": context.content_version,
        "surah_number": context.surah_number,
        "ayah_number": context.ayah_number,
        "page_number": context.page_number,
        "reciter_id": context.reciter_id,
        "recitation_id": context.recitation_id,
        "audio_track_id": context.audio_track_id,
        "playback_ms": context.playback_ms,
        "ad_campaign_id": context.ad_campaign_id,
        "ad_creative_id": context.ad_creative_id,
        "route": context.route,
        "app_version": context.app_version,
        "app_build": context.app_build,
        "client_platform": context.client_platform,
        "os_version": context.os_version,
    }


def message_snapshot(message: FeedbackMessage) -> dict[str, Any]:
    return {
        "id": message.id,
        "client_message_id": message.client_message_id,
        "author_type": message.author_type,
        "body": message.body,
        "created_at": message.created_at,
    }


def ticket_summary_snapshot(ticket: FeedbackTicket) -> dict[str, Any]:
    return {
        "public_id": ticket.public_id,
        "category": ticket.category,
        "subject": ticket.subject,
        "status": ticket.status,
        "priority": ticket.priority,
        "locale": ticket.locale,
        "channel": ticket.channel,
        "sla_response_due_at": ticket.sla_response_due_at,
        "first_response_at": ticket.first_response_at,
        "created_at": ticket.created_at,
        "updated_at": ticket.updated_at,
    }


def ticket_detail_snapshot(ticket: FeedbackTicket) -> dict[str, Any]:
    snapshot = ticket_summary_snapshot(ticket)
    snapshot.update(
        {
            "client_request_id": ticket.client_request_id,
            "contact_email": ticket.contact_email,
            "team": ticket.team,
            "resolved_at": ticket.resolved_at,
            "closed_at": ticket.closed_at,
            "reopened_at": ticket.reopened_at,
            "reopen_count": ticket.reopen_count,
            "context": context_snapshot(ticket.context),
            "messages": [
                message_snapshot(message)
                for message in ticket.messages.filter(visibility=FeedbackVisibility.PUBLIC)
            ],
        }
    )
    return snapshot
