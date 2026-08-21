from __future__ import annotations

from pathlib import Path

import pytest

from quran_backend.modules.quran.importer import import_quran_dataset, validate_quran_dataset
from quran_backend.modules.quran.models import PublicationStatus
from quran_backend.modules.quran.publication import (
    QuranPublicationError,
    publish_quran_version,
)
from tests.test_quran_importer import _write_dataset


@pytest.mark.django_db
def test_publishes_and_activates_complete_import(tmp_path: Path) -> None:
    imported = import_quran_dataset(validate_quran_dataset(_write_dataset(tmp_path / "dataset")))

    result = publish_quran_version(
        edition_code="test-hafs",
        version_value="1.0.0",
        activate=True,
    )

    imported.version.refresh_from_db()
    imported.edition.refresh_from_db()
    assert result.published
    assert result.activated
    assert imported.version.status == PublicationStatus.PUBLISHED
    assert imported.edition.active_version == imported.version


@pytest.mark.django_db
def test_rejects_incomplete_version(tmp_path: Path) -> None:
    imported = import_quran_dataset(validate_quran_dataset(_write_dataset(tmp_path / "dataset")))
    imported.version.pages.all().delete()

    with pytest.raises(QuranPublicationError, match="Page count mismatch"):
        publish_quran_version(
            edition_code="test-hafs",
            version_value="1.0.0",
            activate=True,
        )
