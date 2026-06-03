# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.2]

### Fixed

- Restore the `traces` pipeline so spans are exported to the espresso endpoint. The
  0.4.1 change dropped traces from all pipelines, which stopped span export to Espresso AI
  rather than only excluding traces from the customer endpoint. The customer endpoint was 
  already limited `metrics` and `logs`.

## [0.4.1]

### Changed

- Remove traces from the signals list

## [0.4.0]

### Added

- OTEL collector sidecar that sends telemetry to optional customer endpoint.

## [0.3.1]

### Changed

- Repository and tag split into separate fields. Image tag is now a required input. Default to `latest` has been removed.

## [0.3.0]

### Added

- Support for Azure.

## [0.2.0]

### Changed

- Moved AWS into a dedicated module.

## [0.1.0]

### Added

- Support for optional proxy variables.

## [0.0.1]

### Added

- Initial implementation.
