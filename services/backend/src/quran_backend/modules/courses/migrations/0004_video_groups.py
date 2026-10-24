"""Rights to lesson videos and dubs for the working groups of 0002.

Editors upload, replace and delete them; the reviewer and the publisher watch them.
"""

from typing import Any

from django.contrib.auth.management import create_permissions
from django.db import migrations

EDITORS = "Редактор курсов"
REVIEWERS = "Религиозный рецензент"
PUBLISHERS = "Публикатор"

READ = ("view_coursevideo", "view_coursevideodub")
WRITE = (
    "add_coursevideo",
    "change_coursevideo",
    "delete_coursevideo",
    "add_coursevideodub",
    "change_coursevideodub",
    "delete_coursevideodub",
)
GROUPS = {EDITORS: (*READ, *WRITE), REVIEWERS: READ, PUBLISHERS: READ}


def add_rights(apps: Any, _schema_editor: Any) -> None:
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
    dependencies = [("courses", "0003_video_and_dubs")]

    operations = [migrations.RunPython(add_rights, remove_rights)]
