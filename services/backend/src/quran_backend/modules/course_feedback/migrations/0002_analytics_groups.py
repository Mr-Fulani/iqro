"""Course editors and publishers see «Курсы: сводка» and the analytics of a course."""

from typing import Any

from django.contrib.auth.management import create_permissions
from django.db import migrations

GROUPS = ("Редактор курсов", "Публикатор")


def grant(apps: Any, _schema_editor: Any) -> None:
    app_config = apps.get_app_config("course_feedback")
    app_config.models_module = True
    create_permissions(app_config, apps=apps, verbosity=0)
    app_config.models_module = None

    Group = apps.get_model("auth", "Group")
    Permission = apps.get_model("auth", "Permission")
    permission = Permission.objects.get(
        content_type__app_label="course_feedback", codename="view_courseanalytics"
    )
    for group in Group.objects.filter(name__in=GROUPS):
        group.permissions.add(permission)


def revoke(apps: Any, _schema_editor: Any) -> None:
    Permission = apps.get_model("auth", "Permission")
    Permission.objects.filter(
        content_type__app_label="course_feedback", codename="view_courseanalytics"
    ).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("course_feedback", "0001_initial"),
        ("courses", "0002_course_groups"),
    ]

    operations = [migrations.RunPython(grant, revoke)]
