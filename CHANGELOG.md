# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-06-29

### Added

- `Context::DeadlineExceeded`, a subclass of `Context::Cancelled`, raised when a
  deadline expires so callers can distinguish timeouts from manual cancellation.
- Public `Context#done` channel for composing custom `select` expressions over a
  context and other channels.
- GitHub Actions CI running formatting, specs (also under preview
  multithreading), and example builds across Crystal 1.19.1 and the latest
  release.
- `description`, `authors`, and `repository` metadata in `shard.yml`.
- Ameba lint configuration (`.ameba.yml`) with a dedicated CI lint job, and an
  `.editorconfig`.

### Changed

- Lowered the minimum supported Crystal version to 1.19.1 (from 1.20.2).
  1.19.1 is the floor because Crystal 1.19.0 has a timer regression on Darwin,
  BSD, and Windows that fires `sleep`/timeouts immediately.
- Deadlines are now tracked against a monotonic clock (`Time.instant`) instead
  of wall-clock `Time.utc`, so system clock adjustments no longer move when a
  deadline fires. `Context.with_deadline` still accepts a wall-clock `Time` and
  converts it once at creation; `Context#deadline` now returns a `Time::Instant`.
- Deadlines are fired by a single shared background scheduler (a min-heap of
  pending deadlines) instead of one fiber per deadline.

[Unreleased]: https://github.com/mgomes/context/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/mgomes/context/releases/tag/v0.1.0
