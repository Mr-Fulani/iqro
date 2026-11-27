"""Release 2026.2: the methods of 2026.1 on tzdata 2026.5 (IANA 2026e).

The backend calculates only with releases recorded for its installed tzdata, so
a tzdata update needs a new release. The configurations move into it with
their ids, and 2026.1 keeps copies with the same checksums, so its manifest
stays valid. The app, the site, profiles and Web Push reminders keep the ids
they hold: the method stays as chosen, and the times follow the new tzdata.
"""

from __future__ import annotations

import hashlib
import json
import uuid

from django.db import migrations
from django.utils import timezone

PREVIOUS_VERSION = "2026.1"
PREVIOUS_TZDB_VERSION = "2026.3"
RELEASE_VERSION = "2026.2"
TZDB_VERSION = "2026.5"
NAMESPACE = uuid.UUID("d6bf47f2-dd2b-5a82-9b0e-e3db5f147d89")
NOT_COPIED = {"id", "release", "created_at", "updated_at"}


def _identifier(kind: str, value: str) -> uuid.UUID:
    return uuid.uuid5(NAMESPACE, f"{kind}:{value}")


def _manifest_checksum(release, configurations) -> str:
    payload = {
        "algorithm": release.algorithm,
        "algorithm_version": release.algorithm_version,
        "configuration_schema_version": release.configuration_schema_version,
        "methods": [
            {"checksum_sha256": configuration.checksum_sha256, "code": configuration.method.code}
            for configuration in configurations
        ],
        "timezone_database_version": release.timezone_database_version,
        "version": release.version,
    }
    serialized = json.dumps(
        payload,
        ensure_ascii=True,
        separators=(",", ":"),
        sort_keys=True,
    ).encode()
    return hashlib.sha256(serialized).hexdigest()


def _configurations(config_model, release) -> list:
    return list(
        config_model.objects.filter(release=release)
        .select_related("method")
        .order_by("method__code", "id")
    )


def publish_release(apps, _schema_editor) -> None:
    release_model = apps.get_model("prayer_times", "PrayerConfigRelease")
    config_model = apps.get_model("prayer_times", "PrayerMethodConfig")

    previous = release_model.objects.filter(version=PREVIOUS_VERSION).first()
    if previous is None:
        # No reference data to replace, as in a flushed test database.
        return
    if (
        previous.status != "published"
        or not previous.is_default
        or previous.timezone_database_version != PREVIOUS_TZDB_VERSION
    ):
        msg = (
            f"Release {PREVIOUS_VERSION} must be the published default on {PREVIOUS_TZDB_VERSION}."
        )
        raise RuntimeError(msg)
    release = release_model.objects.create(
        id=_identifier("release", RELEASE_VERSION),
        version=RELEASE_VERSION,
        configuration_schema_version=previous.configuration_schema_version,
        algorithm=previous.algorithm,
        algorithm_version=previous.algorithm_version,
        timezone_database_version=TZDB_VERSION,
        release_notes=(
            f"The methods of {PREVIOUS_VERSION} with the same ids, on tzdata {TZDB_VERSION} "
            "(IANA 2026e: Morocco on +00 from 2026-09-20; British Columbia, Alberta, "
            "Manitoba and Inuvik without clock changes from 2026-11-01)."
        ),
    )
    fields = [
        field.attname
        for field in config_model._meta.concrete_fields
        if field.name not in NOT_COPIED
    ]
    now = timezone.now()
    for configuration in _configurations(config_model, previous):
        config_model.objects.filter(pk=configuration.pk).update(release=release, updated_at=now)
        config_model.objects.create(
            id=_identifier(
                "config",
                f"{PREVIOUS_VERSION}:{configuration.method.code}:tzdata-{PREVIOUS_TZDB_VERSION}",
            ),
            release=previous,
            **{field: getattr(configuration, field) for field in fields},
        )
    if _manifest_checksum(previous, _configurations(config_model, previous)) != (
        previous.manifest_checksum_sha256
    ):
        msg = f"The copies changed the manifest of {PREVIOUS_VERSION}."
        raise RuntimeError(msg)
    # The previous default goes first: only one published release may be the default.
    release_model.objects.filter(pk=previous.pk).update(is_default=False, updated_at=now)
    release_model.objects.filter(pk=release.pk).update(
        status="published",
        is_default=True,
        manifest_checksum_sha256=_manifest_checksum(
            release, _configurations(config_model, release)
        ),
        published_at=now,
        updated_at=now,
    )


def restore_previous_release(apps, _schema_editor) -> None:
    release_model = apps.get_model("prayer_times", "PrayerConfigRelease")
    config_model = apps.get_model("prayer_times", "PrayerMethodConfig")

    release = release_model.objects.filter(version=RELEASE_VERSION).first()
    if release is None:
        return
    previous = release_model.objects.get(version=PREVIOUS_VERSION)
    now = timezone.now()
    for configuration in _configurations(config_model, release):
        # Nothing refers to the copy: clients only ever saw the moved id.
        config_model.objects.filter(release=previous, method_id=configuration.method_id).delete()
        config_model.objects.filter(pk=configuration.pk).update(release=previous, updated_at=now)
    release_model.objects.filter(pk=release.pk).update(is_default=False, updated_at=now)
    release_model.objects.filter(pk=previous.pk).update(is_default=True, updated_at=now)
    release_model.objects.filter(pk=release.pk).delete()


class Migration(migrations.Migration):
    dependencies = [("prayer_times", "0005_load_prayer_cities")]

    operations = [migrations.RunPython(publish_release, restore_previous_release)]
