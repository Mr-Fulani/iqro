from __future__ import annotations

import argparse
import json
import re
import unicodedata
from copy import deepcopy
from pathlib import Path
from typing import Any

ARABIC_RE = re.compile(r"[\u0600-\u06ff]")
CYRILLIC_RE = re.compile(r"[\u0400-\u04ff]")
LATIN_RE = re.compile(r"[\u0041-\u005a\u0061-\u007a\u00c0-\u024f]")
SPACE_RE = re.compile(r"\s+")
RU_ENTRY_RE = re.compile(r"^\s*(\d{1,3})(?:[.:-]|\s)\s*(.*)$")
TR_ENTRY_RE = re.compile(r"^\s*(\d{1,3})(?:[.:-]|\s)\s*(.*)$")
RU_CATEGORY_RE = re.compile(r"^\s*(\d{1,3})\.\s+(.+?)\s*$")

EXPECTED_CATEGORIES = 132
EXPECTED_ENTRIES = 267
REPETITION_OVERRIDES = {
    67: 3,
    83: 7,
    106: 33,
    114: 3,
    119: 3,
    130: 3,
    138: 3,
    148: 7,
}
REPETITION_LABELS = {106: "33 · 33 · 34"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build the versioned full Hisn al-Muslim Dua snapshot.",
    )
    parser.add_argument("--api-root", type=Path, required=True)
    parser.add_argument("--russian-text", type=Path, required=True)
    parser.add_argument("--turkish-text", type=Path, required=True)
    parser.add_argument("--starter", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def read_json(path: Path) -> Any:
    raw = path.read_text(encoding="utf-8-sig")
    sanitized = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]", "", raw)
    sanitized = re.sub(r'^(\s*"[^"\r\n]+):\s*$', r'\1":', sanitized, flags=re.MULTILINE)
    try:
        return json.loads(sanitized)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid API JSON in {path}: {exc}") from exc


def compact(value: str) -> str:
    return SPACE_RE.sub(" ", value.replace("\ufeff", " ")).strip()


def strip_outer_punctuation(value: str) -> str:
    result = compact(value).strip(' \t\r\n"\u201c\u201d\u2018\u2019')
    while result.startswith("("):
        body = result[:-1] if result.endswith(".") else result
        if not body.endswith(")"):
            break
        depth = 0
        closing_index = None
        for index, character in enumerate(body):
            if character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
                if depth == 0:
                    closing_index = index
                    break
        if closing_index != len(body) - 1:
            break
        result = body[1:-1].strip()
    return result


def slugify(value: str) -> str:
    ascii_value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
    slug = re.sub(r"[^a-z0-9]+", "-", ascii_value.lower()).strip("-")
    return slug or "section"


def first_object_value(payload: Any, *, source: Path) -> list[dict[str, Any]]:
    if not isinstance(payload, dict) or len(payload) != 1:
        raise ValueError(f"Unexpected HisnMuslim API payload in {source}")
    value = next(iter(payload.values()))
    if not isinstance(value, list):
        raise ValueError(f"Expected an array in {source}")
    return value


def load_api_language(
    root: Path, language: str
) -> tuple[dict[int, str], dict[int, list[dict[str, Any]]]]:
    language_root = root / language
    index_items = first_object_value(read_json(language_root / "index.json"), source=language_root)
    titles = {int(item["ID"]): compact(str(item["TITLE"])) for item in index_items}
    chapters: dict[int, list[dict[str, Any]]] = {}
    for source_number in range(1, EXPECTED_CATEGORIES + 1):
        path = language_root / f"{source_number}.json"
        chapters[source_number] = first_object_value(read_json(path), source=path)
    if set(titles) != set(chapters):
        raise ValueError(f"{language} API index and chapter files do not match")
    return titles, chapters


def find_sequential_markers(
    lines: list[str],
    pattern: re.Pattern[str],
    *,
    end: int | None = None,
    reject_heading: bool = False,
) -> list[tuple[int, str]]:
    markers: list[tuple[int, str]] = []
    cursor = 0
    limit = len(lines) if end is None else end
    for expected in range(1, EXPECTED_ENTRIES + 1):
        for index in range(cursor, limit):
            match = pattern.match(lines[index])
            if not match or int(match.group(1)) != expected:
                continue
            remainder = compact(match.group(2))
            if reject_heading and remainder and remainder.upper() == remainder:
                continue
            markers.append((index, remainder))
            cursor = index + 1
            break
        else:
            raise ValueError(f"Unable to find entry {expected} after line {cursor + 1}")
    return markers


def parse_russian_categories(lines: list[str]) -> tuple[dict[int, str], int]:
    candidates: dict[int, list[tuple[int, str]]] = {}
    for index, line in enumerate(lines):
        match = RU_CATEGORY_RE.match(line)
        if not match:
            continue
        source_number = int(match.group(1))
        if 1 <= source_number <= EXPECTED_CATEGORIES:
            candidates.setdefault(source_number, []).append((index, compact(match.group(2))))
    categories = {number: values[-1][1].rstrip(".") for number, values in candidates.items()}
    if len(categories) != EXPECTED_CATEGORIES:
        missing = sorted(set(range(1, EXPECTED_CATEGORIES + 1)).difference(categories))
        raise ValueError(f"Russian category index is incomplete: {missing}")
    toc_start = candidates[1][-1][0]
    bibliography_starts = [
        index
        for index, line in enumerate(lines[:toc_start])
        if compact(line).startswith("СПИСОК ИСПОЛЬЗОВАННЫХ ИСТОЧНИКОВ")
    ]
    body_end = bibliography_starts[-1] if bibliography_starts else toc_start
    return categories, body_end


def is_mostly_arabic(value: str) -> bool:
    arabic = len(ARABIC_RE.findall(value))
    latin_or_cyrillic = len(CYRILLIC_RE.findall(value)) + len(LATIN_RE.findall(value))
    return arabic > latin_or_cyrillic


def clean_source_line(value: str) -> str:
    result = compact(value)
    result = re.sub(r"^\(\d+/\d+\)\s*", "", result)
    result = re.sub(r"(?<=[.!?\"”])\d{1,2}$", "", result)
    result = re.sub(r"^[\"“”«»]+|[\"“”«»]+$", "", result)
    return result.strip()


def parse_russian_entries(lines: list[str], *, body_end: int) -> dict[int, dict[str, str]]:
    markers = find_sequential_markers(
        lines,
        RU_ENTRY_RE,
        end=body_end,
        reject_heading=True,
    )
    result: dict[int, dict[str, str]] = {}
    for offset, (start, remainder) in enumerate(markers):
        stop = markers[offset + 1][0] if offset + 1 < len(markers) else body_end
        block = [remainder, *lines[start + 1 : stop]]
        translation_index = next(
            (index for index, line in enumerate(block) if compact(line).startswith("Перевод:")),
            None,
        )
        if translation_index is not None:
            first = compact(block[translation_index]).removeprefix("Перевод:").strip()
            meaning_lines = [first, *block[translation_index + 1 :]]
        else:
            meaning_lines = block
        meaning_parts = []
        for line in meaning_lines:
            cleaned = clean_source_line(line)
            if not cleaned or is_mostly_arabic(cleaned) or not CYRILLIC_RE.search(cleaned):
                continue
            if cleaned.upper() == cleaned and len(cleaned) > 12:
                continue
            meaning_parts.append(cleaned)
        meaning = compact(" ".join(meaning_parts))

        transliteration = ""
        if translation_index is not None and remainder.lstrip().startswith(('"', "“", "«")):
            transliteration_parts = []
            for line in block[:translation_index]:
                cleaned = clean_source_line(line)
                if not cleaned or is_mostly_arabic(cleaned):
                    continue
                transliteration_parts.append(cleaned)
            transliteration = compact(" ".join(transliteration_parts))
        if not meaning:
            raise ValueError(f"Russian meaning is empty for entry {offset + 1}")
        result[offset + 1] = {
            "meaning_text": meaning,
            "transliteration": transliteration,
        }
    return result


def parse_turkish_categories(lines: list[str]) -> dict[int, str]:
    start = next(index for index, line in enumerate(lines) if line.startswith("UYKUDAN UYANINCA"))
    end = next(
        index for index, line in enumerate(lines[start:], start) if line.startswith("BAZI HAYIR")
    )
    raw_titles = lines[start : end + 1]
    titles = []
    for line in raw_titles:
        title = re.sub(r"\s+\d+\s*$", "", compact(line)).rstrip(":.")
        if title:
            titles.append(title)
    if len(titles) != EXPECTED_CATEGORIES:
        raise ValueError(f"Expected 132 Turkish categories, found {len(titles)}")
    return dict(enumerate(titles, start=1))


def parse_turkish_entries(
    lines: list[str],
    *,
    categories: dict[int, str],
) -> dict[int, dict[str, str]]:
    body_start = next(
        index
        for index, line in enumerate(lines)
        if index > EXPECTED_CATEGORIES and line.startswith("UYKUDAN UYANINCA")
    )
    candidates: dict[int, list[tuple[int, str]]] = {}
    for index, line in enumerate(lines[body_start:], start=body_start):
        match = TR_ENTRY_RE.match(line)
        if not match:
            continue
        source_number = int(match.group(1))
        if 1 <= source_number <= EXPECTED_ENTRIES:
            candidates.setdefault(source_number, []).append(
                (index, compact(match.group(2))),
            )
    missing = sorted(set(range(1, EXPECTED_ENTRIES + 1)).difference(candidates))
    if missing:
        raise ValueError(f"Turkish entries are missing source numbers: {missing}")

    duplicates = {
        source_number: values for source_number, values in candidates.items() if len(values) != 1
    }
    if duplicates:
        duplicate_summary = ", ".join(
            f"{source_number} ({len(values)})"
            for source_number, values in sorted(duplicates.items())
        )
        raise ValueError(f"Turkish entries contain duplicate markers: {duplicate_summary}")

    selected = {source_number: values[0] for source_number, values in candidates.items()}
    physical_markers = sorted(
        (index, source_number, remainder) for source_number, (index, remainder) in selected.items()
    )
    next_marker = {
        index: physical_markers[offset + 1][0] if offset + 1 < len(physical_markers) else len(lines)
        for offset, (index, _, _) in enumerate(physical_markers)
    }
    category_titles = {compact(title).upper() for title in categories.values()}
    result: dict[int, dict[str, str]] = {}
    for source_number in range(1, EXPECTED_ENTRIES + 1):
        start, remainder = selected[source_number]
        stop = next_marker[start]
        block = [remainder, *lines[start + 1 : stop]]
        meaning_parts = []
        for line in block:
            cleaned = clean_source_line(line)
            if not cleaned or is_mostly_arabic(cleaned) or not LATIN_RE.search(cleaned):
                continue
            if cleaned.upper().rstrip(":.") in category_titles:
                continue
            if cleaned.startswith("[") and cleaned.endswith("]"):
                continue
            meaning_parts.append(cleaned)
        meaning = compact(" ".join(meaning_parts))
        if not meaning:
            raise ValueError(f"Turkish meaning is empty for entry {source_number}")
        result[source_number] = {"meaning_text": meaning, "transliteration": ""}
    return result


def starter_maps(
    snapshot: dict[str, Any],
) -> tuple[dict[int, dict[str, Any]], dict[int, dict[str, Any]]]:
    categories = {int(item["source_number"]): item for item in snapshot["categories"]}
    entries = {int(item["source_number"]): item for item in snapshot["entries"]}
    return categories, entries


def localized_title(
    language: str,
    source_number: int,
    *,
    api_titles: dict[str, dict[int, str]],
    russian_categories: dict[int, str],
    turkish_categories: dict[int, str],
) -> str:
    if language in api_titles:
        return api_titles[language][source_number]
    if language == "ru":
        return russian_categories[source_number]
    return turkish_categories[source_number]


def build_snapshot(args: argparse.Namespace) -> dict[str, Any]:  # noqa: PLR0915
    api_titles: dict[str, dict[int, str]] = {}
    api_chapters: dict[str, dict[int, list[dict[str, Any]]]] = {}
    for language in ("ar", "en"):
        api_titles[language], api_chapters[language] = load_api_language(
            args.api_root,
            language,
        )
    for source_number in range(1, EXPECTED_CATEGORIES + 1):
        if len(api_chapters["ar"][source_number]) != len(api_chapters["en"][source_number]):
            raise ValueError(f"AR/EN entry count differs in category {source_number}")

    russian_lines = args.russian_text.read_text(encoding="utf-8-sig").splitlines()
    turkish_lines = args.turkish_text.read_text(encoding="utf-8-sig").splitlines()
    russian_categories, russian_body_end = parse_russian_categories(russian_lines)
    turkish_categories = parse_turkish_categories(turkish_lines)
    russian_entries = parse_russian_entries(russian_lines, body_end=russian_body_end)
    turkish_entries = parse_turkish_entries(turkish_lines, categories=turkish_categories)

    starter = read_json(args.starter)
    starter_categories, starter_entries = starter_maps(starter)
    categories: list[dict[str, Any]] = []
    entries: list[dict[str, Any]] = []
    next_entry_number = 1
    for category_number in range(1, EXPECTED_CATEGORIES + 1):
        english_title = api_titles["en"][category_number]
        starter_category = starter_categories.get(category_number)
        translations = []
        for language in ("ar", "en", "ru", "tr"):
            title = localized_title(
                language,
                category_number,
                api_titles=api_titles,
                russian_categories=russian_categories,
                turkish_categories=turkish_categories,
            )
            if starter_category:
                previous = next(
                    item
                    for item in starter_category["translations"]
                    if item["language"] == language
                )
                title = previous["title"]
            translations.append({"language": language, "title": title})
        categories.append(
            {
                "source_number": category_number,
                "slug": (
                    starter_category["slug"]
                    if starter_category
                    else f"{category_number:03d}-{slugify(english_title)[:100]}"
                ),
                "translations": translations,
            }
        )

        arabic_items = api_chapters["ar"][category_number]
        english_items = api_chapters["en"][category_number]
        for arabic_item, english_item in zip(arabic_items, english_items, strict=True):
            source_number = next_entry_number
            next_entry_number += 1
            previous_entry = starter_entries.get(source_number)
            arabic_text = strip_outer_punctuation(
                str(arabic_item.get("ARABIC_TEXT") or arabic_item.get("Text") or "")
            )
            translated_text = strip_outer_punctuation(
                str(english_item.get("TRANSLATED_TEXT") or "")
            )
            language_text = strip_outer_punctuation(
                str(english_item.get("LANGUAGE_ARABIC_TRANSLATED_TEXT") or "")
            )
            english_meaning = translated_text or language_text
            english_transliteration = language_text if translated_text else ""
            if not arabic_text or not english_meaning:
                raise ValueError(f"AR/EN content is empty for entry {source_number}")
            repetitions = REPETITION_OVERRIDES.get(
                source_number,
                int(arabic_item.get("REPEAT") or 1),
            )
            translations = [
                {"language": "ar", "meaning_text": arabic_text},
                {
                    "language": "en",
                    "meaning_text": english_meaning,
                    "transliteration": english_transliteration,
                },
                {"language": "ru", **russian_entries[source_number]},
                {"language": "tr", **turkish_entries[source_number]},
            ]
            evidence = [
                {
                    "kind": "source_note",
                    "provider": "islamhouse",
                    "source_name": "Hisn al-Muslim",
                    "source_reference": f"Hisn al-Muslim, entry {source_number}.",
                    "source_url": "https://islamhouse.com/en/books/39062",
                    "verification_status": "source_only",
                }
            ]
            slug = f"hisn-entry-{source_number:03d}"
            if previous_entry:
                slug = previous_entry["slug"]
                arabic_text = previous_entry["arabic_text"]
                previous_translations = {
                    item["language"]: item for item in previous_entry["translations"]
                }
                for translation in translations:
                    previous_translation = previous_translations[translation["language"]]
                    translation.update(previous_translation)
                evidence = deepcopy(previous_entry.get("evidence", evidence))
            entry = {
                "source_number": source_number,
                "category_source_number": category_number,
                "slug": slug,
                "arabic_text": arabic_text,
                "repetitions": repetitions,
                "translations": translations,
                "evidence": evidence,
            }
            if source_number in REPETITION_LABELS:
                entry["repetition_label"] = REPETITION_LABELS[source_number]
            entries.append(entry)

    if next_entry_number - 1 != EXPECTED_ENTRIES:
        raise ValueError(f"Expected 267 entries, found {next_entry_number - 1}")
    return {
        "schema_version": 1,
        "version": "hisn-full-2026-08-28",
        "collection": {"slug": "hisn-al-muslim"},
        "sources": starter["sources"],
        "normalization_sources": [
            {
                "provider": "hisnmuslim",
                "languages": ["ar", "en"],
                "url": "https://hisnmuslim.com/api",
                "purpose": "chapter alignment, repeat metadata and English transliteration",
            },
            {
                "provider": "islamhouse",
                "languages": ["ar", "en", "ru", "tr"],
                "url": "https://islamhouse.com/en/books/39062",
                "purpose": "primary published editions",
            },
        ],
        "categories": categories,
        "entries": entries,
    }


def main() -> None:
    args = parse_args()
    snapshot = build_snapshot(args)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(  # noqa: T201
        f"Wrote {len(snapshot['categories'])} categories and "
        f"{len(snapshot['entries'])} entries to {args.output}"
    )


if __name__ == "__main__":
    main()
