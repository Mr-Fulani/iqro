# Generated for Quran Platform.

import uuid

from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True

    dependencies = []

    operations = [
        migrations.CreateModel(
            name="SocialProfile",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid7, editable=False, primary_key=True, serialize=False
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "platform",
                    models.CharField(
                        choices=[
                            ("telegram", "Telegram"),
                            ("youtube", "YouTube"),
                            ("instagram", "Instagram"),
                            ("vk", "ВКонтакте"),
                            ("tiktok", "TikTok"),
                            ("x", "X (Twitter)"),
                            ("facebook", "Facebook"),
                            ("threads", "Threads"),
                            ("whatsapp", "WhatsApp"),
                            ("discord", "Discord"),
                            ("linkedin", "LinkedIn"),
                            ("pinterest", "Pinterest"),
                            ("odnoklassniki", "Одноклассники"),
                            ("dzen", "Дзен"),
                            ("rutube", "Rutube"),
                            ("github", "GitHub"),
                            ("reddit", "Reddit"),
                            ("twitch", "Twitch"),
                            ("snapchat", "Snapchat"),
                            ("bluesky", "Bluesky"),
                        ],
                        max_length=32,
                        unique=True,
                    ),
                ),
                ("profile_url", models.URLField(blank=True, max_length=500)),
                (
                    "display_name",
                    models.CharField(
                        blank=True,
                        help_text="Необязательное имя канала или аккаунта, например @iqro_forum.",
                        max_length=100,
                    ),
                ),
                (
                    "sort_order",
                    models.PositiveSmallIntegerField(
                        default=100,
                        help_text="Меньшее число выводится раньше.",
                    ),
                ),
                (
                    "is_active",
                    models.BooleanField(
                        default=True,
                        help_text="Пустая ссылка всегда скрывается, даже если этот флаг включён.",
                    ),
                ),
                (
                    "include_in_seo",
                    models.BooleanField(
                        default=True,
                        help_text="Добавить профиль в Organization.sameAs для поисковых систем.",
                    ),
                ),
            ],
            options={
                "db_table": "website_social_profile",
                "ordering": ("sort_order", "platform"),
                "indexes": [
                    models.Index(
                        fields=["is_active", "sort_order", "platform"],
                        name="website_social_public_idx",
                    )
                ],
                "constraints": [
                    models.CheckConstraint(
                        condition=models.Q(
                            ("is_active", False),
                            models.Q(("profile_url", ""), _negated=True),
                            _connector="OR",
                        ),
                        name="website_social_active_url_required",
                    )
                ],
            },
        ),
    ]
