#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

TELEMT_REPOSITORY="${TELEMT_REPOSITORY:-telemt/telemt}"
TELEMT_VERSION="${TELEMT_VERSION:-latest}"
IMAGE="${IMAGE:-telemt-local}"
TARGET="${TARGET:-prod}"
PUSH="${PUSH:-0}"
NO_CACHE="${NO_CACHE:-0}"
PLATFORM="${PLATFORM:-}"

tag_from_version() {
  local version="$1"
  version="${version#refs/tags/}"
  version="${version#v}"
  if [ -z "$version" ]; then
    version="latest"
  fi
  printf '%s' "$version"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'ERROR: command not found: %s\n' "$1" >&2
    exit 1
  }
}

usage() {
  cat <<'USAGE'
Usage:
  TELEMT_VERSION=<release-tag> ./build.sh

Examples:
  ./build.sh
  TELEMT_VERSION=3.4.10 ./build.sh
  TELEMT_VERSION=3.4.10 TARGET=debug ./build.sh
  TELEMT_VERSION=3.4.10 IMAGE=ghcr.io/Telemtinstall/telemt PUSH=1 ./build.sh

Variables:
  TELEMT_REPOSITORY  GitHub repo with releases. Default: telemt/telemt
  TELEMT_VERSION     Release tag or latest. Default: latest
  IMAGE              Local or remote image name. Default: telemt-local
  TARGET             Dockerfile target: prod or debug. Default: prod
  PLATFORM           Optional docker platform, e.g. linux/amd64 or linux/arm64
  NO_CACHE           1 disables Docker build cache.
  PUSH               1 pushes the built image. Default: 0
USAGE
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
  esac

  need_cmd docker

  case "$TARGET" in
    prod|debug) ;;
    *) printf 'ERROR: TARGET must be prod or debug\n' >&2; exit 1 ;;
  esac

  local tag
  tag="$(tag_from_version "$TELEMT_VERSION")"
  local full_image="${IMAGE}:${tag}"

  printf 'Telemt Docker build\n'
  printf '  repository: %s\n' "$TELEMT_REPOSITORY"
  printf '  version:    %s\n' "$TELEMT_VERSION"
  printf '  target:     %s\n' "$TARGET"
  printf '  image:      %s\n' "$full_image"
  printf '  push:       %s\n' "$PUSH"

  if [ "$TELEMT_VERSION" = "latest" ]; then
    printf '\nWARNING: TELEMT_VERSION=latest is useful for testing only. Use an exact release tag for production.\n\n'
  fi

  build_args=(
    build
    --pull
    --target "$TARGET"
    --build-arg "TELEMT_REPOSITORY=$TELEMT_REPOSITORY"
    --build-arg "TELEMT_VERSION=$TELEMT_VERSION"
    -t "$full_image"
  )

  if [ -n "$PLATFORM" ]; then
    build_args+=(--platform "$PLATFORM")
  fi

  if [ "$NO_CACHE" = "1" ]; then
    build_args+=(--no-cache)
  fi

  build_args+=("$SCRIPT_DIR")

  docker "${build_args[@]}"

  printf '\nBuilt image:\n  %s\n' "$full_image"
  printf '\nVersion check:\n'
  docker run --rm --entrypoint /app/telemt "$full_image" --version || true

  if [ "$PUSH" = "1" ]; then
    printf '\nPushing image:\n  %s\n' "$full_image"
    docker push "$full_image"
  else
    printf '\nPUSH=0, image was not published.\n'
  fi
}

main "$@"
