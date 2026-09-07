from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("quran", "0005_mushaf_renditions")]

    operations = [
        migrations.AlterField(
            model_name="mushafrenditionrelease",
            name="source_commit",
            field=models.CharField(
                blank=True, max_length=40, verbose_name="Git commit источника (если есть)"
            ),
        ),
        migrations.AddField(
            model_name="mushafrenditionrelease",
            name="source_metadata",
            field=models.JSONField(
                default=dict, verbose_name="Источник: издание, версия данных и шрифта"
            ),
        ),
    ]
