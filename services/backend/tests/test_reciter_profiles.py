from __future__ import annotations

from importlib import import_module

import pytest
from django.core.validators import URLValidator

from quran_backend.modules.audio.models import Reciter

profiles_data = import_module("quran_backend.modules.audio.reciter_profiles")
profiles_migration = import_module("quran_backend.modules.audio.migrations.0009_reciter_profiles")


EXPECTED_CODES = {
    "qf-1-abdulbaset-abdulsamad-mujawwad",
    "qf-2-abdul-baset-abdul-samad",
    "qf-3-abdur-rahman-as-sudais",
    "qf-4-abu-bakr-al-shatri",
    "qf-5-hani-ar-rifai",
    "qf-6-mahmoud-khaleel-al-husary",
    "qf-7-mishari-rashid-al-afasy",
    "qf-9-muhammad-siddiq-al-minshawi",
    "qf-10-saud-ash-shuraym",
    "qf-12-mahmoud-khaleel-al-husary",
    "qf-13-saad-al-ghamdi",
    "qf-19-ahmed-ibn-ali-al-ajmy",
    "qf-158-abdullah-ali-jabir",
    "qf-159-maher-al-muaiqly",
    "qf-160-bandar-baleela",
    "qf-174-yasser-ad-dussary",
    "qf-175-abdullah-hamad-abu-sharida",
    "qf-176-ahmed-tahoun",
}


def test_curated_reciter_profiles_cover_catalog_in_all_supported_languages() -> None:
    profiles = profiles_data.RECITER_PROFILES

    assert set(profiles) == EXPECTED_CODES
    for profile in profiles.values():
        for locale in ("ar", "en", "ru", "tr"):
            assert profile[f"name_{locale}"].strip()
            assert profile[f"biography_{locale}"].strip()
        assert len(profile["country_code"]) == 2
        URLValidator()(profile["profile_source_url"])
        assert profile["profile_source_checked_on"] == profiles_data.SOURCE_CHECKED_ON

    assert (
        profiles["qf-1-abdulbaset-abdulsamad-mujawwad"] == profiles["qf-2-abdul-baset-abdul-samad"]
    )
    assert profiles["qf-12-mahmoud-khaleel-al-husary"] == profiles["qf-6-mahmoud-khaleel-al-husary"]


class _CurrentApps:
    @staticmethod
    def get_model(app_label: str, model_name: str) -> type[Reciter]:
        assert (app_label, model_name) == ("audio", "Reciter")
        return Reciter


@pytest.mark.django_db
def test_curated_reciter_profile_migration_updates_existing_catalog_row() -> None:
    reciter = Reciter.objects.create(
        code="qf-13-saad-al-ghamdi",
        name_ar="Saad al-Ghamdi",
        name_en="Saad al-Ghamdi",
        name_ru="Saad al-Ghamdi",
    )

    profiles_migration.populate_reciter_profiles(_CurrentApps(), None)
    reciter.refresh_from_db()

    assert reciter.name_ar == "سعد الغامدي"
    assert reciter.name_tr == "Saad el-Gamidi"
    assert reciter.biography_ru
    assert reciter.biography_tr
    assert reciter.country_code == "SA"
    assert reciter.profile_source_url == "https://quran.com/en/reciters/13"
    assert reciter.profile_source_checked_on == profiles_data.SOURCE_CHECKED_ON
