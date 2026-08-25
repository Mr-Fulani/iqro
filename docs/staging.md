# Staging: создание с нуля и первый запуск

Дата проверки инструкции: 25 августа 2026 года.

Staging — отдельная публичная копия приложения для проверки реального HTTPS, интеграций,
миграций, SEO, мониторинга и нагрузки до production. Она не использует production-БД,
production-секреты или production-bucket.

Фактический бюджетный staging проекта создан: `https://staging.iqro.forum` работает на Hetzner
CX23 через budget overlay, TLS и запрет индексации активны, отдельный Cloudflare R2 bucket
настроен, backup/verify/restore-check выполнен. Последний зафиксированный pre-publication
capacity результат находится в
[отчёте CX23](capacity/staging-cx23-prepublication-2026-08-25.md).

Среда ещё не является production: R2 custom media domain и согласованный media/Quran corpus не
активированы, offsite backup и постоянный production-sized observability stack не закрыты.
Инструкция ниже остаётся источником истины для пересоздания staging и последующего production
rollout; секреты и IP-ограничения в документацию не записываются.

## Что уже автоматизировано

- `compose.staging.yaml` добавляет к production topology автоматический HTTPS через Caddy и
  тестовую почту Mailpit;
- `ops/staging/init.py` создаёт отдельный env, генерирует независимые секреты и ставит права
  `0600`; существующий файл он не перезаписывает;
- `ops/staging/preflight.py` проверяет домены, proxy chain, разделение БД, HTTPS, секреты и
  готовность media, не печатая значения секретов;
- `ops/staging/configure_media.py` безопасно записывает R2 credentials и генерирует точную CORS
  policy для staging origins;
- Caddy выпускает и продлевает TLS certificate, делает HTTP → HTTPS redirect и запрещает
  индексирование staging через `X-Robots-Tag` и отдельный `robots.txt`;
- Mailpit перехватывает email-коды внутри staging. Его web UI слушает только `127.0.0.1` VPS;
- все ежедневные команды доступны как `make staging-*`.

```mermaid
flowchart LR
    U[Web / Mobile / Telegram Mini App] -->|HTTPS API/HTML| C[Caddy :443]
    C --> G[Nginx gateway]
    G --> W[Next.js web]
    G --> A[Django API]
    A --> P[(PostgreSQL)]
    A --> R[(Redis)]
    A --> Q[Celery worker / Beat]
    A --> M[Mailpit test email]
    U -->|audio/image bytes| D[Cloudflare R2 custom domain / CDN]
    A -. metadata and upload API .-> D
```

Главное следствие схемы: аудиобайты не проходят через VPS или Django. Увеличение числа
чтецов/качества увеличивает storage/CDN usage, но не требует заранее покупать media-серверы.

## 1. Что нужно создать вручную

### 1.1. Два имени

Пример для домена `example.org`:

- приложение: `staging.example.org`;
- media/CDN: `media.staging.example.org`.

Первое имя будет указывать на VPS. Второе позже подключается прямо к R2 bucket и **не** должно
указывать на VPS.

### 1.2. VPS

Стандартный staging-профиль рассчитан на:

- 4 vCPU;
- 8 GiB RAM;
- 80 GiB SSD;
- Ubuntu 24.04/26.04 LTS x86_64;
- публичный IPv4 и SSH key.

Это стартовая конфигурация, а не доказанная ёмкость. Для capacity/soak окна с полным
Prometheus/Grafana baseline разумно временно увеличить VPS до 8 vCPU/16 GiB, провести замер и
вернуть меньший размер. Так постоянная мощность покупается по текущей потребности, а не под
100 000 DAU заранее.

Для бюджетного функционального staging разрешён профиль 2 vCPU / 4 GiB RAM / 40 GiB SSD
(например Hetzner CX23), но только через `compose.staging.budget.yaml`. Он запускает по одному
API/Celery worker, уменьшает memory/CPU ceilings, собирает образы последовательно и не включает
постоянный observability stack. Такой сервер проверяет продуктовые сценарии, HTTPS, R2 и smoke,
но его результаты нельзя объявлять capacity-гарантией будущего более мощного production.

В firewall провайдера открыть:

| Порт | Источник | Назначение |
|---:|---|---|
| `22/tcp` | только ваш текущий IP | SSH |
| `80/tcp` | internet | ACME и HTTP → HTTPS |
| `443/tcp`, `443/udp` | internet | HTTPS/HTTP3 |

PostgreSQL, Redis, backend, Mailpit, Grafana и Prometheus наружу не открывать. Docker может
обходить некоторые правила UFW, поэтому основную границу лучше задать firewall самого VPS
provider; это отдельно отмечено и в официальной
[Docker Ubuntu installation guide](https://docs.docker.com/engine/install/ubuntu/).

### 1.3. DNS приложения

Создать запись:

```text
Type: A
Name: staging
Value: <PUBLIC_VPS_IP>
TTL: Auto
Proxy: DNS only на время первого запуска
```

Проверка с локального компьютера:

```bash
dig +short staging.example.org
```

Команда должна вернуть IP нового VPS. Запись media пока не создаётся вручную: её добавит
подключение R2 custom domain.

## 2. Установка Docker на пустой VPS

Подключиться по SSH и установить Docker Engine/Compose из официального apt repository. Актуальный
источник команд — [Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/):

```bash
sudo apt update
sudo apt install -y ca-certificates curl git
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"
```

Переподключиться по SSH, затем проверить:

```bash
docker version
docker compose version
```

Членство в группе `docker` фактически даёт административный доступ к host. На staging оно
выдаётся только отдельному deploy-пользователю с SSH key.

На 4 GiB host один раз добавьте 2 GiB swap только как защиту от краткого пика во время сборки:

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h
```

Swap не заменяет RAM и не используется для доказательства capacity; его задача — не допустить
OOM во время первой последовательной Docker-сборки.

## 3. Доставка текущего commit на сервер

Сейчас у проекта нет Git remote, поэтому безопасный первый вариант — передать только tracked
файлы текущего commit, без локальных env и незакоммиченных файлов.

На VPS один раз:

```bash
sudo mkdir -p /opt/quran
sudo chown "$USER":"$USER" /opt/quran
```

На локальном компьютере из корня проекта:

```bash
git archive --format=tar HEAD | ssh <USER>@<PUBLIC_VPS_IP> 'tar -xf - -C /opt/quran'
```

После добавления private Git remote сервер лучше перевести на checkout конкретного release
commit/tag. Не копируйте на VPS локальные `.env`, `.git` или development database.

## 4. Создание staging-конфигурации

На VPS:

```bash
cd /opt/quran
make staging-init \
  STAGING_HOST=staging.example.org \
  STAGING_MEDIA_HOST=media.staging.example.org \
  STAGING_ACME_EMAIL=ops@example.org
```

Команда создаёт игнорируемый Git файл `ops/staging/staging.env`, генерирует все application
secrets и ничего секретного не выводит. Повторный запуск не перезапишет существующий файл.

Проверить базовую готовность:

```bash
make staging-preflight
make staging-budget-config  # 2 vCPU / 4 GiB
# make staging-config       # стандартный 4 vCPU / 8 GiB профиль
```

До настройки R2 первая команда покажет `WARN`. Это сознательно разрешает поднять текст/API и
HTTPS раньше, но не разрешает публиковать media или считать audio capacity проверенной.

## 5. Первый запуск сайта и API

Убедиться, что DNS уже возвращает IP VPS, затем:

```bash
make staging-budget-up
make staging-budget-ps
```

Caddy обратится к ACME CA, получит certificate для `STAGING_HOST` и будет автоматически его
продлевать. Для автоматического HTTPS публичные `80` и `443` должны быть доступны; это требование
описано в [Caddy HTTPS quick-start](https://caddyserver.com/docs/quick-starts/https).

Проверка:

```bash
curl -I http://staging.example.org/
curl -I https://staging.example.org/
curl https://staging.example.org/api/v1/health/ready
curl https://staging.example.org/robots.txt
```

Ожидается redirect на HTTPS, успешный HTTPS-ответ, ready health и `Disallow: /` для robots.

Если запуск не прошёл:

```bash
make staging-budget-ps
make staging-budget-logs
```

### Тестовые email-коды

Mailpit не опубликован в internet. Открыть SSH tunnel на локальном компьютере:

```bash
ssh -L 8025:127.0.0.1:8025 <USER>@<PUBLIC_VPS_IP>
```

Пока SSH открыт, UI доступен только вам на `http://127.0.0.1:8025`. Коды входа staging
появляются там и не отправляются реальным адресатам.

## 6. Подключение Cloudflare R2 для изображений и аудио

Этот этап обязателен до media publication и audio capacity test, но не до первого HTTPS smoke.

В Cloudflare dashboard:

1. Создать отдельный bucket, например `quran-staging`.
2. Создать R2 API token с Object Read & Write только для этого bucket.
3. Сохранить `Account ID`, `Access Key ID` и `Secret Access Key`; secret показывается один раз.
4. В bucket → Settings → Custom Domains подключить `media.staging.example.org` и дождаться
   статуса `Active`. Cloudflare требует, чтобы domain zone находилась в том же account; custom
   domain включает CDN/cache controls. `r2.dev` для этой среды не нужен. См.
   [официальную инструкцию public bucket/custom domain](https://developers.cloudflare.com/r2/buckets/public-buckets/).

На VPS безопасно записать credentials (они не попадут в shell history или stdout):

```bash
make staging-media-configure \
  STAGING_R2_ACCOUNT_ID=<32_HEX_ACCOUNT_ID> \
  STAGING_R2_BUCKET=quran-staging
```

Команда запросит Access Key ID и Secret Access Key скрытым вводом, обновит `staging.env` и
создаст `ops/staging/r2-cors.json`. Содержимое JSON не секретно. Его нужно вставить в
bucket → Settings → CORS Policy → JSON и сохранить. Policy разрешает только точные staging
origins, `GET`/`HEAD`, Range и нужные плееру response headers. Формат соответствует
[Cloudflare R2 CORS guide](https://developers.cloudflare.com/r2/buckets/cors/).

После активации domain/CORS:

```bash
make staging-media-preflight
make staging-up
```

Далее accepted/versioned assets загружаются immutable upload-командами из раздела
[Managed media CDN contract](operations.md#managed-media-cdn-contract), а публичный CDN contract
проверяется до активации релиза. Credential нельзя вставлять в браузер, mobile app, Telegram
Mini App, Git или issue tracker.

## 7. Monitoring, backup и нагрузка

Наблюдаемость включается только на время эксплуатационной проверки или load window:

```bash
make staging-observability-up
```

Не запускайте этот полный stack на бюджетном 4 GiB host одновременно с приложением: для него
используются health/metrics endpoints, `docker stats` и bounded JSON reports. Полный временной ряд
Prometheus/Grafana и финальный capacity run выполняются уже на production-sized машине.

Grafana/Prometheus/Alertmanager слушают loopback. Пример tunnel для Grafana:

```bash
ssh -L 3001:127.0.0.1:3001 <USER>@<PUBLIC_VPS_IP>
```

Затем открыть `http://127.0.0.1:3001`. После теста:

```bash
make staging-observability-down
```

До первого release window выполнить:

```bash
make staging-backup
make staging-backup-verify
make staging-restore-check
```

После этого по порядку запускаются public-read, audio-CDN и disposable auth/sync сценарии из
[operations runbook](operations.md#staged-public-read-capacity-test). Число стабильных
одновременных пользователей фиксируется только из JSON reports и server-side metrics реального
staging, не из DAU и не из лимитов Docker Compose.

## 8. Обновление и откат

Перед обновлением всегда сохранить проверенный backup:

```bash
make staging-backup
make staging-backup-verify
```

Передать новый проверенный commit тем же `git archive`, затем на VPS:

```bash
cd /opt/quran
make staging-budget-config
make staging-budget-up
make staging-budget-ps
```

`staging.env`, PostgreSQL/Redis volumes, Caddy certificates и backup directory не входят в Git
archive и сохраняются. `make` автоматически маркирует staging images коротким SHA текущего
commit. Для воспроизводимого отката нужно хранить номер ранее развёрнутого commit и развернуть
его archive тем же способом; migration compatibility проверяется до rollout.

### Временная проверка нескольких реплик на budget staging

Это бесплатная проверка механизма горизонтального масштабирования на том же VPS, а не новый
capacity-профиль и не high availability. Сначала должны быть собраны и запущены проверенные
release images. Команда валидирует границы, подставляет реальное число API-реплик в database
connection budget и только затем меняет topology без сборки образов:

```bash
cd /opt/quran
make staging-budget-scale API_REPLICAS=2 WEB_REPLICAS=2
make staging-budget-ps
python3 ops/load/smoke.py \
  --base-url https://staging.example.org \
  --requests 200 \
  --concurrency 10
```

Во время окна проверить, что видны ровно две healthy `backend` и две healthy `web` реплики,
gateway распределяет некэшируемые probe-запросы между обоими backend, а 5xx, p95, host RAM,
swap и database headroom остаются в пределах gate. На CX23 не оставлять `2+2` постоянно без
измеренной необходимости: после доказательства вернуть экономный профиль той же безопасной
командой:

```bash
make staging-budget-scale API_REPLICAS=1 WEB_REPLICAS=1
make staging-budget-ps
```

Потеря единственного VPS по-прежнему остановит все реплики. Настоящая HA начинается только с
нескольких hosts/зон и внешнего load balancer.

## 9. Definition of done

Staging считается созданным, когда одновременно выполнено:

- `https://STAGING_HOST` и readiness отвечают извне;
- HTTP перенаправляется на HTTPS, certificate валиден, staging закрыт от индексации;
- `make staging-preflight` и `make staging-config` зелёные;
- email login проверен через закрытый Mailpit UI;
- отдельный R2 bucket/custom domain/CORS активны и `make staging-media-preflight` зелёный;
- на стандартном профиле Grafana доступна через SSH tunnel и alert delivery проверена; на
  budget-профиле сохранены health/metrics/load reports, а полный observability gate остаётся
  открытым до production-sized среды;
- backup → verify → restore-check выполнены;
- integration E2E и три capacity harness дали сохранённые reports.

До выполнения этих пунктов roadmap checkbox «production-like staging deployed» остаётся открыт.
