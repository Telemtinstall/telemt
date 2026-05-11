#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_VERSION="2026-05-06"
INSTALL_DIR="${INSTALL_DIR:-/opt/telemt-docker}"
STATE_FILE="${STATE_FILE:-/root/.install_docker_telemt.state}"
SAVED_CONFIG="${SAVED_CONFIG:-/root/.install_docker_telemt.config}"
SECRET_FILE="${SECRET_FILE:-$INSTALL_DIR/telemt-secret.env}"

DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
TELEMT_IMAGE="${TELEMT_IMAGE:-telemt-local:latest}"
TELEMT_VERSION="${TELEMT_VERSION:-latest}"
TELEMT_USER="${TELEMT_USER:-default}"
TELEMT_MAX_TCP_CONNS="${TELEMT_MAX_TCP_CONNS:-1000}"
AD_TAG="${AD_TAG:-}"
USE_MIDDLE_PROXY="${USE_MIDDLE_PROXY:-}"
ENABLE_LOGS="${ENABLE_LOGS:-no}"
ENABLE_DOCKER_HARDENING="${ENABLE_DOCKER_HARDENING:-yes}"
ENABLE_HIGH_LOAD_TUNING="${ENABLE_HIGH_LOAD_TUNING:-no}"
AUTO_BUILD_IMAGE="${AUTO_BUILD_IMAGE:-yes}"
MASK_SITE_MODE="${MASK_SITE_MODE:-fancy}"
SCRIPT_LANG="${SCRIPT_LANG:-en}"
ASSUME_YES="${ASSUME_YES:-0}"

PUBLIC_IP=""
SCRIPT_LANG_FROM_CLI="0"

say() {
  printf '%s\n' "$*"
}

die() {
  if [ "${SCRIPT_LANG:-en}" = "ru" ]; then
    printf 'ОШИБКА: %s\n' "$*" >&2
  else
    printf 'ERROR: %s\n' "$*" >&2
  fi
  exit 1
}

is_ru() {
  [ "${SCRIPT_LANG:-en}" = "ru" ]
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

normalize_script_lang() {
  case "$(lower "$1")" in
    ru|rus|russian|рус|русский) printf 'ru' ;;
    en|eng|english|'') printf 'en' ;;
    *) return 1 ;;
  esac
}

usage() {
  if is_ru; then
    cat <<'EOF'
Использование:
  ./install_docker-telemt.sh [-lang ru|en]

Примеры:
  ./install_docker-telemt.sh
  ./install_docker-telemt.sh -lang ru
  ./install_docker-telemt.sh --lang en

Опции:
  -lang, --lang   Язык интерфейса установщика: en или ru.
  -h, --help      Показать эту справку.
EOF
    return 0
  fi

  cat <<'EOF'
Usage:
  ./install_docker-telemt.sh [-lang ru|en]

Examples:
  ./install_docker-telemt.sh
  ./install_docker-telemt.sh -lang ru
  ./install_docker-telemt.sh --lang en

Options:
  -lang, --lang   Installer interface language: en or ru.
  -h, --help      Show this help.
EOF
}

parse_args() {
  local value
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -lang|--lang)
        shift
        [ "$#" -gt 0 ] || die "Missing value for -lang. Use ru or en."
        value="$1"
        SCRIPT_LANG="$(normalize_script_lang "$value")" || die "Bad language: $value. Use ru or en."
        SCRIPT_LANG_FROM_CLI="1"
        ;;
      -lang=*|--lang=*)
        value="${1#*=}"
        SCRIPT_LANG="$(normalize_script_lang "$value")" || die "Bad language: $value. Use ru or en."
        SCRIPT_LANG_FROM_CLI="1"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
    shift
  done
}

have() {
  command -v "$1" >/dev/null 2>&1
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    if is_ru; then
      die "Запустите от root."
    else
      die "Run as root."
    fi
  fi
}

normalize_yes_no() {
  case "$(lower "$1")" in
    y|yes|д|да|true|1) printf 'yes' ;;
    n|no|н|нет|false|0|'') printf 'no' ;;
    *) return 1 ;;
  esac
}

ask_default() {
  local var="$1"
  local prompt="$2"
  local default="$3"
  local value
  if [ -n "${!var:-}" ]; then
    default="${!var}"
  fi
  if [ "$ASSUME_YES" = "1" ]; then
    printf -v "$var" '%s' "$default"
    return 0
  fi
  if [ -n "$default" ]; then
    read -r -p "$prompt [$default]: " value
    value="${value:-$default}"
  else
    read -r -p "$prompt: " value
  fi
  printf -v "$var" '%s' "$value"
}

ask_yes_no() {
  local var="$1"
  local prompt="$2"
  local default="$3"
  local value normalized
  if [ "$ASSUME_YES" = "1" ]; then
    if normalized="$(normalize_yes_no "$default")"; then
      printf -v "$var" '%s' "$normalized"
      return 0
    fi
  fi
  while true; do
    if is_ru; then
      read -r -p "$prompt yes/no/да/нет [$default]: " value
    else
      read -r -p "$prompt yes/no [$default]: " value
    fi
    value="${value:-$default}"
    if normalized="$(normalize_yes_no "$value")"; then
      printf -v "$var" '%s' "$normalized"
      return 0
    fi
    if is_ru; then
      say "Ответьте yes/no или да/нет."
    else
      say "Please answer yes or no."
    fi
  done
}

normalize_mask_site_mode() {
  case "$(lower "$1")" in
    fancy|pretty|beautiful|красивую|красивая|красиво|yes|y|да|д) printf 'fancy' ;;
    empty|blank|пустую|пустая|пусто|no|n|нет|н) printf 'empty' ;;
    *) return 1 ;;
  esac
}

ask_mask_site_mode() {
  local value normalized
  if [ "$ASSUME_YES" = "1" ]; then
    MASK_SITE_MODE="$(normalize_mask_site_mode "$MASK_SITE_MODE")"
    return 0
  fi
  while true; do
    if is_ru; then
      read -r -p "Маскировочная страница: fancy=красивая или empty=пустая [$MASK_SITE_MODE]: " value
    else
      read -r -p "Mask site page: fancy or empty [$MASK_SITE_MODE]: " value
    fi
    value="${value:-$MASK_SITE_MODE}"
    if normalized="$(normalize_mask_site_mode "$value")"; then
      MASK_SITE_MODE="$normalized"
      return 0
    fi
    if is_ru; then
      say "Ответьте fancy или empty."
    else
      say "Please answer fancy or empty."
    fi
  done
}

validate_inputs() {
  [[ "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]] || die "Bad domain: $DOMAIN"
  [[ "$EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || die "Bad email: $EMAIL"
  [[ "$TELEMT_USER" =~ ^[A-Za-z0-9_.-]{1,64}$ ]] || die "Bad Telemt user name: $TELEMT_USER"
  [[ "$TELEMT_MAX_TCP_CONNS" =~ ^[0-9]+$ ]] || die "Bad connection limit: $TELEMT_MAX_TCP_CONNS"
  [[ "$TELEMT_IMAGE" =~ ^[A-Za-z0-9._/:@+-]+$ ]] || die "Bad Docker image: $TELEMT_IMAGE"
  [[ "$TELEMT_VERSION" =~ ^[A-Za-z0-9._/@:+-]+$ ]] || die "Bad Telemt version: $TELEMT_VERSION"
  if [ -n "$AD_TAG" ]; then
    [[ "$AD_TAG" =~ ^[A-Fa-f0-9]{32}$ ]] || die "ad_tag must be 32 hex chars."
  fi
  normalize_yes_no "$USE_MIDDLE_PROXY" >/dev/null || die "Bad USE_MIDDLE_PROXY"
  normalize_yes_no "$ENABLE_LOGS" >/dev/null || die "Bad ENABLE_LOGS"
  normalize_yes_no "$ENABLE_DOCKER_HARDENING" >/dev/null || die "Bad ENABLE_DOCKER_HARDENING"
  normalize_yes_no "$ENABLE_HIGH_LOAD_TUNING" >/dev/null || die "Bad ENABLE_HIGH_LOAD_TUNING"
  normalize_yes_no "$AUTO_BUILD_IMAGE" >/dev/null || die "Bad AUTO_BUILD_IMAGE"
  normalize_mask_site_mode "$MASK_SITE_MODE" >/dev/null || die "Bad MASK_SITE_MODE"
  normalize_script_lang "$SCRIPT_LANG" >/dev/null || die "Bad SCRIPT_LANG"
  USE_MIDDLE_PROXY="$(normalize_yes_no "$USE_MIDDLE_PROXY")"
  ENABLE_LOGS="$(normalize_yes_no "$ENABLE_LOGS")"
  ENABLE_DOCKER_HARDENING="$(normalize_yes_no "$ENABLE_DOCKER_HARDENING")"
  ENABLE_HIGH_LOAD_TUNING="$(normalize_yes_no "$ENABLE_HIGH_LOAD_TUNING")"
  AUTO_BUILD_IMAGE="$(normalize_yes_no "$AUTO_BUILD_IMAGE")"
  MASK_SITE_MODE="$(normalize_mask_site_mode "$MASK_SITE_MODE")"
  SCRIPT_LANG="$(normalize_script_lang "$SCRIPT_LANG")"
}

save_config() {
  umask 077
  cat > "$SAVED_CONFIG" <<EOF
DOMAIN=$(printf '%q' "$DOMAIN")
EMAIL=$(printf '%q' "$EMAIL")
TELEMT_IMAGE=$(printf '%q' "$TELEMT_IMAGE")
TELEMT_VERSION=$(printf '%q' "$TELEMT_VERSION")
TELEMT_USER=$(printf '%q' "$TELEMT_USER")
TELEMT_MAX_TCP_CONNS=$(printf '%q' "$TELEMT_MAX_TCP_CONNS")
AD_TAG=$(printf '%q' "$AD_TAG")
USE_MIDDLE_PROXY=$(printf '%q' "$USE_MIDDLE_PROXY")
ENABLE_LOGS=$(printf '%q' "$ENABLE_LOGS")
ENABLE_DOCKER_HARDENING=$(printf '%q' "$ENABLE_DOCKER_HARDENING")
ENABLE_HIGH_LOAD_TUNING=$(printf '%q' "$ENABLE_HIGH_LOAD_TUNING")
AUTO_BUILD_IMAGE=$(printf '%q' "$AUTO_BUILD_IMAGE")
MASK_SITE_MODE=$(printf '%q' "$MASK_SITE_MODE")
SCRIPT_LANG=$(printf '%q' "$SCRIPT_LANG")
EOF
}

load_config_if_exists() {
  if [ -f "$SAVED_CONFIG" ]; then
    if is_ru; then
      say "Найден сохраненный конфиг: $SAVED_CONFIG"
    else
      say "Resume config found: $SAVED_CONFIG"
    fi
    # shellcheck disable=SC1090
    source "$SAVED_CONFIG"
  fi
}

step_done() {
  [ -f "$STATE_FILE" ] && grep -Fxq "$1" "$STATE_FILE"
}

mark_done() {
  install -d -m 0700 "$(dirname "$STATE_FILE")"
  touch "$STATE_FILE"
  grep -Fxq "$1" "$STATE_FILE" 2>/dev/null || printf '%s\n' "$1" >> "$STATE_FILE"
}

write_file_root() {
  local path="$1"
  local mode="$2"
  local owner="$3"
  install -d -m 0755 "$(dirname "$path")"
  cat > "$path"
  chown "$owner" "$path"
  chmod "$mode" "$path"
}

public_ipv4() {
  curl -4fsS --max-time 10 https://api.ipify.org 2>/dev/null ||
  curl -4fsS --max-time 10 https://ifconfig.me 2>/dev/null ||
  curl -4fsS --max-time 10 https://icanhazip.com 2>/dev/null | tr -d '[:space:]'
}

domain_ipv4s() {
  getent ahostsv4 "$1" 2>/dev/null | awk '{print $1}' | sort -u
}

port_listeners() {
  local port="$1"
  ss -H -ltnp 2>/dev/null | awk -v p=":$port" '$4 ~ p "$" {print}'
}

check_port_clean_or_nginx() {
  local port="$1"
  local listeners
  listeners="$(port_listeners "$port" || true)"
  [ -z "$listeners" ] && return 0
  if printf '%s\n' "$listeners" | grep -q 'nginx'; then
    return 0
  fi
  printf '%s\n' "$listeners"
  die "Port $port/tcp is already in use by a non-nginx process. Use a clean server or free the port first."
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif have docker-compose; then
    docker-compose "$@"
  else
    die "Docker Compose is not installed."
  fi
}

install_packages() {
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl openssl jq iproute2 nginx certbot docker.io

  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libnginx-mod-stream || true
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker-cli docker-buildx || true
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker-compose-plugin || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker-compose

  ensure_docker_available
  systemctl enable --now nginx || true
  systemctl enable --now certbot.timer 2>/dev/null || true
}

install_official_docker_packages() {
  local os_id os_codename docker_codename arch

  [ -r /etc/os-release ] || die "Cannot detect OS for Docker CLI fallback."
  # shellcheck disable=SC1091
  source /etc/os-release
  os_id="${ID:-}"
  os_codename="${VERSION_CODENAME:-}"

  case "$os_id" in
    debian|ubuntu) ;;
    *) die "Docker CLI is missing and automatic Docker CE fallback supports only Debian/Ubuntu." ;;
  esac

  if [ -z "$os_codename" ] && have lsb_release; then
    os_codename="$(lsb_release -cs)"
  fi
  [ -n "$os_codename" ] || die "Cannot detect Debian/Ubuntu codename for Docker CE fallback."

  docker_codename="$os_codename"
  if [ "$os_id" = "debian" ] && [ "$docker_codename" = "trixie" ]; then
    say "Docker CE repo for Debian trixie may be unavailable; using bookworm Docker repo for CLI fallback."
    docker_codename="bookworm"
  fi

  arch="$(dpkg --print-architecture)"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${os_id}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${os_id} ${docker_codename} stable
EOF
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

ensure_docker_available() {
  if have docker; then
    systemctl enable --now docker
    return 0
  fi

  say "Docker daemon package is installed, but Docker CLI is missing. Trying distro docker-cli package..."
  if have apt-get; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker-cli docker-buildx || true
  fi

  if ! have docker; then
    say "Docker CLI is still missing. Installing official Docker CE CLI packages..."
    install_official_docker_packages
  fi

  have docker || die "Docker CLI is still not available after installation."
  systemctl enable --now docker
  docker version >/dev/null
}

image_name_and_tag() {
  local image="$1"
  local last name tag

  if [[ "$image" == *@sha256:* ]]; then
    return 1
  fi

  last="${image##*/}"
  if [[ "$last" == *:* ]]; then
    name="${image%:*}"
    tag="${last##*:}"
  else
    name="$image"
    tag="$TELEMT_VERSION"
  fi

  [ -n "$tag" ] || tag="latest"
  printf '%s\n%s\n' "$name" "$tag"
}

build_local_image() {
  local script_dir build_script parsed image_name image_tag
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  build_script="${BUILD_SCRIPT:-$script_dir/build.sh}"

  [ -f "$build_script" ] || die "Cannot auto-build Docker image: build.sh is not found near install_docker-telemt.sh."
  chmod +x "$build_script"

  parsed="$(image_name_and_tag "$TELEMT_IMAGE")" || die "Cannot auto-build digest-pinned image: $TELEMT_IMAGE"
  image_name="$(printf '%s\n' "$parsed" | sed -n '1p')"
  image_tag="$(printf '%s\n' "$parsed" | sed -n '2p')"

  say "Building Telemt Docker image automatically:"
  say "  image:   ${image_name}:${image_tag}"
  say "  version: ${image_tag}"
  (
    cd "$(dirname "$build_script")"
    IMAGE="$image_name" TELEMT_VERSION="$image_tag" PUSH=0 "$build_script"
  )
}

check_docker_image() {
  say "Checking Docker image: $TELEMT_IMAGE"
  if docker image inspect "$TELEMT_IMAGE" >/dev/null 2>&1; then
    say "Docker image exists locally."
    return 0
  fi

  if [[ "$TELEMT_IMAGE" != telemt-local:* ]]; then
    say "Docker image is not local. Trying docker pull..."
    if docker pull "$TELEMT_IMAGE"; then
      return 0
    fi
  else
    say "Local image is not built yet."
  fi

  if [ "$AUTO_BUILD_IMAGE" = "yes" ]; then
    build_local_image
    docker image inspect "$TELEMT_IMAGE" >/dev/null 2>&1 && return 0
    die "Image build finished, but Docker cannot inspect $TELEMT_IMAGE."
  fi

  if docker image inspect "$TELEMT_IMAGE" >/dev/null 2>&1; then
    return 0
  fi

  cat >&2 <<EOF
ERROR: Cannot find or pull image: $TELEMT_IMAGE

Auto-build is disabled. Build the local image manually:
  cd docker-telemt
  TELEMT_VERSION=<version> ./build.sh

Or use a registry image:
  TELEMT_IMAGE=ghcr.io/Telemtinstall/telemt:<version> ./install_docker-telemt.sh
EOF
  exit 1
}

ensure_secret() {
  install -d -m 0700 "$INSTALL_DIR"
  if [ -f "$SECRET_FILE" ]; then
    # shellcheck disable=SC1090
    source "$SECRET_FILE"
  fi
  if [ -z "${TELEMT_SECRET:-}" ]; then
    TELEMT_SECRET="$(openssl rand -hex 16)"
  fi
  umask 077
  cat > "$SECRET_FILE" <<EOF
TELEMT_SECRET=$(printf '%q' "$TELEMT_SECRET")
EOF
  chmod 600 "$SECRET_FILE"
}

configure_high_load() {
  [ "$ENABLE_HIGH_LOAD_TUNING" = "yes" ] || return 0

  say "Writing /etc/sysctl.d/99-telemt-high-load.conf"
  {
    cat <<'EOF'
# Telemt high-load tuning.
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
fs.file-max = 2097152
EOF
    if [ -r /proc/sys/net/ipv4/tcp_available_congestion_control ] &&
       grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control; then
      cat <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    fi
  } > /etc/sysctl.d/99-telemt-high-load.conf

  chmod 0644 /etc/sysctl.d/99-telemt-high-load.conf
  sysctl --system
}

write_mask_site_http_only() {
  local install_started_at
  install_started_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  install -d -m 0755 "/var/www/$DOMAIN/.well-known/acme-challenge"

  if [ "$MASK_SITE_MODE" = "empty" ]; then
    : > "/var/www/$DOMAIN/index.html"
  else
    cat > "/var/www/$DOMAIN/index.html" <<EOF
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${DOMAIN}</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #202020;
      --panel: #f4f4f1;
      --text: #f7f7f5;
      --muted: #b9b9b4;
      --ink: #2a2a2a;
      --line: rgba(255,255,255,.13);
      --accent: #8fd3ff;
    }
    * { box-sizing: border-box; }
    html, body { min-height: 100%; margin: 0; }
    body {
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background:
        radial-gradient(circle at 78% 32%, rgba(143,211,255,.08), transparent 28%),
        linear-gradient(135deg, #242424 0%, var(--bg) 100%);
      color: var(--text);
      display: grid;
      place-items: center;
      padding: 40px 22px;
    }
    main {
      width: min(980px, 100%);
      display: grid;
      gap: 56px;
    }
    .domain {
      color: var(--muted);
      font-size: 15px;
      letter-spacing: .08em;
      text-transform: uppercase;
    }
    .hero {
      display: grid;
      grid-template-columns: minmax(0, 1fr) 260px;
      gap: 56px;
      align-items: center;
    }
    h1 {
      font-size: clamp(44px, 8vw, 86px);
      line-height: .92;
      margin: 0 0 20px;
      letter-spacing: 0;
      text-transform: uppercase;
    }
    p {
      color: var(--muted);
      line-height: 1.7;
      max-width: 680px;
      margin: 0;
      font-size: 18px;
    }
    .timer-label {
      margin: 34px 0 14px;
      color: var(--muted);
      font-size: 16px;
    }
    .timer {
      background: var(--panel);
      color: var(--ink);
      border-radius: 8px;
      padding: 28px 30px;
      display: grid;
      grid-template-columns: repeat(4, minmax(80px, 1fr));
      gap: 18px;
      width: min(650px, 100%);
      box-shadow: 0 24px 60px rgba(0,0,0,.26);
    }
    .num {
      display: block;
      font-size: clamp(34px, 6vw, 58px);
      font-weight: 300;
      line-height: 1;
      font-variant-numeric: tabular-nums;
    }
    .unit {
      display: block;
      margin-top: 10px;
      color: #676761;
      font-size: 11px;
      letter-spacing: .22em;
      text-transform: uppercase;
    }
    .machine {
      position: relative;
      width: 240px;
      height: 240px;
      border: 13px solid rgba(255,255,255,.22);
      border-radius: 50%;
    }
    .machine:before {
      content: "";
      position: absolute;
      inset: 42px;
      border: 13px solid rgba(255,255,255,.19);
      border-left-color: transparent;
      border-radius: 50%;
      animation: spin 14s linear infinite;
    }
    .machine:after {
      content: "";
      position: absolute;
      width: 170px;
      height: 92px;
      right: -54px;
      bottom: 8px;
      border: 13px solid rgba(255,255,255,.22);
      border-radius: 18px;
      background:
        linear-gradient(rgba(255,255,255,.22), rgba(255,255,255,.22)) 24px 24px / 118px 10px no-repeat,
        linear-gradient(rgba(255,255,255,.22), rgba(255,255,255,.22)) 24px 52px / 118px 10px no-repeat;
    }
    .contact {
      border-top: 1px solid var(--line);
      padding-top: 26px;
      color: var(--muted);
      display: flex;
      align-items: center;
      flex-wrap: wrap;
      gap: 12px;
    }
    .telemt-button {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-height: 40px;
      padding: 0 18px;
      border: 1px solid rgba(143,211,255,.5);
      border-radius: 8px;
      background: rgba(143,211,255,.12);
      color: var(--text);
      text-decoration: none;
      font-weight: 700;
      letter-spacing: .03em;
      text-transform: lowercase;
      transition: background .2s ease, border-color .2s ease;
    }
    .telemt-button:hover {
      background: rgba(143,211,255,.2);
      border-color: var(--accent);
    }
    @keyframes spin { to { transform: rotate(360deg); } }
    @media (max-width: 760px) {
      main { gap: 34px; }
      .hero { grid-template-columns: 1fr; gap: 28px; }
      .machine { display: none; }
      .timer { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    }
  </style>
</head>
<body>
  <main>
    <div class="domain">${DOMAIN}</div>
    <section class="hero" aria-label="Статус сайта">
      <div>
        <h1>Сайт уже работает</h1>
        <p>Страница держит свет включенным, пока система спокойно занимается своими делами.</p>
        <div class="timer-label">Работает с момента установки:</div>
        <div class="timer" aria-live="polite">
          <div><span class="num" id="days">0</span><span class="unit">дней</span></div>
          <div><span class="num" id="hours">00</span><span class="unit">часов</span></div>
          <div><span class="num" id="minutes">00</span><span class="unit">минут</span></div>
          <div><span class="num" id="seconds">00</span><span class="unit">секунд</span></div>
        </div>
      </div>
      <div class="machine" aria-hidden="true"></div>
    </section>
    <section class="contact">
      <span>Связаться с нами можно в</span>
      <a class="telemt-button" href="https://github.com/Telemtinstall/telemt">telemt</a>
    </section>
  </main>
  <script>
    const startedAt = new Date("${install_started_at}");
    const pad = function(value) { return String(value).padStart(2, "0"); };
    function updateTimer() {
      const diff = Math.max(0, Date.now() - startedAt.getTime());
      const totalSeconds = Math.floor(diff / 1000);
      const days = Math.floor(totalSeconds / 86400);
      const hours = Math.floor(totalSeconds % 86400 / 3600);
      const minutes = Math.floor(totalSeconds % 3600 / 60);
      const seconds = totalSeconds % 60;
      document.getElementById("days").textContent = String(days);
      document.getElementById("hours").textContent = pad(hours);
      document.getElementById("minutes").textContent = pad(minutes);
      document.getElementById("seconds").textContent = pad(seconds);
    }
    updateTimer();
    setInterval(updateTimer, 1000);
  </script>
</body>
</html>
EOF
  fi
  chmod 0644 "/var/www/$DOMAIN/index.html"

  rm -f /etc/nginx/sites-enabled/default
  write_file_root "/etc/nginx/sites-available/$DOMAIN" 0644 root:root <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    access_log off;
    error_log /var/log/nginx/${DOMAIN}.error.log crit;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/${DOMAIN};
        default_type "text/plain";
        try_files \$uri =404;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF
  ln -sfn "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"
  nginx -t
  systemctl reload nginx || systemctl restart nginx
}

issue_certificate() {
  certbot certonly \
    --webroot \
    -w "/var/www/$DOMAIN" \
    -d "$DOMAIN" \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    --keep-until-expiring
  systemctl enable --now certbot.timer 2>/dev/null || true
}

write_nginx_full_config() {
  local access_log_line="access_log off;"
  if [ "$ENABLE_LOGS" = "yes" ]; then
    access_log_line="access_log /var/log/nginx/${DOMAIN}.access.log;"
  fi

  write_file_root "/etc/nginx/sites-available/$DOMAIN" 0644 root:root <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    ${access_log_line}
    error_log /var/log/nginx/${DOMAIN}.error.log crit;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/${DOMAIN};
        default_type "text/plain";
        try_files \$uri =404;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 127.0.0.1:8443 ssl http2;
    server_name ${DOMAIN};
    ${access_log_line}
    error_log /var/log/nginx/${DOMAIN}.error.log crit;

    root /var/www/${DOMAIN};
    index index.html;

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers off;

    location / {
        try_files \$uri /index.html =404;
    }
}
EOF

  write_file_root /etc/nginx/modules-enabled/60-telemt-stream-sni.conf 0644 root:root <<EOF
stream {
    map \$ssl_preread_server_name \$telemt_backend {
        ${DOMAIN} 127.0.0.1:1443;
        default   127.0.0.1:8443;
    }

    server {
        listen 443;
        proxy_pass \$telemt_backend;
        ssl_preread on;
        proxy_connect_timeout 5s;
        proxy_timeout 24h;
    }
}
EOF
  nginx -t
  systemctl reload nginx || systemctl restart nginx
}

write_telemt_config() {
  install -d -m 0750 "$INSTALL_DIR"
  install -d -m 0777 "$INSTALL_DIR/runtime"

  local middle_bool="false"
  [ "$USE_MIDDLE_PROXY" = "yes" ] && middle_bool="true"

  {
    cat <<EOF
show_link = ["${TELEMT_USER}"]

[general]
fast_mode = true
use_middle_proxy = ${middle_bool}
config_strict = true
log_level = "silent"
EOF
    if [ -n "$AD_TAG" ]; then
      printf 'ad_tag = "%s"\n' "$AD_TAG"
    fi
    cat <<EOF

[general.links]
show = ["${TELEMT_USER}"]
public_host = "${DOMAIN}"
public_port = 443

[general.modes]
classic = false
secure = false
tls = true

[network]
ipv4 = true
ipv6 = false
prefer = 4

[server]
port = 1443
listen_addr_ipv4 = "127.0.0.1"
listen_addr_ipv6 = "::1"
proxy_protocol = false
metrics_listen = "127.0.0.1:9090"
metrics_whitelist = ["127.0.0.1/32", "::1/128"]

[server.api]
enabled = true
listen = "127.0.0.1:9091"
read_only = true
whitelist = ["127.0.0.1/32", "::1/128"]
request_body_limit_bytes = 65536
minimal_runtime_enabled = true
minimal_runtime_cache_ttl_ms = 1000

[[server.listeners]]
ip = "127.0.0.1"
announce = "${PUBLIC_IP}"

[censorship]
tls_domain = "${DOMAIN}"
mask = true
mask_host = "127.0.0.1"
mask_port = 8443
tls_emulation = true
tls_front_dir = "/tmp/telemt-tlsfront"
tls_full_cert_ttl_secs = 0
alpn_enforce = true

[access]
replay_check_len = 65536
ignore_time_skew = false

[access.users]
"${TELEMT_USER}" = "${TELEMT_SECRET}"

[access.user_max_tcp_conns]
"${TELEMT_USER}" = ${TELEMT_MAX_TCP_CONNS}

[[upstreams]]
type = "direct"
enabled = true
weight = 10
EOF
  } > "$INSTALL_DIR/telemt.toml"
  chown 65532:65532 "$INSTALL_DIR/telemt.toml"
  chmod 600 "$INSTALL_DIR/telemt.toml"
}

fix_runtime_permissions() {
  if [ -f "$INSTALL_DIR/telemt.toml" ]; then
    chown 65532:65532 "$INSTALL_DIR/telemt.toml"
    chmod 600 "$INSTALL_DIR/telemt.toml"
  fi
  install -d -m 0777 "$INSTALL_DIR/runtime"
}

write_compose() {
  local logging_block
  local hardening_block
  if [ "$ENABLE_LOGS" = "yes" ]; then
    logging_block='
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"'
  else
    logging_block='
    logging:
      driver: "none"'
  fi

  if [ "$ENABLE_DOCKER_HARDENING" = "yes" ]; then
    hardening_block='
    healthcheck:
      test: [ "CMD", "/app/telemt", "healthcheck", "/etc/telemt/telemt.toml", "--mode", "liveness" ]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s
    security_opt:
      - no-new-privileges=true
    cap_drop:
      - ALL
    read_only: true
    tmpfs:
      - /tmp:rw,nosuid,nodev,noexec,size=16m
    pids_limit: 256
    mem_limit: 256m
    cpus: "0.50"'
  else
    hardening_block='
    healthcheck:
      disable: true'
  fi

  cat > "$INSTALL_DIR/docker-compose.yml" <<EOF
services:
  telemt:
    image: ${TELEMT_IMAGE}
    container_name: telemt
    restart: unless-stopped
    network_mode: host
    environment:
      RUST_LOG: "error"
    volumes:
      - ${INSTALL_DIR}/telemt.toml:/etc/telemt/telemt.toml:ro
    command: ["/etc/telemt/telemt.toml"]
${hardening_block}${logging_block}
    ulimits:
      nofile:
        soft: 65536
        hard: 262144
EOF
  chmod 600 "$INSTALL_DIR/docker-compose.yml"
}

start_telemt() {
  cd "$INSTALL_DIR"
  compose_cmd config >/dev/null
  compose_cmd up -d --force-recreate
}

write_firewall_hints() {
  if have ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow 80/tcp
    ufw allow 443/tcp
  fi
  if have firewall-cmd && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-service=http || true
    firewall-cmd --permanent --add-service=https || true
    firewall-cmd --reload || true
  fi
}

validate_install() {
  sleep 8
  ss -lntp | grep -E ':(80|443|8443|1443|9090|9091)\b' || true
  curl -fsS "http://127.0.0.1:9091/v1/users" | tee /tmp/telemt-users.json >/dev/null
  grep -q '"ok":true' /tmp/telemt-users.json
  grep -o 'tg://proxy[^"]*' /tmp/telemt-users.json > /root/telemt-proxy-link.txt || true
  chmod 600 /root/telemt-proxy-link.txt 2>/dev/null || true

  local probe_log="/root/telemt-active-probing-check.txt"
  : > "$probe_log"
  chmod 600 "$probe_log" 2>/dev/null || true

  if is_ru; then
    say "Active probing check: openssl s_client -connect ${PUBLIC_IP}:443 -servername ${DOMAIN}"
  else
    say "Active probing check: openssl s_client -connect ${PUBLIC_IP}:443 -servername ${DOMAIN}"
  fi
  {
    printf '[openssl s_client]\n'
    printf 'command=openssl s_client -connect %s:443 -servername %s -verify_hostname %s -brief\n' "$PUBLIC_IP" "$DOMAIN" "$DOMAIN"
  } >> "$probe_log"
  timeout 15 openssl s_client \
    -connect "${PUBLIC_IP}:443" \
    -servername "${DOMAIN}" \
    -verify_hostname "${DOMAIN}" \
    -verify_return_error \
    -brief </dev/null >> "$probe_log" 2>&1 || {
      cat "$probe_log" >&2 || true
      if is_ru; then
        die "Active probing openssl check failed. Проверьте DNS, сертификат, nginx stream и Telemt mask_host/mask_port."
      else
        die "Active probing openssl check failed. Check DNS, certificate, nginx stream, and Telemt mask_host/mask_port."
      fi
    }

  if is_ru; then
    say "Active probing check: curl -I --resolve ${DOMAIN}:443:${PUBLIC_IP} https://${DOMAIN}/"
  else
    say "Active probing check: curl -I --resolve ${DOMAIN}:443:${PUBLIC_IP} https://${DOMAIN}/"
  fi
  {
    printf '\n[curl --resolve]\n'
    printf 'command=curl -I --resolve %s:443:%s https://%s/\n' "$DOMAIN" "$PUBLIC_IP" "$DOMAIN"
  } >> "$probe_log"
  curl -fsSIL --resolve "${DOMAIN}:443:${PUBLIC_IP}" "https://${DOMAIN}/" >> "$probe_log" 2>&1 || {
      cat "$probe_log" >&2 || true
      if is_ru; then
        die "Active probing curl check failed. Обычный HTTPS-запрос к домену через IP сервера не получил корректный ответ."
      else
        die "Active probing curl check failed. A normal HTTPS request to the domain through the server IP did not return a valid response."
      fi
    }
  sed -n '1,24p' "$probe_log" || true
}

print_plan() {
  if is_ru; then
    cat <<EOF

План установки:
  домен:              $DOMAIN
  публичный IPv4:     $PUBLIC_IP
  email:              $EMAIL
  Docker image:       $TELEMT_IMAGE
  автосборка image:   $AUTO_BUILD_IMAGE
  страница маскировки: $MASK_SITE_MODE
  пользователь Telemt: $TELEMT_USER
  лимит подключений:  $TELEMT_MAX_TCP_CONNS
  ad_tag:             $([ -n "$AD_TAG" ] && printf yes || printf no)
  middle_proxy:       $USE_MIDDLE_PROXY
  логи включены:      $ENABLE_LOGS
  Docker hardening:   $ENABLE_DOCKER_HARDENING
  high-load tuning:   $ENABLE_HIGH_LOAD_TUNING

Установщик настроит:
  - TLS-Fronting + TCP-Splitting схему для своего домена
  - nginx HTTP -> HTTPS redirect
  - nginx SNI stream на публичном 443/tcp
  - HTTPS mask site на 127.0.0.1:8443 ($MASK_SITE_MODE page)
  - Telemt внутри Docker на 127.0.0.1:1443
  - Telemt API на 127.0.0.1:9091
  - Telemt metrics на 127.0.0.1:9090
  - Let's Encrypt сертификат и certbot renewal timer
  - финальную active probing проверку через openssl s_client и curl --resolve
  - опциональный Docker runtime hardening и healthcheck
EOF

    if [ "$ENABLE_DOCKER_HARDENING" = "yes" ]; then
      cat <<'EOF'

Docker hardening включит:
  - read_only root filesystem
  - cap_drop: ALL
  - no-new-privileges
  - tmpfs для /tmp
  - pids/memory/cpu limits
  - Docker healthcheck
EOF
    else
      cat <<'EOF'

Docker hardening выключен:
  - filesystem контейнера будет writable
  - Linux capabilities не будут сброшены этим compose-файлом
  - Docker healthcheck выключен в compose
EOF
    fi

    if [ "$ENABLE_HIGH_LOAD_TUNING" = "yes" ]; then
      cat <<'EOF'

High-load tuning запишет /etc/sysctl.d/99-telemt-high-load.conf:
  - net.core.somaxconn = 65535
  - net.ipv4.tcp_max_syn_backlog = 65535
  - net.ipv4.tcp_keepalive_time = 300
  - net.ipv4.tcp_keepalive_intvl = 30
  - net.ipv4.tcp_keepalive_probes = 5
  - fs.file-max = 2097152
  - BBR/fq, если поддерживается ядром
EOF
    fi
    return 0
  fi

  cat <<EOF

Install plan:
  domain:             $DOMAIN
  public IPv4:        $PUBLIC_IP
  email:              $EMAIL
  docker image:       $TELEMT_IMAGE
  auto-build image:   $AUTO_BUILD_IMAGE
  mask site page:     $MASK_SITE_MODE
  Telemt user:        $TELEMT_USER
  connection limit:   $TELEMT_MAX_TCP_CONNS
  ad_tag:             $([ -n "$AD_TAG" ] && printf yes || printf no)
  middle_proxy:       $USE_MIDDLE_PROXY
  logs enabled:       $ENABLE_LOGS
  Docker hardening:   $ENABLE_DOCKER_HARDENING
  high-load tuning:   $ENABLE_HIGH_LOAD_TUNING

This installer will configure:
  - TLS-Fronting + TCP-Splitting for your own domain
  - nginx HTTP -> HTTPS redirect
  - nginx SNI stream on public 443/tcp
  - HTTPS mask site on 127.0.0.1:8443 ($MASK_SITE_MODE page)
  - Telemt inside Docker on 127.0.0.1:1443
  - Telemt API on 127.0.0.1:9091
  - Telemt metrics on 127.0.0.1:9090
  - Let's Encrypt certificate and certbot renewal timer
  - final active probing check with openssl s_client and curl --resolve
  - optional Docker runtime hardening and healthcheck
EOF

  if [ "$ENABLE_DOCKER_HARDENING" = "yes" ]; then
    cat <<'EOF'

Docker hardening will enable:
  - read_only root filesystem
  - cap_drop: ALL
  - no-new-privileges
  - tmpfs for /tmp
  - pids/memory/cpu limits
  - Docker healthcheck
EOF
  else
    cat <<'EOF'

Docker hardening is disabled:
  - container filesystem will be writable
  - Linux capabilities are not dropped by this compose file
  - Docker healthcheck is disabled in compose
EOF
  fi

  if [ "$ENABLE_HIGH_LOAD_TUNING" = "yes" ]; then
    cat <<'EOF'

High-load tuning will write /etc/sysctl.d/99-telemt-high-load.conf:
  - net.core.somaxconn = 65535
  - net.ipv4.tcp_max_syn_backlog = 65535
  - net.ipv4.tcp_keepalive_time = 300
  - net.ipv4.tcp_keepalive_intvl = 30
  - net.ipv4.tcp_keepalive_probes = 5
  - fs.file-max = 2097152
  - BBR/fq if supported by the kernel
EOF
  fi
}

confirm_plan() {
  [ "$ASSUME_YES" = "1" ] && return 0
  local answer
  if is_ru; then
    read -r -p "Введите y, yes или да для продолжения: " answer
  else
    read -r -p "Type y or yes to continue: " answer
  fi
  case "$(lower "$answer")" in
    y|yes|д|да) ;;
    *)
      if is_ru; then
        die "Отменено."
      else
        die "Cancelled."
      fi
      ;;
  esac
}

interactive_inputs() {
  if is_ru; then
    cat <<'EOF'
Установщик Telemt Docker.

Перед запуском:
  1. Используйте чистый Debian/Ubuntu сервер.
  2. Создайте DNS A-запись: <домен> -> IPv4 этого сервера.
  3. Убедитесь, что порты 80/tcp и 443/tcp доступны из интернета.
  4. Держите build.sh рядом с этим установщиком; image будет собран автоматически, если его нет.

EOF

    ask_default DOMAIN "Домен прокси" "$DOMAIN"
    EMAIL="${EMAIL:-admin@$DOMAIN}"
    ask_default EMAIL "Email для Let's Encrypt" "$EMAIL"
    ask_default TELEMT_IMAGE "Docker image Telemt" "$TELEMT_IMAGE"
    ask_mask_site_mode
    ask_default TELEMT_USER "Имя пользователя Telemt" "$TELEMT_USER"
    ask_default TELEMT_MAX_TCP_CONNS "Максимум подключений Telemt" "$TELEMT_MAX_TCP_CONNS"
    ask_default AD_TAG "MTProxy ad_tag, Enter = пропустить" "$AD_TAG"
  else
    cat <<'EOF'
Telemt Docker installer.

Before running:
  1. Use a clean Debian/Ubuntu server.
  2. Create DNS A record: <domain> -> this server IPv4.
  3. Make sure ports 80/tcp and 443/tcp are reachable.
  4. Keep build.sh next to this installer; the image will be built automatically if missing.

EOF

    ask_default DOMAIN "Proxy domain" "$DOMAIN"
    EMAIL="${EMAIL:-admin@$DOMAIN}"
    ask_default EMAIL "Let's Encrypt email" "$EMAIL"
    ask_default TELEMT_IMAGE "Telemt Docker image" "$TELEMT_IMAGE"
    ask_mask_site_mode
    ask_default TELEMT_USER "Telemt user name" "$TELEMT_USER"
    ask_default TELEMT_MAX_TCP_CONNS "Max Telemt connections" "$TELEMT_MAX_TCP_CONNS"
    ask_default AD_TAG "MTProxy ad_tag, Enter = skip" "$AD_TAG"
  fi

  if [ -z "$USE_MIDDLE_PROXY" ]; then
    if [ -n "$AD_TAG" ]; then
      USE_MIDDLE_PROXY="yes"
    else
      USE_MIDDLE_PROXY="no"
    fi
  fi
  if is_ru; then
    ask_yes_no USE_MIDDLE_PROXY "Использовать Telegram middle proxy" "$USE_MIDDLE_PROXY"
    ask_yes_no ENABLE_LOGS "Включить access-логи nginx/Docker" "$ENABLE_LOGS"
    ask_yes_no ENABLE_DOCKER_HARDENING "Включить Docker hardening и healthcheck" "$ENABLE_DOCKER_HARDENING"
    ask_yes_no ENABLE_HIGH_LOAD_TUNING "Включить high-load tuning для большого числа клиентов" "$ENABLE_HIGH_LOAD_TUNING"
  else
    ask_yes_no USE_MIDDLE_PROXY "Use Telegram middle proxy" "$USE_MIDDLE_PROXY"
    ask_yes_no ENABLE_LOGS "Enable nginx/Docker access logs" "$ENABLE_LOGS"
    ask_yes_no ENABLE_DOCKER_HARDENING "Enable Docker hardening and healthcheck" "$ENABLE_DOCKER_HARDENING"
    ask_yes_no ENABLE_HIGH_LOAD_TUNING "Enable high-load tuning for many clients" "$ENABLE_HIGH_LOAD_TUNING"
  fi
}

main() {
  parse_args "$@"
  need_root
  local requested_script_lang="$SCRIPT_LANG"
  load_config_if_exists
  if [ "$SCRIPT_LANG_FROM_CLI" = "1" ]; then
    SCRIPT_LANG="$requested_script_lang"
  fi
  interactive_inputs
  validate_inputs
  save_config

  if ! have curl || ! have ss || ! have getent; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl iproute2 libc-bin
  fi

  PUBLIC_IP="$(public_ipv4)"
  if ! [[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    if is_ru; then
      die "Не удалось определить публичный IPv4."
    else
      die "Cannot detect public IPv4."
    fi
  fi

  say
  if is_ru; then
    say "[01] DNS и проверка портов"
    say "server_public_ipv4=$PUBLIC_IP"
    say "IPv4 домена:"
  else
    say "[01] DNS and port preflight"
    say "server_public_ipv4=$PUBLIC_IP"
    say "domain_ipv4s:"
  fi
  domain_ipv4s "$DOMAIN" || true
  if ! domain_ipv4s "$DOMAIN" | grep -Fxq "$PUBLIC_IP"; then
    if is_ru; then
      die "DNS A-запись для $DOMAIN не указывает на IPv4 этого сервера: $PUBLIC_IP."
    else
      die "DNS A record for $DOMAIN does not point to this server IPv4 $PUBLIC_IP."
    fi
  fi
  check_port_clean_or_nginx 80
  check_port_clean_or_nginx 443

  print_plan
  confirm_plan

  if step_done packages; then
    is_ru && say "[02] Установка пакетов (уже выполнено)" || say "[02] Install packages (already done)"
  else
    is_ru && say "[02] Установка пакетов" || say "[02] Install packages"
    install_packages
    mark_done packages
  fi
  ensure_docker_available

  if step_done docker_image; then
    is_ru && say "[03] Проверка Docker image (уже выполнено)" || say "[03] Check Docker image (already done)"
  else
    is_ru && say "[03] Проверка Docker image" || say "[03] Check Docker image"
    check_docker_image
    mark_done docker_image
  fi

  if step_done high_load; then
    is_ru && say "[04] High-load tuning (уже выполнено)" || say "[04] High-load tuning (already done)"
  else
    is_ru && say "[04] High-load tuning" || say "[04] High-load tuning"
    configure_high_load
    mark_done high_load
  fi

  if step_done cert; then
    is_ru && say "[05] nginx HTTP и сертификат (уже выполнено)" || say "[05] nginx HTTP and certificate (already done)"
  else
    is_ru && say "[05] nginx HTTP и сертификат" || say "[05] nginx HTTP and certificate"
    write_mask_site_http_only
    issue_certificate
    mark_done cert
  fi

  if step_done config; then
    is_ru && say "[06] Конфиг Telemt и nginx SNI (уже выполнено)" || say "[06] Telemt config and nginx SNI (already done)"
  else
    is_ru && say "[06] Конфиг Telemt и nginx SNI" || say "[06] Telemt config and nginx SNI"
    ensure_secret
    write_telemt_config
    write_compose
    write_nginx_full_config
    write_firewall_hints
    mark_done config
  fi
  fix_runtime_permissions

  is_ru && say "[07] Запуск Telemt" || say "[07] Start Telemt"
  start_telemt

  is_ru && say "[08] Проверка" || say "[08] Validate"
  validate_install

  if is_ru; then
    cat <<EOF

Готово.

Ссылка прокси:
$(cat /root/telemt-proxy-link.txt 2>/dev/null || true)

Файлы:
  конфиг:       $INSTALL_DIR/telemt.toml
  compose:      $INSTALL_DIR/docker-compose.yml
  секрет:       $SECRET_FILE
  сохраненный ввод: $SAVED_CONFIG
  ссылка:       /root/telemt-proxy-link.txt
  active probe: /root/telemt-active-probing-check.txt

Команды:
  cd $INSTALL_DIR
  docker compose ps || docker-compose ps
  curl -fsS http://127.0.0.1:9091/v1/users | jq
EOF
  else
    cat <<EOF

Done.

Proxy link:
$(cat /root/telemt-proxy-link.txt 2>/dev/null || true)

Files:
  config:       $INSTALL_DIR/telemt.toml
  compose:      $INSTALL_DIR/docker-compose.yml
  secret:       $SECRET_FILE
  saved input:  $SAVED_CONFIG
  link:         /root/telemt-proxy-link.txt
  active probe: /root/telemt-active-probing-check.txt

Commands:
  cd $INSTALL_DIR
  docker compose ps || docker-compose ps
  curl -fsS http://127.0.0.1:9091/v1/users | jq
EOF
  fi
}

main "$@"
