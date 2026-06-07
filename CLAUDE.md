**Claude Cloak (`clc`)** is a single-file bash utility (`clc.sh`) that manages Git worktrees (for using with Claude Code) and helps obfuscate usage of Claude Code in repositories where Claude-related files cannot be committed.

The goal is to enable user to work with Claude Code effectively and efficiently in any Git repository (across its worktrees), even without leaving any trace of Claude Code usage in committed files.

## Main features

- Git only.
  - Git must be available on $PATH.
  - Avoids replicating Git features — only implements helpful add-on layer.
- Detects **current repo** at call-site.
  - Distinguishes each current repo by path to its **main worktree** (path to its main `.git` directory).
  - Distinguishes main worktree from **peer worktrees** (any other worktree).
  - Distinguishes **current worktree** as worktree from which this command was called (can be main or one of the peers).
- Distinguishes **managed worktrees** from unmanaged ones.
  - Managed worktree is either the main worktree or a peer worktree that follows path convention.
  - Path convention for managed peer worktree: if main worktree is at `/repos/main-repo`, managed peer peer worktree is at `/repos/main-repo-<worktree-name>`.
  - Allows easily creating and deleting managed worktrees.
  - Allows convenience actions on worktrees.
- Defines **Claude-related files** as:
  - `CLAUDE.md` file (at any depth of worktree).
  - `/.claude/` directory (only in the root of worktree) with all contents.
- Manages Claude-related files (the "second brain") only in managed worktrees.
  - Allows ignoring these files locally (via `.git/info/exclude`).
  - **Enrollment** (`enroll`) fully manages a repo; `save`/`compare`/`restore` operate against the central git store; `ignore`/`unignore` are the gitignore-only step.

## Mission (the two-slice model)

clc serves projects that need plausible deniability of agentic usage — or that simply don't want to commit a Claude "second brain" into their own VCS. It provides separate version management in two cleanly separated slices:

- **Slice A — main code:** version-controlled in place, in the project's own git repo. The second brain never enters it.
- **Slice B — second brain:** *also* version-controlled, but separately and centrally — one git-backed store per machine holds the second brains of all enrolled projects, with optional auto-backup (git remote and/or local bundle) for cross-machine durability.

The owner (this machine's user) is the **prime** audience; published is secondary. Design owner-first, keep it clean enough to ship.

## Architecture (v2)

- **Central store** — a non-bare git repo at `$(clc_data_dir)/store` (default `~/.local/share/clc/store`). Its working tree mirrors each enrolled project's second brain under a **HOME-relative path** (e.g. `Developer/clc/CLAUDE.md`). Real git history replaces v1's timestamp snapshots. `save`/`restore`/`compare`/`diff`/`ls`/`new` all back onto the store HEAD mirror.
  - Sync (`store_sync_project`) is **copy-based, delete-aware, and subtree-scoped**: it re-materializes only that project's `-- "$rel"` subtree (removes orphans, copies current brain, commits), so a concurrent project's in-flight subtree is never swept. Submodule subtrees are skipped (they are nested projects). This is the single most bug-prone area — keep every git path `$rel`-scoped.
- **Registry / manifest** — committed *into* the store at `.clc/registry`. Line-oriented TAB-separated text (`<HOME-relative path> TAB <origin-url> [TAB meta…]`), **sorted on every write**, atomic (`render → .tmp → mv`). It is both the local registry and the cross-machine cold-start manifest. (Config uses git-config; the registry uses text because a multi-machine-synced manifest merges far more cleanly as sorted one-line-per-project text.)
- **Identity = HOME-relative path** of the **main worktree**. A repo outside `$HOME` has no identity → error, never guess. Moves are handled by an explicit `clc relink` (a fresh clone has no stable ID anyway, and a silent cross-machine move is a footgun).
- **Enrollment (4 steps)** — `enroll` = local-gitignore the brain + register in the manifest + install hooks + initial sync. `unenroll` reverses all four. `ignore`/`unignore` are aliases for the gitignore-only step.
- **Hooks** — `post-commit` + `post-merge` + `post-checkout`, installed **once** at the main gitdir (honoring `core.hooksPath`). Each is a fail-safe, non-blocking shim (`clc sync --from-hook … || true`) wrapped in a sentinel-marked block (`# >>> clc managed >>>` … `# <<< clc managed <<<`) — composes with husky/lefthook, never clobbers user content, cleanly uninstalls by sentinel. Cadence is **best-effort**: commit/merge/checkout fire; `git rebase` does *not* fire for replayed commits → manual `clc sync`. A commit in any worktree syncs *that worktree's* brain (current-worktree-wins); a peer source prints a warning.
- **Backups** — git-config subsections in the config file (`[clc "backup.<name>"] kind = remote|bundle; …`). Decoupled from the per-commit store sync: a successful sync triggers a **debounced** (default 15 min, configurable), **backgrounded, fail-safe** push to all targets; `clc backup` forces an immediate synchronous push. Bundle targets write a single small blob rotated atomically with `.prev`. Per-target last-success stamps + a failure log live under the state dir.
- **XDG locations** — config `~/.config/clc` (the `config` file; sync/track this), data `~/.local/share/clc` (store + registry), state `~/.local/state/clc` (locks, backup stamps/log). Defaults follow the XDG spec; `CLC_STORE` overrides the data/store root (back-compat + test isolation). Reads are guarded (`git config … || true`) so a missing key never trips `set -euo pipefail`.
- **Concurrency** — every store mutation takes a mandatory **mkdir-based** advisory lock (`with_store_lock`, no `flock` dependency) under the state dir.
- **Cross-machine** — **surface, don't auto-apply**: `clc doctor` reports missing / origin-drift / unregistered read-only; `clc clone`/`adopt` cold-start guarded (never clobber a non-empty non-matching dir); `clc relink` re-keys a moved repo; `clc migrate` does a one-shot v1→v2 import (discover via the legacy `~/.clc/saved/*/full-path.txt`, verify via the local-gitignore signal, one current-brain commit — pre-v2 history is not replayed).

### Determinism seams (matter for development + testing)

The snapshot suite stays green by construction:

- **Routine output is content-derived, not history-derived.** `status`/`doctor` report sync *state* (in-sync / drifted / never-synced) by diffing the worktree brain against the store HEAD mirror — no SHAs, no dates. The one wall-clock exception is backup-staleness age in `status`/`doctor`, pinned via the `CLC_NOW` seam.
- **Store commits keep real wall-clock dates** in production; a fixed clc identity + `commit.gpgsign=false` are stamped once into the store's own `.git/config` at `store_init` (no per-commit `-c`).
- **Harness** pins `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE` in fixtures, isolates `XDG_*_HOME` + `CLC_STORE`, applies one shared SHA-scrub (`%%SHA%%`) in `run.sh`, and uses `CLC_SYNC_SYNC=1` (synchronous backup push, capturable) + `CLC_NOW=<epoch>` (pins all wall-clock math) for backup tests.

A determinism-breaking change ships its normalization in the **same** commit — never leave the suite red.

## Conventions

Compartmentalized code. Short, readable functions. Succinct comments where it aids readability. Aim for extendability. Industry standards for shell scripting. Human-friendly, formatted, informative output. When called without arguments, actions limited to read-only (always safe to call without arguments). Support options. Action specified as first non-option argument.

Output style: section headers via `print_header`; muted secondary info via `CLR_MUTED`; warnings via `print_warning_line` / `CLR_WARN`. `--no-color` (or `NO_COLOR` env, or non-TTY stdout) disables all ANSI codes.

## Development loop

No compilation necessary, script should remain a single file and be runnable from it. Remember to always keep --help output in sync with latest features.

## Verification loop

`test/run.sh` is the snapshot test runner. See `test/CLAUDE.md` for full details on the test system and how to add new tests.

```bash
bash test/run.sh               # run all cases (exit 1 on any diff)
bash test/run.sh base          # run a single case
bash test/run.sh --update      # regenerate all snapshots
bash test/run.sh --update base # regenerate snapshots for one case
```

When adding a feature, run `--update` after verifying the new output is correct, then commit the updated snapshots alongside the code change.
