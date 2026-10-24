"""Three working groups for thematic courses (docs/courses/plan.md, section 2).

Editors write texts; the religious reviewer signs a release; the publisher
publishes, hides and rolls back. The owner, a superuser, can do everything.
"""

from typing import Any

from django.contrib.auth.management import create_permissions
from django.db import migrations

EDITORS = "Редактор курсов"
REVIEWERS = "Религиозный рецензент"
PUBLISHERS = "Публикатор"

READ = (
    "view_course",
    "view_courselesson",
    "view_courserelease",
    "view_coursedocument",
)
GROUPS = {
    EDITORS: (
        *READ,
        "add_course",
        "change_course",
        "delete_course",
        "add_courselesson",
        "change_courselesson",
        "delete_courselesson",
    ),
    REVIEWERS: (*READ, "sign_course"),
    PUBLISHERS: (*READ, "publish_course"),
}


def create_groups(apps: Any, _schema_editor: Any) -> None:
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


def remove_groups(apps: Any, _schema_editor: Any) -> None:
    apps.get_model("auth", "Group").objects.filter(name__in=GROUPS).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("courses", "0001_initial"),
        ("auth", "0012_alter_user_first_name_max_length"),
        ("contenttypes", "0002_remove_content_type_name"),
    ]

    operations = [migrations.RunPython(create_groups, remove_groups)]
