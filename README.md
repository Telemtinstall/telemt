# Telemt Docker Image Builder

This directory builds a local Telemt Docker image from official upstream release artifacts and includes a Docker-based Telemt server installer.

The image is not published unless `PUSH=1` is explicitly set.

Latest repository changes are tracked in [CHANGELOG.md](CHANGELOG.md).

## RU

### Быстрый выбор

```text
build.sh                  Собрать Docker image Telemt.
install_docker-telemt.sh  Установить сервер: nginx + certbot + Docker Telemt + маскировка.
compose.example.yml       Пример hardened compose для ручной интеграции.
```

### Что делает

`Dockerfile` скачивает официальный Telemt release asset из `telemt/telemt`, скачивает рядом `.sha256`, проверяет checksum и кладет бинарник в минимальный image.

По умолчанию собирается `prod` image:

- base: `gcr.io/distroless/static-debian12:nonroot`;
- process user: non-root;
- config path: `/etc/telemt/telemt.toml`;
- healthcheck: `telemt healthcheck /etc/telemt/telemt.toml --mode liveness`;
- no shell, no package manager in final image.

Также есть `debug` target на `debian:12-slim` с `curl`, `iproute2`, `busybox`.

### Локальная сборка

```bash
chmod +x ./build.sh
./build.sh
```

Для production лучше указывать точный release tag:

```bash
TELEMT_VERSION=<version> ./build.sh
```

Собрать debug image:

```bash
TARGET=debug ./build.sh
```

Проверить версию:

```bash
docker run --rm --entrypoint /app/telemt telemt-local:latest --version
```

### Установка сервера

`install_docker-telemt.sh` ставит полный серверный слой вокруг Docker image:

- архитектура `TLS-Fronting + TCP-Splitting` только для вашего домена;
- nginx HTTP -> HTTPS redirect;
- nginx SNI stream на внешнем `443/tcp`;
- HTTPS mask site на `127.0.0.1:8443`;
- Telemt в Docker на `127.0.0.1:1443`;
- Telemt API только на `127.0.0.1:9091`;
- Telemt metrics только на `127.0.0.1:9090`;
- Let's Encrypt сертификат и `certbot.timer`;
- выбор маскировочной страницы: красивая заглушка или пустой HTML;
- Docker hardening и healthcheck с отдельным вопросом;
- отключение runtime-логов по умолчанию;
- опционально `ad_tag`, `middle_proxy`, high-load tuning.

В этой схеме обычный сканер или браузер без MTProxy-ключа получает HTTPS-сайт-заглушку с настоящим сертификатом вашего домена. Telemt не подменяет TLS и не делает MITM: он оставляет валидных MTProxy-клиентов внутри Telemt, а остальные TLS-соединения передаёт на mask site как TCP-поток.

Перед запуском нужен чистый Debian/Ubuntu сервер, A-запись домена на IPv4 сервера и свободные `80/tcp`, `443/tcp`.

Обычный запуск:

```bash
chmod +x ./install_docker-telemt.sh
./install_docker-telemt.sh
```

Русский интерфейс установщика:

```bash
./install_docker-telemt.sh -lang ru
```

На чистом VPS обычно вход выполняется сразу под `root`, поэтому `sudo` не нужен и может быть не установлен. Если вы запускаете не под `root`, используйте:

```bash
if [ "$(id -u)" -eq 0 ]; then
  ./install_docker-telemt.sh -lang ru
elif command -v sudo >/dev/null 2>&1; then
  sudo ./install_docker-telemt.sh -lang ru
else
  su -c "./install_docker-telemt.sh -lang ru"
fi
```

Если `telemt-local:<tag>` ещё не собран, установщик сам запустит `build.sh` из этого же каталога. Отдельно запускать `build.sh` перед установкой больше не обязательно.

Если image находится в registry:

```bash
TELEMT_IMAGE=ghcr.io/Telemtinstall/telemt:latest ./install_docker-telemt.sh
```

Скрипт спросит:

```text
Proxy domain
Let's Encrypt email
Telemt Docker image
Mask site page: fancy or empty
Telemt user name
Max Telemt connections
MTProxy ad_tag, Enter = skip
Use Telegram middle proxy
Enable nginx/Docker access logs
Enable Docker hardening and healthcheck
Enable high-load tuning for many clients
```

В конце установки скрипт выполняет active probing проверку на вашем домене:

```bash
openssl s_client -connect <server_ipv4>:443 -servername <domain>
curl -I --resolve <domain>:443:<server_ipv4> https://<domain>/
```

Результат сохраняется в `/root/telemt-active-probing-check.txt`. Если обычный HTTPS-запрос через IP сервера не получает корректный ответ, установка останавливается с ошибкой, потому что маскировочный слой работает неправильно.

По умолчанию используется красивая заглушка. Если выбрать `empty`, nginx будет отдавать пустой `index.html` с `200 OK`, без видимого текста. Логи доступа выключены. Docker hardening включен по умолчанию, но его можно отключить. High-load tuning выключен и применяется только после отдельного подтверждения.

Если Docker hardening включен, compose добавляет:

```text
read_only root filesystem
cap_drop: ALL
no-new-privileges
tmpfs for /tmp
pids/memory/cpu limits
Docker healthcheck
```

Если Docker hardening отключен, контейнер запускается проще: без `read_only`, `cap_drop`, `no-new-privileges`, `tmpfs` и без compose healthcheck.

### Публикация

По умолчанию публикации нет. Чтобы отправить image в registry, нужно явно включить `PUSH=1`:

```bash
IMAGE=ghcr.io/Telemtinstall/telemt PUSH=1 ./build.sh
```

Перед публикацией нужно быть залогиненным:

```bash
docker login ghcr.io
```

### Переменные

```text
TELEMT_REPOSITORY  GitHub repo с release assets. Default: telemt/telemt
TELEMT_VERSION     Release tag или latest. Default: latest
IMAGE              Имя image. Default: telemt-local
AUTO_BUILD_IMAGE   yes автоматически собирает image, если его нет. Default: yes
MASK_SITE_MODE     fancy или empty. Default: fancy
TARGET             prod или debug. Default: prod
PLATFORM           linux/amd64 или linux/arm64, опционально
NO_CACHE           1 отключает build cache
PUSH               1 публикует image, по умолчанию 0
```

### Compose пример

`compose.example.yml` показывает hardened-запуск:

- `network_mode: host`;
- config монтируется read-only;
- Docker logs отключены;
- root filesystem read-only;
- `cap_drop: ALL`;
- `no-new-privileges`;
- `ulimits.nofile` поднят до `65536/262144`.

## EN

### Quick Choice

```text
build.sh                  Build the Telemt Docker image.
install_docker-telemt.sh  Install server: nginx + certbot + Docker Telemt + masking.
compose.example.yml       Hardened compose example for manual integration.
```

### What It Does

`Dockerfile` downloads the official Telemt release asset from `telemt/telemt`, downloads the matching `.sha256`, verifies the checksum, and copies the binary into a minimal runtime image.

Default target is `prod`:

- base: `gcr.io/distroless/static-debian12:nonroot`;
- process user: non-root;
- config path: `/etc/telemt/telemt.toml`;
- healthcheck: `telemt healthcheck /etc/telemt/telemt.toml --mode liveness`;
- no shell or package manager in the final image.

There is also a `debug` target based on `debian:12-slim` with `curl`, `iproute2`, and `busybox`.

### Local Build

```bash
chmod +x ./build.sh
./build.sh
```

For production, use an exact release tag:

```bash
TELEMT_VERSION=<version> ./build.sh
```

Build the debug image:

```bash
TARGET=debug ./build.sh
```

Check version:

```bash
docker run --rm --entrypoint /app/telemt telemt-local:latest --version
```

### Server Install

`install_docker-telemt.sh` installs the full server layer around the Docker image:

- `TLS-Fronting + TCP-Splitting` architecture for your own domain only;
- nginx HTTP -> HTTPS redirect;
- nginx SNI stream on public `443/tcp`;
- HTTPS mask site on `127.0.0.1:8443`;
- Telemt in Docker on `127.0.0.1:1443`;
- Telemt API only on `127.0.0.1:9091`;
- Telemt metrics only on `127.0.0.1:9090`;
- Let's Encrypt certificate and `certbot.timer`;
- mask page choice: playful placeholder or empty HTML;
- Docker hardening and healthcheck with a dedicated prompt;
- runtime logs disabled by default;
- optional `ad_tag`, `middle_proxy`, and high-load tuning.

In this architecture, a normal scanner or browser without the MTProxy key receives the HTTPS mask site with a real certificate for your domain. Telemt does not replace TLS and does not perform MITM: valid MTProxy clients stay inside Telemt, while other TLS connections are relayed to the mask site as a TCP stream.

Before running, use a clean Debian/Ubuntu server, create a DNS A record pointing to the server IPv4, and keep `80/tcp` and `443/tcp` free.

Normal run:

```bash
chmod +x ./install_docker-telemt.sh
./install_docker-telemt.sh
```

Russian installer UI:

```bash
./install_docker-telemt.sh -lang ru
```

On a clean VPS you usually log in as `root`, so `sudo` is not needed and may not be installed. If you are not root, use:

```bash
if [ "$(id -u)" -eq 0 ]; then
  ./install_docker-telemt.sh -lang ru
elif command -v sudo >/dev/null 2>&1; then
  sudo ./install_docker-telemt.sh -lang ru
else
  su -c "./install_docker-telemt.sh -lang ru"
fi
```

If `telemt-local:<tag>` is not built yet, the installer runs `build.sh` from the same directory automatically. Running `build.sh` before the installer is no longer required.

If the image is in a registry:

```bash
TELEMT_IMAGE=ghcr.io/Telemtinstall/telemt:latest ./install_docker-telemt.sh
```

The script asks:

```text
Proxy domain
Let's Encrypt email
Telemt Docker image
Mask site page: fancy or empty
Telemt user name
Max Telemt connections
MTProxy ad_tag, Enter = skip
Use Telegram middle proxy
Enable nginx/Docker access logs
Enable Docker hardening and healthcheck
Enable high-load tuning for many clients
```

At the end of the install, the script runs an active probing check against your own domain:

```bash
openssl s_client -connect <server_ipv4>:443 -servername <domain>
curl -I --resolve <domain>:443:<server_ipv4> https://<domain>/
```

The result is saved to `/root/telemt-active-probing-check.txt`. If a normal HTTPS request through the server IP does not return a valid response, the installer stops with an error because the masking layer is not working correctly.

The playful placeholder is used by default. If `empty` is selected, nginx serves an empty `index.html` with `200 OK` and no visible text. Access logs are disabled by default. Docker hardening is enabled by default, but can be disabled. High-load tuning is disabled and is applied only after explicit confirmation.

When Docker hardening is enabled, compose adds:

```text
read_only root filesystem
cap_drop: ALL
no-new-privileges
tmpfs for /tmp
pids/memory/cpu limits
Docker healthcheck
```

When Docker hardening is disabled, the container runs in a simpler mode without `read_only`, `cap_drop`, `no-new-privileges`, `tmpfs`, and compose healthcheck.

### Publishing

Publishing is disabled by default. To push an image to a registry, set `PUSH=1` explicitly:

```bash
IMAGE=ghcr.io/Telemtinstall/telemt PUSH=1 ./build.sh
```

Log in first:

```bash
docker login ghcr.io
```

### Variables

```text
TELEMT_REPOSITORY  GitHub repo with release assets. Default: telemt/telemt
TELEMT_VERSION     Release tag or latest. Default: latest
IMAGE              Image name. Default: telemt-local
AUTO_BUILD_IMAGE   yes builds the image automatically when missing. Default: yes
MASK_SITE_MODE     fancy or empty. Default: fancy
TARGET             prod or debug. Default: prod
PLATFORM           linux/amd64 or linux/arm64, optional
NO_CACHE           1 disables build cache
PUSH               1 publishes the image, default is 0
```

### Compose Example

`compose.example.yml` shows a hardened runtime:

- `network_mode: host`;
- config mounted read-only;
- Docker logs disabled;
- read-only root filesystem;
- `cap_drop: ALL`;
- `no-new-privileges`;
- `ulimits.nofile` raised to `65536/262144`.

## Source

Based on the official Telemt Docker approach:

- https://github.com/telemt/telemt
- https://github.com/telemt/telemt/blob/main/Dockerfile
