from __future__ import annotations

from pathlib import Path
from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.tajweed.course import (
    DEFAULT_SNAPSHOT,
    TajweedCourseError,
    load_course_snapshot,
)
from quran_backend.modules.tajweed.course_publication import import_tajweed_course


class Command(BaseCommand):
    help = "Импортирует снимок курса «Таджвид» как черновик и собирает документы."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("snapshot", nargs="?", default=str(DEFAULT_SNAPSHOT))

    def handle(self, *_args: Any, **options: Any) -> None:
        try:
            version = import_tajweed_course(load_course_snapshot(Path(options["snapshot"])))
        except TajweedCourseError as error:
            raise CommandError(str(error)) from error
        self.stdout.write(
            self.style.SUCCESS(
                f"{version}: {version.status}. Подпишите и опубликуйте версию в админке."
            )
        )
