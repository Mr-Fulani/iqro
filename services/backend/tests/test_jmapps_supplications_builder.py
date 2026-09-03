from __future__ import annotations

import hashlib
import json
import sqlite3
from pathlib import Path

import pytest
from scripts.build_jmapps_supplications_snapshot import (
    _load_rows,
    _read_database,
    _validate_aligned_rows,
    _validate_quran_reference,
    _validate_source_text,
    build_snapshot,
    default_lock_path,
    default_output_path,
    load_source_lock,
    rendered_snapshot,
)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_jmapps_snapshot_is_byte_reproducible_and_source_remains_unchanged() -> None:
    lock_path = default_lock_path()
    lock = load_source_lock(lock_path)
    database_path = lock_path.parent / lock["source"]["database"]["vendored_path"]
    original_database_checksum = _sha256(database_path)

    generated = rendered_snapshot(build_snapshot(lock_path))

    assert generated == default_output_path().read_text(encoding="utf-8")
    assert hashlib.sha256(generated.encode()).hexdigest() == lock["output"]["snapshot_sha256"]
    assert _sha256(database_path) == original_database_checksum
    payload = json.loads(generated)
    assert [entry["source_number"] for entry in payload["entries"]] == list(range(1, 55))
    assert len(payload["audio"]) == 54
    assert all(len(entry["translations"]) == 4 for entry in payload["entries"])
    assert all(item["reader_name"] == "" for item in payload["audio"])
    assert all(item["rights_basis"] == "iqro_owner_attested" for item in payload["audio"])
    assert all(len(item["checksum_sha256"]) == 64 for item in payload["audio"])
    locked_audio = lock["source"]["audio"]["assets"]
    assert [item["checksum_sha256"] for item in payload["audio"]] == [
        item[4] for item in locked_audio
    ]
    assert {
        evidence["verification_status"]
        for entry in payload["entries"]
        for evidence in entry["evidence"]
    } == {"source_only"}


def test_jmapps_builder_rejects_database_not_matching_source_lock(tmp_path: Path) -> None:
    original_lock_path = default_lock_path()
    lock = load_source_lock(original_lock_path)
    database_path = original_lock_path.parent / lock["source"]["database"]["vendored_path"]
    lock["source"]["database"]["vendored_path"] = str(database_path.resolve())
    lock["source"]["database"]["sha256"] = "0" * 64
    tampered_lock = tmp_path / "source.lock.json"
    tampered_lock.write_text(json.dumps(lock), encoding="utf-8")

    with pytest.raises(ValueError, match="SHA-256 does not match"):
        build_snapshot(tampered_lock)


def test_jmapps_builder_rejects_unattested_rights_basis(tmp_path: Path) -> None:
    original_lock_path = default_lock_path()
    lock = load_source_lock(original_lock_path)
    lock["source"]["rights_basis"] = "unknown"
    tampered_lock = tmp_path / "source.lock.json"
    tampered_lock.write_text(json.dumps(lock), encoding="utf-8")

    with pytest.raises(ValueError, match="rights_basis"):
        build_snapshot(tampered_lock)


@pytest.mark.parametrize(
    ("value", "message"),
    [
        ("valid\x00hidden", "control"),
        ("valid\nsecond line", "control"),
        ("valid\u202ehidden", "bidi"),
        ("<script>alert(1)</script>", "HTML"),
    ],
)
def test_jmapps_builder_rejects_unsafe_source_text(value: str, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        _validate_source_text(value, label="test value")


@pytest.mark.parametrize("reference", ["0:1", "115:1", "1:8", "2:287", "2:5-4"])
def test_jmapps_builder_rejects_invalid_canonical_quran_range(reference: str) -> None:
    with pytest.raises(ValueError, match="Quran"):
        _validate_quran_reference(reference, source_number=1)


def _localized_rows(*, audio_key: str = "a_1") -> dict[str, list[dict[str, object]]]:
    row = {
        "id": 1,
        "ayah_arabic": "رَبَّنَا",
        "ayah_translation": "Our Lord",
        "ayah_source": "2:126",
        "name_audio": audio_key,
    }
    return {language: [dict(row)] for language in ("en", "ru", "tr")}


def test_jmapps_builder_rejects_unexpected_audio_key() -> None:
    with pytest.raises(ValueError, match="Unexpected audio key"):
        _validate_aligned_rows(_localized_rows(audio_key="a_2"))


def _create_source_table(connection: sqlite3.Connection, language: str) -> None:
    connection.execute(
        f'CREATE TABLE "Table_of_supplications_{language}" ('
        "id INTEGER, ayah_arabic TEXT, ayah_translation TEXT, "
        "ayah_source TEXT, name_audio TEXT)"
    )
    connection.execute(
        f'INSERT INTO "Table_of_supplications_{language}" VALUES (?, ?, ?, ?, ?)',  # noqa: S608 -- bounded test language
        (1, "رَبَّنَا", "Our Lord", "2:126", "a_1"),
    )


def test_jmapps_builder_rejects_missing_source_id(tmp_path: Path) -> None:
    path = tmp_path / "missing-id.db"
    connection = sqlite3.connect(path)
    try:
        for language in ("en", "ru", "tr"):
            _create_source_table(connection, language)
        connection.commit()
    finally:
        connection.close()

    with pytest.raises(ValueError, match=r"consecutive IDs 1\.\.2"):
        _read_database(path, expected_count=2)


def test_jmapps_builder_rejects_unexpected_database_schema() -> None:
    connection = sqlite3.connect(":memory:")
    connection.row_factory = sqlite3.Row
    connection.execute(
        'CREATE TABLE "Table_of_supplications_en" ('
        "id INTEGER, ayah_arabic TEXT, ayah_translation TEXT)"
    )
    try:
        with pytest.raises(ValueError, match="Unexpected columns"):
            _load_rows(connection, "en")
    finally:
        connection.close()
