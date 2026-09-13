from __future__ import annotations

from dataclasses import dataclass

from django.db import transaction

from quran_backend.modules.core.content_revalidation import enqueue_quran_content_change
from quran_backend.modules.quran.models import (
    Ayah,
    PublicationStatus,
    QuranEdition,
    QuranEditionVersion,
)


class QuranPublicationError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class QuranPublicationResult:
    version: QuranEditionVersion
    published: bool
    activated: bool


@transaction.atomic
def publish_quran_version(
    *,
    edition_code: str,
    version_value: str,
    activate: bool,
) -> QuranPublicationResult:
    edition = QuranEdition.objects.select_for_update().filter(code=edition_code).first()
    if edition is None:
        raise QuranPublicationError(f"Unknown Quran edition: {edition_code}.")
    version = (
        QuranEditionVersion.objects.select_for_update()
        .filter(edition=edition, version=version_value)
        .first()
    )
    if version is None:
        raise QuranPublicationError(
            f"Unknown Quran edition version: {edition_code}@{version_value}."
        )
    if version.status == PublicationStatus.WITHDRAWN:
        raise QuranPublicationError("A withdrawn Quran version cannot be published.")

    _validate_complete_version(version)
    published = version.status != PublicationStatus.PUBLISHED
    if published:
        version.publish()
        version.full_clean()
        version.save(update_fields=["status", "published_at", "updated_at"])

    activated = activate and edition.active_version_id != version.id
    if activated:
        edition.active_version = version
        edition.full_clean()
        edition.save(update_fields=["active_version", "updated_at"])
    if published or activated:
        enqueue_quran_content_change(
            action="activated" if activated else "published",
            edition=edition.code,
            version=version.version,
        )
    return QuranPublicationResult(version=version, published=published, activated=activated)


def _validate_complete_version(version: QuranEditionVersion) -> None:
    actual_surahs = version.surahs.count()
    actual_pages = version.pages.count()
    actual_juz = version.juz.count()
    actual_hizb = version.hizb.count()
    actual_rub_el_hizb = version.rub_el_hizb.count()
    actual_ayahs = Ayah.objects.filter(surah__edition_version=version).count()
    covered_ayahs = (
        Ayah.objects.filter(
            surah__edition_version=version, page_mappings__page__edition_version=version
        )
        .distinct()
        .count()
    )
    if actual_surahs != version.surah_count:
        raise QuranPublicationError(
            f"Surah count mismatch: expected {version.surah_count}, got {actual_surahs}."
        )
    if actual_pages != version.page_count:
        raise QuranPublicationError(
            f"Page count mismatch: expected {version.page_count}, got {actual_pages}."
        )
    if actual_juz != version.juz_count:
        raise QuranPublicationError(
            f"Juz count mismatch: expected {version.juz_count}, got {actual_juz}."
        )
    if actual_hizb != version.hizb_count:
        raise QuranPublicationError(
            f"Hizb count mismatch: expected {version.hizb_count}, got {actual_hizb}."
        )
    if actual_rub_el_hizb != version.rub_el_hizb_count:
        raise QuranPublicationError(
            "Rub el Hizb count mismatch: "
            f"expected {version.rub_el_hizb_count}, got {actual_rub_el_hizb}."
        )
    if (
        version.hizb_count
        and Ayah.objects.filter(
            surah__edition_version=version,
            hizb_number__isnull=True,
        ).exists()
    ):
        raise QuranPublicationError("Published Hizb metadata must cover every ayah.")
    if (
        version.rub_el_hizb_count
        and Ayah.objects.filter(
            surah__edition_version=version,
            rub_el_hizb_number__isnull=True,
        ).exists()
    ):
        raise QuranPublicationError("Published Rub el Hizb metadata must cover every ayah.")
    if actual_ayahs <= 0 or covered_ayahs != actual_ayahs:
        raise QuranPublicationError(
            f"Ayah page coverage mismatch: expected {actual_ayahs}, got {covered_ayahs}."
        )
    if not version.manifests.exists():
        raise QuranPublicationError("The version has no verified source manifest.")
