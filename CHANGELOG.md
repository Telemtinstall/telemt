# Changelog

## 2026-05-19

### Changed

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
