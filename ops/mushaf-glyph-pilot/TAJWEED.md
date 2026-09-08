# QCF V4 Tajweed → native IQRO

Полный источник — существующий Quran.Foundation Mushaf **19**, Hafs, 604 страницы,
6236 аятов. Отдельное оформление `qcf-v4-tajweed-hafs`, не новый риваят и не замена
канонического текста, аудиокаталога, имён/портретов чтецов или других Мусхафов.

## Зафиксированные входы

- Backend snapshot SHA-256 источника:
  `b7f0bcd06bfd51232555a163c1f1ce404bd62b14791ce357c7c5689d70b72e60`.
- `tajweed.source.lock.json`: 604 WOFF2, SHA/bytes каждого, SHA snapshot, palette 0.
  Canonical lock SHA: `414069309a42a6a539d42b3f122232c48ef41a5c2f3e173570cf5250c8e42c8f`.
- Оригинальные URL:
  `https://verses.quran.foundation/fonts/quran/hafs/v4/colrv1/woff2/p{page}.woff2`.
  **Содержимое всех закреплённых файлов — COLR version 0**, несмотря на `colrv1` в URL.
  Адаптер сохраняет порядок оригинальных слоёв и RGBA палитры, не раскрашивает текст
  эвристически. Неизвестная версия COLR/несовместимый источник отвергаются.
- Заголовки сур используют закреплённый QPC Unicode-шрифт из KFGQPC набора только
  как оформление. Аяты, номера и басмала — из QF19; подмены аятов другим шрифтом нет.

## Геометрия и ограничения

Одинаковая с остальными новыми оформлениями сетка IQRO на 15 строк. Это собственная
раскладка, **не официальное факсимиле**. Масштаб контуров и hit regions согласован.
Glyph без записи COLR рисуется собственным outline в foreground, как предусмотрено
форматом шрифта; это не font fallback. Внутрисловные пробелы сохраняют advance.
Пустые glyph-слои пропускаются только при отсутствии контура/границ; полностью пустое
видимое слово вызывает отказ. Особенность записи `1950117` / 2:181 / p27 / `ﳍ`,
которую источник назвал word вместо end, исправляется только при полном совпадении
закреплённой идентичности; произвольные расхождения не игнорируются.

Выход: 604 geometry maps + 1812 lossless WebP шириной 720/1440/2160; каждое изображение
декодируется и сравнивается с исходным SVG-рендером. Backend проверяет все 6236
канонических ссылок, Flutter — изображения и hit-test каждой области на phone/tablet.
Пакеты имеют отдельные immutable edition/version/cache keys; право публикации source19
проверяется по актуальному source19 snapshot, а не checksum другого источника.

Версия `qcf-v4-tajweed-iqro-20260908-v1`, renderer `iqro-qcf-v4-tajweed-1`.
Manifest SHA: `8c9bbab040e59a5000a2c443f2f416b61a0ecad029eec0ad7b3ad8bb0c59c68d`.
Изображения всех трёх ширин и геометрия: 499161290 bytes; offline-пакет выбирает одну
ширину, поэтому его размер меньше. Бинарные корпуса не включаются в Git.

## Воспроизводимость

После read-only `export_qf_mushaf_source --mushaf 19`:

```sh
python3 ops/mushaf-glyph-pilot/fetch_tajweed.py --help
python3 ops/mushaf-glyph-pilot/tajweed.py --help
# Требуются закреплённые snapshot/604 fonts и decoration-source KFGQPC.
python3 ops/mushaf-glyph-pilot/tajweed.py \
  --source-dir /absolute/path/source \
  --decoration-source /absolute/path/kfgqpc-source \
  --output-dir /absolute/path/new-immutable-bundle
```

Runtime/code identities сохраняются в build-identity; другие исходники/версии не
перезаписывают готовый output. Tests: `test_tajweed.py` (4), backend full-publication
test с read-only canonical mapping, Flutter full-bundle test. Все прошли локально.
Runtime staging publication, device/offline QA и редакционное принятие фиксируются
отдельно в `clients/iqro_mobile/docs/PUBLIC_RELEASE_PLAN.md`. Production/store sign-off
не следует из наличия ключей API или успешного технического теста.
