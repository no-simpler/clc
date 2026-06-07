# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.1] - 2026-06-07

### Fixed
- The central store now captures your full second brain even when files match your global gitignore (e.g. `.claude/settings.local.json` via `core.excludesfile` or `~/.config/git/ignore`). Previously those files were silently dropped from the store and from backups.
- Git hooks installed by `clc enroll` now reference clc through its stable path rather than a version-pinned Homebrew Cellar path, so `brew upgrade` no longer silently breaks auto-sync.

## [2.0.0] - 2026-06-07

Major release. clc grows from "save Claude files to local timestamp snapshots,
restore across worktrees" into a centrally version-controlled, auto-syncing,
cross-machine **second-brain** store. The two slices are cleanly separated: your
code stays in its own git repo (the second brain never enters it), and the second
brain is *also* version-controlled — separately and centrally — in one git-backed
store per machine, with optional auto-backup for durability across machines.

### Added
- **Central git-backed store** (`$XDG_DATA_HOME/clc/store`, default
  `~/.local/share/clc/store`): a real (non-bare) git repo whose working tree
  mirrors every enrolled project's second brain under a HOME-relative path. Real
  git history replaces v1's timestamp snapshots.
- **Enrollment**: `clc enroll` graduates the old ignore-only setup into a single
  step — local-gitignore the brain, register the project in the store's manifest,
  install sync hooks, and do an initial sync. `clc unenroll` reverses all four.
  `ignore`/`unignore` remain as the gitignore-only step.
- **Auto-sync via git hooks** (`post-commit`/`post-merge`/`post-checkout`):
  committing in any worktree mirrors that worktree's brain into the store
  (current-worktree-wins; a warning prints when synced from a peer). Best-effort
  cadence — rebase-replayed commits don't fire hooks; run `clc sync` manually.
  Hooks compose with existing hooks / `core.hooksPath` via a sentinel-marked block.
- **Backups** (`clc backup` + automatic on sync): configurable targets — a git
  remote or a local bundle (rotated atomically via `.prev`). Decoupled from the
  per-commit store sync, debounced (default 15 min, configurable), backgrounded
  and fail-safe (an offline/unauthed target warns and logs, never blocks a commit).
- **Cross-machine**: the registry/manifest committed into the store doubles as a
  cold-start manifest. `clc clone` / `clc adopt` cold-start a fresh machine
  (guarded — never clobber a non-empty directory); `clc relink` re-keys a moved
  repo; `clc doctor` reports drift read-only (never acts).
- **`clc migrate`**: one-shot v1→v2 import — discovers v1-clc-touched repos and
  enrolls them (pre-migration timestamp history is not replayed).
- **Config** via `git config -f $XDG_CONFIG_HOME/clc/config`; **XDG locations**
  for config / data / state. `CLC_STORE` still overrides the data root.

### Changed
- `save` is now an alias for the store sync; `save`/`restore`/`compare`/`diff`
  operate against the store mirror (the HEAD-committed brain) instead of the
  latest timestamp snapshot. `status` now also reports enrollment, hook, and
  backup-staleness state. Project identity is the repo's HOME-relative path.

### Removed
- The v1 `~/.clc/saved/<name>@<md5>/<timestamp>/` snapshot store and its
  path-hash machinery. (Run `clc migrate` to bring v1 projects into the v2 store.)

### Design notes (folded in from the now-retired V2.md design doc)
- **Non-bare git store** so the owner can browse every brain laid out on disk and
  cold-start is a plain checkout; the trade-off (one shared index) is handled by a
  mandatory mkdir-based store lock (no `flock`, for macOS portability).
- **Copy-sync, not symlink** (symlinks are more conspicuous, bake in machine paths,
  and blur the commit cadence). Sync is **subtree-scoped and delete-aware** —
  re-materialize only the project's subtree, drop orphans, never sweep another
  project's in-flight changes. Nested submodules get their own un-clobbered subtrees.
- **Registry as sorted line-oriented text** (not git-config) so a cross-machine-
  synced manifest merges cleanly; config stays git-config (local, single-writer).
- **Identity = HOME-relative path** with an explicit `clc relink` for moves (a
  silent cross-machine move is itself a footgun); cross-machine reconciliation is
  **surface-don't-apply** — clc reports, the user runs the fix.
- **Determinism**: routine output is content-derived (no SHAs/dates); store commits
  keep real dates with a fixed identity + `gpgsign=false` stamped into the store's
  own `.git/config`; the test harness pins `GIT_*_DATE`, isolates `XDG_*`/`CLC_STORE`,
  and uses `CLC_NOW` / `CLC_SYNC_SYNC` seams for backup timing/async.
- Backup mechanics (bundle `.prev` rotation, fail-safe backgrounded push) are
  adapted from the local `Nexus` tool; clc adds debounce + locking (Nexus has
  neither, assuming single-machine last-writer-wins) and drops Nexus's encryption
  and no-remote rule.

## [1.4.1] - 2026-04-09

### Changed
- Faster Claude file search in repos with large submodules: `find` now prunes submodule directories instead of traversing them.

## [1.4.0] - 2026-04-09

### Added
- Git submodule support: `clc` now works correctly in repositories that contain submodules.

## [1.3.0] - 2026-03-27

### Added
- New `pull` command: rebases a peer worktree's branch onto the current branch, then stages the diff so you can review and commit. Use `-c` to commit immediately.
- New `close` command: like `pull`, but also removes the peer worktree afterwards. Use `-k` to keep the branch, `-c` to auto-commit.
- New `--no-gpg` flag: suppresses GPG commit signing for commands that create commits (`pull -c`, `close -c`).

### Maintenance
- Fixed a CI test flake caused by environment-dependent `git rerere` output.

## [1.2.0] - 2026-03-21

### Added
- New `diff` command: shows a unified diff of your current Claude files against the latest saved state, so you can see exactly what changed before committing or saving.

## [1.1.1] - 2026-03-16

### Fixed
- Paths in `clc` output now correctly display `~` instead of the full home directory path.

### Changed
- Improved `--help` output for clarity and completeness.

## [1.1.0] - 2026-03-16

### Added
- Bash 3.2 support: `clc` now works with macOS's built-in `/bin/bash` (3.2) out of the box, with no separate Bash installation required.

### Changed
- Removed the Bash 4.0+ version guard.
- Replaced associative-array usage in `_compare_claude_files` (Bash 4.0+ only) with a portable `mktemp`/`comm` approach.
- Fixed empty-array expansion under `set -u` in `main()` for Bash 3.2 compatibility.
- Test runner and case scripts now invoke clc via `"$BASH"` to respect the active interpreter.
- Removed dead code: unused constants (`CLC_CLAUDE_FILES`, `CLC_CLAUDE_DIRS`), unused variable (`IS_GOLDEN`), unused function (`is_managed_worktree`), and unused locals in `cmd_ignore`/`cmd_unignore`.
- Unified `\002` field-separator style in `list_all_worktrees` to use `$'\002'` consistently with all callers.

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

[Unreleased]: https://github.com/no-simpler/clc/compare/v2.0.1...HEAD
[2.0.1]: https://github.com/no-simpler/clc/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/no-simpler/clc/compare/v1.4.1...v2.0.0
[1.4.1]: https://github.com/no-simpler/clc/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/no-simpler/clc/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/no-simpler/clc/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/no-simpler/clc/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/no-simpler/clc/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/no-simpler/clc/compare/v1.0.3...v1.1.0
[1.0.3]: https://github.com/no-simpler/clc/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/no-simpler/clc/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/no-simpler/clc/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/no-simpler/clc/releases/tag/v1.0.0
