# Staging R2: synthetic audio CDN capacity evidence

Дата прогона: 25 августа 2026 года. Цель — проверить самый дорогой контур отдельно от VPS:
`client → media.staging.iqro.forum → Cloudflare R2/CDN`.

## Границы результата

- bucket: только `iqro-staging-media`, storage class Standard;
- объект: `diagnostics/audio-capacity/synthetic-zero-8m-v1.mp3`, 8 MiB;
- объект синтетический и не является записью Корана: нулевые байты с `audio/mpeg` нужны только
  для измерения CDN `HEAD`/Range, TTFB и throughput без копирования чужого аудио;
- manifest: [staging-r2-synthetic-audio-manifest-2026-08-25.json](staging-r2-synthetic-audio-manifest-2026-08-25.json);
- CDN contract: [staging-r2-synthetic-audio-contract-2026-08-25.json](staging-r2-synthetic-audio-contract-2026-08-25.json), pass;
- load generator находился в одном регионе и использовал HTTP/1.1 keep-alive connections;
- warm CDN: все измеряемые Range-ответы были `206` и преимущественно
  `CF-Cache-Status: HIT`;
- gate: error rate <= 1%, p95 TTFB <= 750 ms.

Cloudflare R2 custom domain возвращает точный `206 Content-Range`, но может не повторять
`Accept-Ranges` на самом `206`; заголовок присутствует на `HEAD`. Harness исправлен так, чтобы
принимать корректный `206` с точным диапазоном и по-прежнему требовать `Accept-Ranges: bytes`
на `HEAD`. Регрессия покрыта unit-тестами.

## Профили и результаты

Playback-профиль использует Range 64 KiB и паузу 2 секунды. Это соответствует примерно
256 kbps на непрерывно активного клиента до учёта задержки запроса и является консервативным
профилем для записей 128–192 kbps.

| Профиль | Плееры | Время | Запросы | Ошибки | p95 TTFB | p50 throughput | Gate |
|---|---:|---:|---:|---:|---:|---:|:---:|
| playback | 10 | 62 s | 275 | 0% | 166 ms | 5 077 kbps | pass |
| playback | 25 | 122 s | 1 229 | 0% | 446 ms | 2 073 kbps | pass |
| playback | 30 | 184 s | 1 922 | 0% | 818 ms | 1 007 kbps | **fail** |
| playback | 35 | 183 s | 2 173 | 0.05% | 817 ms | 836 kbps | **fail** |
| playback | 50 | 184 s | 2 414 | 0% | 1 070 ms | 335 kbps | **fail** |

Машиночитаемые reports:

- [playback 10/25](staging-r2-synthetic-audio-playback-2026-08-25.json);
- [boundary 30](staging-r2-synthetic-audio-boundary-30-2026-08-25.json);
- [boundary 35](staging-r2-synthetic-audio-boundary-35-2026-08-25.json);
- [boundary 50](staging-r2-synthetic-audio-boundary-50-2026-08-25.json).

Отдельный намеренно агрессивный профиль использовал Range 128 KiB каждые 0.5 секунды — около
2 Mbps запрашиваемого потока на клиента. На нём 5 клиентов прошли с p95 TTFB 175 ms, а 10 уже
не прошли: p95 TTFB 1 202 ms при 0% HTTP errors. Результат сохранён в
[aggressive report](staging-r2-synthetic-audio-smoke-2026-08-25.json) как точка деградации, а
не как модель обычного воспроизведения.

## Влияние на VPS и стоимость теста

Во время 10 и 50 CDN-плееров web использовал 0–0.01% CPU, backend около 0.4%, PostgreSQL
0–0.01%. Аудиобайты не проходили через Hetzner VPS. Это подтверждает архитектурную развязку:
рост аудиопрослушиваний не требует увеличивать application server только ради egress.

Все прогоны вместе использовали значительно меньше 10 000 read operations и 1 GiB transfer,
плюс один 8 MiB object/PutObject. Это далеко ниже опубликованного бесплатного месячного лимита
R2 Standard: 10 GB-month, 1 млн Class A, 10 млн Class B и бесплатный egress. Фактическая
стоимость всё равно зависит от уже израсходованного usage аккаунта. Актуальные значения:
[Cloudflare R2 pricing](https://developers.cloudflare.com/r2/pricing/).

## Что можно и нельзя обещать

На данном одно-регионном warm-CDN маршруте подтверждены **минимум 25 параллельных playback
клиентов** при консервативном 256 kbps request profile. 30 и выше не прошли p95 TTFB gate, хотя
throughput оставался выше 192 kbps и HTTP errors были 0–0.05%.

Это не глобальный предел Cloudflare R2 и не доказательство реального Quran audio release.
Production gate требует разрешённый immutable multi-surah/multi-reciter manifest, cache-cold и
warm фазы, генераторы из нескольких регионов, browser/player startup-buffering QoE и provider
billing analytics. До этого synthetic evidence используется только как нижняя граница и
проверка архитектуры.
