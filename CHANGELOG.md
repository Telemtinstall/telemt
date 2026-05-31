# Changelog

## 2026-05-19

### Changed

- Removed HTTP/2 from the generated nginx mask-site listener for compatibility with nginx 1.24 and older distribution builds. The mask site only needs plain HTTPS, while Telemt traffic still goes through the nginx stream SNI router.
- Added `--fix-nginx` / `-fix` emergency doctor mode. It backs up changed nginx files, removes only incompatible `http2` directives, runs `nginx -t`, checks Docker/Compose, starts/reconciles the Telemt container, verifies `telemt.toml`, local API, certbot timer, and listening ports without changing Telemt secrets, users, certificates, or `telemt.toml` contents.
- The same doctor mode now detects duplicate top-level nginx `stream {}` files, keeps the installer-managed Telemt stream config, backs up and disables the extra stream files, then reruns `nginx -t`.
- Doctor mode no longer asks Docker Compose to recreate an existing Telemt container. It uses `docker start telemt` when the container already exists, avoiding the Compose v1 "image has been removed, volume data could be lost" prompt.
- If the Telemt container is missing and compose references a missing `telemt-local:*` image, doctor mode now rebuilds it with the local `build.sh` before trying `compose up`.
- Improved the final active probing check in the Docker installer:
  - forces IPv4 with `openssl s_client -4` and `curl -4`;
  - stores the full result in `/root/telemt-active-probing-check.txt`;
  - prints automatic diagnostics on failure: DNS A/AAAA, listening ports, nginx status/test, stream config, Docker container/logs, and firewall state;
  - redacts proxy links/secrets from diagnostic Docker logs;
  - explains common `BIO_connect:connect error` causes and the exact next steps.
- Raised the default Telemt connection limit from `1000` to `5000`.
- Removed default Docker CPU/RAM/PID limits from generated compose files. Hardening still keeps `read_only`, `cap_drop`, `no-new-privileges`, `tmpfs`, healthcheck, and high `nofile` ulimits.
- Aligned generated Docker compose with the live Telemt standard: explicit non-root `user: "65532:65532"`, `RUST_LOG=warn`, `logging.driver=none` by default, and `nofile=65535/65535`.
- Added copy-paste Git, `wget`, and `curl` download commands for the Docker installer in RU and EN documentation.
- Fixed Docker installer proxy link generation: links are now built explicitly as valid TLS MTProxy links, saved in both `https://t.me/proxy` and `tg://proxy` forms, instead of relying on fragile JSON `grep` extraction.
- Fixed resume-mode link generation: reruns now load the existing secret from `telemt-secret.env` or the installed `telemt.toml` instead of failing with an unbound `TELEMT_SECRET`.
- Added an ACME HTTP-01 preflight before `certbot`: the installer now creates a temporary challenge file, verifies it locally and through the server public IPv4, opens `80/443` in active UFW/firewalld before certificate issuance, and writes clear diagnostics to `/root/telemt-acme-http01-check.txt` when the challenge path is unreachable.
- Added `--update` mode for the Docker installer. It preserves existing `telemt.toml`, `docker-compose.yml`, secrets, links, and nginx configs, rebuilds/pulls the Telemt image, recreates the container, and reruns validation.
- Added IDN/punycode normalization for domains and Let's Encrypt email domains. Cyrillic/IDN input is converted to ASCII punycode; invalid punycode is rejected before system changes.
- Added explicit `censorship.exclusive_mask` for new Telemt `3.4.12+` installs so the configured SNI domain is pinned to the local HTTPS mask backend.

## 2026-05-11

### Added

- Added this changelog to track Docker installer changes.
- Added a bilingual installer notice explaining that this is a Bash installer/Dockerfile, not an official Telemt installer, and listing software sources.
- Added strict Telemt config validation and API request body limit to generated configs:
  - `config_strict = true`
  - `request_body_limit_bytes = 65536`

### Changed

- Updated documentation examples to use the latest Telemt release by default.
- Kept explicit version pinning as an optional production workflow through `TELEMT_VERSION=<version>`.

### Not Added

- Did not add quota reset API handling because the intended setup is unlimited.
- Did not add Grafana or external metrics stack.
- Did not add third-party domain fronting.
