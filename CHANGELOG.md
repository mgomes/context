# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Context::DeadlineExceeded`, a subclass of `Context::Cancelled`, raised when a
  deadline expires so callers can distinguish timeouts from manual cancellation.
- Public `Context#done` channel for composing custom `select` expressions over a
  context and other channels.
- GitHub Actions CI running formatting, specs, the execution-context preview
  spec, and example builds across Crystal 1.20.2 and the latest release.
- `description`, `authors`, and `repository` metadata in `shard.yml`.

### Changed

- Deadlines are now tracked against a monotonic clock (`Time.instant`) instead
  of wall-clock `Time.utc`, so system clock adjustments no longer move when a
  deadline fires. `Context.with_deadline` still accepts a wall-clock `Time` and
  converts it once at creation; `Context#deadline` now returns a `Time::Instant`.
- Deadlines are fired by a single shared background scheduler (a min-heap of
  pending deadlines) instead of one fiber per deadline, so an abandoned deadline
  context can be collected before it fires.

[Unreleased]: https://github.com/mgomes/context/commits/master
