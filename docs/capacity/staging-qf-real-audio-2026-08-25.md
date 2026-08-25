# Quran.Foundation real multi-reciter audio: bounded staging probe

Дата прогона: 25 августа 2026 года.

## Что проверено

Проверены три реальных streaming-only записи суры 1 из production Content API
Quran.Foundation:

- Mishari Rashid al-’Afasy, source reciter `7`;
- Maher al-Muaiqly, source reciter `159`;
- Yasser ad-Dussary, source reciter `174`.

Для каждого asset выполнены ровно три обычных запроса: `HEAD`, startup Range 64 KiB и seek
Range 64 KiB. Это **не нагрузочный тест провайдера**. Всего выполнено 9 audio requests;
контент не сохранялся, URL не записывались в evidence, БД и R2 не изменялись.

Порог технической доставки: TTFB не более 1 500 ms и Range throughput не менее 512 kbps.
Проверялись HTTPS, официальный allowlisted host, MIME, `206`, точный запрошенный byte interval,
CORS и согласованность полного размера с metadata Content API.

## Результат

| Чтец | HEAD/startup/seek | Metadata bytes | Origin bytes | Delivery | Release gate |
|---|:---:|---:|---:|:---:|:---:|
| Mishari al-’Afasy | `200/206/206` | 839 808 | 793 327 | PASS | **FAIL metadata** |
| Maher al-Muaiqly | `200/206/206` | 753 249 | 753 249 | PASS | PASS |
| Yasser ad-Dussary | `200/206/206` | 571 029 | 571 029 | PASS | PASS |

У всех трёх assets `Content-Type: audio/mpeg`, `Access-Control-Allow-Origin: *`, startup и seek
Range вернули правильные интервалы и 64 KiB. Общий Range p95 TTFB — **241 ms**, p50 throughput —
**4 604 kbps**. Поэтому обычная доставка трёх реальных записей технически работает.

Общий release gate остаётся failed: у Mishari размер в Content API отличается от фактического
размера того же файла на официальном audio host. Браузер может воспроизводить файл, но наш API
до исправления записал бы неверное поле `bytes`.

## Исправление импортера

Quran.Foundation importer больше не доверяет `file_size` без проверки. Для каждого внешнего
track он выполняет bounded `HEAD` на allowlisted HTTPS audio host и сохраняет фактически
наблюдаемый `Content-Length`. Это не копирует запись и не разрешает offline download.

Публикация всё равно остаётся заблокированной до проверки целостности каталога всех 114 сур,
актуального content/license решения, religious/editorial и product sign-off. Эта проверка
целостности не является нагрузочным тестом. Полный real-audio performance/soak решением
владельца перенесён после ограниченного Web MVP. Согласно
[Quran.Foundation Developer Terms](https://api-docs.quran.foundation/legal/developer-terms/),
QF Content показывается только внутри приложения, не превращается в наш распространяемый
пакет и не копируется в R2 без отдельного письменного разрешения.

## Evidence и границы

- [sanitized JSON](staging-qf-real-audio-probe-2026-08-25.json);
- [synthetic R2 capacity](staging-r2-synthetic-audio-2026-08-25.md) отдельно подтверждает
  25 warm-CDN playback clients, но не качество конкретной записи;
- этот одно-регионный one-shot probe не доказывает multi-surah soak, mobile buffering,
  background playback, глобальную доступность или provider capacity;
- реальный capacity test на инфраструктуре Quran.Foundation не проводится: это чужой сервис.

Следующий безопасный шаг — проверить 114-surah draft catalog без публикации и без нагрузочного
профиля, зафиксировать metadata/origin расхождения и получить внешние sign-off по
[подготовленному пакету](../sign-offs/README.md). Только после этого можно включать конкретного
чтеца в публичный UI. Полный browser/mobile playback QoE и soak остаются post-MVP задачами.
