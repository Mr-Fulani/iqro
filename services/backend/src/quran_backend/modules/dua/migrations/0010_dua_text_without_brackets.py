import json
from pathlib import Path

from django.db import migrations, models


def clean_texts(apps, schema_editor):  # noqa: ARG001
    """Replace the bracketed source texts with their cleaned reading.

    The sources wrap the du'a in (( )), add the repetition count in brackets after
    it and put commentary in brackets inside the translation. The data file holds,
    per entry and language, the text without brackets and the commentary as a
    separate note; the Arabic edition's meaning is the du'a itself, so it follows
    the cleaned Arabic.
    """

    snapshot_path = Path(__file__).resolve().parents[1] / "data" / "dua_text_cleanup_v1.json"
    snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
    entry_model = apps.get_model("dua", "DuaEntry")
    translation_model = apps.get_model("dua", "DuaEntryTranslation")
    variant_model = apps.get_model("dua", "DuaEntryTimeVariant")
    for collection in snapshot["collections"]:
        entries = {
            entry.source_number: entry
            for entry in entry_model.objects.filter(
                collection_version__collection__slug=collection["collection"],
                collection_version__version=collection["version"],
            )
        }
        for item in collection["entries"]:
            entry = entries.get(item["source_number"])
            if entry is None:
                continue
            translations = translation_model.objects.filter(entry=entry)
            if "arabic_text" in item:
                entry.arabic_text = item["arabic_text"]
                entry.save(update_fields=("arabic_text", "updated_at"))
                translations.filter(language_code="ar").update(meaning_text=item["arabic_text"])
            for language_code, fields in item.get("translations", {}).items():
                translations.filter(language_code=language_code).update(**fields)
            for time_of_day, variant in item.get("time_variants", {}).items():
                rows = variant_model.objects.filter(entry=entry, time_of_day=time_of_day)
                if "arabic_text" in variant:
                    rows.update(arabic_text=variant["arabic_text"])
                    rows.filter(language_code="ar").update(meaning_text=variant["arabic_text"])
                for language_code, fields in variant.get("translations", {}).items():
                    rows.filter(language_code=language_code).update(**fields)


class Migration(migrations.Migration):
    dependencies = [
        ("dua", "0009_dua_entry_time_variants"),
    ]

    operations = [
        migrations.AddField(
            model_name="duaentrytranslation",
            name="note",
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name="duaentrytimevariant",
            name="note",
            field=models.TextField(blank=True),
        ),
        migrations.RunPython(clean_texts, migrations.RunPython.noop),
    ]
