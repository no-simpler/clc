**Claude Cloak (`clc`)** is a single-file bash utility (`clc.sh`) that manages Git worktrees (for using with Claude Code) and helps obfuscate usage of Claude Code in repositories where Claude-related files cannot be committed.

The goal is to enable user to work with Claude Code effectively and efficiently in any Git repository (across its worktrees), even without leaving any trace of Claude Code usage in committed files.

## Main features

- Git only.
  - Git must be available on $PATH.
  - Avoids replicating Git features — only implements helpful add-on layer.
- Detects **current repo** at call-site.
  - Distinguishes each current repo by path to its **main worktree** (path to its main `.git` directory).
  - Distinguishes the main worktree from the other worktrees.
  - Distinguishes the **current worktree** as the worktree from which this command was called (can be the main or any other).
- Worktree model (v3): worktrees fold into Claude Code's own location.
  - A **managed** worktree lives at `<main worktree>/.claude/worktrees/<name>` — the same path `claude --worktree` uses, so clc-created and Claude-Code-created worktrees are indistinguishable and equally managed.
  - A worktree anywhere else (a checkout outside that dir) is **foreign**: still listed and launchable, but never auto-removed by `rm`/`prune` (adopt it first with `clc name`).
  - The nested worktrees are kept out of the second brain by `_nested_git_boundaries` (they are separate projects); creating a worktree under `.claude/worktrees/` therefore assumes the brain is locally ignored (`clc enroll`/`ignore`), or the main tree shows it as untracked.
  - `clc go` is the one-verb resume-or-create launcher; `clc name` renames a worktree's directory (and adopts a foreign one); `rm`/`prune`/`pull`/`close` operate on managed worktrees by **selector** (index/name/branch/unique-prefix). The **brain** actions (`ls`/`save`/`compare`/`diff`/`restore`/`reconcile`) also take an optional trailing selector via `resolve_target_worktree` — resolution-only (never creates), defaulting to the current worktree when omitted, mutually exclusive with `--all`.
- Defines **Claude-related files** as:
  - `CLAUDE.md` file (at any depth of worktree).
  - `/.claude/` directory (only in the root of worktree) with all contents.
- Manages Claude-related files (the "second brain") per worktree.
  - Allows ignoring these files locally (via `.git/info/exclude`).
  - **Enrollment** (`enroll`) fully manages a repo; `save`/`compare`/`restore` operate against the central git store; `ignore`/`unignore` are the gitignore-only step.

## Mission (the two-slice model)

clc serves projects that need plausible deniability of agentic usage — or that simply don't want to commit a Claude "second brain" into their own VCS. It provides separate version management in two cleanly separated slices:

- **Slice A — main code:** version-controlled in place, in the project's own git repo. The second brain never enters it.
- **Slice B — second brain:** *also* version-controlled, but separately and centrally — one git-backed store per machine holds the second brains of all enrolled projects, with optional auto-backup (git remote and/or local bundle) for cross-machine durability.

The owner (this machine's user) is the **prime** audience; published is secondary. Design owner-first, keep it clean enough to ship.

## Architecture (v2)

- **Central store** — a non-bare git repo at `$(clc_data_dir)/store` (default `~/.local/share/clc/store`). Its working tree mirrors each enrolled project's second brain under a **HOME-relative path** (e.g. `Developer/clc/CLAUDE.md`). Real git history replaces v1's timestamp snapshots. `save`/`restore`/`compare`/`diff`/`ls`/`go` all back onto the store HEAD mirror.
  - Sync (`store_sync_project`) is **copy-based, delete-aware, and subtree-scoped**: it re-materializes only that project's `-- "$rel"` subtree (removes orphans, copies current brain, commits), so a concurrent project's in-flight subtree is never swept. Submodule subtrees are skipped (they are nested projects). This is the single most bug-prone area — keep every git path `$rel`-scoped.
- **Registry / manifest** — committed *into* the store at `.clc/registry`. Line-oriented TAB-separated text (`<HOME-relative path> TAB <origin-url> [TAB meta…]`), **sorted on every write**, atomic (`render → .tmp → mv`). It is both the local registry and the cross-machine cold-start manifest. (Config uses git-config; the registry uses text because a multi-machine-synced manifest merges far more cleanly as sorted one-line-per-project text.)
- **Identity = HOME-relative path** of the **main worktree**. A repo outside `$HOME` has no identity → error, never guess. Moves are handled by an explicit `clc relink` (a fresh clone has no stable ID anyway, and a silent cross-machine move is a footgun).
- **Enrollment (4 steps)** — `enroll` = local-gitignore the brain + register in the manifest + install hooks + initial sync. `unenroll` reverses all four. `ignore`/`unignore` are aliases for the gitignore-only step.
- **Hooks** — `post-commit` + `post-merge` + `post-checkout`, installed **once** at the main gitdir (honoring `core.hooksPath`). Each is a fail-safe, non-blocking shim (`clc sync --from-hook … || true`) wrapped in a sentinel-marked block (`# >>> clc managed >>>` … `# <<< clc managed <<<`) — composes with husky/lefthook, never clobbers user content, cleanly uninstalls by sentinel. Cadence is **best-effort**: commit/merge/checkout fire; `git rebase` does *not* fire for replayed commits → manual `clc sync`. Direction-aware (v3.1): a **main** commit mirrors main → store (canonical trunk); a **peer** commit that is *strictly ahead and uncontested* auto-promotes its brain into store + main (notice to stderr), while a diverged/contested peer gets a rate-limited `clc reconcile` nudge (behind peers stay silent — they refresh on the next `clc go`).
- **Direction-aware reconciliation (v3.1)** — every worktree records a **baseline** (the store commit it last agreed with) in its private gitdir (`<gitdir>/clc-brain-baseline`; per-worktree, uncommitted, survives `clc name`, never walked into the brain). A 3-way classify (`_classify_brain`: baseline vs store vs worktree) labels each brain file **behind / ahead / diverged / same**, which drives the tiered automation: behind → fast-forward (take store), ahead → promote (store + main), diverged → prompt. `clc reconcile` is the read-only directional view; `clc reconcile --apply [-y]` resolves in place (a/b/c per diverged file, or safe-only under `-y`). `restore` warns about data loss only for genuine local-only (ahead/diverged) content. A missing baseline (legacy worktree, or one made by `claude --worktree`) is handled two ways (v3.3): (1) **self-healing** — `baseline_seed_if_synced` records a baseline the first time `clc go`-resume or a hook observes the worktree fully in sync with the store, so the gap stops arising; (2) **inferred direction** — `_classify_brain` takes the main worktree and, with no baseline, labels a worktree-present difference **ahead** when the store copy still equals main's (an uncontested trunk) and **diverged** otherwise. Inference drives the human view and explicit `clc reconcile --apply`/`clc save`, but the silent commit-hook auto-promote stays gated on a **real** baseline (`_CL_UNKNOWN -eq 0`) — an inferred-ahead peer could be stale, so it only nudges. `clc fsck [--fix]` reconciles store working-tree↔index, reporting/removing the untracked orphans the pre-v3.1 orphan-removal bug could strand.
- **Backups** — git-config subsections in the config file (`[clc "backup.<name>"] kind = remote|bundle; …`). Decoupled from the per-commit store sync: a successful sync triggers a **debounced** (default 15 min, configurable), **backgrounded, fail-safe** push to all targets; `clc backup` forces an immediate synchronous push. Bundle targets write a single small blob rotated atomically with `.prev`. Per-target last-success stamps + a failure log live under the state dir.
- **XDG locations** — config `~/.config/clc` (the `config` file; sync/track this), data `~/.local/share/clc` (store + registry), state `~/.local/state/clc` (locks, backup stamps/log). Defaults follow the XDG spec; `CLC_STORE` overrides the data/store root (back-compat + test isolation). Reads are guarded (`git config … || true`) so a missing key never trips `set -euo pipefail`.
- **Concurrency** — every store mutation takes a mandatory **mkdir-based** advisory lock (`with_store_lock`, no `flock` dependency) under the state dir.
- **Cross-machine** — **surface, don't auto-apply**: `clc doctor` reports missing / origin-drift / unregistered read-only; `clc clone`/`adopt` cold-start guarded (never clobber a non-empty non-matching dir); `clc relink` re-keys a moved repo; `clc migrate` does a one-shot v1→v2 import (discover via the legacy `~/.clc/saved/*/full-path.txt`, verify via the local-gitignore signal, one current-brain commit — pre-v2 history is not replayed).

### Determinism seams (matter for development + testing)

The snapshot suite stays green by construction:

- **Routine output is content-derived, not history-derived.** `status`/`doctor` report sync *state* (in-sync / drifted / never-synced) by diffing the worktree brain against the store HEAD mirror — no SHAs, no dates. The one wall-clock exception is backup-staleness age in `status`/`doctor`, pinned via the `CLC_NOW` seam. Baselines hold a store SHA but live in the gitdir (never printed, never walked into the store/brain), so they don't leak into snapshots; `diff` prints repo-relative paths (`a/<rel>`, `b/<rel>`). The direction-aware hook nudges are rate-limited via the same `CLC_NOW` seam (`CLC_NUDGE_INTERVAL`).
- **Store commits keep real wall-clock dates** in production; a fixed clc identity + `commit.gpgsign=false` are stamped once into the store's own `.git/config` at `store_init` (no per-commit `-c`).
- **Harness** pins `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE` in fixtures, isolates `XDG_*_HOME` + `CLC_STORE`, applies one shared SHA-scrub (`%%SHA%%`) in `run.sh`, and uses `CLC_SYNC_SYNC=1` (synchronous backup push, capturable) + `CLC_NOW=<epoch>` (pins all wall-clock math) for backup tests. `CLC_LAUNCH_CMD` overrides the launched binary (default `claude`) so `go` tests point it at a deterministic stub instead of spawning Claude Code.

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
