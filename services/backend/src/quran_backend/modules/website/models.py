from __future__ import annotations

from typing import Any
from urllib.parse import urlsplit

from django.core.exceptions import ValidationError
from django.db import models

from quran_backend.modules.core.models import BaseModel


class SocialPlatform(models.TextChoices):
    TELEGRAM = "telegram", "Telegram"
    YOUTUBE = "youtube", "YouTube"
    INSTAGRAM = "instagram", "Instagram"
    VK = "vk", "ВКонтакте"
    TIKTOK = "tiktok", "TikTok"
    X = "x", "X (Twitter)"
    FACEBOOK = "facebook", "Facebook"
    THREADS = "threads", "Threads"
    WHATSAPP = "whatsapp", "WhatsApp"
    DISCORD = "discord", "Discord"
    LINKEDIN = "linkedin", "LinkedIn"
    PINTEREST = "pinterest", "Pinterest"
    ODNOKLASSNIKI = "odnoklassniki", "Одноклассники"
    DZEN = "dzen", "Дзен"
    RUTUBE = "rutube", "Rutube"
    GITHUB = "github", "GitHub"
    REDDIT = "reddit", "Reddit"
    TWITCH = "twitch", "Twitch"
    SNAPCHAT = "snapchat", "Snapchat"
    BLUESKY = "bluesky", "Bluesky"


SOCIAL_PLATFORM_HOSTS: dict[str, frozenset[str]] = {
    SocialPlatform.TELEGRAM: frozenset({"t.me", "telegram.me"}),
    SocialPlatform.YOUTUBE: frozenset({"youtube.com", "www.youtube.com", "youtu.be"}),
    SocialPlatform.INSTAGRAM: frozenset({"instagram.com", "www.instagram.com"}),
    SocialPlatform.VK: frozenset({"vk.com", "www.vk.com"}),
    SocialPlatform.TIKTOK: frozenset({"tiktok.com", "www.tiktok.com"}),
    SocialPlatform.X: frozenset({"x.com", "www.x.com", "twitter.com", "www.twitter.com"}),
    SocialPlatform.FACEBOOK: frozenset(
        {"facebook.com", "www.facebook.com", "m.facebook.com", "fb.com", "www.fb.com"}
    ),
    SocialPlatform.THREADS: frozenset({"threads.net", "www.threads.net"}),
    SocialPlatform.WHATSAPP: frozenset(
        {"wa.me", "whatsapp.com", "www.whatsapp.com", "chat.whatsapp.com"}
    ),
    SocialPlatform.DISCORD: frozenset(
        {"discord.gg", "discord.com", "www.discord.com", "discordapp.com"}
    ),
    SocialPlatform.LINKEDIN: frozenset({"linkedin.com", "www.linkedin.com"}),
    SocialPlatform.PINTEREST: frozenset({"pinterest.com", "www.pinterest.com", "pin.it"}),
    SocialPlatform.ODNOKLASSNIKI: frozenset({"ok.ru", "www.ok.ru"}),
    SocialPlatform.DZEN: frozenset({"dzen.ru", "www.dzen.ru", "zen.yandex.ru"}),
    SocialPlatform.RUTUBE: frozenset({"rutube.ru", "www.rutube.ru"}),
    SocialPlatform.GITHUB: frozenset({"github.com", "www.github.com"}),
    SocialPlatform.REDDIT: frozenset({"reddit.com", "www.reddit.com"}),
    SocialPlatform.TWITCH: frozenset({"twitch.tv", "www.twitch.tv"}),
    SocialPlatform.SNAPCHAT: frozenset({"snapchat.com", "www.snapchat.com"}),
    SocialPlatform.BLUESKY: frozenset({"bsky.app", "www.bsky.app"}),
}


class SocialProfile(BaseModel):
    """One canonical platform profile, reusable by web, mobile and mini-app clients."""

    platform = models.CharField(max_length=32, choices=SocialPlatform, unique=True)
    profile_url = models.URLField(max_length=500, blank=True)
    display_name = models.CharField(
        max_length=100,
        blank=True,
        help_text="Необязательное имя канала или аккаунта, например @iqro_forum.",
    )
    sort_order = models.PositiveSmallIntegerField(
        default=100,
        help_text="Меньшее число выводится раньше.",
    )
    is_active = models.BooleanField(
        default=True,
        help_text="Пустая ссылка всегда скрывается, даже если этот флаг включён.",
    )
    include_in_seo = models.BooleanField(
        default=True,
        help_text="Добавить профиль в Organization.sameAs для поисковых систем.",
    )

    class Meta:
        db_table = "website_social_profile"
        ordering = ("sort_order", "platform")
        constraints = [
            models.CheckConstraint(
                condition=models.Q(is_active=False) | ~models.Q(profile_url=""),
                name="website_social_active_url_required",
            ),
        ]
        indexes = [
            models.Index(
                fields=("is_active", "sort_order", "platform"),
                name="website_social_public_idx",
            ),
        ]

    def __str__(self) -> str:
        return str(self.get_platform_display())

    def clean(self) -> None:
        super().clean()
        self.profile_url = self.profile_url.strip()
        self.display_name = self.display_name.strip()
        if not self.profile_url:
            self.is_active = False
            return

        parsed = urlsplit(self.profile_url)
        try:
            port = parsed.port
        except ValueError as exc:
            raise ValidationError({"profile_url": "Некорректный порт в адресе."}) from exc
        if (
            parsed.scheme != "https"
            or parsed.hostname is None
            or parsed.username is not None
            or parsed.password is not None
            or port not in {None, 443}
        ):
            raise ValidationError(
                {"profile_url": "Укажите безопасный HTTPS-адрес без логина, пароля и порта."}
            )

        hostname = parsed.hostname.lower().rstrip(".")
        allowed_hosts = SOCIAL_PLATFORM_HOSTS.get(self.platform, frozenset())
        if hostname not in allowed_hosts:
            expected = ", ".join(sorted(allowed_hosts)) or "домен выбранной платформы"
            raise ValidationError(
                {"profile_url": f"Адрес не относится к выбранной платформе. Допустимо: {expected}."}
            )

    def save(self, *args: Any, **kwargs: Any) -> None:
        self.profile_url = self.profile_url.strip()
        self.display_name = self.display_name.strip()
        self.full_clean()
        super().save(*args, **kwargs)
