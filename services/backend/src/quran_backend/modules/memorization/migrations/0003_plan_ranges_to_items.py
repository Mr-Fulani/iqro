from __future__ import annotations

from typing import Any

from django.db import migrations


def plan_ranges_to_active_items(apps: Any, _schema_editor: Any) -> None:
    """Turn every existing plan range into that user's active list item."""
    plan_model = apps.get_model("memorization", "MemorizationPlan")
    item_model = apps.get_model("memorization", "MemorizationItem")
    users_with_active = set(
        item_model.objects.filter(status="active").values_list("user_id", flat=True)
    )
    item_model.objects.bulk_create(
        [
            item_model(
                user_id=plan.user_id,
                start_ayah_id=plan.start_ayah_id,
                end_ayah_id=plan.end_ayah_id,
                status="active",
                position=0,
                source="manual",
            )
            for plan in plan_model.objects.only("user_id", "start_ayah_id", "end_ayah_id")
            if plan.user_id not in users_with_active
        ],
        batch_size=500,
    )


def remove_items(apps: Any, _schema_editor: Any) -> None:
    apps.get_model("memorization", "MemorizationItem").objects.all().delete()


class Migration(migrations.Migration):
    dependencies = [
        ("memorization", "0002_memorization_item"),
    ]

    operations = [
        migrations.RunPython(plan_ranges_to_active_items, remove_items),
    ]
