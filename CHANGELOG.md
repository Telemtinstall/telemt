# Changelog

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
