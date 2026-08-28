import hashlib
import json
from pathlib import Path

from django.db import migrations
from django.utils import timezone


def seed_hisn_starter(apps, schema_editor):  # noqa: ARG001
    snapshot_path = Path(__file__).resolve().parents[1] / "data" / "hisn_al_muslim_starter_v1.json"
    snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
    checksum = hashlib.sha256(
        json.dumps(
            snapshot,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode()
    ).hexdigest()

    collection_model = apps.get_model("dua", "DuaCollection")
    version_model = apps.get_model("dua", "DuaCollectionVersion")
    source_edition_model = apps.get_model("dua", "DuaSourceEdition")
    category_model = apps.get_model("dua", "DuaCategory")
    category_translation_model = apps.get_model("dua", "DuaCategoryTranslation")
    entry_model = apps.get_model("dua", "DuaEntry")
    entry_translation_model = apps.get_model("dua", "DuaEntryTranslation")
    evidence_model = apps.get_model("dua", "DuaEvidence")

    collection, _ = collection_model.objects.get_or_create(slug=snapshot["collection"]["slug"])
    version, created = version_model.objects.get_or_create(
        collection=collection,
        version=snapshot["version"],
        defaults={
            "schema_version": snapshot["schema_version"],
            "checksum_sha256": checksum,
            "status": "published",
            "category_count": len(snapshot["categories"]),
            "entry_count": len(snapshot["entries"]),
            "published_at": timezone.now(),
        },
    )
    if not created:
        if version.checksum_sha256 != checksum:
            raise RuntimeError("Hisn starter version exists with a different checksum.")
        collection.active_version = version
        collection.save(update_fields=("active_version", "updated_at"))
        return

    for source in snapshot["sources"]:
        source_edition_model.objects.create(
            collection_version=version,
            language_code=source["language"],
            provider=source["provider"],
            source_item_id=source["source_item_id"],
            title=source["title"],
            author=source["author"],
            translator=source.get("translator", ""),
            reviewer=source.get("reviewer", ""),
            source_url=source["source_url"],
            rights_url=source["rights_url"],
            source_version=source["source_version"],
        )

    categories = {}
    for sort_order, payload in enumerate(snapshot["categories"], start=1):
        category = category_model.objects.create(
            collection_version=version,
            source_number=payload["source_number"],
            slug=payload["slug"],
            sort_order=sort_order,
        )
        categories[category.source_number] = category
        for translation in payload["translations"]:
            category_translation_model.objects.create(
                category=category,
                language_code=translation["language"],
                title=translation["title"],
            )

    for sort_order, payload in enumerate(snapshot["entries"], start=1):
        entry = entry_model.objects.create(
            collection_version=version,
            category=categories[payload["category_source_number"]],
            source_number=payload["source_number"],
            slug=payload["slug"],
            arabic_text=payload["arabic_text"],
            repetitions=payload.get("repetitions", 1),
            sort_order=sort_order,
        )
        for translation in payload["translations"]:
            entry_translation_model.objects.create(
                entry=entry,
                language_code=translation["language"],
                meaning_text=translation["meaning_text"],
                transliteration=translation.get("transliteration", ""),
            )
        for evidence_order, evidence in enumerate(payload.get("evidence", []), start=1):
            evidence_model.objects.create(
                entry=entry,
                kind=evidence["kind"],
                provider=evidence["provider"],
                source_name=evidence["source_name"],
                source_reference=evidence["source_reference"],
                source_url=evidence.get("source_url", ""),
                grade=evidence.get("grade", ""),
                external_id=evidence.get("external_id", ""),
                verification_status=evidence.get("verification_status", "source_only"),
                sort_order=evidence_order,
            )

    collection.active_version = version
    collection.save(update_fields=("active_version", "updated_at"))


class Migration(migrations.Migration):
    dependencies = [("dua", "0001_initial")]

    operations = [
        migrations.RunPython(seed_hisn_starter, migrations.RunPython.noop),
    ]
