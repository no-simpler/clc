# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.3] - 2026-03-15

### Changed
- `install.sh`: replaced open-ended `$PATH` iteration fallback with a hard-coded list of common install directories; installer now gives up with a clear error if none match.

## [1.0.2] - 2026-03-15

### Fixed
- `install.sh`: installation directory is now verified to be on `$PATH` before selection; `~/.local/bin` is only created when it is already referenced in `$PATH`.

## [1.0.1] - 2026-03-15

### Changed
- Removed Homebrew tap references; curl installer is now the primary installation method.
- Added CHANGELOG.

## [1.0.0] - 2026-03-15

### Added
- Initial public release.
- Worktree management: `new`, `rm`, `prune`, `ls` commands.
- Claude file operations: `save`, `restore`, `compare`, `ignore` commands.
- Snapshot-based test suite.
- curl installer (`install.sh`) and GitHub Actions CI.

[Unreleased]: https://github.com/no-simpler/clc/compare/v1.0.3...HEAD
[1.0.3]: https://github.com/no-simpler/clc/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/no-simpler/clc/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/no-simpler/clc/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/no-simpler/clc/releases/tag/v1.0.0
