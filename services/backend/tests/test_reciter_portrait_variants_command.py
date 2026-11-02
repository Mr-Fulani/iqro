from __future__ import annotations

from io import StringIO
from unittest.mock import patch

import pytest
from django.core.management import CommandError, call_command
from django.test import override_settings

from quran_backend.modules.audio.models import Reciter
from quran_backend.modules.audio.portrait_upload import (
    ReciterPortraitUploadError,
    ReciterPortraitVariants,
)

COMMAND = "quran_backend.modules.audio.management.commands.generate_reciter_portrait_variants"


def _reciter(code: str, **fields: str) -> Reciter:
    return Reciter.objects.create(
        code=code,
        name_ar=code,
        name_en=code,
        name_ru=code,
        **fields,
    )


@pytest.mark.django_db
@override_settings(PUBLIC_AUDIO_BASE_URL="https://cdn.example.test/")
def test_portrait_variants_command_is_read_only_without_apply() -> None:
    pending = _reciter("pending", portrait_object_key="audio/reciter-portraits/pending/a.png")
    _reciter("no-portrait")
    stdout = StringIO()

    with patch(f"{COMMAND}.store_reciter_portrait_variants") as store:
        call_command("generate_reciter_portrait_variants", stdout=stdout)

    store.assert_not_called()
    assert "pending: audio/reciter-portraits/pending/a.png" in stdout.getvalue()
    assert "1 portraits need copies" in stdout.getvalue()
    pending.refresh_from_db()
    assert pending.portrait_display_object_key == ""


@pytest.mark.django_db
@override_settings(PUBLIC_AUDIO_BASE_URL="https://cdn.example.test/")
def test_portrait_variants_command_stores_copies_and_reports_failures() -> None:
    pending = _reciter("pending", portrait_object_key="audio/reciter-portraits/pending/a.png")
    broken = _reciter("broken", portrait_object_key="audio/reciter-portraits/broken/b.png")
    done = _reciter(
        "done",
        portrait_object_key="audio/reciter-portraits/done/c.png",
        portrait_display_object_key="audio/reciter-portraits/done/640.webp",
        portrait_thumbnail_object_key="audio/reciter-portraits/done/320.webp",
    )
    sources: list[str] = []

    def store(source: str, **options: object) -> ReciterPortraitVariants:
        sources.append(source)
        if options["reciter_code"] == "broken":
            raise ReciterPortraitUploadError("broken picture")
        return ReciterPortraitVariants(
            display_object_key="audio/reciter-portraits/pending/640.webp",
            thumbnail_object_key="audio/reciter-portraits/pending/320.webp",
        )

    with (
        patch(f"{COMMAND}.portrait_uploader"),
        patch(f"{COMMAND}.store_reciter_portrait_variants", side_effect=store),
        patch(f"{COMMAND}.enqueue_reciter_content_change") as revalidate,
        pytest.raises(CommandError, match="broken"),
    ):
        call_command("generate_reciter_portrait_variants", "--apply", stdout=StringIO())

    assert sources == [
        "https://cdn.example.test/audio/reciter-portraits/broken/b.png",
        "https://cdn.example.test/audio/reciter-portraits/pending/a.png",
    ]
    pending.refresh_from_db()
    broken.refresh_from_db()
    done.refresh_from_db()
    assert pending.portrait_object_key == "audio/reciter-portraits/pending/a.png"
    assert pending.portrait_display_object_key == "audio/reciter-portraits/pending/640.webp"
    assert pending.portrait_thumbnail_object_key == "audio/reciter-portraits/pending/320.webp"
    assert broken.portrait_display_object_key == ""
    assert done.portrait_display_object_key == "audio/reciter-portraits/done/640.webp"
    revalidate.assert_called_once_with(action="updated", reciter_id=pending.id)
