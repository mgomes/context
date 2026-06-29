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

[Unreleased]: https://github.com/mgomes/context/commits/master
