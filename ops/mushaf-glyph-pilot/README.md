# QCF V2 — native staging rendition

## Полное подключение, 2026-09-07

Реализовано отдельное визуальное издание `qcf-v2-hafs`, привязанное к действующей
канонической версии `madani-hafs`. Это **тестовая раскладка IQRO**, не официальное
факсимиле и не разрешение на production-публикацию. Ни один из инструментов ниже
не импортирует заново Коран, чтецов, аудио или фотографии администратора.

- `source.full.lock.json` закрепляет все 604 TTF, базу и шрифт заголовков:
  606 файлов, 228 559 304 байта. `fetch_full.py` сверяет Git blob SHA-1 закреплённого
  дерева и SHA-256. `build_full.py` готовит 1812 lossless WebP и 604 карты аятов.
- Полный build возобновляемый: каждый результат проверяется по receipt; manifest
  создаётся только после последней страницы. SHA кода рендера входит в identity.
  `--raster-cache-dir` повторно использует изображение только при совпадении SHA
  заново построенного SVG и проверке размеров/SHA всех файлов. Исходники не меняются.
- Для единственного `p245.ttf` с SHA-256 `3aa219eb172861eee4915f284f4c2cc11c9ee8caa21fda7c3c8bbcb517773d68`
  нормализуется только cmap **в памяти**: две совпадающие Unicode-таблицы вместо
  повреждённой legacy Macintosh-таблицы. Другие таблицы, glyph IDs и кривые
  сохраняются побайтно; это покрыто регрессионным тестом. Неизвестные дефекты
  других файлов останавливают сборку, а не включают font fallback.
- Backend: `MushafRendition → MushafRenditionRelease → MushafRenditionPage`.
  Админка только для просмотра с русскими подписями. Добавочная миграция `0005`
  не меняет существующие таблицы/идентификаторы. Публикация проверяет 604 страницы,
  все 6236 аятов, полное совпадение canonical page mapping, геометрию, 3 разрешения
  и хеши. Сначала immutable upload, затем атомарное включение. Ошибка/смена
  canonical version во время загрузки не изменяет публичный указатель.
- API: `/api/v1/quran/mushaf-renditions`, `/{code}/pages/{number}`,
  `/{code}/offline-manifest`. Последние два пути продолжают первый.
  Preview доступно только в staging settings; production не публикуется командой.
- Flutter: выбор `native:qcf-v2-hafs`, раздельные API/page cache/content keys,
  сохранённая настройка, фрагменты аятов того же оформления. Скачанное старое
  издание остаётся. По одному download controller на визуальное издание, поэтому
  переключение во время скачивания не создаёт второго писателя файлов.
  Канонический repository, bookmarks и аудио остаются `madani-hafs`.
  Production-сборка не включает staging preview из сохранённых preferences.

Подготовка (новые каталоги; не выполнять очистку существующих):

```bash
python3 ops/mushaf-glyph-pilot/fetch_full.py --tree /absolute/path/pinned-git-tree.json --output /absolute/path/new-source
python3 ops/mushaf-glyph-pilot/build_full.py --source-dir /absolute/path/new-source --output-dir /absolute/path/new-bundle
```

После проверенных backup, commit и staging deployment, внутри backend runtime:

```bash
python manage.py publish_mushaf_rendition /absolute/path/bundle/manifest.json --validate-only
python manage.py publish_mushaf_rendition /absolute/path/bundle/manifest.json
```

Bundle передаётся отдельно от `git archive` в новый каталог. Секреты и базы из
локального окружения не передаются. Исходные TTF/DB не включаются в APK или
публичный media bucket. В хранилище загружаются только проверенные WebP под
`quran/mushaf-renditions/staging/qcf-v2-hafs/{version}/{manifest SHA}/`.

Дополнительные opt-in проверки:

```bash
IQRO_MUSHAF_FULL_SOURCE_DIR=/absolute/path/new-source python3 -m unittest discover -s ops/mushaf-glyph-pilot -p 'test_*.py'
# Из services/backend, на изолированной pytest-БД и публичном snapshot page mapping:
IQRO_MUSHAF_FULL_BUNDLE_DIR=/absolute/path/new-bundle IQRO_CANONICAL_PAGE_MAPPING=/absolute/path/mapping.json .venv/bin/pytest tests/test_mushaf_full_publication.py --no-cov
# Из clients/iqro_mobile: декодирование 1812 изображений, карта всех 6236 аятов:
IQRO_MUSHAF_FULL_BUNDLE_DIR=/absolute/path/new-bundle flutter test --no-pub test/integration/mushaf_full_bundle_test.dart
```

Факт деплоя/установки и результаты проверок фиксируются отдельно в
`clients/iqro_mobile/docs/PUBLIC_RELEASE_PLAN.md`; наличие кода само по себе
не означает установку нового издания пользователю.

## История: шестистраничный пилот

Статус: **технический черновик, не опубликованное издание**. Проверяются страницы
1, 2, 3, 50, 255, 604 из одного закреплённого набора
[JMApps/mymushaf](https://github.com/JMApps/mymushaf/tree/1d040f68d284f8e6db515157f8425abfefd78df6).
Не изменяет backend, каталог чтецов, пользовательские загрузки или действующий
`madani-hafs`. Не включает скрытые варианты в мобильном меню.

## Что реализовано

- `source.lock.json`: commit, размеры и SHA-256 базы и шести постраничных TTF.
  База содержит 604 страницы, 114 сур, 6236 аятов, 83668 записей слов.
- `prepare.py`: read-only аудит всей базы и подготовка выбранных страниц.
  Проверяются последовательность слов/страниц, покрытие аятов, заголовки,
  112 вводных басмал, размер/хеш каждого файла, семейство каждого шрифта.
- HarfBuzz сохраняет позиционирование составных слов и знаков остановки;
  fontTools извлекает исходные кривые, включая составные глифы. Никакого
  системного font fallback, перерисовки арабского текста или AI-генерации.
- Один равномерный масштаб глифов на страницу. Высота строк учитывает реальные
  огласовки/нижние элементы; минимум 6 единиц свободного межстрочного пространства.
  Для выделения используются области той же раскладки, а не старого скана.
- `raster.cjs`: lossless WebP 720/1440/2160 px, каждый размер рендерится из SVG,
  а не увеличивается из маленькой картинки. После кодирования сравниваются
  декодированные пиксели. SVG не может подключать URL, изображения или шрифты.
- `*.mobile.json`: компактная карта в формате существующего `MushafPageData`.
  У аята поля `surah` и `number`; публичных URL и выдуманных backend UUID нет.
  Эти файлы **не** являются публикационным manifest/API.
- Локальный просмотр с выделением всех строк одного аята. Это инструмент QA,
  не web-приложение пользователя; аудио в нём намеренно не подключено.
- Все команды подготовки требуют новый output directory. Существующие файлы
  не перезаписываются и не удаляются. Частичный результат не имеет завершённого
  manifest и не может автоматически включить издание.

Рендер — **IQRO layout draft**, не заявление о пиксельном совпадении с официальной
печатной страницей. В TTF имя семейства `QCF2NNN`, поле версии содержит `KFGQPC TEST`.
Имя репозитория и публичность файлов не подменяют запись происхождения контента.
Заголовки берутся из отдельного `surah_name_v4.ttf`; это осознанная черновая
композиция, не официальная декорация QCF V2. `qcf_bsml.ttf` закреплён для аудита,
но **не используется**: его набор отличается. Вводная басмала составляется
из первых четырёх глифов аята 1:1 исходной базы, без номера аята.

## Воспроизведение

Python 3.11+, зависимости из `requirements.txt` в отдельном окружении. Подготовка
проверяет fontTools 4.43.0, uharfbuzz 0.56.1 и HarfBuzz 14.4.0. Растровый pilot
проверен на Node + sharp 0.35.4, libvips 8.18.6, librsvg 2.62.91, libwebp 1.6.0.
Другой raster runtime требует отдельного сравнения/версии, а не удаления проверки.
`npm ci --ignore-scripts` устанавливает закреплённые registry-пакеты; до использования
проверить `sharp.versions`. Общесистемные Flutter/backend зависимости не изменяются.

Пример скачивания **только девяти контрольных файлов**, около 23 МБ. Все URL
закреплены на commit; секреты/ключи не требуются. Не использовать существующий
каталог с пользовательскими файлами и не выполнять очистку без разрешения.

```bash
IQRO_PILOT_SOURCE_DIR="$(mktemp -d /tmp/iqro-mushaf-source.XXXXXX)"
IQRO_PILOT_ORIGIN="https://raw.githubusercontent.com/JMApps/mymushaf/1d040f68d284f8e6db515157f8425abfefd78df6"
curl -fS --max-time 180 "$IQRO_PILOT_ORIGIN/assets/databases/mushaf_database.db" -o "$IQRO_PILOT_SOURCE_DIR/mushaf_database.db"
for IQRO_PILOT_PAGE in 1 2 3 50 255 604; do
  curl -fS --max-time 60 "$IQRO_PILOT_ORIGIN/assets/pageFonts/p$IQRO_PILOT_PAGE.ttf" -o "$IQRO_PILOT_SOURCE_DIR/p$IQRO_PILOT_PAGE.ttf" || break
done
for IQRO_PILOT_FONT in qcf_bsml.ttf surah_name_v4.ttf; do
  curl -fS --max-time 60 "$IQRO_PILOT_ORIGIN/assets/fonts/$IQRO_PILOT_FONT" -o "$IQRO_PILOT_SOURCE_DIR/$IQRO_PILOT_FONT" || break
done
python3 ops/mushaf-glyph-pilot/prepare.py \
  --source-dir "$IQRO_PILOT_SOURCE_DIR" --output-dir "$IQRO_PILOT_SOURCE_DIR/vectors"
node ops/mushaf-glyph-pilot/raster.cjs "$IQRO_PILOT_SOURCE_DIR/vectors" "$IQRO_PILOT_SOURCE_DIR/rasters"
```

Команды `prepare`/`raster` завершатся ошибкой, если скачивание неполное, файл
подменён, runtime отличается или output уже существует. При ошибке ничего
автоматически не очищать. Для визуального просмотра:

```bash
python3 -m http.server 8766 --bind 127.0.0.1 --directory "$IQRO_PILOT_SOURCE_DIR/vectors"
```

## Тесты

```bash
IQRO_MUSHAF_SOURCE_DIR="$IQRO_PILOT_SOURCE_DIR" \
  python3 -m unittest discover -s ops/mushaf-glyph-pilot -p test_prepare.py -v
node --test ops/mushaf-glyph-pilot/raster.test.cjs
cd clients/iqro_mobile
IQRO_MUSHAF_PILOT_DIR="$IQRO_PILOT_SOURCE_DIR/rasters" \
  flutter test --no-pub test/integration/mushaf_source_pilot_test.dart
```

Source-интеграция без переменных окружения **пропускается**, а не считается
проверенной. Flutter-тест реально декодирует 18 WebP и проверяет checksum,
размеры/наличие пикселей, 98 областей выделения, обратное преобразование координат
и равномерный масштаб в portrait/landscape/portrait. Это не физический поворот
телефона и не benchmark. Synthetic fixture teardown затрагивает только данные
самих тестов, никогда скачанную базу/шрифты.

## Результат контрольного прогона 2026-09-07

Версия раскладки `iqro-glyph-pilot-2`, raster `iqro-glyph-pilot-raster-1`.
16 Python-тестов, 4 Node-теста; полный Flutter-прогон — 345 успешных тестов
(333 существующих + 12 source-проверок). После уточнения масштаба повторены
16 Python, 4 Node и полный Flutter-набор 345 тестов; анализ Flutter без замечаний.

| Страница | Слова / области аятов | Карта, байт | WebP 2160 px, байт |
|---|---:|---:|---:|
| 1 | 36 / 10 | 2082 | 151240 |
| 2 | 41 / 9 | 1906 | 148744 |
| 3 | 138 / 24 | 4549 | 441646 |
| 50 | 144 / 21 | 3993 | 406722 |
| 255 | 107 / 16 | 3122 | 345464 |
| 604 | 73 / 18 | 3600 | 259036 |

Просмотрены все шесть страниц первоначального черновика; после изменения
масштаба повторно проверены страницы 1 и 3 и выделение 2:7. Редакционное сравнение
с эталонной печатью/исходным приложением и проверка всех 604 страниц ещё не выполнены.
Технические цифры для шести страниц не являются измеренным размером полного издания.

Локальные результаты текущего прогона (не архив релиза):
`/tmp/iqro-mushaf-font-pilot.dNIPhX/preview-v6`,
`/tmp/iqro-mushaf-font-pilot.dNIPhX/raster-v3`,
`/tmp/iqro-mushaf-flutter-final-tests-20260907.log`,
`/tmp/iqro-mushaf-python-tests-20260907.log`.

## Исторический план после шестистраничного пилота

1. Сопоставить контрольную типографику с эталоном; закрепить окончательную
   раскладку/декорации и условия набора. Не переименовывать draft в official facsimile.
2. Расширить lock на все 604 TTF того же commit, проверить все знаки/страницы,
   выполнять подготовку ограниченными возобновляемыми batch-ами. Сейчас скачано
   **6**, а не 604 шрифта. Около 208 МБ полного набора не добавлять в APK.
3. Backend: отдельная visual edition/version, полный manifest, immutable storage,
   нормализованные ayah regions с привязкой к существующим `surah:number` и UUID,
   атомарная публикация только после полного покрытия. Не смешивать JMApps bundle
   с Quran.Foundation source `1` только потому, что оба называют шрифт QCF V2.
4. Flutter: edition-aware выбор, API/manifest/cache/offline и excerpts; только затем
   менять `supportedOnMobile`. Сохранять текущие downloads и canonical audio IDs.
5. На Android: выбор нового издания → короткий тап/удержание → правильный аят
   в плеере/подробностях → offline/restart → повороты/низкая память. До этого
   новые страницы нельзя называть установленными или готовыми к публикации.
