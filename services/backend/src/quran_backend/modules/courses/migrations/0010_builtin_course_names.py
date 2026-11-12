"""«Имена Аллаха» are one more built-in card of the catalog: the row of its cover."""

from typing import Any

from django.db import migrations, models


def add_row(apps: Any, _schema_editor: Any) -> None:
    apps.get_model("courses", "BuiltInCourseCover").objects.get_or_create(course="names")


def remove_row(apps: Any, _schema_editor: Any) -> None:
    apps.get_model("courses", "BuiltInCourseCover").objects.filter(course="names").delete()


class Migration(migrations.Migration):
    dependencies = [
        ("courses", "0009_learner_progress_names"),
    ]

    operations = [
        migrations.AlterField(
            model_name="builtincoursecover",
            name="course",
            field=models.CharField(
                choices=[
                    ("salah", "Обучение намазу"),
                    ("tajweed", "Таджвид"),
                    ("names", "Имена Аллаха"),
                ],
                max_length=16,
                unique=True,
            ),
        ),
        migrations.RunPython(add_row, remove_row),
    ]
