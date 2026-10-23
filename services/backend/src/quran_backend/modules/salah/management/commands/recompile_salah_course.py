from __future__ import annotations

from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.core.content_revalidation import enqueue_salah_content_change
from quran_backend.modules.salah.importer import compile_version
from quran_backend.modules.salah.models import SalahCourse
from quran_backend.modules.salah.resolvers import SalahFormulaError


class Command(BaseCommand):
    help = (
        "Пересобирает документы опубликованной версии курса намаза из её снимка: "
        "формулы разрешаются заново, например после смены учебного чтеца."
    )

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("--course", default=None, help="slug курса; по умолчанию все")

    def handle(self, *_args: Any, **options: Any) -> None:
        courses = SalahCourse.objects.exclude(active_version=None).select_related("active_version")
        if options["course"]:
            courses = courses.filter(slug=options["course"])
        if not courses.exists():
            raise CommandError("Нет опубликованной версии курса.")
        for course in courses:
            version = course.active_version
            assert version is not None
            try:
                compile_version(version)
            except SalahFormulaError as error:
                raise CommandError(f"{version}: {error}") from error
            enqueue_salah_content_change(
                action="activated", course=course.slug, version=version.version
            )
            self.stdout.write(self.style.SUCCESS(f"{version}: документы пересобраны."))
