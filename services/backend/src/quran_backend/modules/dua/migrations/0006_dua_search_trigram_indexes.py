from django.contrib.postgres.indexes import GinIndex
from django.db import migrations


def _search_indexes():
    return (
        (
            "DuaEntry",
            GinIndex(
                fields=("arabic_text",),
                name="dua_entry_arabic_trgm_gin",
                opclasses=("gin_trgm_ops",),
            ),
        ),
        (
            "DuaEntryTranslation",
            GinIndex(
                fields=("meaning_text",),
                name="dua_entry_meaning_trgm_gin",
                opclasses=("gin_trgm_ops",),
            ),
        ),
        (
            "DuaEntryTranslation",
            GinIndex(
                fields=("transliteration",),
                name="dua_entry_translit_trgm_gin",
                opclasses=("gin_trgm_ops",),
            ),
        ),
        (
            "DuaCategoryTranslation",
            GinIndex(
                fields=("title",),
                name="dua_category_title_trgm_gin",
                opclasses=("gin_trgm_ops",),
            ),
        ),
    )


def add_postgresql_search_indexes(apps, schema_editor):
    if schema_editor.connection.vendor != "postgresql":
        return
    schema_editor.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    for model_name, index in _search_indexes():
        model = apps.get_model("dua", model_name)
        schema_editor.add_index(model, index)


def remove_postgresql_search_indexes(apps, schema_editor):
    if schema_editor.connection.vendor != "postgresql":
        return
    for model_name, index in reversed(_search_indexes()):
        model = apps.get_model("dua", model_name)
        schema_editor.remove_index(model, index)
    # pg_trgm is database-wide and may be shared by future domains. Leaving the
    # empty extension installed makes rollback safe for unrelated consumers.


class Migration(migrations.Migration):
    dependencies = [
        ("dua", "0005_dua_audio_and_favorites"),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[
                migrations.RunPython(
                    add_postgresql_search_indexes,
                    remove_postgresql_search_indexes,
                ),
            ],
            state_operations=[
                migrations.AddIndex(
                    model_name="duaentry",
                    index=GinIndex(
                        fields=("arabic_text",),
                        name="dua_entry_arabic_trgm_gin",
                        opclasses=("gin_trgm_ops",),
                    ),
                ),
                migrations.AddIndex(
                    model_name="duaentrytranslation",
                    index=GinIndex(
                        fields=("meaning_text",),
                        name="dua_entry_meaning_trgm_gin",
                        opclasses=("gin_trgm_ops",),
                    ),
                ),
                migrations.AddIndex(
                    model_name="duaentrytranslation",
                    index=GinIndex(
                        fields=("transliteration",),
                        name="dua_entry_translit_trgm_gin",
                        opclasses=("gin_trgm_ops",),
                    ),
                ),
                migrations.AddIndex(
                    model_name="duacategorytranslation",
                    index=GinIndex(
                        fields=("title",),
                        name="dua_category_title_trgm_gin",
                        opclasses=("gin_trgm_ops",),
                    ),
                ),
            ],
        ),
    ]
