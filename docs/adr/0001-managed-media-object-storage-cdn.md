# ADR 0001: Managed media через Cloudflare R2 и CDN custom domain

- Статус: принято для первого production deployment
- Дата: 24 августа 2026 года
- Область: публичные managed audio, изображения Мусхафа, портреты и будущие offline packages

## Контекст

Аудио — основной потенциальный источник нагрузки и расходов. Передача байтов через Django,
локальный диск application-host или заранее купленные media-серверы мешает горизонтальному
масштабированию и связывает доступность API с потоковым воспроизведением. При этом beta не
нуждается в инфраструктуре, зарезервированной под 100 000 DAU.

Нужен pay-as-you-go origin с S3-совместимым upload API, публичный CDN hostname, byte ranges,
CORS для web/Telegram Mini App, стабильная валидация кэша и возможность сменить provider без
изменения продуктового API.

## Решение

Первый production provider — Cloudflare R2 Standard за custom domain
`media.<production-domain>` с Cloudflare Cache. Выбор основан на оплате фактического storage и
операций, отсутствии платы R2 за internet egress на дату ADR и наличии S3-compatible API.
Актуальные условия всегда перепроверяются перед deployment по официальным страницам
[R2 pricing](https://developers.cloudflare.com/r2/pricing/) и
[S3 API compatibility](https://developers.cloudflare.com/r2/api/s3/api/); этот ADR не фиксирует
цену в коде.

Custom domain обязателен, потому что именно он включает CDN cache/security controls. Публичный
`r2.dev` разрешён только для временного smoke и выключается в production. Это соответствует
официальной модели [R2 public buckets](https://developers.cloudflare.com/r2/buckets/public-buckets/).
Для media hostname создаётся явное Cache Everything rule на allowlisted object prefixes;
query string не участвует, потому что public object URL по контракту не содержит query.

Доступ разделяется:

- upload/list/delete идут только через аутентифицированный S3-compatible endpoint из worker или
  release pipeline; credentials никогда не попадают в API response и клиенты;
- публичное чтение идёт только через `https://media.<production-domain>`;
- Django хранит metadata, object key, checksum и наблюдаемый strong ETag, но не проксирует
  media bytes;
- provider adapter принимает S3 endpoint/bucket/credentials из secret store, поэтому перенос
  в AWS S3, Backblaze B2 или другой совместимый origin не меняет доменные модели и public URL
  contract;
- данные размещаются в допустимой юрисдикции только после legal/privacy sign-off.

## Object и HTTP contract

Managed object key является версионным и никогда не перезаписывается:

```text
audio/{recitation-code}/{content-version}/{scope}-{number}/{rendition}.{extension}
```

Исправление создаёт новую content version или rendition key. Удаление опубликованного объекта
запрещено до завершения withdrawal/retention window. Для каждого объекта upload pipeline
устанавливает корректный `Content-Type` и `Cache-Control: public, max-age=31536000, immutable`.

Перед публикацией `ops/media/contract.py` проверяет для каждого origin web/Mini App:

- `HEAD 200`, точные `Content-Length`/`Content-Type`, `Accept-Ranges: bytes`;
- quoted strong `ETag`, одинаковый для HEAD, Range и conditional response;
- `GET Range: bytes=0-0` → `206` и точный `Content-Range`;
- unsatisfied range → `416` и `Content-Range: bytes */<size>`;
- `If-None-Match` → `304`;
- CORS allow-origin, `Vary: Origin` для origin-specific ответа и exposure заголовков
  `Accept-Ranges`, `Content-Range`, `ETag`;
- immutable public cache не короче одного года.

R2 CORS настраивается на точные production/staging origins по официальному
[CORS guide](https://developers.cloudflare.com/r2/buckets/cors/). Wildcard допустим только для
действительно публичных credentialless assets; cookie и Authorization для media запрещены.

## Стоимость и масштабирование

S0 использует один bucket, один custom domain и Standard storage без зарезервированных media
servers. Новая постоянная мощность не покупается по DAU. Решение о tiered cache, дополнительном
provider, signed delivery или выделенном processing pipeline принимается по byte hit ratio,
origin operations, startup/buffering, storage growth и стоимости на audio-minute.

Cloudflare account не создаётся этим ADR: provisioning, billing limit, budget alerts, lifecycle,
access token scope и rollback проходят отдельный deployment review.

## Последствия и открытые работы

- `AudioTrack` должен остаться логическим таймлайном, а codec/bitrate/size/checksum/object key и
  реальный ETag переехать в отдельные `AudioRendition`.
- API сохраняет один default asset для обратной совместимости и добавляет список renditions;
  выбор качества выполняет клиент по сети/настройке, не backend proxy.
- Upload/import pipeline обязан формировать manifest и сохранять contract evidence до смены
  recitation status на published.
- Для disaster recovery нужен inventory/versioning policy и независимая проверка восстановления;
  PostgreSQL dump не является резервной копией media.

## Отклонённые варианты

- Local filesystem/Nginx: дешёв на старте, но связывает media с host и не выдерживает
  безболезненную репликацию.
- Django audio proxy: переносит egress, Range connections и отказ CDN в API-контур.
- Заранее выделенный media cluster: оплачивает неподтверждённую нагрузку и усложняет операции.
- Provider-specific URLs в БД/API: усложняют миграцию; сохраняются provider-neutral object keys
  и отдельный public base URL.
