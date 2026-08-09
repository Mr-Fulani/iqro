from __future__ import annotations

from typing import Any

from django import forms
from django.contrib import admin
from django.core.exceptions import ValidationError
from django.http import HttpRequest
from rest_framework.exceptions import ValidationError as DRFValidationError

from quran_backend.modules.feedback.models import (
    FeedbackAudit,
    FeedbackAuthorType,
    FeedbackContext,
    FeedbackMessage,
    FeedbackPriority,
    FeedbackTicket,
)
from quran_backend.modules.feedback.serializers import validate_plain_text
from quran_backend.modules.feedback.services import (
    OPERATOR_TRANSITIONS,
    operator_update_ticket,
    register_operator_message,
)


class FeedbackTicketAdminForm(forms.ModelForm):  # type: ignore[type-arg]
    transition_reason = forms.CharField(
        required=False,
        max_length=500,
        widget=forms.Textarea(attrs={"rows": 2}),
        help_text="Required when status, priority, team, or assignee changes.",
    )

    class Meta:
        model = FeedbackTicket
        fields = ("status", "priority", "team", "assignee")

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        self.original_status = self.instance.status
        if self.instance.pk:
            self.original_status = (
                FeedbackTicket.objects.only("status").get(pk=self.instance.pk).status
            )

    def clean_transition_reason(self) -> str:
        value = str(self.cleaned_data.get("transition_reason", ""))
        try:
            return validate_plain_text(value)
        except DRFValidationError as exc:
            raise ValidationError(exc.detail) from exc

    def clean(self) -> dict[str, Any]:
        cleaned_data = super().clean() or {}
        changed_workflow_fields = {"status", "priority", "team", "assignee"}.intersection(
            self.changed_data
        )
        if changed_workflow_fields and not cleaned_data.get("transition_reason"):
            self.add_error("transition_reason", "Document the reason for this workflow change.")
        new_status = cleaned_data.get("status")
        if (
            new_status
            and new_status != self.original_status
            and new_status not in OPERATOR_TRANSITIONS.get(self.original_status, set())
        ):
            self.add_error(
                "status",
                f"Transition {self.original_status} -> {new_status} is not allowed.",
            )
        return cleaned_data


class FeedbackContextInline(admin.StackedInline):  # type: ignore[type-arg]
    model = FeedbackContext
    extra = 0
    can_delete = False
    max_num = 0
    fields = (
        "edition_code",
        "content_version",
        "surah_number",
        "ayah_number",
        "page_number",
        "reciter_id",
        "recitation_id",
        "audio_track_id",
        "playback_ms",
        "ad_campaign_id",
        "ad_creative_id",
        "route",
        "app_version",
        "app_build",
        "client_platform",
        "os_version",
        "created_at",
    )
    readonly_fields = fields

    def has_add_permission(self, _request: HttpRequest, _obj: object | None = None) -> bool:
        return False

    def has_change_permission(self, _request: HttpRequest, _obj: object | None = None) -> bool:
        return True

    def has_delete_permission(self, _request: HttpRequest, _obj: object | None = None) -> bool:
        return False


@admin.register(FeedbackTicket)
class FeedbackTicketAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    form = FeedbackTicketAdminForm
    list_display = (
        "public_id",
        "category",
        "status",
        "priority",
        "team",
        "assignee",
        "sla_response_due_at",
        "created_at",
    )
    list_filter = ("category", "status", "priority", "team", "channel", "locale")
    search_fields = ("=public_id", "subject", "=reporter__id", "contact_email")
    ordering = ("-created_at",)
    list_select_related = ("reporter", "assignee")
    readonly_fields = (
        "id",
        "public_id",
        "reporter",
        "client_request_id",
        "category",
        "subject",
        "locale",
        "channel",
        "contact_email",
        "sla_response_due_at",
        "first_response_at",
        "resolved_at",
        "closed_at",
        "reopened_at",
        "reopen_count",
        "last_public_message_at",
        "created_at",
        "updated_at",
    )
    fieldsets = (
        (
            "Identity",
            {"fields": ("id", "public_id", "reporter", "client_request_id", "created_at")},
        ),
        (
            "Report",
            {"fields": ("category", "subject", "locale", "channel", "contact_email")},
        ),
        (
            "Workflow",
            {
                "fields": (
                    "status",
                    "priority",
                    "team",
                    "assignee",
                    "transition_reason",
                )
            },
        ),
        (
            "SLA and lifecycle",
            {
                "fields": (
                    "sla_response_due_at",
                    "first_response_at",
                    "resolved_at",
                    "closed_at",
                    "reopened_at",
                    "reopen_count",
                    "last_public_message_at",
                    "updated_at",
                )
            },
        ),
    )
    inlines = (FeedbackContextInline,)
    actions = ("escalate_to_critical",)

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_delete_permission(self, _request: HttpRequest, _obj: object | None = None) -> bool:
        return False

    def save_model(
        self,
        request: HttpRequest,
        obj: FeedbackTicket,
        form: FeedbackTicketAdminForm,
        change: bool,
    ) -> None:
        if not change:  # pragma: no cover - add permission is disabled.
            return
        changes = {
            field: form.cleaned_data[field]
            for field in ("status", "priority", "team", "assignee")
            if field in form.changed_data
        }
        saved = operator_update_ticket(
            obj.id,
            request.user,  # type: ignore[arg-type]
            changes=changes,
            reason=str(form.cleaned_data.get("transition_reason", "")),
        )
        for field in (
            "status",
            "priority",
            "team",
            "assignee",
            "sla_response_due_at",
            "resolved_at",
            "closed_at",
            "updated_at",
        ):
            setattr(obj, field, getattr(saved, field))

    @admin.action(description="Escalate selected tickets to critical priority")
    def escalate_to_critical(
        self,
        request: HttpRequest,
        queryset: Any,
    ) -> None:
        for ticket_id in queryset.values_list("id", flat=True):
            operator_update_ticket(
                ticket_id,
                request.user,  # type: ignore[arg-type]
                changes={"priority": FeedbackPriority.CRITICAL},
                reason="Manual critical escalation from the feedback inbox.",
            )


class FeedbackMessageAdminForm(forms.ModelForm):  # type: ignore[type-arg]
    class Meta:
        model = FeedbackMessage
        fields = ("ticket", "visibility", "body")

    def clean_body(self) -> str:
        value = str(self.cleaned_data["body"])
        try:
            return validate_plain_text(value)
        except DRFValidationError as exc:
            raise ValidationError(exc.detail) from exc


@admin.register(FeedbackMessage)
class FeedbackMessageAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    form = FeedbackMessageAdminForm
    list_display = ("id", "ticket", "author_type", "visibility", "author", "created_at")
    list_filter = ("author_type", "visibility", "created_at")
    search_fields = ("=id", "=ticket__public_id", "body")
    raw_id_fields = ("ticket",)
    readonly_fields = ("id", "client_message_id", "author", "author_type", "created_at")

    def has_change_permission(self, request: HttpRequest, obj: object | None = None) -> bool:
        return obj is None and super().has_change_permission(request, obj)

    def has_delete_permission(self, _request: HttpRequest, _obj: object | None = None) -> bool:
        return False

    def save_model(
        self,
        request: HttpRequest,
        obj: FeedbackMessage,
        form: FeedbackMessageAdminForm,
        change: bool,
    ) -> None:
        if change:  # pragma: no cover - immutable messages cannot be edited.
            return
        obj.author = request.user  # type: ignore[assignment]
        obj.author_type = FeedbackAuthorType.OPERATOR
        super().save_model(request, obj, form, change)
        register_operator_message(obj.id, request.user)  # type: ignore[arg-type]


class ImmutableReadOnlyAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    actions = None

    def has_add_permission(self, _request: HttpRequest) -> bool:
        return False

    def has_change_permission(self, _request: HttpRequest, _obj: object | None = None) -> bool:
        return False

    def has_delete_permission(self, _request: HttpRequest, _obj: object | None = None) -> bool:
        return False


@admin.register(FeedbackAudit)
class FeedbackAuditAdmin(ImmutableReadOnlyAdmin):
    list_display = ("id", "ticket", "actor_type", "action", "actor", "created_at")
    list_filter = ("actor_type", "action", "created_at")
    search_fields = ("=id", "=ticket__public_id", "=actor__id", "reason")
    readonly_fields = (
        "id",
        "ticket",
        "actor",
        "actor_type",
        "action",
        "old_values",
        "new_values",
        "reason",
        "created_at",
        "updated_at",
    )


@admin.register(FeedbackContext)
class FeedbackContextAdmin(ImmutableReadOnlyAdmin):
    list_display = (
        "ticket",
        "edition_code",
        "content_version",
        "surah_number",
        "ayah_number",
        "page_number",
    )
    search_fields = ("=ticket__public_id", "edition_code", "content_version")
