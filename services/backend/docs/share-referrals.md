# Share / Referral backend contract

Этот модуль расширяет базовую нативную функцию «Поделиться приложением». Сам Share Sheet
остаётся клиентской функцией и работает с bundled fallback без сети. Backend управляет текстами и
доверенными URL без выпуска клиента, выдаёт непрозрачные referral-коды, принимает аналитику,
фиксирует атрибуцию и только на сервере создаёт и подтверждает бонусы.

Модуль: `quran_backend.modules.share_referrals`. Миграция: `share_referrals/0001_initial.py`.

## Новые endpoints

### `GET /api/v1/share/config`

Публичная cacheable-конфигурация. Параметры:

- `locale=ru|en|ar|tr` (по умолчанию `en`);
- `campaign=<stable-key>` необязателен; без него выбирается доступная кампания с наибольшим
  `priority`.

Если кампания и перевод доступны, ответ содержит `key`, `config_version`, `updated_at`, фактически
выбранный `locale`, `title`, `message`, `cta_label`, canonical download URL, App Store / Google Play
URL и `referral_enabled`. Если перевода нет, используется английский, затем первый доступный;
`used_fallback=true` сообщает об этом клиенту.

Отсутствие активной локализованной кампании — штатный ответ `200`:

```json
{
  "available": false,
  "fallback_reason": "no_active_localized_campaign",
  "requested_locale": "ru",
  "used_fallback": true,
  "campaign": null
}
```

Так клиент однозначно переключается на bundled fallback. Ответ поддерживает `ETag` и публичное
кэширование. URL читаются только из валидированной серверной конфигурации.

### `POST /api/v1/me/referrals/links`

Требует подтверждённый аккаунт (`User.status=active`). Гостю возвращается RFC 9457 problem с
`code=verified_account_required` и HTTP 403.

```json
{"campaign_key": "app-invite"}
```

`campaign_key` можно пропустить — будет выбрана текущая кампания с максимальным приоритетом.
Первый запрос возвращает `201`, повторный — тот же код и `200`. Уникальность `(campaign, owner)` и
транзакционная блокировка делают операцию идемпотентной и конкурентно безопасной. Код генерируется
`secrets.token_urlsafe`, не содержит UUID, email или иной PII. Отозванная/отключённая ссылка не
заменяется новой автоматически.

### `GET /api/v1/me/referrals/summary`

Требует подтверждённый аккаунт. Необязательный query-параметр `campaign`. Ответ:

```json
{
  "campaign_key": "app-invite",
  "invited": 5,
  "qualified": 3,
  "reward_balance": 50,
  "pending_reward": 25
}
```

Ответ не содержит идентификаторы, email или другие данные приглашённых и всегда отдаётся с
`private, no-store`.

### `POST /api/v1/share/events`

Требует действующую авторизацию, но принимает и guest account. `account_mode` вычисляется по
серверному пользователю: клиентское значение не является доверенным. Лимит по умолчанию —
`120/hour` на пользователя.

Canonical API envelope:

```json
{
  "client_event_id": "019c...",
  "campaign_key": "app-invite",
  "referral_code": "optional-opaque-code",
  "action": "share_sheet_opened",
  "result": "succeeded",
  "channel": "system",
  "occurred_at": "2026-08-30T12:00:00Z",
  "metadata": {
    "app_version": "1.2.0",
    "platform": "android",
    "source_screen": "settings"
  }
}
```

Допустимые metadata keys: `app_version`, `app_build`, `platform`, `os_major`, `source_screen`.
Вложенные объекты, произвольные поля и длинные строки отклоняются. События принимаются не старше
30 дней и не более чем на пять минут из будущего. Уникальный `client_event_id` даёт `201` при
первой записи и `200/replayed=true` при полном повторе. Повтор UUID с изменёнными данными — 409
`share_event_conflict`. Клиентские события никогда не создают атрибуцию или бонус.

API также напрямую принимает envelope существующего `ShareGateway`, поэтому UI-контракт менять не
нужно:

| ShareGateway | Canonical storage |
|---|---|
| `eventId` | `client_event_id` |
| `campaignId` | `campaign_key` |
| `occurredAt` | `occurred_at` |
| `accountMode` | игнорируется; вычисляет сервер |
| `open-system-share` | `share_sheet_opened`, default channel `system` |
| `copy-link` | `link_copied`, default channel `copy` |
| `copy-code` | `referral_code_copied`, default channel `copy` |
| `shared`, `copied` | `succeeded` |
| `dismissed` | `cancelled` |
| `unavailable` | `failed` |

### `GET /r/{code}`

Публичная короткая ссылка. Backend проверяет campaign active flag, timezone-aware window,
`referral_enabled`, link enabled/revoked state. При успехе фиксируется один `ReferralClick` без IP,
user agent и PII, затем выполняется 302 на `canonical_download_url`. Backend добавляет только
непрозрачные `referral_code` и `campaign`; query-параметры вроде `next` или `redirect_url`
игнорируются. Target всегда строится из сохранённого и повторно проверенного HTTPS URL, поэтому
endpoint не является open redirect. Отозванный, выключенный, неизвестный или просроченный код даёт
404 `referral_link_unavailable`.

## Модель данных и инварианты

- `ShareCampaign`: стабильный key, active/window, доверенные URL, приоритет, reward points и
  монотонный `config_version`.
- `ShareCampaignCopy`: уникальный перевод на `ru/en/ar/tr`. Изменение текста повышает версию
  кампании.
- `ReferralLink`: один долговечный непрозрачный код на `(campaign, owner)`, обратимое disable и
  необратимое revoke с оператором, временем и причиной.
- `ShareEvent` и `ReferralClick`: append-only аналитика. `ShareEvent.client_event_id` глобально
  уникален.
- `ReferralAttribution`: связь code → подтверждённый invitee; invitee уникален внутри кампании,
  self-referral запрещён, есть idempotency key и source.
- `ReferralQualification`: явное `pending → qualified|rejected`. Автоматического fake-signup hook
  нет.
- `ReferralReward`: серверный ledger entry `pending → approved|reversed` и `approved → reversed`;
  сумма копируется из кампании в момент квалификации, поэтому последующая смена кампании не
  переписывает историю.
- `ReferralRewardAudit`: append-only аудит создания, одобрения и отмены.

Все временные окна используют timezone-aware Django datetimes. Критические create/transition
services используют `transaction.atomic`, `select_for_update` и уникальные constraints. Повторные
qualification/approval/reversal не создают повторных начислений или audit rows.

## Django Admin: инструкция оператору

Раздел «Приглашения и промокоды» предназначен для операционного менеджера.

### Запуск кампании

1. Создать «Кампанию “Поделиться”» и задать неизменяемый после релиза `key`.
2. Указать только принадлежащие продукту HTTPS URLs. Canonical URL — единственный target короткого
   redirect.
3. Добавить inline-переводы RU, EN, AR, TR. Английский — обязательный продуктовый fallback.
4. Указать окно, приоритет, включить campaign/referrals и при необходимости reward points.
5. Проверить колонку «Доступна сейчас» и ссылку «Открыть HTTPS-страницу».

Любое сохранение campaign/copy увеличивает `config_version`; новый текст начнёт приходить клиенту
после обновления ETag/cache, без релиза приложения.

### Ссылки и abuse control

Ссылки создаёт только API. В списке нет email — поиск ведётся по exact code или opaque user UUID.
Доступны явные actions:

- «Отключить» — обратимая пауза;
- «Включить» — работает только для неотозванных ссылок;
- «Отозвать без возможности включения» — необратимо, с operator/time/reason audit fields.

### Ручная атрибуция и квалификация

Пока нет trusted install/signup hook, оператор создаёт «Атрибуцию приглашения»: выбирает ссылку,
подтверждённый invitee и UUID idempotency key из проверенного кейса. Admin сам ставит
`manual_admin`, кампанию и оператора и создаёт pending qualification. Direct self-referral и
повторная атрибуция invitee в одной кампании блокируются.

На экране qualifications оператор выполняет action «Подтвердить…», «Отклонить…» или «Отменить
подтверждённое…». Qualification создаёт ровно одно pending reward, если `reward_points > 0`. Это
не зачисляет баланс автоматически. Отмена qualification атомарно переводит связанное начисление в
`reversed`, поэтому баланс и счётчик qualified сразу перестают его учитывать.

### Начисления

Исторические поля ledger read-only. Оператор использует только actions:

- «Одобрить ожидающие начисления»;
- «Отменить начисления с записью в аудит».

Events, clicks и reward audit полностью read-only и не удаляются из Admin. Для retention в будущем
нужна отдельная согласованная privacy policy и management command, а не ручное удаление.

## Flutter / ShareGateway integration

Production adapter делает следующие независимые операции:

1. `getExperience`: GET config; при `available=false`, timeout или offline возвращает bundled
   fallback. Поле `configVersion` берётся из server `config_version` как строка.
2. Для verified account параллельно POST get-or-create link и GET summary. HTTP 403 оставляет
   обычную download link без ошибки основного sharing flow.
3. `trackEvent`: отправляет текущий gateway envelope как есть либо canonical snake_case. Outbox
   сохраняет один UUID до ответа `200/201`; 409 отправляется в dead-letter diagnostics, а не
   ретраится бесконечно.
4. Никаких bonus calculations в Flutter. UI показывает только server summary.

Share Sheet и copy должны завершаться даже при полной недоступности backend. Analytics outbox не
должен блокировать пользователя.

## Privacy, abuse и эксплуатационные ограничения

- В short URL нет email/user UUID; code имеет криптографическую энтропию и непрозрачен.
- Click не хранит IP или user agent. Event metadata строго allow-listed.
- Redirect не принимает target URL и не использует client-provided destination.
- Event, link и redirect имеют отдельные fixed-window throttles. Edge/CDN rate limiting и bot
  mitigation всё равно рекомендуются перед публичным запуском.
- Бонус создаётся только через trusted service `record_referral_attribution` +
  `qualify_referral`; event ingestion не является доказательством install/signup.
- Для автоматизации signup backend должен вызвать `record_referral_attribution(...,
  source="signup_hook")` только после подтверждённого аккаунта и anti-abuse checks. Endpoint для
  client-side qualification специально отсутствует.
- Баллы пока являются внутренними целыми points без денежной стоимости, сроков действия и payout.
  Такие правила нужно утвердить до публичного обещания бонуса пользователям.

## Environment и rate limits

Без секретов и обязательных env-переменных. Настраиваемые безопасные лимиты:

- `QURAN_SHARE_EVENT_RATE` — default `120/hour`;
- `QURAN_REFERRAL_LINK_RATE` — default `30/hour`;
- `QURAN_REFERRAL_REDIRECT_RATE` — default `300/hour`.

Public short-link domain задаётся в кампании как HTTPS `short_link_base_url`. Если поле пустое,
ответ link API строится из allow-listed host текущего API request и `/r/{code}`.

## Решения, которые ещё нужны от product owner

- окончательный stable campaign key (`app-invite` или совместимый с bundled
  `evergreen-share-v1`);
- production canonical domain и App Store / Google Play URLs;
- юридические правила бонусов, срок действия, лимиты на пользователя и антифрод-критерии;
- trusted lifecycle event, который квалифицирует приглашение (verified signup, first reading goal,
  retention day N и т. п.);
- retention period для events/clicks и необходимость consent/analytics opt-out;
- нужен ли отдельный install-attribution provider для iOS/Android. Текущий redirect надёжно считает
  clicks, но сам по себе не доказывает install.
