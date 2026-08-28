from __future__ import annotations

from typing import Any

from django.db import transaction
from rest_framework import status
from rest_framework.exceptions import APIException, ValidationError

from quran_backend.modules.accounts.models import Device, User
from quran_backend.modules.reading.models import QuranReaderPreference

SUPPORTED_LOCALES = {"ar", "en", "ru", "tr"}


class QuranReaderPreferenceRevisionConflictError(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = "The Quran reader preference changed on another client."
    default_code = "quran_reader_preference_revision_conflict"


def get_quran_reader_preference(user: User, locale: str) -> dict[str, Any]:
    _validate_locale(locale)
    preference = (
        QuranReaderPreference.objects.filter(user=user, locale=locale)
        .select_related("device")
        .first()
    )
    return quran_reader_preference_snapshot(preference, locale=locale)


def quran_reader_preference_snapshot(
    preference: QuranReaderPreference | None,
    *,
    locale: str,
) -> dict[str, Any]:
    if preference is None:
        return {
            "id": None,
            "locale": locale,
            "translation_enabled": False,
            "translation_source_id": None,
            "tafsir_enabled": False,
            "tafsir_source_id": None,
            "revision": 0,
            "client_updated_at": None,
            "device_id": None,
            "created_at": None,
            "updated_at": None,
        }
    return {
        "id": str(preference.id),
        "locale": preference.locale,
        "translation_enabled": preference.translation_enabled,
        "translation_source_id": preference.translation_source_id,
        "tafsir_enabled": preference.tafsir_enabled,
        "tafsir_source_id": preference.tafsir_source_id,
        "revision": preference.revision,
        "client_updated_at": preference.client_updated_at.isoformat(),
        "device_id": str(preference.device_id) if preference.device_id else None,
        "created_at": preference.created_at.isoformat(),
        "updated_at": preference.updated_at.isoformat(),
    }


@transaction.atomic
def put_quran_reader_preference(
    *,
    user: User,
    device: Device | None,
    locale: str,
    data: dict[str, Any],
) -> dict[str, Any]:
    _validate_locale(locale)
    User.objects.select_for_update().only("id").get(pk=user.pk)
    current = (
        QuranReaderPreference.objects.select_for_update().filter(user=user, locale=locale).first()
    )
    desired = (
        data["translation_enabled"],
        data["translation_source_id"],
        data["tafsir_enabled"],
        data["tafsir_source_id"],
    )
    if current is not None and _stored_state(current) == desired:
        return quran_reader_preference_snapshot(current, locale=locale)
    if current is None:
        if data["base_revision"] != 0:
            raise QuranReaderPreferenceRevisionConflictError
    elif data["base_revision"] != current.revision:
        raise QuranReaderPreferenceRevisionConflictError

    values = {
        "translation_enabled": data["translation_enabled"],
        "translation_source_id": data["translation_source_id"],
        "tafsir_enabled": data["tafsir_enabled"],
        "tafsir_source_id": data["tafsir_source_id"],
        "client_updated_at": data["client_updated_at"],
        "device": device,
    }
    if current is None:
        preference = QuranReaderPreference(user=user, locale=locale, revision=1, **values)
    else:
        preference = current
        for field, value in values.items():
            setattr(preference, field, value)
        preference.revision += 1
    preference.full_clean()
    preference.save()
    return quran_reader_preference_snapshot(preference, locale=locale)


def _stored_state(preference: QuranReaderPreference) -> tuple[bool, int | None, bool, int | None]:
    return (
        preference.translation_enabled,
        preference.translation_source_id,
        preference.tafsir_enabled,
        preference.tafsir_source_id,
    )


def _validate_locale(locale: str) -> None:
    if locale not in SUPPORTED_LOCALES:
        raise ValidationError({"locale": "Use one of: ar, en, ru, tr."})
