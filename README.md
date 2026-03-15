# clc — Claude Code Cloak

> Use Claude Code effectively in any repo — without leaving traces.

[![Latest Release](https://img.shields.io/github/v/release/no-simpler/clc)](https://github.com/no-simpler/clc/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Why

Many repos disallow Claude-related files (`CLAUDE.md`, `.claude/`) from being committed — company policy, open-source norms, or just keeping things clean. But you still want Claude Code's full capabilities: custom instructions, project context, and settings that follow you across branches.

`clc` solves this by managing your Claude files outside of git while keeping them available in any worktree. Save once, restore anywhere — no trace left in committed history.

## Installation

### Homebrew (recommended)

```bash
brew tap no-simpler/clc
brew install clc
```

### curl installer

```bash
curl -fsSL https://github.com/no-simpler/clc/releases/latest/download/install.sh | bash
```

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

# Keep Claude files out of git (one-time setup per worktree)
clc ignore

# Save your Claude files to ~/.clc/
clc save

# Create a new worktree and restore your Claude files into it
clc new -c my-feature

# Check if your current worktree is in sync with the saved state
clc compare
```

## Commands

### Inspect

| Command | Description |
|---------|-------------|
| `clc` / `clc status` | Show repository info and managed worktrees |
| `clc ls` | List Claude-related files. Tracked or git-visible files are marked. |

### Claude files

| Command | Description |
|---------|-------------|
| `clc ignore` | Add Claude-related patterns to `.git/info/exclude` |
| `clc unignore` | Remove Claude-related patterns from `.git/info/exclude` |
| `clc save` | Save Claude-related files from the current worktree to `~/.clc/saved/` |
| `clc compare` | Compare current worktree against the latest saved state (exit 0 = in sync) |
| `clc restore` | Restore Claude files from the latest saved state. Prompts before changes. |

### Worktrees

| Command | Description |
|---------|-------------|
| `clc new [-c] <name> [<branch>]` | Create a new managed peer worktree. `-c` restores Claude files. |
| `clc rm [-b] <name>` | Remove a managed peer worktree. |
| `clc prune [-b]` | Remove all clean, non-current managed peer worktrees. |

**Flags**: `-b` / `--with-branch` (rm, prune) also deletes the git branch. `-c` / `--with-claude` (new) restores Claude files after creation.

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
/repos/other-location      ← unmanaged (clc won't touch it)
```

### Storage layout

Claude files are saved to `~/.clc/saved/` keyed by repo (not worktree), so all worktrees of a repo share one saved state:

```
~/.clc/saved/<repo-name>@<hash>/
  full-path.txt           # human-readable path
  <timestamp>/            # one directory per save
    CLAUDE.md
    docs/CLAUDE.md
    .claude/settings.json
    ...
```

## Development

```bash
# Run all tests
bash test/run.sh

# Run a single test case
bash test/run.sh base

# Regenerate snapshots after intentional output changes
bash test/run.sh --update
bash test/run.sh --update base
```

See `test/CLAUDE.md` for full details on the test system and how to add new cases.
