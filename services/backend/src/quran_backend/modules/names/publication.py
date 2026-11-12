# Russian messages for the editor intentionally contain Cyrillic letters.
# ruff: noqa: RUF001
"""Imports a list of names, compiles its documents and publishes versions.

Flow, as for the prayer course: import (a draft) or a draft copied from another
version in the admin → the owner edits the names in the admin → signs off →
publish (the previous version is withdrawn, the site is revalidated).
"""

from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping
from typing import Any

from django.db import transaction
from django.utils import timezone

from quran_backend.modules.alerts.services import course_version_event
from quran_backend.modules.core.content_revalidation import enqueue_names_content_change
from quran_backend.modules.names.models import (
    NAMES_LANGUAGES,
    TRANSLITERATION_LANGUAGES,
    DivineName,
    NamesCollection,
    NamesDocument,
    NamesStatus,
    NamesVersion,
)

SCHEMA_VERSION = 1
LANGUAGE_LABELS = {"ru": "русский", "en": "английский", "tr": "турецкий", "ar": "арабский"}


class NamesError(Exception):
    """What keeps a list from being imported, signed or published, line by line."""

    def __init__(self, problems: list[str]) -> None:
        super().__init__("\n".join(problems))
        self.problems = problems


def version_problems(version: NamesVersion) -> list[str]:
    """What is still missing before the owner can sign the version."""
    problems = []
    for field, label in (("list_source", "источник списка"), ("tafsir_source", "толкования")):
        missing = [
            LANGUAGE_LABELS[language]
            for language in NAMES_LANGUAGES
            if not getattr(version, f"{field}_{language}").strip()
        ]
        if missing:
            problems.append(f"Версия: не указан {label} ({', '.join(missing)}).")
    names = list(version.names.order_by("position"))
    if not names:
        problems.append("В версии нет ни одного имени.")
    if [name.position for name in names] != list(range(1, len(names) + 1)):
        problems.append("Номера имён должны идти подряд с 1, без пропусков.")
    for name in names:
        missing = [
            f"{label} [{language}]"
            for field, label, languages in (
                ("transliteration", "имя буквами языка", TRANSLITERATION_LANGUAGES),
                ("meaning", "значение", NAMES_LANGUAGES),
                ("tafsir", "толкование", NAMES_LANGUAGES),
            )
            for language in languages
            if not getattr(name, f"{field}_{language}").strip()
        ]
        if missing:
            problems.append(f"{name}: не заполнено — {', '.join(missing)}.")
        own = [
            bool(getattr(name, f"tafsir_source_{language}").strip()) for language in NAMES_LANGUAGES
        ]
        if any(own) and not all(own):
            problems.append(f"{name}: свой источник толкования указан не на всех языках.")
    return problems


def compile_document(version: NamesVersion, language: str) -> dict[str, Any]:
    return {
        "collection": {
            "slug": version.collection.slug,
            "version": version.version,
            "language": language,
            "published_at": version.published_at.isoformat() if version.published_at else None,
            "list_source": getattr(version, f"list_source_{language}"),
            "tafsir_source": getattr(version, f"tafsir_source_{language}"),
        },
        "names": [
            {
                "slug": name.slug,
                "position": name.position,
                "arabic": name.arabic,
                "transliteration": getattr(name, f"transliteration_{language}", ""),
                "meaning": getattr(name, f"meaning_{language}"),
                "tafsir": getattr(name, f"tafsir_{language}"),
                "tafsir_source": getattr(name, f"tafsir_source_{language}")
                or getattr(version, f"tafsir_source_{language}"),
                "tafsir_ref": name.tafsir_ref,
                "ayah": {"surah": name.surah, "ayah": name.ayah, "word": name.word_position}
                if name.surah and name.ayah
                else None,
            }
            for name in version.names.order_by("position")
        ],
    }


def compile_version(version: NamesVersion) -> list[NamesDocument]:
    """(Re)builds the document of every language from the version's rows."""
    documents = []
    for language in NAMES_LANGUAGES:
        payload = compile_document(version, language)
        encoded = json.dumps(
            payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")
        ).encode()
        document, _ = NamesDocument.objects.update_or_create(
            version=version,
            language=language,
            defaults={
                "payload": payload,
                "checksum_sha256": hashlib.sha256(encoded).hexdigest(),
                "bytes": len(encoded),
            },
        )
        documents.append(document)
    return documents


def _text(value: object, language: str) -> str:
    return str(value.get(language) or "").strip() if isinstance(value, Mapping) else ""


@transaction.atomic
def import_names(data: Mapping[str, Any]) -> NamesVersion:
    """Creates a draft from a data file; a version that already exists is left as it is."""
    if data.get("schema_version") != SCHEMA_VERSION:
        raise NamesError([f"Ожидается schema_version = {SCHEMA_VERSION}."])
    meta = data.get("collection")
    rows = data.get("names")
    if not isinstance(meta, Mapping) or not meta.get("slug") or not meta.get("version"):
        raise NamesError(["Нужны collection.slug и collection.version."])
    if not isinstance(rows, list) or not rows:
        raise NamesError(["Нужен непустой список names."])
    collection, _ = NamesCollection.objects.get_or_create(slug=str(meta["slug"]))
    existing = NamesVersion.objects.filter(
        collection=collection, version=str(meta["version"])
    ).first()
    if existing is not None:
        return existing
    version = NamesVersion.objects.create(
        collection=collection,
        version=str(meta["version"]),
        **{
            f"{field}_{language}": _text(data.get(field), language)
            for field in ("list_source", "tafsir_source")
            for language in NAMES_LANGUAGES
        },
    )
    names = []
    for position, row in enumerate(rows, start=1):
        ayah = row.get("ayah") or {}
        name = DivineName(
            version=version,
            position=position,
            slug=str(row.get("slug") or ""),
            arabic=str(row.get("arabic") or "").strip(),
            tafsir_ref=str(row.get("tafsir_ref") or "").strip(),
            surah=ayah.get("surah"),
            ayah=ayah.get("ayah"),
            word_position=ayah.get("word"),
            **{
                f"{field}_{language}": _text(row.get(field), language)
                for field, languages in (
                    ("transliteration", TRANSLITERATION_LANGUAGES),
                    ("meaning", NAMES_LANGUAGES),
                    ("tafsir", NAMES_LANGUAGES),
                    ("tafsir_source", NAMES_LANGUAGES),
                )
                for language in languages
            },
        )
        try:
            name.full_clean(exclude=["version"], validate_constraints=False)
        except Exception as error:
            raise NamesError([f"Имя {position} ({name.arabic}): {error}"]) from error
        names.append(name)
    slugs = [name.slug for name in names]
    if len(set(slugs)) != len(slugs):
        raise NamesError(["Коды имён (slug) повторяются."])
    DivineName.objects.bulk_create(names)
    return version


def sign_names_version(version: NamesVersion, user: Any, note: str = "") -> None:
    """The owner's sign-off of a complete draft: every card in every language."""
    problems = version_problems(version)
    if problems:
        raise NamesError(problems)
    version.sign(user, note)
    compile_version(version)


@transaction.atomic
def copy_names_version(source: NamesVersion, version: str) -> NamesVersion:
    """A new draft with the names of `source`, which stays as it is."""
    if NamesVersion.objects.filter(collection=source.collection, version=version).exists():
        raise NamesError([f"Версия {version} уже есть."])
    copied = {
        field.attname
        for field in NamesVersion._meta.concrete_fields
        if field.name.startswith(("list_source_", "tafsir_source_"))
    }
    draft = NamesVersion.objects.create(
        collection=source.collection,
        version=version,
        **{name: getattr(source, name) for name in copied},
    )
    skipped = {"id", "version_id", "created_at", "updated_at"}
    fields = [f.attname for f in DivineName._meta.concrete_fields if f.attname not in skipped]
    DivineName.objects.bulk_create(
        DivineName(version=draft, **{field: getattr(name, field) for field in fields})
        for name in source.names.all()
    )
    course_version_event(draft, "draft")
    return draft


@transaction.atomic
def publish_names_version(version: NamesVersion) -> NamesVersion:
    """Publishes a signed draft and makes it the list's active version."""
    version = (
        NamesVersion.objects.select_for_update().select_related("collection").get(pk=version.pk)
    )
    if version.status != NamesStatus.DRAFT:
        raise NamesError(["Опубликовать можно только черновик."])
    if not version.is_signed:
        raise NamesError(["Версию нужно сначала подписать."])
    problems = version_problems(version)
    if problems:
        raise NamesError(problems)
    collection = NamesCollection.objects.select_for_update().get(pk=version.collection_id)
    previous = collection.active_version
    if previous is not None:
        previous.status = NamesStatus.WITHDRAWN
        previous.save(update_fields=["status", "updated_at"])
    version.status = NamesStatus.PUBLISHED
    version.published_at = timezone.now()
    version.save(update_fields=["status", "published_at", "updated_at"])
    compile_version(version)
    collection.active_version = version
    collection.save(update_fields=["active_version", "updated_at"])
    enqueue_names_content_change(
        action="activated", collection=collection.slug, version=version.version
    )
    course_version_event(version, "published")
    return version
