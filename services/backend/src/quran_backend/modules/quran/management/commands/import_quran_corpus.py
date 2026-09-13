from pathlib import Path
from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.quran.corpus_import import import_canonical_corpus
from quran_backend.modules.quran.models import QuranFoundationMushaf


class Command(BaseCommand):
    help = "Import checksum-pinned Quran text and QF page mapping, without PDF or artwork."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("corpus", type=Path)

    def handle(self, *_args: Any, **options: Any) -> None:
        try:
            version = import_canonical_corpus(options["corpus"])
        except (ValueError, OSError, KeyError, QuranFoundationMushaf.DoesNotExist) as exc:
            raise CommandError(f"Canonical import failed: {exc}") from exc
        self.stdout.write(self.style.SUCCESS(f"Canonical Quran ready: {version}"))
