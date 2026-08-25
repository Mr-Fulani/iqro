# Quran dataset build specification

`build_quran_dataset` использует отдельную JSON-спецификацию для каждого издания Мусхафа.
Поэтому код сборщика одинаков для Hafs, Warsh, Qaloun, Shu'bah и других риваятов, а различия
хранятся как данные и проходят одинаковые проверки.

Без `--spec` команда использует прежний закреплённый профиль `madani-hafs@1.0.2`. Для другого
издания передайте файл явно:

```bash
uv run python manage.py build_quran_dataset \
  /path/to/normalized-quran.json \
  /path/to/page-regions \
  /path/to/page-assets/manifest.json \
  /path/to/output-dataset \
  --spec /path/to/edition-build-spec.json
```

Минимальная форма спецификации:

```jsonc
{
  "schema_version": 1,
  "source_version": "official-warsh-package-2026-08-25",
  "edition": {
    "code": "madani-warsh",
    "version": "1.0.0",
    "asset_version": "1.0.0",
    "name_ar": "مصحف ورش",
    "name_en": "Warsh Mushaf",
    "name_ru": "Мусхаф Варш",
    "riwayah": "Warsh 'an Nafi",
    "source_name": "Pinned official package",
    "source_url": "https://provider.example/package",
    "license_name": "Reviewed provider terms",
    "license_url": "https://provider.example/terms"
  },
  "corpus_sha256": "<64 lowercase hex characters>",
  "polygon_set_sha256": "<64 lowercase hex characters>",
  "expected_counts": {
    "surahs": "<verified positive integer>",
    "ayahs": "<verified positive integer>",
    "pages": "<verified positive integer>",
    "juz": "<verified positive integer>",
    "hizb": "<verified positive integer>",
    "rub_el_hizb": "<verified positive integer>"
  },
  "geometry": {
    "registered_page_scale": 2.337,
    "standard_viewbox": [345.0, 550.0],
    "opening_viewbox": [235.0, 235.0],
    "opening_page_count": 2,
    "page_assignment_authority": "Reviewed official Warsh polygon geometry"
  },
  "sources": {
    "corpus": {"provider": "Official provider", "license": "Reviewed terms"},
    "regions": {"provider": "Official provider", "license": "Reviewed terms"},
    "assets": {"provider": "Official provider", "license": "Reviewed terms"}
  }
}
```

Placeholder в примере намеренно не является допустимым входом. В рабочем JSON каждое поле
`expected_counts` должно быть числом из проверенного source manifest конкретного риваята;
нельзя переносить числа текущего Hafs dataset по предположению.

Поле `surah_names_ru` можно не задавать для обычного полного набора из 114 сур: тогда
используется встроенный проверенный список русских названий. Для набора с другим количеством
сур поле обязательно и должно содержать ровно `expected_counts.surahs` элементов.

Сборщик прекращает работу, если:

- checksum корпуса или полного набора polygon JSON не совпал;
- код издания может выйти за безопасный object-key prefix;
- corpus, regions или page manifest не покрывают заявленные количества;
- хотя бы один аят не имеет геометрии или ссылается на неизвестную страницу;
- координаты выходят за зарегистрированную страницу;
- отсутствуют обязательные provenance, license или edition metadata.

Входной Quran corpus пока должен быть предварительно приведён к существующему
нормализованному JSON-контракту (`surahs[]`, `ayahs[]`, номера juz/hizb/rub и исходная page
mapping). Если официальный поставщик отдаёт другой формат, для него нужен небольшой adapter,
но основная сборка, проверка и импорт dataset уже не требуют изменений в коде.
