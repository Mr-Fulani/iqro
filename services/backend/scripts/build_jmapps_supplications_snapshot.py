from __future__ import annotations

import argparse
import hashlib
import json
import re
import sqlite3
from pathlib import Path
from typing import Any

EXPECTED_COLUMNS = ("id", "ayah_arabic", "ayah_translation", "ayah_source", "name_audio")
SOURCE_LANGUAGES = ("en", "ru", "tr")
OUTPUT_LANGUAGES = ("ar", "en", "ru", "tr")
SOURCE_REFERENCE_RE = re.compile(
    r"(?P<surah>[1-9][0-9]{0,2}):(?P<start>[1-9][0-9]{0,2})"
    r"(?:-(?P<end>[1-9][0-9]{0,2}))?\Z"
)
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
COMMIT_RE = re.compile(r"[0-9a-f]{40}\Z")
GIT_SHA1_RE = re.compile(r"[0-9a-f]{40}\Z")
HTML_TAG_RE = re.compile(r"</?[A-Za-z][^>]*>", re.DOTALL)
FORBIDDEN_BIDI_CONTROLS = frozenset(
    {
        "\u061c",
        "\u200e",
        "\u200f",
        "\u202a",
        "\u202b",
        "\u202c",
        "\u202d",
        "\u202e",
        "\u2066",
        "\u2067",
        "\u2068",
        "\u2069",
    }
)
QURAN_AYAH_COUNTS = (
    7,
    286,
    200,
    176,
    120,
    165,
    206,
    75,
    129,
    109,
    123,
    111,
    43,
    52,
    99,
    128,
    111,
    110,
    98,
    135,
    112,
    78,
    118,
    64,
    77,
    227,
    93,
    88,
    69,
    60,
    34,
    30,
    73,
    54,
    45,
    83,
    182,
    88,
    75,
    85,
    54,
    53,
    89,
    59,
    37,
    35,
    38,
    29,
    18,
    45,
    60,
    49,
    62,
    55,
    78,
    96,
    29,
    22,
    24,
    13,
    14,
    11,
    11,
    18,
    12,
    12,
    30,
    52,
    52,
    44,
    28,
    28,
    20,
    56,
    40,
    31,
    50,
    40,
    46,
    42,
    29,
    19,
    36,
    25,
    22,
    17,
    19,
    26,
    30,
    20,
    15,
    21,
    11,
    8,
    8,
    19,
    5,
    8,
    8,
    11,
    11,
    8,
    3,
    9,
    5,
    4,
    7,
    3,
    6,
    3,
    5,
    4,
    5,
    6,
)

COLLECTION_TITLES = {
    "ar": "أدعية من القرآن",
    "en": "Supplications from the Quran",
    "ru": "Мольбы из Корана",
    "tr": "Kur'ân-ı Kerîm'den duâlar",  # noqa: RUF001 - source spelling
}

TABLE_QUERIES = {
    "en": (
        "SELECT id, ayah_arabic, ayah_translation, ayah_source, name_audio "
        'FROM "Table_of_supplications_en" ORDER BY id'
    ),
    "ru": (
        "SELECT id, ayah_arabic, ayah_translation, ayah_source, name_audio "
        'FROM "Table_of_supplications_ru" ORDER BY id'
    ),
    "tr": (
        "SELECT id, ayah_arabic, ayah_translation, ayah_source, name_audio "
        'FROM "Table_of_supplications_tr" ORDER BY id'
    ),
}


def default_lock_path() -> Path:
    return (
        Path(__file__).resolve().parents[1]
        / "source_data"
        / "jmapps"
        / "supplications_from_quran"
        / "source.lock.json"
    )


def default_output_path() -> Path:
    return (
        Path(__file__).resolve().parents[1]
        / "src"
        / "quran_backend"
        / "modules"
        / "dua"
        / "data"
        / "supplications_from_quran_jmapps_v1.json"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build the IQRO Dua snapshot from the pinned JMApps "
            "supplications_from_quran SQLite database."
        )
    )
    parser.add_argument("--lock", type=Path, default=default_lock_path())
    parser.add_argument("--output", type=Path, default=default_output_path())
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail unless the committed output is byte-for-byte reproducible.",
    )
    return parser.parse_args()


def _require_dict(container: dict[str, Any], key: str) -> dict[str, Any]:
    value = container.get(key)
    if not isinstance(value, dict):
        raise ValueError(f"{key} must be an object")
    return value


def _require_string(container: dict[str, Any], key: str) -> str:
    value = container.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{key} must be a non-empty string")
    return value.strip()


def load_source_lock(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"Unable to read source lock {path}: {exc}") from exc
    if not isinstance(payload, dict) or payload.get("schema_version") != 1:
        raise ValueError("The source lock must be an object with schema_version=1")

    source = _require_dict(payload, "source")
    output = _require_dict(payload, "output")
    database = _require_dict(source, "database")
    audio = _require_dict(source, "audio")
    commit = _require_string(source, "commit")
    checksum = _require_string(database, "sha256")
    if COMMIT_RE.fullmatch(commit) is None:
        raise ValueError("source.commit must be a lowercase 40-character Git SHA")
    if SHA256_RE.fullmatch(checksum) is None:
        raise ValueError("source.database.sha256 must be a lowercase SHA-256 digest")
    snapshot_checksum = output.get("snapshot_sha256")
    if not isinstance(snapshot_checksum, str) or SHA256_RE.fullmatch(snapshot_checksum) is None:
        raise ValueError("output.snapshot_sha256 must be a lowercase SHA-256 digest")
    if source.get("rights_basis") != "iqro_owner_attested":
        raise ValueError("source.rights_basis must be iqro_owner_attested")
    if output.get("languages") != list(OUTPUT_LANGUAGES):
        raise ValueError("output.languages must be exactly ar, en, ru and tr")
    if output.get("entry_count") != audio.get("asset_count"):
        raise ValueError("The locked text and audio entry counts must match")
    _locked_audio_assets(audio, expected_count=int(output["entry_count"]))
    return payload


def _locked_audio_assets(
    audio: dict[str, Any], *, expected_count: int
) -> dict[int, tuple[str, str, int, str]]:
    raw_assets = audio.get("assets")
    if not isinstance(raw_assets, list) or len(raw_assets) != expected_count:
        raise ValueError(f"source.audio.assets must contain {expected_count} rows")
    assets: dict[int, tuple[str, str, int, str]] = {}
    for row in raw_assets:
        if not isinstance(row, list) or len(row) != 5:
            raise ValueError("Every source.audio.assets row must have five values")
        source_number, filename, blob_sha1, size_bytes, checksum_sha256 = row
        if not isinstance(source_number, int) or source_number < 1 or source_number in assets:
            raise ValueError("Locked audio source numbers must be unique positive integers")
        if filename != f"a_{source_number}.mp3":
            raise ValueError(f"Locked audio filename does not match entry {source_number}")
        if not isinstance(blob_sha1, str) or GIT_SHA1_RE.fullmatch(blob_sha1) is None:
            raise ValueError(f"Locked audio {source_number} has an invalid Git blob SHA-1")
        if not isinstance(size_bytes, int) or isinstance(size_bytes, bool) or size_bytes <= 0:
            raise ValueError(f"Locked audio {source_number} has an invalid size")
        if not isinstance(checksum_sha256, str) or SHA256_RE.fullmatch(checksum_sha256) is None:
            raise ValueError(f"Locked audio {source_number} has an invalid SHA-256")
        assets[source_number] = (filename, blob_sha1, size_bytes, checksum_sha256)
    if sorted(assets) != list(range(1, expected_count + 1)):
        raise ValueError("Locked audio source numbers must be consecutive")
    return assets


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _database_path(lock_path: Path, lock: dict[str, Any]) -> Path:
    database = lock["source"]["database"]
    path = lock_path.parent / _require_string(database, "vendored_path")
    if not path.is_file():
        raise ValueError(f"The locked source database does not exist: {path}")
    expected_size = database.get("size_bytes")
    if not isinstance(expected_size, int) or expected_size <= 0:
        raise ValueError("source.database.size_bytes must be a positive integer")
    if path.stat().st_size != expected_size:
        raise ValueError("The source database size does not match the lock")
    if _sha256(path) != database["sha256"]:
        raise ValueError("The source database SHA-256 does not match the lock")
    return path


def _load_rows(connection: sqlite3.Connection, language: str) -> list[dict[str, Any]]:
    table = f"Table_of_supplications_{language}"
    columns = tuple(
        row[1] for row in connection.execute(f'PRAGMA table_info("{table}")').fetchall()
    )
    if columns != EXPECTED_COLUMNS:
        raise ValueError(f"Unexpected columns in {table}: {columns}")
    rows = connection.execute(TABLE_QUERIES[language]).fetchall()
    return [dict(row) for row in rows]


def _read_database(path: Path, expected_count: int) -> dict[str, list[dict[str, Any]]]:
    connection = sqlite3.connect(f"{path.resolve().as_uri()}?mode=ro&immutable=1", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        connection.execute("PRAGMA query_only = ON")
        integrity = connection.execute("PRAGMA quick_check").fetchone()
        if integrity is None or integrity[0] != "ok":
            raise ValueError("The source SQLite database failed PRAGMA quick_check")
        result = {language: _load_rows(connection, language) for language in SOURCE_LANGUAGES}
    finally:
        connection.close()

    expected_ids = list(range(1, expected_count + 1))
    for language, rows in result.items():
        if [row["id"] for row in rows] != expected_ids:
            raise ValueError(f"{language} rows must contain consecutive IDs 1..{expected_count}")
        for row in rows:
            for key in EXPECTED_COLUMNS[1:]:
                _validate_source_text(
                    row[key],
                    label=f"{language} row {row['id']} {key}",
                )
    return result


def _validate_source_text(value: object, *, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} must be a non-empty string")
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise ValueError(f"{label} contains a forbidden control character")
    if any(character in FORBIDDEN_BIDI_CONTROLS for character in value):
        raise ValueError(f"{label} contains a forbidden bidi control")
    if HTML_TAG_RE.search(value) is not None:
        raise ValueError(f"{label} contains forbidden HTML")
    return value.strip()


def _validate_quran_reference(value: object, *, source_number: int) -> str:
    reference = _validate_source_text(
        value,
        label=f"entry {source_number} Quran reference",
    )
    match = SOURCE_REFERENCE_RE.fullmatch(reference)
    if match is None:
        raise ValueError(f"Entry {source_number} has an invalid Quran reference")
    surah = int(match.group("surah"))
    start = int(match.group("start"))
    end = int(match.group("end") or start)
    if surah > len(QURAN_AYAH_COUNTS):
        raise ValueError(f"Entry {source_number} Quran surah is out of range")
    ayah_count = QURAN_AYAH_COUNTS[surah - 1]
    if start > end or end > ayah_count:
        raise ValueError(f"Entry {source_number} Quran ayah range is invalid")
    return reference


def _validate_aligned_rows(rows: dict[str, list[dict[str, Any]]]) -> None:
    english_rows = rows["en"]
    for index, english in enumerate(english_rows):
        source_number = int(english["id"])
        expected_audio = f"a_{source_number}"
        _validate_quran_reference(english["ayah_source"], source_number=source_number)
        for language in SOURCE_LANGUAGES:
            localized = rows[language][index]
            if localized["ayah_arabic"].strip() != english["ayah_arabic"].strip():
                raise ValueError(f"Arabic text differs in {language} entry {source_number}")
            if localized["name_audio"].strip() != expected_audio:
                raise ValueError(f"Unexpected audio key in {language} entry {source_number}")


def _source_editions(
    *, provider: str, repository_url: str, commit: str, database_path: str, rights_basis: str
) -> list[dict[str, Any]]:
    source_url = f"{repository_url}/blob/{commit}/{database_path}"
    return [
        {
            "language": language,
            "provider": provider,
            "source_item_id": f"main_supplications.db:{language}",
            "title": COLLECTION_TITLES[language],
            "author": "",
            "source_url": source_url,
            "rights_url": "",
            "rights_basis": rights_basis,
            "source_version": commit,
        }
        for language in OUTPUT_LANGUAGES
    ]


def build_snapshot(lock_path: Path) -> dict[str, Any]:
    lock = load_source_lock(lock_path)
    source = lock["source"]
    output = lock["output"]
    database = source["database"]
    expected_count = int(output["entry_count"])
    rows = _read_database(_database_path(lock_path, lock), expected_count)
    _validate_aligned_rows(rows)

    repository_url = source["repository_url"].rstrip("/")
    commit = source["commit"]
    provider = source["provider"]
    rights_basis = source["rights_basis"]
    database_path = database["repository_path"]
    database_url = f"{repository_url}/blob/{commit}/{database_path}"
    audio_directory = source["audio"]["repository_directory"].strip("/")
    locked_audio = _locked_audio_assets(source["audio"], expected_count=expected_count)

    entries: list[dict[str, Any]] = []
    audio_assets: list[dict[str, Any]] = []
    for index, english in enumerate(rows["en"]):
        source_number = int(english["id"])
        arabic_text = english["ayah_arabic"].strip()
        audio_filename, audio_blob_sha1, audio_size, audio_sha256 = locked_audio[source_number]
        entries.append(
            {
                "source_number": source_number,
                "category_source_number": 1,
                "slug": f"quran-supplication-{source_number:03d}",
                "arabic_text": arabic_text,
                "repetitions": 1,
                "translations": [
                    {"language": "ar", "meaning_text": arabic_text},
                    *(
                        {
                            "language": language,
                            "meaning_text": rows[language][index]["ayah_translation"].strip(),
                        }
                        for language in SOURCE_LANGUAGES
                    ),
                ],
                "evidence": [
                    {
                        "kind": "quran",
                        "provider": provider,
                        "source_name": "Supplications from the Quran",
                        "source_reference": english["ayah_source"].strip(),
                        "source_url": database_url,
                        "external_id": str(source_number),
                        "verification_status": "source_only",
                    }
                ],
            }
        )
        audio_assets.append(
            {
                "source_number": source_number,
                "language_code": "ar",
                "provider": provider,
                "reader_name": "",
                "reader_name_ar": "",
                "external_url": (
                    "https://raw.githubusercontent.com/"
                    f"JMApps/supplications_from_quran/{commit}/"
                    f"{audio_directory}/{audio_filename}"
                ),
                "source_url": (
                    f"{repository_url}/blob/{commit}/{audio_directory}/{audio_filename}"
                ),
                "rights_url": "",
                "rights_basis": rights_basis,
                "source_version": commit,
                "content_type": "audio/mpeg",
                "size_bytes": audio_size,
                "checksum_sha256": audio_sha256,
                "source_git_blob_sha1": audio_blob_sha1,
                "sort_order": 1,
                "is_active": True,
            }
        )

    return {
        "schema_version": int(output["schema_version"]),
        "version": output["version"],
        "collection": {"slug": output["collection_slug"]},
        "sources": _source_editions(
            provider=provider,
            repository_url=repository_url,
            commit=commit,
            database_path=database_path,
            rights_basis=rights_basis,
        ),
        "categories": [
            {
                "source_number": 1,
                "slug": "quranic-supplications",
                "translations": [
                    {"language": language, "title": COLLECTION_TITLES[language]}
                    for language in OUTPUT_LANGUAGES
                ],
            }
        ],
        "entries": entries,
        "audio": audio_assets,
        "provenance": {
            "provider": provider,
            "repository_url": repository_url,
            "source_commit": commit,
            "source_database_path": database_path,
            "source_database_sha256": database["sha256"],
            "audio_tree_sha1": source["audio"]["git_tree_sha1"],
            "rights_basis": rights_basis,
            "editorial_verification": "source_only",
        },
    }


def rendered_snapshot(snapshot: dict[str, Any]) -> str:
    return json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n"


def main() -> None:
    args = parse_args()
    lock = load_source_lock(args.lock)
    rendered = rendered_snapshot(build_snapshot(args.lock))
    rendered_checksum = hashlib.sha256(rendered.encode()).hexdigest()
    if rendered_checksum != lock["output"].get("snapshot_sha256"):
        raise SystemExit(
            "Generated snapshot SHA-256 does not match output.snapshot_sha256 in the source lock."
        )
    if args.check:
        try:
            existing = args.output.read_text(encoding="utf-8")
        except OSError as exc:
            raise SystemExit(f"Unable to read generated snapshot {args.output}: {exc}") from exc
        if existing != rendered:
            raise SystemExit(
                f"Generated snapshot is stale; rebuild {args.output} from {args.lock}."
            )
        print(f"Verified reproducible snapshot {args.output}")  # noqa: T201
        return
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(rendered, encoding="utf-8")
    print(  # noqa: T201
        f"Wrote {len(json.loads(rendered)['entries'])} entries to {args.output}"
    )


if __name__ == "__main__":
    main()
