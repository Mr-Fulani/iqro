# Модель проверки чтения вслух

Что слушает чтеца на Android (README приложения, раздел «Проверка чтения вслух»):

- `model-int8.onnx` — модель [Hisnlabs/tajweed-v2](https://huggingface.co/Hisnlabs/tajweed-v2), Apache-2.0
  (`LICENSE-Apache-2.0.txt`), файл `onnx/model-int8.onnx` без изменений,
  sha256 `79cca1a2fc7ef81e325a3071a5f26cfec69203ef2c63177549065cdc1022c373`. Построена на
  `tarteel-ai/whisper-base-ar-quran` (Apache-2.0) и разметке `obadx/muaalem-model-v3_2` (MIT).
- `expected.json` — ожидаемые звуки каждого аята и места гунны и мадда муттасыль; строится
  `tool/recitation_model/build_table.py` движком правил модели (`imam.py`) и `quran-transcript` (MIT).
- `mel_filters.bin` — 80 мел-фильтров Whisper (тот же скрипт).
- `LICENSE-onnxruntime.txt` — лицензия ONNX Runtime (MIT), которая исполняет модель; сама библиотека —
  зависимость Gradle `com.microsoft.onnxruntime:onnxruntime-android`.

Лицензии показываются в приложении: «Настройки» → «Лицензии». Совпадение таблицы с текстом на экране по
всем аятам проверяет `test/features/recitation_model_table_test.dart`.
