# Quran source provenance audit

Дата проверки: 25 августа 2026 года.

Объект проверки: `madani-hafs@1.0.2`.

Итог: **версию 1.0.2 нельзя активировать в production до исправления provenance page artwork**.
Dataset технически цел и остаётся полезным для закрытого от индексации staging, но его release evidence
не позволяет без дополнительного юридического решения утверждать, что все 604 WebP получены
непосредственно из зафиксированного официального источника.

Это технический аудит происхождения, а не юридическое заключение и не религиозный sign-off.

## Матрица источников

| Слой | Фактический источник | Зафиксированное доказательство | Условия | Результат |
|---|---|---|---|---|
| Текст аятов | Tanzil через pinned mirror commit | SHA-256 исходного JSON и Tanzil payload записаны в source lock | CC BY 3.0; текст нельзя изменять, источник и ссылка обязательны | Технически подтверждено; перед релизом проверить точную публичную атрибуцию и воспроизведение notice |
| Ayah regions/page mapping | `quranpedia/quran-svg` pinned commit | Commit и aggregate SHA-256 для 604 JSON записаны в source lock | Собственный polygon/JSON слой опубликован как CC0 1.0 | Технически подтверждено; юридический reviewer подтверждает применимость |
| Page artwork | PDF SHA-256 `76c690…34a`, из него построены 604 WebP | PDF metadata: `Author=quran.ws`, `Creator/Producer=pdf.quran.ws`; asset manifest и hashes полные | `pdf.quran.ws` описывает страницы как King Fahd Complex Madani mushaf; отдельный зафиксированный terms snapshot дистрибутора отсутствует | **Недостаточно для релиза 1.0.2** |
| Права официального издателя | King Fahd Glorious Qur'an Printing Complex | Официальная developer platform предлагает digital Muṣḥaf для computer/smart apps и websites | Фактические условия должен подтвердить legal reviewer для конкретного артефакта и способа распространения | Источник подходит как целевой, но текущий PDF не скачан и не закреплён непосредственно с официальной платформы |

## Обнаруженное противоречие

Manifest и код называют page source «pinned KFQC PDF», но проверяемая metadata конкретного PDF
указывает `quran.ws`. Сам сайт `pdf.quran.ws` заявляет, что PDF построен из King Fahd Complex
masters, однако в source lock нет download URL, даты получения, сохранённого terms evidence или
прямого checksum официального пакета, связывающего наш PDF с этими masters.

Нельзя исправлять это простым переименованием источника внутри уже собранной `1.0.2`: версия и
её артефакты неизменяемы. Исправление выпускается новым content version.

## Выбранный безопасный путь

1. `madani-hafs@1.0.2` не выпускать в production. Временная активация на noindex staging
   разрешена только для технического SSR/API/load test и не считается sign-off.
2. Получить page artwork напрямую с официальной
   [King Fahd Complex developer platform](https://qurancomplex.gov.sa/en/techquran/dev/) или
   [официального digital-mushaf портала](https://dm.qurancomplex.gov.sa/).
3. Зафиксировать download URL, дату, исходный filename, размер, SHA-256, официальный terms URL
   и неизменяемую копию notice/terms evidence в source lock нового кандидата.
4. Детерминированно построить новые page assets и dataset как новую версию, предварительно
   обозначенную `madani-hafs@1.1.0`; старые WebP и manifest не перезаписывать.
5. Повторить 604-page checksum/geometry audit, curated ручную проверку и viewport matrix.
6. Проверить, что публичная `/sources` показывает Tanzil attribution, Quranpedia/CC0 layer,
   King Fahd Complex как владельца page edition и ссылки на применимые условия.
7. Только для нового immutable кандидата получить religious/editorial, license/legal и product
   sign-off, затем upload/publish/activate.

## Первичные и проверяемые ссылки

- [Tanzil Text License](https://tanzil.net/docs/Text_License)
- [King Fahd Complex developer platform](https://qurancomplex.gov.sa/en/techquran/dev/)
- [King Fahd Complex digital mushaf portal](https://dm.qurancomplex.gov.sa/)
- [quranpedia/quran-svg NOTICE](https://github.com/quranpedia/quran-svg/blob/main/NOTICE.md)
- [Фактическая страница quran.ws Hafs PDF](https://pdf.quran.ws/hafs/)

Перед внешним sign-off reviewer должен открыть актуальные первичные условия повторно: этот
документ фиксирует инженерное решение и дату проверки, но не заменяет консультацию юриста.
