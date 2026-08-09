# Generated for Django 6.1 on 2026-08-09

import django.db.models.deletion
import quran_backend.modules.feedback.models
import uuid
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="FeedbackTicket",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid7,
                        editable=False,
                        primary_key=True,
                        serialize=False,
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "public_id",
                    models.CharField(
                        default=quran_backend.modules.feedback.models.generate_feedback_public_id,
                        editable=False,
                        max_length=32,
                        unique=True,
                    ),
                ),
                ("client_request_id", models.UUIDField()),
                ("request_fingerprint", models.CharField(editable=False, max_length=64)),
                (
                    "category",
                    models.CharField(
                        choices=[
                            ("general", "General suggestion"),
                            ("technical", "Technical problem"),
                            ("religious_content", "Religious content concern"),
                            ("page_layout", "Mushaf page or region problem"),
                            ("audio", "Audio, timing or reciter problem"),
                            ("advertisement", "Advertisement complaint"),
                            ("account_sync", "Account or synchronization"),
                            ("donation_link", "Donation or external link"),
                            (
                                "accessibility_localization",
                                "Accessibility or localization",
                            ),
                            ("other", "Other"),
                        ],
                        max_length=40,
                    ),
                ),
                ("subject", models.CharField(max_length=160)),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("new", "New"),
                            ("triaged", "Triaged"),
                            ("in_progress", "In progress"),
                            ("waiting_for_user", "Waiting for user"),
                            ("resolved", "Resolved"),
                            ("rejected", "Rejected"),
                            ("duplicate", "Duplicate"),
                            ("closed", "Closed"),
                        ],
                        default="new",
                        max_length=24,
                    ),
                ),
                (
                    "priority",
                    models.CharField(
                        choices=[
                            ("normal", "Normal"),
                            ("high", "High"),
                            ("critical", "Critical"),
                        ],
                        default="normal",
                        max_length=16,
                    ),
                ),
                ("locale", models.CharField(max_length=8)),
                (
                    "channel",
                    models.CharField(
                        choices=[
                            ("ios", "iOS"),
                            ("android", "Android"),
                            ("web", "Web"),
                            ("telegram", "Telegram Mini App"),
                        ],
                        max_length=16,
                    ),
                ),
                ("contact_email", models.EmailField(blank=True, max_length=254, null=True)),
                ("team", models.CharField(blank=True, max_length=64)),
                (
                    "sla_response_due_at",
                    models.DateTimeField(blank=True, db_index=True, null=True),
                ),
                ("first_response_at", models.DateTimeField(blank=True, null=True)),
                ("resolved_at", models.DateTimeField(blank=True, null=True)),
                ("closed_at", models.DateTimeField(blank=True, null=True)),
                ("reopened_at", models.DateTimeField(blank=True, null=True)),
                ("reopen_count", models.PositiveSmallIntegerField(default=0)),
                ("last_public_message_at", models.DateTimeField(blank=True, null=True)),
                (
                    "assignee",
                    models.ForeignKey(
                        blank=True,
                        limit_choices_to={"is_staff": True},
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="assigned_feedback_tickets",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "reporter",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="feedback_tickets",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "db_table": "feedback_ticket",
                "ordering": ["-created_at", "-id"],
            },
        ),
        migrations.CreateModel(
            name="FeedbackMessage",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid7,
                        editable=False,
                        primary_key=True,
                        serialize=False,
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("client_message_id", models.UUIDField(default=uuid.uuid7)),
                (
                    "author_type",
                    models.CharField(
                        choices=[
                            ("reporter", "Reporter"),
                            ("operator", "Operator"),
                            ("system", "System"),
                        ],
                        max_length=16,
                    ),
                ),
                (
                    "visibility",
                    models.CharField(
                        choices=[("public", "Public"), ("internal", "Internal")],
                        max_length=16,
                    ),
                ),
                ("body", models.TextField(max_length=4000)),
                (
                    "author",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="feedback_messages",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "ticket",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="messages",
                        to="feedback.feedbackticket",
                    ),
                ),
            ],
            options={
                "db_table": "feedback_message",
                "ordering": ["created_at", "id"],
            },
        ),
        migrations.CreateModel(
            name="FeedbackContext",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid7,
                        editable=False,
                        primary_key=True,
                        serialize=False,
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("edition_code", models.CharField(blank=True, max_length=64)),
                ("content_version", models.CharField(blank=True, max_length=64)),
                ("surah_number", models.PositiveSmallIntegerField(blank=True, null=True)),
                ("ayah_number", models.PositiveSmallIntegerField(blank=True, null=True)),
                ("page_number", models.PositiveSmallIntegerField(blank=True, null=True)),
                ("reciter_id", models.CharField(blank=True, max_length=128)),
                ("recitation_id", models.CharField(blank=True, max_length=128)),
                ("audio_track_id", models.CharField(blank=True, max_length=128)),
                ("playback_ms", models.PositiveBigIntegerField(blank=True, null=True)),
                ("ad_campaign_id", models.CharField(blank=True, max_length=128)),
                ("ad_creative_id", models.CharField(blank=True, max_length=128)),
                ("route", models.CharField(blank=True, max_length=255)),
                ("app_version", models.CharField(blank=True, max_length=32)),
                ("app_build", models.CharField(blank=True, max_length=32)),
                (
                    "client_platform",
                    models.CharField(
                        blank=True,
                        choices=[
                            ("ios", "iOS"),
                            ("android", "Android"),
                            ("web", "Web"),
                            ("telegram", "Telegram Mini App"),
                        ],
                        max_length=16,
                    ),
                ),
                ("os_version", models.CharField(blank=True, max_length=64)),
                (
                    "ticket",
                    models.OneToOneField(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="context",
                        to="feedback.feedbackticket",
                    ),
                ),
            ],
            options={"db_table": "feedback_context"},
        ),
        migrations.CreateModel(
            name="FeedbackAudit",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid7,
                        editable=False,
                        primary_key=True,
                        serialize=False,
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "actor_type",
                    models.CharField(
                        choices=[
                            ("reporter", "Reporter"),
                            ("operator", "Operator"),
                            ("system", "System"),
                        ],
                        max_length=16,
                    ),
                ),
                (
                    "action",
                    models.CharField(
                        choices=[
                            ("created", "Created"),
                            ("status_changed", "Status changed"),
                            ("routing_changed", "Routing changed"),
                            ("message_added", "Message added"),
                            ("reopened", "Reopened"),
                        ],
                        max_length=24,
                    ),
                ),
                ("old_values", models.JSONField(blank=True, default=dict)),
                ("new_values", models.JSONField(blank=True, default=dict)),
                ("reason", models.CharField(blank=True, max_length=500)),
                (
                    "actor",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="feedback_audit_events",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "ticket",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="audit_events",
                        to="feedback.feedbackticket",
                    ),
                ),
            ],
            options={
                "db_table": "feedback_audit",
                "ordering": ["created_at", "id"],
            },
        ),
        migrations.AddIndex(
            model_name="feedbackticket",
            index=models.Index(
                fields=["reporter", "created_at", "id"],
                name="fb_ticket_reporter_time_idx",
            ),
        ),
        migrations.AddIndex(
            model_name="feedbackticket",
            index=models.Index(
                fields=["status", "priority", "sla_response_due_at"],
                name="feedback_ticket_sla_idx",
            ),
        ),
        migrations.AddIndex(
            model_name="feedbackticket",
            index=models.Index(
                fields=["category", "status"],
                name="feedback_ticket_route_idx",
            ),
        ),
        migrations.AddConstraint(
            model_name="feedbackticket",
            constraint=models.UniqueConstraint(
                fields=("reporter", "client_request_id"),
                name="feedback_ticket_reporter_request_unique",
            ),
        ),
        migrations.AddConstraint(
            model_name="feedbackticket",
            constraint=models.CheckConstraint(
                condition=models.Q(("locale__in", ["ar", "en", "ru"])),
                name="feedback_ticket_supported_locale",
            ),
        ),
        migrations.AddIndex(
            model_name="feedbackmessage",
            index=models.Index(
                fields=["ticket", "visibility", "created_at"],
                name="feedback_message_public_idx",
            ),
        ),
        migrations.AddConstraint(
            model_name="feedbackmessage",
            constraint=models.UniqueConstraint(
                fields=("ticket", "client_message_id"),
                name="feedback_message_ticket_client_unique",
            ),
        ),
        migrations.AddConstraint(
            model_name="feedbackcontext",
            constraint=models.CheckConstraint(
                condition=models.Q(
                    ("surah_number__isnull", True),
                    models.Q(("surah_number__gte", 1), ("surah_number__lte", 114)),
                    _connector="OR",
                ),
                name="feedback_context_surah_range",
            ),
        ),
        migrations.AddConstraint(
            model_name="feedbackcontext",
            constraint=models.CheckConstraint(
                condition=models.Q(
                    ("ayah_number__isnull", True),
                    ("ayah_number__gte", 1),
                    _connector="OR",
                ),
                name="feedback_context_ayah_positive",
            ),
        ),
        migrations.AddConstraint(
            model_name="feedbackcontext",
            constraint=models.CheckConstraint(
                condition=models.Q(
                    ("page_number__isnull", True),
                    models.Q(("page_number__gte", 1), ("page_number__lte", 604)),
                    _connector="OR",
                ),
                name="feedback_context_page_range",
            ),
        ),
        migrations.AddIndex(
            model_name="feedbackaudit",
            index=models.Index(
                fields=["ticket", "created_at"],
                name="feedback_audit_time_idx",
            ),
        ),
    ]
