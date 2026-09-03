import hashlib
import json
from pathlib import Path

from django.db import migrations
from django.utils import timezone


def _snapshot():
    path = Path(__file__).resolve().parents[1] / "data" / "supplications_from_quran_jmapps_v1.json"
    payload = json.loads(path.read_text(encoding="utf-8"))
    checksum = hashlib.sha256(
        json.dumps(
            payload,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode()
    ).hexdigest()
    return payload, checksum


def _publish_version(collection, version):
    previous = collection.active_version
    if previous and previous.pk != version.pk:
        previous.status = "withdrawn"
        previous.save(update_fields=("status", "updated_at"))
    version.status = "published"
    if version.published_at is None:
        version.published_at = timezone.now()
    version.save(update_fields=("status", "published_at", "updated_at"))
    collection.active_version = version
    collection.save(update_fields=("active_version", "updated_at"))


def seed_quran_supplications(apps, schema_editor):  # noqa: ARG001
    snapshot, checksum = _snapshot()
    collection_model = apps.get_model("dua", "DuaCollection")
    version_model = apps.get_model("dua", "DuaCollectionVersion")
    source_model = apps.get_model("dua", "DuaSourceEdition")
    category_model = apps.get_model("dua", "DuaCategory")
    category_translation_model = apps.get_model("dua", "DuaCategoryTranslation")
    entry_model = apps.get_model("dua", "DuaEntry")
    entry_translation_model = apps.get_model("dua", "DuaEntryTranslation")
    evidence_model = apps.get_model("dua", "DuaEvidence")
    audio_model = apps.get_model("dua", "DuaAudioAsset")

    collection, _ = collection_model.objects.get_or_create(slug=snapshot["collection"]["slug"])
    version, created = version_model.objects.get_or_create(
        collection=collection,
        version=snapshot["version"],
        defaults={
            "schema_version": snapshot["schema_version"],
            "checksum_sha256": checksum,
            "status": "draft",
            "category_count": len(snapshot["categories"]),
            "entry_count": len(snapshot["entries"]),
        },
    )
    if not created:
        if version.checksum_sha256 != checksum:
            raise RuntimeError("The Quran supplications version exists with a different checksum.")
        _publish_version(collection, version)
        return

    for source in snapshot["sources"]:
        source_model.objects.create(
            collection_version=version,
            language_code=source["language"],
            provider=source["provider"],
            source_item_id=source["source_item_id"],
            title=source["title"],
            author=source.get("author", ""),
            translator=source.get("translator", ""),
            reviewer=source.get("reviewer", ""),
            source_url=source["source_url"],
            rights_url=source.get("rights_url", ""),
            rights_basis=source["rights_basis"],
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
            repetition_label=payload.get("repetition_label", ""),
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

    audio_model.objects.bulk_create(
        [
            audio_model(
                collection=collection,
                collection_version=version,
                source_number=audio["source_number"],
                language_code=audio["language_code"],
                provider=audio["provider"],
                reader_name=audio.get("reader_name", ""),
                reader_name_ar=audio.get("reader_name_ar", ""),
                external_url=audio["external_url"],
                object_key=None,
                content_type=audio.get("content_type", "audio/mpeg"),
                size_bytes=audio.get("size_bytes", 0),
                checksum_sha256=audio.get("checksum_sha256", ""),
                source_url=audio["source_url"],
                rights_url=audio.get("rights_url", ""),
                rights_basis=audio["rights_basis"],
                source_version=audio["source_version"],
                sort_order=audio.get("sort_order", 1),
                is_active=audio.get("is_active", True),
            )
            for audio in snapshot.get("audio", [])
        ]
    )
    _publish_version(collection, version)


def withdraw_quran_supplications(apps, schema_editor):  # noqa: ARG001
    collection_model = apps.get_model("dua", "DuaCollection")
    version_model = apps.get_model("dua", "DuaCollectionVersion")
    collection = collection_model.objects.filter(slug="supplications-from-quran").first()
    if collection is None:
        return
    version = version_model.objects.filter(
        collection=collection,
        version="jmapps-bd4eef1",
    ).first()
    if version is None:
        return
    if collection.active_version_id == version.pk:
        collection.active_version = None
        collection.save(update_fields=("active_version", "updated_at"))
    version.status = "withdrawn"
    version.save(update_fields=("status", "updated_at"))


class Migration(migrations.Migration):
    dependencies = [
        ("dua", "0007_version_scoped_dua_audio"),
    ]

    operations = [
        migrations.RunPython(seed_quran_supplications, withdraw_quran_supplications),
    ]
