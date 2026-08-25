from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("audio", "0005_audio_rendition_origin_etag"),
    ]

    operations = [
        migrations.AlterField(
            model_name="recitationedition",
            name="style",
            field=models.CharField(
                choices=[
                    ("murattal", "Murattal"),
                    ("mujawwad", "Mujawwad"),
                    ("muallim", "Muallim"),
                    ("kids-repeat", "Kids repeat"),
                ],
                default="murattal",
                max_length=16,
            ),
        ),
    ]
