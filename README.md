# clc — Claude Cloak

> Version-control your Claude "second brain" separately from your code — never in the project's own git, durable across machines.

[![Latest Release](https://img.shields.io/github/v/release/no-simpler/clc)](https://github.com/no-simpler/clc/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Why

Some projects can't (or shouldn't) commit Claude Code's files — `CLAUDE.md`, `.claude/` — into their own version control. But that "second brain" is real, evolving work you still want versioned, recoverable, and carried across your machines.

`clc` keeps the two slices cleanly separated:

- **Slice A — your code** stays version-controlled in place, in the project's own git repo. The second brain **never enters it.**
- **Slice B — your second brain** is *also* version-controlled, but **separately and centrally**: one git-backed store per machine holds the second brains of **all** enrolled projects, with real git history. Optional **auto-backup** (push to a private git remote and/or write a local bundle) makes it durable across machines.

As an enrolled project evolves, its second brain evolves alongside it **mostly automatically** — committed into the store on the same cadence as your code commits (via git hooks) — without ever leaving a trace in the project's own history. The result is full Claude Code capability with plausible deniability of agentic usage.

All `clc` actions are either non-destructive or prompt before making changes; cross-machine reconciliation never clobbers existing directories.

## Key concepts

- **Second brain** — a project's Claude files: `CLAUDE.md` at any depth + the `.claude/` directory at the worktree root. Conceptually repo-wide (one per repo).
- **Enrolled project** — a repo `clc` actively manages: its second brain is locally-gitignored, it has a registry entry, sync hooks are installed, and its brain is mirrored into the central store.
- **Central store** — a per-machine **git repository** (at `~/.local/share/clc/store`) whose working tree mirrors every enrolled project's second brain under a HOME-relative path. Real git history is the version record for Slice B.
- **Registry / manifest** — the index of enrolled projects, committed *into* the store (so it's portable and auto-backed-up). Maps each project (by HOME-relative path) to its origin URL. Doubles as the cross-machine cold-start manifest.
- **Backup target** — a configured destination the store is pushed to: a **git remote** or a **local bundle** blob.
- **Worktree** — a checked-out working directory of a repo. Every repo has a **main worktree** (where `.git` lives); **peer worktrees** can be added. `clc` manages peers that follow its [path convention](#managed-worktrees).

## Installation

### Homebrew (recommended)

```bash
brew install no-simpler/tap/clc
```

To upgrade later: `brew upgrade clc`

### curl installer

```bash
curl -fsSL https://github.com/no-simpler/clc/releases/latest/download/install.sh | bash
```

> **Note**: This installs the version available at that moment. To update, re-run the command.

### Manual

Download `clc.sh`, place it somewhere on your `$PATH` as `clc`, and make it executable:

```bash
curl -fsSL https://github.com/no-simpler/clc/releases/latest/download/clc.sh -o ~/.local/bin/clc
chmod +x ~/.local/bin/clc
```

**Requirements**: bash 3.2+, git

## Quick start

```bash
# In any git repo — see status (enrollment, hooks, backups, worktrees)
clc

# List Claude files detected in this worktree
clc ls

# Fully manage this repo: gitignore the brain, register it, install sync
# hooks, and sync the brain into the central store. (One-time per repo.)
clc enroll

# From now on, committing in this repo auto-syncs the brain into the store.
git commit -m "work"          # post-commit hook mirrors the brain into the store

# Manually sync / compare / restore the brain against the store at any time
clc save                       # sync current worktree's brain into the store
clc compare                    # in sync with the store? (exit 0 = yes)
clc diff                       # full git diff of any mismatch
clc restore                    # pull the stored brain into this worktree (prompts)
clc reconcile                  # read-only 3-way view: worktree vs store vs main

# Worktrees — create a peer, work, transplant back, clean up
clc go my-feature              # create-or-resume worktree + branch, brain seeded, launch claude
clc go feature/CC-123-name     # worktree "name", branch "feature/CC-123-name"
clc pull my-feature            # stage a peer's changes onto the current branch
clc pull -c my-feature         # stage and commit
clc close my-feature           # pull, then remove the worktree + branch
clc rm my-feature              # remove a clean peer worktree + branch
clc prune                      # remove all clean managed peer worktrees
```

### Configure a backup target

Backup targets are git-config subsections in `~/.config/clc/config`. Configure at least one so the store is durable beyond local disk:

```bash
# A git remote (e.g. a private GitHub repo) — cheap, incremental
git config -f ~/.config/clc/config clc.backup.github.kind remote
git config -f ~/.config/clc/config clc.backup.github.url  git@github.com:me/clc-store.git

# A local bundle blob (e.g. an iCloud-backed path) — single small file, rotated
# (~/Documents is iCloud-backed when "Desktop & Documents Folders" sync is on)
git config -f ~/.config/clc/config clc.backup.icloud.kind bundle
git config -f ~/.config/clc/config clc.backup.icloud.path '~/Documents/clc-store.bundle'
```

A successful sync triggers a **debounced** (default 15 min), backgrounded, fail-safe push to all targets. Force an immediate push anytime:

```bash
clc backup                     # push the store to every target now (ignores debounce)
```

### Cross-machine cold start

On a fresh machine, restore the store from a backup into `~/.local/share/clc/store` (`git clone <remote>` or unbundle the blob), then:

```bash
clc clone                      # for each registered project: clone its origin to its
                               # HOME-relative path, deploy the brain, install hooks
clc adopt                      # like clone, but only into already-present matching repos
clc doctor                     # read-only: report missing / origin-drift / unregistered
clc relink                     # after moving a repo: re-key the registry + move the subtree
```

`clone`/`adopt` are **guarded** — they never clobber a non-empty, non-matching directory.

### Migrating from v1

v1 saved timestamp snapshots under `~/.clc/saved/`. Import them once:

```bash
clc migrate                    # discover clc-touched repos from the legacy store and
                               # enroll them (idempotent; pre-v2 history is not replayed)
```

## Commands

### Inspect

| Command              | Description                                                       |
| -------------------- | ---------------------------------------------------------------- |
| `clc` / `clc status` | Show repo info, enrollment, hooks, backup staleness, worktrees   |
| `clc ls` / `clc list`| List Claude files. Tracked or git-visible files are marked.      |

### Claude files

| Command        | Description                                                                       |
| -------------- | -------------------------------------------------------------------------------- |
| `clc enroll`   | Gitignore the brain, register the repo, install sync hooks, sync into the store  |
| `clc unenroll` | Reverse enroll: deregister, remove hooks, drop the brain from the store, un-ignore |
| `clc ignore`   | Add Claude file patterns to `.git/info/exclude` (gitignore-only step)            |
| `clc unignore` | Remove Claude file patterns from `.git/info/exclude`                             |
| `clc save`     | Sync the current worktree's brain into the central store (alias for `sync`). `--force-empty` allows erasing the store from an empty brain |
| `clc compare`  | Compare current worktree against the stored state (exit 0 = in sync)             |
| `clc diff`     | Like compare, but prints a full git diff for all mismatches                      |
| `clc restore`  | Restore Claude files from the stored state. Prompts before changes.              |
| `clc reconcile`| Read-only 3-way view of the brain across the current worktree, store, and main   |
| `clc backup`   | Force an immediate push of the store to all configured backup targets            |

### Worktrees

| Command                                   | Description                                                              |
| ----------------------------------------- | ------------------------------------------------------------------------ |
| `clc new [-n\|--no-claude] <name> [<branch>]` | Create a managed peer worktree. Restores the brain by default.       |
| `clc rm [-k\|--keep-branch] <name>`       | Remove a managed peer worktree and its branch.                          |
| `clc prune [-k\|--keep-branch]`           | Remove all clean, non-current managed peer worktrees and their branches. |

### Transplant

| Command                                          | Description                                                                                      |
| ------------------------------------------------ | ----------------------------------------------------------------------------------------------- |
| `clc pull [-c\|--commit] <name>`                 | Transplant all changes from a peer worktree's branch onto the current branch as staged changes.  |
| `clc close [-c\|--commit] [-k\|--keep-branch] <name>` | Same as pull, then removes the peer worktree and deletes its branch.                       |

### Cross-machine

| Command                  | Description                                                                          |
| ------------------------ | ----------------------------------------------------------------------------------- |
| `clc doctor`             | Report cross-machine drift (missing / origin drift / unregistered). Read-only.      |
| `clc relink [<old-path>]`| Re-key a moved repo: rewrite the registry and move its store subtree.                |
| `clc clone`              | Cold-start: clone each registered repo, deploy the brain, install hooks. Guarded.    |
| `clc adopt`              | Like clone but never clones — deploy brain + hooks into already-present repos.        |
| `clc migrate`            | One-shot v1→v2: enroll clc-touched repos discovered in the legacy `~/.clc/saved` store. |

**Flags**: `-k, --keep-branch` (rm, prune, close) keeps the git branch instead of deleting it. `-n, --no-claude` (new) skips restoring the brain after creation. `-c, --commit` (pull, close) commits immediately after staging. Global: `--no-color` disables ANSI output; `--no-gpg` suppresses GPG commit signing.

## How it works

### Managed worktrees

A worktree is "managed" if it is the main worktree or a peer worktree following the path convention:

```
/repos/my-project          ← main worktree
/repos/my-project-feature  ← managed peer (name: "feature")
/repos/my-project-hotfix   ← managed peer (name: "hotfix")
/repos/other-location      ← unmanaged peer
```

### The central store

The store is a normal (non-bare) git repo whose working tree mirrors each enrolled project's second brain under its **HOME-relative path**. You can `cd` into it and browse every brain. Real git history replaces v1's timestamp snapshots.

```
~/.local/share/clc/store/            ← a git repo
  .clc/registry                      ← the manifest (committed; sorted, tab-separated)
  Developer/clc/CLAUDE.md
  Developer/clc/.claude/settings.json
  Developer/halo/CLAUDE.md
  work/foo/.claude/...
```

Sync is **copy-based** (the brain stays as real, locally-gitignored files in your worktree — Claude Code reads/writes them normally), **delete-aware**, and **subtree-scoped**: a sync only ever touches that one project's subtree, removing orphaned files and committing the change. Concurrent syncs serialize behind a mkdir-based store lock.

### XDG locations

| Kind   | Location (default)                  | Holds                                  |
| ------ | ----------------------------------- | -------------------------------------- |
| config | `~/.config/clc` (`$XDG_CONFIG_HOME`)| `config` (backup targets) — sync this  |
| data   | `~/.local/share/clc` (`$XDG_DATA_HOME`) | `store/` (git repo) + registry      |
| state  | `~/.local/state/clc` (`$XDG_STATE_HOME`)| locks, backup stamps + log          |

`CLC_STORE` overrides the data/store root (back-compat + test isolation).

### Auto-sync via hooks

`clc enroll` installs `post-commit`, `post-merge`, and `post-checkout` hooks (once, at the main `.git`; composes with existing hooks / `core.hooksPath` via a sentinel-marked block, never clobbering your content). Each calls `clc sync --from-hook` fail-safe — it never blocks or fails your commit.

Cadence is **best-effort**: synced on commit, merge, and checkout. `git rebase` does **not** fire these for replayed commits — if the brain changed mid-rebase, run `clc sync` (or `clc save`) manually. The store mirrors the **main worktree** (canonical), regardless of which worktree fired the hook — so a commit in a feature worktree can never clobber or wipe the stored brain. A guard also refuses to erase a populated store from an empty worktree brain (override with `clc save --force-empty`). When a peer worktree's brain has diverged, the hook prints a one-line nudge; promote those edits deliberately with `clc save` (or pull the stored brain with `clc restore`), and use `clc reconcile` to see the 3-way delta.

### Backups

Pushing to backup targets is **decoupled** from the per-commit store sync:

- **Debounced** — after a successful sync, targets are pushed no more often than the configured interval (default 15 min; set `clc.backup.interval` or a per-target `interval`). `clc backup` forces an immediate push.
- **Backgrounded + fail-safe** — the push survives the parent shell, never blocks the commit; an offline/unauthed target warns + logs (under `~/.local/state/clc`), never fails the commit. Staleness is surfaced in `status` / `doctor`.
- **Target kinds** — a **git remote** (incremental `git push`) or a **local bundle** (a single small blob rewritten atomically with a `.prev` rotation, so an interrupted bundle never leaves zero valid copies).

### Conventions for a seamless cross-machine experience

1. **Uniform HOME-relative repo paths** across machines (`~/Developer/clc` everywhere). The HOME-relative path is the identity; divergence is reported by `clc doctor`, never silently reconciled.
2. **Sync `~/.config/clc`** (YADM or similar). Config uses `~`-relative paths; host-specific targets are skipped with a warning where they don't apply.
3. **Configure at least one backup target.** Without it, the store is not durable beyond local disk.
4. **Enroll / unenroll / relink via `clc`** — don't hand-edit the store or `.git/info/exclude`.
5. **Edit the brain in the main worktree.** Editing divergent brains in multiple peers simultaneously is unsupported (last commit wins; the store's git history is the recovery net).
