"""The two built-in course covers and the rights to them (docs/courses/README.md).

A cover goes to the site on save, without a release, so the publisher changes
it; the editor sees it.
"""

from typing import Any

from django.contrib.auth.management import create_permissions
from django.db import migrations

EDITORS = "Редактор курсов"
PUBLISHERS = "Публикатор"

READ = ("view_builtincoursecover",)
WRITE = ("change_builtincoursecover",)
GROUPS = {EDITORS: READ, PUBLISHERS: (*READ, *WRITE)}
COURSES = ("salah", "tajweed")


def add_rows_and_rights(apps: Any, _schema_editor: Any) -> None:
    for course in COURSES:
        apps.get_model("courses", "BuiltInCourseCover").objects.get_or_create(course=course)

    app_config = apps.get_app_config("courses")
    app_config.models_module = True
    create_permissions(app_config, apps=apps, verbosity=0)
    app_config.models_module = None

    Group = apps.get_model("auth", "Group")
    Permission = apps.get_model("auth", "Permission")
    for name, codenames in GROUPS.items():
        group, _ = Group.objects.get_or_create(name=name)
        group.permissions.add(
            *Permission.objects.filter(content_type__app_label="courses", codename__in=codenames)
        )


def remove_rights(apps: Any, _schema_editor: Any) -> None:
    Permission = apps.get_model("auth", "Permission")
    for group in apps.get_model("auth", "Group").objects.filter(name__in=GROUPS):
        group.permissions.remove(
            *Permission.objects.filter(content_type__app_label="courses", codename__in=READ + WRITE)
        )


class Migration(migrations.Migration):
    dependencies = [("courses", "0006_builtin_course_cover")]

    operations = [migrations.RunPython(add_rows_and_rights, remove_rights)]
