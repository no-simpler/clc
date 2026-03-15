# clc — Claude Code Cloak

> Use Claude Code effectively in any repo — without leaving traces.

[![Latest Release](https://img.shields.io/github/v/release/no-simpler/clc)](https://github.com/no-simpler/clc/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Why

In some repos, committing Claude-related files (`CLAUDE.md`, `.claude/`) may be undesirable. But you still want Claude Code's full capabilities: custom instructions, project context, and settings that follow you across branches.

`clc` solves this by managing your Claude files outside of git while keeping them available in any worktree. Save once, restore anywhere — no trace left in committed history.

All `clc` actions are either non-destructive or prompt for confirmation before making changes.

## Installation

### curl installer (recommended)

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

**Requirements**: bash 4.0+, git

## Quick start

```bash
# In any git repo — see current status
clc

# List Claude files detected in this worktree
clc ls

# Keep Claude files out of git (one-time setup per repository)
clc ignore

# Save your Claude files to ~/.clc/
clc save

# Create a new worktree and restore your Claude files into it
clc new my-feature # (worktree `my-feature`, Git branch `my-feature`)
# or
clc new feature/CC-123-short-name # (worktree `short-name`, Git branch `feature/CC-123-short-name`)
# or
clc new tree-name some/specific/branch-name # (worktree `tree-name`, Git branch `some/specific/branch-name`)

# Check if Claude files in your current worktree are in sync with the saved state
clc compare

# Safely discard worktree and its branch (rejects destructive actions)
clc rm my-feature
clc rm short-name
clc rm tree-name
# or
clc prune # removes all clean managed worktrees
```

## Commands

### Inspect

| Command              | Description                                                         |
| -------------------- | ------------------------------------------------------------------- |
| `clc` / `clc status` | Show repository info and managed worktrees                          |
| `clc ls`             | List Claude-related files. Tracked or git-visible files are marked. |

### Claude files

| Command        | Description                                                                |
| -------------- | -------------------------------------------------------------------------- |
| `clc ignore`   | Add Claude-related patterns to `.git/info/exclude`                         |
| `clc unignore` | Remove Claude-related patterns from `.git/info/exclude`                    |
| `clc save`     | Save Claude-related files from the current worktree to `~/.clc/saved/`     |
| `clc compare`  | Compare current worktree against the latest saved state (exit 0 = in sync) |
| `clc restore`  | Restore Claude files from the latest saved state. Prompts before changes.  |

### Worktrees

| Command                                   | Description                                                              |
| ----------------------------------------- | ------------------------------------------------------------------------ |
| `clc new [--no-claude] <name> [<branch>]` | Create a new managed peer worktree. Restores Claude files by default.    |
| `clc rm [--keep-branch] <name>`           | Remove a managed peer worktree and its branch.                           |
| `clc prune [--keep-branch]`               | Remove all clean, non-current managed peer worktrees and their branches. |

**Flags**: `--keep-branch` (rm, prune) keeps the git branch instead of deleting it. `--no-claude` (new) skips restoring Claude files after creation.

## How it works

### Claude-related files

`clc` manages two kinds of files:

- `CLAUDE.md` — at any depth within the worktree
- `.claude/` — only at the worktree root

### Managed worktrees

A worktree is "managed" if it is the main worktree or a peer worktree following the path convention:

```
/repos/my-project          ← main worktree
/repos/my-project-feature  ← managed peer (name: "feature")
/repos/my-project-hotfix   ← managed peer (name: "hotfix")
/repos/other-location      ← unmanaged peer
```

### Storage layout

Claude files are saved to `~/.clc/saved/` keyed by repo (not worktree), so saves from any worktree accumulate in one place. Each save is stored by timestamp for data-loss protection; only the latest is used.

```
~/.clc/saved/<repo-name>@<hash>/
  full-path.txt           # human-readable path
  <timestamp>/            # one directory per save
    CLAUDE.md
    docs/CLAUDE.md
    .claude/settings.json
    ...
```
