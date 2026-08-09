from __future__ import annotations

import hashlib
import json
import uuid
from decimal import Decimal

from django.db import migrations
from django.utils import timezone

RELEASE_VERSION = "2026.1"
ALGORITHM = "adhan-js-python-adapter"
ALGORITHM_VERSION = "4.4.4-quran.1-adhanpy.1.0.5"
TZDB_VERSION = "2026.3"
SCHEMA_VERSION = 1
SOURCE_NAME = "Batoul Apps Adhan JS calculation preset"
SOURCE_URL = "https://unpkg.com/adhan@4.4.4/lib/esm/CalculationMethod.js"
SOURCE_VERSION = "4.4.4"
SOURCE_CHECKSUM = "b6da8fa129d7474c8c558a9de2254c08a86b9bb2c0edaee183a8fa6be5edcdbc"
AUTHORITY_NAME = "Batoul Apps / Adhan JS reference preset"
AUTHORITY_URL = "https://github.com/batoulapps/adhan-js/blob/v4.4.4/METHODS.md"
NAMESPACE = uuid.UUID("d6bf47f2-dd2b-5a82-9b0e-e3db5f147d89")

METHODS = (
    {
        "code": "muslim-world-league",
        "name_ar": "رابطة العالم الإسلامي",
        "name_en": "Muslim World League",
        "name_ru": "Всемирная исламская лига",
        "fajr": "18.00",
        "isha_angle": "17.00",
        "adjustments": {"dhuhr": 1},
    },
    {
        "code": "egyptian",
        "name_ar": "الهيئة المصرية العامة للمساحة",
        "name_en": "Egyptian General Authority of Survey",
        "name_ru": "Египетское главное управление геодезии",
        "fajr": "19.50",
        "isha_angle": "17.50",
        "adjustments": {"dhuhr": 1},
    },
    {
        "code": "karachi",
        "name_ar": "جامعة العلوم الإسلامية بكراتشي",
        "name_en": "University of Islamic Sciences, Karachi",
        "name_ru": "Университет исламских наук, Карачи",
        "fajr": "18.00",
        "isha_angle": "18.00",
        "adjustments": {"dhuhr": 1},
    },
    {
        "code": "umm-al-qura",
        "name_ar": "جامعة أم القرى",
        "name_en": "Umm al-Qura University, Makkah",
        "name_ru": "Университет Умм аль-Кура, Мекка",  # noqa: RUF001
        "fajr": "18.50",
        "isha_interval": 90,
        "adjustments": {},
    },
    {
        "code": "dubai",
        "name_ar": "طريقة دبي",
        "name_en": "Dubai",
        "name_ru": "Дубай",
        "fajr": "18.20",
        "isha_angle": "18.20",
        "adjustments": {"sunrise": -3, "dhuhr": 3, "asr": 3, "maghrib": 3},
    },
    {
        "code": "moonsighting-committee",
        "name_ar": "لجنة رؤية الهلال",
        "name_en": "Moonsighting Committee",
        "name_ru": "Комитет наблюдения луны",
        "fajr": "18.00",
        "isha_angle": "18.00",
        "adjustments": {"dhuhr": 5, "maghrib": 3},
    },
    {
        "code": "north-america",
        "name_ar": "الجمعية الإسلامية لأمريكا الشمالية",
        "name_en": "ISNA / North America",
        "name_ru": "ISNA / Северная Америка",
        "fajr": "15.00",
        "isha_angle": "15.00",
        "adjustments": {"dhuhr": 1},
    },
    {
        "code": "kuwait",
        "name_ar": "طريقة الكويت",
        "name_en": "Kuwait",
        "name_ru": "Кувейт",
        "fajr": "18.00",
        "isha_angle": "17.50",
        "adjustments": {},
    },
    {
        "code": "qatar",
        "name_ar": "طريقة قطر",
        "name_en": "Qatar",
        "name_ru": "Катар",
        "fajr": "18.00",
        "isha_interval": 90,
        "adjustments": {},
    },
)


def _identifier(kind: str, value: str) -> uuid.UUID:
    return uuid.uuid5(NAMESPACE, f"{kind}:{value}")


def _configuration_payload(method: dict[str, object]) -> dict[str, object]:
    raw_adjustments = dict(method["adjustments"])
    adjustments = {
        prayer: int(raw_adjustments.get(prayer, 0))
        for prayer in ("fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha")
    }
    isha_angle = method.get("isha_angle")
    return {
        "adjustments": adjustments,
        "default_high_latitude_rule": "middle_of_night",
        "default_polar_resolution": "unresolved",
        "fajr_angle": str(method["fajr"]),
        "isha_angle": str(isha_angle) if isha_angle is not None else None,
        "isha_interval_minutes": method.get("isha_interval"),
        "method": method["code"],
        "ramadan_isha_interval_minutes": None,
        "schema_version": SCHEMA_VERSION,
        "source": {
            "checksum_sha256": SOURCE_CHECKSUM,
            "name": SOURCE_NAME,
            "url": SOURCE_URL,
            "version": SOURCE_VERSION,
        },
        "supported_high_latitude_rules": [
            "middle_of_night",
            "seventh_of_night",
            "twilight_angle",
        ],
        "supported_polar_resolutions": ["aqrab_balad", "aqrab_yaum", "unresolved"],
    }


def _checksum(payload: dict[str, object]) -> str:
    serialized = json.dumps(
        payload,
        ensure_ascii=True,
        separators=(",", ":"),
        sort_keys=True,
    ).encode()
    return hashlib.sha256(serialized).hexdigest()


def seed_reference_release(apps, _schema_editor) -> None:
    PrayerMethod = apps.get_model("prayer_times", "PrayerMethod")
    PrayerConfigRelease = apps.get_model("prayer_times", "PrayerConfigRelease")
    PrayerMethodConfig = apps.get_model("prayer_times", "PrayerMethodConfig")

    release = PrayerConfigRelease.objects.create(
        id=_identifier("release", RELEASE_VERSION),
        version=RELEASE_VERSION,
        configuration_schema_version=SCHEMA_VERSION,
        algorithm=ALGORITHM,
        algorithm_version=ALGORITHM_VERSION,
        timezone_database_version=TZDB_VERSION,
        release_notes=(
            "Pinned technical reference configuration derived from Adhan JS 4.4.4. "
            "Replacement releases require documented source and review."
        ),
    )
    checksums: list[tuple[str, str]] = []
    for definition in METHODS:
        code = str(definition["code"])
        method = PrayerMethod.objects.create(
            id=_identifier("method", code),
            code=code,
            name_ar=definition["name_ar"],
            name_en=definition["name_en"],
            name_ru=definition["name_ru"],
            description_ar="إعداد مرجعي موثق من مكتبة Adhan JS.",
            description_en="Versioned reference preset documented by Adhan JS.",
            description_ru="Версионированный эталонный пресет из документации Adhan JS.",
            authority_name=AUTHORITY_NAME,
            authority_url=AUTHORITY_URL,
        )
        payload = _configuration_payload(definition)
        config_checksum = _checksum(payload)
        raw_adjustments = dict(definition["adjustments"])
        PrayerMethodConfig.objects.create(
            id=_identifier("config", f"{RELEASE_VERSION}:{code}"),
            release=release,
            method=method,
            fajr_angle=Decimal(str(definition["fajr"])),
            isha_angle=(
                Decimal(str(definition["isha_angle"]))
                if definition.get("isha_angle") is not None
                else None
            ),
            isha_interval_minutes=definition.get("isha_interval"),
            ramadan_isha_interval_minutes=None,
            fajr_adjustment_minutes=int(raw_adjustments.get("fajr", 0)),
            sunrise_adjustment_minutes=int(raw_adjustments.get("sunrise", 0)),
            dhuhr_adjustment_minutes=int(raw_adjustments.get("dhuhr", 0)),
            asr_adjustment_minutes=int(raw_adjustments.get("asr", 0)),
            maghrib_adjustment_minutes=int(raw_adjustments.get("maghrib", 0)),
            isha_adjustment_minutes=int(raw_adjustments.get("isha", 0)),
            supports_middle_of_night=True,
            supports_seventh_of_night=True,
            supports_twilight_angle=True,
            default_high_latitude_rule="middle_of_night",
            supports_polar_unresolved=True,
            supports_polar_aqrab_balad=True,
            supports_polar_aqrab_yaum=True,
            default_polar_resolution="unresolved",
            source_name=SOURCE_NAME,
            source_url=SOURCE_URL,
            source_version=SOURCE_VERSION,
            source_checksum_sha256=SOURCE_CHECKSUM,
            checksum_sha256=config_checksum,
        )
        checksums.append((code, config_checksum))

    manifest_payload = {
        "algorithm": ALGORITHM,
        "algorithm_version": ALGORITHM_VERSION,
        "configuration_schema_version": SCHEMA_VERSION,
        "methods": [
            {"checksum_sha256": checksum, "code": code} for code, checksum in sorted(checksums)
        ],
        "timezone_database_version": TZDB_VERSION,
        "version": RELEASE_VERSION,
    }
    PrayerConfigRelease.objects.filter(pk=release.pk).update(
        status="published",
        is_default=True,
        manifest_checksum_sha256=_checksum(manifest_payload),
        published_at=timezone.now(),
    )


def unseed_reference_release(apps, _schema_editor) -> None:
    PrayerMethod = apps.get_model("prayer_times", "PrayerMethod")
    PrayerConfigRelease = apps.get_model("prayer_times", "PrayerConfigRelease")
    PrayerConfigRelease.objects.filter(version=RELEASE_VERSION).delete()
    PrayerMethod.objects.filter(code__in=[method["code"] for method in METHODS]).delete()


class Migration(migrations.Migration):
    dependencies = [("prayer_times", "0001_initial")]

    operations = [migrations.RunPython(seed_reference_release, unseed_reference_release)]
