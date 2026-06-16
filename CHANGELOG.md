# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [3.0.1] - 2026-06-16

A bug-fix release closing a data-loss regression in v3's worktree flow, plus a more robust model for reconciling the second brain across worktrees. Your store, enrollment, and backups are unchanged. **Upgrade promptly** — the installed `clc` is what your git hooks call, so the fix only takes effect once the binary on your `PATH` is 3.0.1.

### Fixed
- **`clc go` no longer wipes your stored second brain when creating a worktree.** Creating a managed worktree runs `git worktree add`, which fires clc's `post-checkout` hook *inside the brand-new, still-empty worktree*. The hook's auto-sync read the brain from that empty worktree and deleted the project's entire stored brain as "orphans" — so the new worktree (and every future one) came up blank. The hook now always syncs from the **main** worktree, and a safety guard refuses to erase a populated store from an empty source. If your store was already wiped, your on-disk brain is intact: run `clc save` from the main worktree to restore it.
- **Stale nested-worktree gitlinks are swept from the store.** A removed worktree could leave a `160000` gitlink behind in the parent's store subtree (plain `git rm` exits non-zero on it and the error was swallowed); the orphan-removal now force-removes it, and the leak vector (`git add -A`) is gone.

### Added
- **`clc save --force-empty`** — the explicit escape hatch to erase a project's stored brain when the worktree brain is genuinely empty (the new guard otherwise refuses). Never available to the git hook.
- **`clc reconcile`** — a read-only 3-way view of the brain across the current worktree, the store (canonical), and the main worktree, so you can see divergence and choose to promote (`clc save`) or take (`clc restore`) deliberately.

### Changed
- **The second brain is reconciled around the main worktree as canonical.** A commit in a peer worktree no longer silently overwrites the store with that worktree's brain (the old "current-worktree-wins"); it keeps the store mirroring main and prints a one-line nudge when the peer's brain has diverged, so you promote edits deliberately with `clc save`.

## [3.0.0] - 2026-06-16

This is a **breaking release** that reimagines clc's worktree workflow around a single low-friction verb. Your second brain (store, enrollment, save/restore/compare, hooks, backups) is unchanged and migrates without action.

### Added
- **`clc go [<selector>]` — one verb to resume or create-and-launch a worktree session.** Pick a worktree by number, name, branch, or unique prefix (`clc go 2`, `clc go login`, `clc go feature/login`) and clc `cd`s in and launches `claude` for you — no more hunting for the directory and branch by hand. With no selector it shows a numbered menu (single keystroke to choose). If nothing matches, it *creates* the worktree from that branch and launches it: silently when the branch already exists, with a one-key confirm when it would be a brand-new branch. Flags: `-y` (skip the confirm), `--no-brain` (don't restore the second brain), `--no-launch` (set up only), and `-- <args>` to pass arguments through to `claude` (e.g. `clc go login -- --resume`).
- **`clc name <selector> <new-name>` — rename a worktree's directory.** Renames clutter like Claude Code's auto-named `bright-running-fox` into something memorable, and *adopts* a worktree created elsewhere into clc's management. The branch is left untouched.

### Changed
- **Worktrees now live under `<repo>/.claude/worktrees/<name>`** — the exact location `claude --worktree` uses — instead of sibling `<repo>-<name>` directories. clc-created and Claude-Code-created worktrees are now indistinguishable and equally managed. (Creating worktrees here assumes the repo's second brain is locally ignored, which `clc enroll`/`clc ignore` handles.)
- **`clc status` lists every worktree in one numbered section** (the main worktree is `#1`), with the current worktree marked, so the numbers line up with `clc go <n>`.
- **All prompts are now single-keystroke** — press `y`, no Enter.
- **`rm`, `prune`, `pull`, and `close` now take a selector** (index, name, branch, or unique prefix) and operate on worktrees under `.claude/worktrees/` only.

### Removed
- **`clc new` is gone — use `clc go`**, which now does create-and-launch. Running `clc new` prints a pointer to `clc go`.

### Migration
- Existing sibling worktrees (`<repo>-<name>`) still appear in `clc status` and launch via `clc go`, but they're treated as **foreign**: `rm`/`prune` won't touch them. Run `clc name <selector> <new-name>` to relocate one under `.claude/worktrees/` and bring it under full management.

## [2.1.2] - 2026-06-16

### Fixed
- `clc compare`, `ls`, and friends are fast again in a project whose second brain hosts a full nested worktree (e.g. Claude Code's `.claude/worktrees/<name>/`). The v2.1.1 nested-boundary check scanned the whole worktree on the filesystem and ran several times per command, so a large repo could take ~30s per invocation; clc now asks Git directly (`git worktree list` + `git submodule status`), bringing it back to about a second. (Trade-off: a nested boundary is now recognized only if Git tracks it as a worktree or submodule — which covers the cases that occur in practice; an unregistered, hand-placed clone dropped inside `.claude/` is no longer auto-excluded.)

## [2.1.1] - 2026-06-16

### Fixed
- A linked Git worktree nested inside your second brain — most commonly Claude Code's own `.claude/worktrees/<name>/`, a full checkout of the repo — is no longer swallowed into the outer project's brain. Previously `clc ls`/`save` walked straight into it and treated every file in that worktree (potentially tens of thousands) as Claude files. clc now prunes any nested Git boundary (submodule, linked worktree, or nested clone) everywhere the brain is enumerated, so only the real brain is listed, stored, compared, and backed up.

## [2.1.0] - 2026-06-11

### Added
- `--all` (`-a`) for `save`, `compare`, `diff`, and `restore`: operate across **every** enrolled repo in one pass instead of just the current one. Runnable from anywhere — no current repo required.
  - `clc save --all` snapshots every enrolled project's second brain into the store in a single call (handy as a checkpoint before risky work).
  - `clc compare --all` prints a one-line-per-repo audit (in sync / drifted / never synced / missing) and exits non-zero if any repo has drifted.
  - `clc diff --all` shows the full Git diff for every drifted repo.
  - `clc restore --all` reconciles every repo's worktree from the store, prompting per repo before any data loss.
  - Repos that aren't present on this machine are reported `missing` and skipped (never purged from the store).

## [2.0.2] - 2026-06-07

### Changed
- The managed second brain now respects your project's ignore intent: brain files matched by an in-repo `.gitignore` (at any depth — e.g. a dependency's `vendor/…/CLAUDE.md`) or by your global excludes (e.g. the per-machine `.claude/settings.local.json`) are kept out of the store and backups. clc still disregards only its *own* `.git/info/exclude` patterns, so your actual brain is stored as before. This corrects both v1 (which captured everything) and the 2.0.1 "capture-all" behavior.

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

[Unreleased]: https://github.com/no-simpler/clc/compare/v3.0.1...HEAD
[3.0.1]: https://github.com/no-simpler/clc/compare/v3.0.0...v3.0.1
[3.0.0]: https://github.com/no-simpler/clc/compare/v2.1.2...v3.0.0
[2.1.2]: https://github.com/no-simpler/clc/compare/v2.1.1...v2.1.2
[2.1.1]: https://github.com/no-simpler/clc/compare/v2.1.0...v2.1.1
[2.1.0]: https://github.com/no-simpler/clc/compare/v2.0.2...v2.1.0
[2.0.2]: https://github.com/no-simpler/clc/compare/v2.0.1...v2.0.2
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
