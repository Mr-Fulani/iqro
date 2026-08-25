# Quran content acceptance record — template

Создайте копию этого файла для каждого нового immutable dataset. Поля нельзя переносить из
старой версии без повторной проверки hashes и источников.

Статус: **release blocked until every gate below is approved**

## Release identity

- Edition: `________________________________`
- Content version: `________________________________`
- Dataset schema: `________________________________`
- Aggregate SHA-256: `________________________________`
- Asset manifest SHA-256: `________________________________`
- Counts: surahs `____`, ayahs `____`, pages `____`, juz `____`, hizb `____`, rub `____`
- Source lock path/commit: `________________________________`
- Candidate build date and timezone: `________________________________`

## Source and rights matrix

| Layer | Exact source URL/release | Retrieved | SHA-256/commit | Terms/notice snapshot | Attribution | Decision |
|---|---|---|---|---|---|---|
| Quran text | | | | | | `PASS / FAIL` |
| Ayah/page mapping | | | | | | `PASS / FAIL` |
| Page artwork/font | | | | | | `PASS / FAIL` |
| Translations, if any | | | | | | `PASS / FAIL / N/A` |

Нельзя указывать официального владельца вместо фактического download source. Redirect chain,
исходный filename, размер, SHA-256 и действовавшие на дату получения условия сохраняются в
release evidence. Юридический reviewer проверяет не только название лицензии, но и наш способ
публичного отображения, CDN delivery и атрибуцию.

## Automated technical gates

| Проверка | Результат | Evidence/CI run |
|---|---|---|
| Source lock и aggregate/per-file checksums | `PASS / FAIL` | |
| Exact expected Quran structure counts | `PASS / FAIL` | |
| Dataset schema and publication validator | `PASS / FAIL` | |
| Page/region geometry full sweep | `PASS / FAIL / N/A` | |
| Asset manifest and CDN contract | `PASS / FAIL / N/A` | |
| Server-rendered surah/ayah smoke | `PASS / FAIL` | |
| Mobile/tablet/desktop viewport matrix | `PASS / FAIL` | |
| RU/EN/AR/TR metadata and AR/RTL | `PASS / FAIL` | |
| Backup before import and tested rollback path | `PASS / FAIL` | |
| Release CI/security on exact commit | `PASS / FAIL` | |

Технический gate проверяет целостность, но не является религиозным или юридическим решением.

## Religious/editorial review

Минимум проверить страницы 1–2, последнюю страницу, границы сур/джуза/хизба, длинный и
многосегментный аят, номер страницы/суры/аята, Arabic text и интерактивную область на mobile,
tablet и desktop. Reviewer может расширить выборку и обязан остановить release при сомнении.

- Reviewed cases/pages/ayahs: `________________________________`
- Findings/tickets: `________________________________`
- Reviewer name: `________________________________`
- Qualification: `________________________________`
- Decision: `APPROVED / REJECTED / CHANGES REQUIRED`
- Confirmation/signature reference: `________________________________`
- Date and timezone: `________________________________`

## Legal/license review

- Exact public attribution reviewed: `YES / NO`
- Public `/sources` evidence: `________________________________`
- Distribution/display model reviewed: `________________________________`
- Territory/commercial restrictions: `________________________________`
- Reviewer name and role: `________________________________`
- Decision: `APPROVED / REJECTED / CHANGES REQUIRED`
- Advice/message/ticket reference: `________________________________`
- Date and timezone: `________________________________`

## Product decision

- Application release commit/image tags: `________________________________`
- Public origin: `________________________________`
- Decision: `APPROVED / REJECTED`
- Product owner name and role: `________________________________`
- Ticket/signature reference: `________________________________`
- Date and timezone: `________________________________`

## Activation and rollback

- Pre-activation backup/checksum: `________________________________`
- Exact import/publish command or release job: `________________________________`
- Expected active content pointer: `________________________________`
- Previous accepted version: `________________________________`
- Rollback command/job: `________________________________`
- Cache purge/revalidation evidence: `________________________________`
- Post-activation smoke evidence: `________________________________`

Публикация разрешена только если automated technical, religious/editorial, legal/license и
product decisions относятся к одним и тем же hashes/version. Исправление создаёт новый
immutable candidate и новый record.
