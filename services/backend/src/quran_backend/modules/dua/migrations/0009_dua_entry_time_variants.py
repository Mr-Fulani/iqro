import json
import uuid
from pathlib import Path

import django.db.models.deletion
from django.db import migrations, models


def seed_time_variants(apps, schema_editor):  # noqa: ARG001
    """Give the morning and evening adhkar cards their own reading of chapter 27.

    The data file lists, per entry and time, the Arabic and the translations that
    differ from the source; every other language keeps the source text, so each
    listed entry gets a row for every language it is published in.
    """

    snapshot_path = (
        Path(__file__).resolve().parents[1] / "data" / "hisn_al_muslim_time_variants_v1.json"
    )
    snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
    entry_model = apps.get_model("dua", "DuaEntry")
    variant_model = apps.get_model("dua", "DuaEntryTimeVariant")
    entries = {
        entry.source_number: entry
        for entry in entry_model.objects.filter(
            collection_version__collection__slug=snapshot["collection"],
            collection_version__version=snapshot["version"],
            source_number__in=[item["source_number"] for item in snapshot["entries"]],
        ).prefetch_related("translations")
    }
    for item in snapshot["entries"]:
        entry = entries.get(item["source_number"])
        if entry is None:
            continue
        for time_of_day in ("morning", "evening"):
            variant = item.get(time_of_day)
            if variant is None:
                continue
            arabic_text = variant.get("arabic_text", entry.arabic_text)
            for translation in entry.translations.all():
                override = variant.get("translations", {}).get(translation.language_code, {})
                # The Arabic edition's meaning is the du'a itself.
                default_meaning = (
                    arabic_text if translation.language_code == "ar" else translation.meaning_text
                )
                variant_model.objects.update_or_create(
                    entry=entry,
                    time_of_day=time_of_day,
                    language_code=translation.language_code,
                    defaults={
                        "arabic_text": arabic_text,
                        "meaning_text": override.get("meaning_text", default_meaning),
                        "transliteration": override.get(
                            "transliteration", translation.transliteration
                        ),
                    },
                )


class Migration(migrations.Migration):
    dependencies = [
        ("dua", "0008_seed_quran_supplications"),
    ]

    operations = [
        migrations.CreateModel(
            name="DuaEntryTimeVariant",
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
                    "time_of_day",
                    models.CharField(
                        choices=[("morning", "Morning"), ("evening", "Evening")], max_length=8
                    ),
                ),
                ("language_code", models.CharField(max_length=8)),
                ("arabic_text", models.TextField()),
                ("meaning_text", models.TextField()),
                ("transliteration", models.TextField(blank=True)),
                (
                    "entry",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="time_variants",
                        to="dua.duaentry",
                    ),
                ),
            ],
            options={
                "db_table": "dua_entry_time_variant",
                "ordering": ("time_of_day", "language_code"),
                "constraints": [
                    models.UniqueConstraint(
                        fields=("entry", "time_of_day", "language_code"),
                        name="dua_entry_time_variant_unique",
                    )
                ],
            },
        ),
        migrations.RunPython(seed_time_variants, migrations.RunPython.noop),
    ]
