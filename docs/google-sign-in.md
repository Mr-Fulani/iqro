# Вход через Google

Сайт и Android-приложение умеют входить Google-аккаунтом в одно касание. Вход по коду из
письма остаётся запасным. Пока на сервере не заданы client ID, функция выключена: кнопка
не показывается ни на сайте, ни в приложении, а `POST /api/v1/auth/google` отвечает 404.

## Как это устроено

1. Сайт показывает кнопку Google Identity Services и One Tap на странице входа. Приложение
   на Android открывает лист выбора аккаунта Credential Manager (пакет `google_sign_in` 7.x).
2. Google выдаёт подписанный ID-токен (JWT) для нашего **Web client ID**. Android-приложение
   тоже запрашивает токен для Web client ID (`serverClientId`), поэтому `aud` у токена тот же.
3. Клиент отправляет токен на `POST /api/v1/auth/google` вместе со своей гостевой сессией.
   Бэкенд проверяет подпись по ключам Google (`https://www.googleapis.com/oauth2/v3/certs`,
   кэш по `Cache-Control`), `iss`, `aud` (Web и Android client ID), срок `exp`/`iat` с допуском
   60 секунд и `email_verified`.
4. Аккаунт ищется по идентификатору Google (`sub`), затем по проверенной почте. Аккаунт,
   созданный по коду из письма, получает вторую привязку (Google) — дубля не появляется.
   Если не нашёлся никакой, гость становится аккаунтом с этой почтой. Гостевые закладки и
   прогресс переносятся так же, как при входе по коду.
5. Ответ — те же access/refresh-токены, что и после кода из письма.

Настройки клиенты получают с `GET /api/v1/auth/google/config`: `{"enabled": true,
"client_id": "<Web client ID>"}`. Пересобирать приложение после включения не нужно.

«Сменить аккаунт» в профиле: выход, сброс выбранного Google-аккаунта и сразу новый выбор.
«Выйти» тоже сбрасывает выбор, чтобы следующий вход спросил, каким аккаунтом входить.

Удаление аккаунта и его отмена по-прежнему подтверждаются кодом из письма.

## Что создать в Google Cloud

Всё делается владельцем в консоли Google Cloud под аккаунтом **fulani.dev@gmail.com**,
в одном проекте (например, «IQRO»). Android-клиент и Web-клиент обязаны быть в одном
проекте, иначе Android не выдаст токен для Web client ID.

### 1. Экран согласия (Google Auth Platform → Branding / Audience)

- Название приложения: IQRO; почта поддержки и контактная почта разработчика.
- Домашняя страница `https://iqro.forum`, политика конфиденциальности
  `https://iqro.forum/ru/privacy`, условия `https://iqro.forum/ru/terms`.
- Авторизованный домен: `iqro.forum`.
- Тип пользователей: **External**. Доступы (scopes): только `openid`, `email`, `profile` —
  они не «чувствительные», проверка приложения Google для них не требуется.
- Статус публикации: **In production**. В статусе Testing войти смогут только
  добавленные тестовые пользователи.

### 2. Web client (Clients → Create client → Web application)

- Название: `IQRO web`.
- Authorized JavaScript origins:
  - `https://iqro.forum`
  - `https://www.iqro.forum`
  - для локальной разработки: `http://localhost` и `http://localhost:3000`
- Authorized redirect URIs: не нужны (кнопка работает через callback, без перенаправлений).
- Client ID вида `123…-abc.apps.googleusercontent.com` — это `QURAN_GOOGLE_WEB_CLIENT_ID`.
  Секрет клиента (client secret) не используется: не копируйте его никуда.

### 3. Android client (Clients → Create client → Android)

Нужны два Android-клиента с пакетом `forum.iqro.app`, по одному на каждый ключ:

| Клиент | SHA-1 | Где взять |
|---|---|---|
| `IQRO Android (Play)` | сертификат **ключа подписи приложения** | Play Console → Тестирование и выпуск → Целостность приложения → Подпись приложения → «Сертификат ключа подписи приложения» |
| `IQRO Android (upload)` | сертификат **ключа загрузки** | там же, «Сертификат ключа загрузки», или `keytool -list -v -keystore ~/Documents/IQRO-play-key/iqro-upload.jks -alias iqro-upload` (пароль вводит владелец) |

Установки из Google Play подписаны ключом Play App Signing, поэтому без первого клиента
вход в магазинной сборке не заработает. Второй нужен для сборок, которые ставятся мимо
Play (APK, подписанный ключом загрузки).

Временный клиент для проверки отладочной сборки (создаётся только по слову владельца
и удаляется после проверки): пакет `forum.iqro.app`, SHA-1 отладочного ключа этого Mac
`C3:B7:A8:89:74:24:C5:06:04:F3:F3:79:5C:98:BE:5B:F5:D0:31:A3`.

## Что прописать на проде

В `services/backend/.env.production` (передаётся в backend через `env_file`):

```
QURAN_GOOGLE_WEB_CLIENT_ID=<Client ID из шага 2>
QURAN_GOOGLE_ANDROID_CLIENT_IDS=<Client ID Play>,<Client ID upload>
```

`QURAN_GOOGLE_WEB_CLIENT_ID` включает функцию. Android-клиенты попадают в список
допустимых `aud`; токены Credential Manager обычно приходят с `aud` = Web client ID, но
так вход не сломается, если Google выдаст токен прямо на Android-клиент.

Необязательные лимиты (по умолчанию):

```
QURAN_GOOGLE_SIGN_IN_IDENTITY_RATE=20/hour
QURAN_GOOGLE_SIGN_IN_IP_BURST_RATE=300/hour
```

После правки env перезапустите backend (`make production-up` с TLS-оверлеем, как при
обычном выкладывании) и проверьте:

```
curl -s https://iqro.forum/api/v1/auth/google/config
```

Ответ `{"enabled":true,"client_id":"…"}` — кнопка появится на сайте и в приложении.

## Безопасность и CSP

- Сайт загружает `https://accounts.google.com/gsi/client` только на странице входа и только
  при включённой функции. CSP (Next.js и шлюз nginx) разрешает скрипт `…/gsi/client`, стиль
  `…/gsi/style` и фрейм `https://accounts.google.com/gsi/`.
- `Cross-Origin-Opener-Policy: same-origin-allow-popups`: в браузерах без FedCM кнопка
  Google открывает всплывающее окно, которому нужен `window.opener`.
- Ключи Google кэшируются; неизвестный `kid` перечитывает их не чаще раза в минуту.
- Имя и аватар из токена не сохраняются: в базе остаются почта, отметка о подтверждении и
  идентификатор аккаунта Google (`AuthIdentity` с `provider=google`).
