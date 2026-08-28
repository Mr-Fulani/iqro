from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("dua", "0002_seed_hisn_starter")]

    operations = [
        migrations.AddField(
            model_name="duaentry",
            name="repetition_label",
            field=models.CharField(blank=True, max_length=32),
        ),
    ]
