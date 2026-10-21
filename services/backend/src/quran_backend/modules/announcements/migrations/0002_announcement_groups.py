"""Two working groups for announcements.

Editors prepare and publish ordinary announcements. Fundraising, push, step
windows and forced updates need `publish_sensitive_announcement`, which no group
receives: only the owner (a superuser) signs them.
"""

from typing import Any

from django.contrib.auth.management import create_permissions
from django.db import migrations

EDITORS = "Редактор объявлений"
RELIGIOUS_REVIEWERS = "Проверяющий религиозные тексты"

EDITOR_PERMISSIONS = (
    "view_announcement",
    "add_announcement",
    "change_announcement",
    "publish_announcement",
    "view_announcementtranslation",
    "add_announcementtranslation",
    "change_announcementtranslation",
    "view_announcementstep",
    "add_announcementstep",
    "change_announcementstep",
    "delete_announcementstep",
    "view_announcementsettings",
)
REVIEWER_PERMISSIONS = (
    "view_announcement",
    "view_announcementtranslation",
    "view_announcementstep",
    "review_religious_content",
)


def create_groups(apps: Any, _schema_editor: Any) -> None:
    app_config = apps.get_app_config("announcements")
    app_config.models_module = True
    create_permissions(app_config, apps=apps, verbosity=0)
    app_config.models_module = None

    Group = apps.get_model("auth", "Group")
    Permission = apps.get_model("auth", "Permission")
    for name, codenames in (
        (EDITORS, EDITOR_PERMISSIONS),
        (RELIGIOUS_REVIEWERS, REVIEWER_PERMISSIONS),
    ):
        group, _ = Group.objects.get_or_create(name=name)
        group.permissions.add(
            *Permission.objects.filter(
                content_type__app_label="announcements",
                codename__in=codenames,
            )
        )


def remove_groups(apps: Any, _schema_editor: Any) -> None:
    apps.get_model("auth", "Group").objects.filter(name__in=(EDITORS, RELIGIOUS_REVIEWERS)).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("announcements", "0001_initial"),
        ("auth", "0012_alter_user_first_name_max_length"),
        ("contenttypes", "0002_remove_content_type_name"),
    ]

    operations = [migrations.RunPython(create_groups, remove_groups)]
