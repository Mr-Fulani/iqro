from __future__ import annotations

from django.apps import AppConfig


class ShareReferralsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "quran_backend.modules.share_referrals"
    verbose_name = "Приглашения и промокоды"
