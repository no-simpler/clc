**Claude Code Cloak (`clc`)** is a single-file bash utility (`clc.sh`) that helps obfuscate usage of Claude Code in repositories where Claude-related files cannot be committed. The goal is to work with Claude Code effectively and efficiently in any Git repository (and its subordinate worktrees) without leaving any trace of Claude Code usage in committed files.

## Main features

- Git only.
  - Git must be available on $PATH.
  - Avoids replicating Git features — only implements helpful add-on layer.
- Detects **current repo** at call-site.
  - Distinguishes each current repo by **main path** (path to its main `.git` directory, not path to current worktree).
  - Distinguishes worktree at main path from peer worktrees (any other worktree).
- Manages peer worktrees that follow convention.
  - If main repo is at `/repos/main-repo`, manages only peer worktrees at `/repos/main-repo-[worktree-name]`.
  - Allows easily creating and deleting managed worktrees.
  - Does not go too deep into worktree management.
- Manages `CLAUDE.md` files (at any depth) and `/.claude/` directory for current repo.
  - Allows ignoring these files locally (via `.git/info/exclude`).
  - Saves current Claude files: moves managed files to local storage at `~/.clc/` (grouped by main path).
  - Restores previously saved Claude files: moves managed files from

## Conventions

Compartmentalized code. Short, readable functions. Succinct comments where it aids readability. Aim for extendability. Industry standards for shell scripting. Human-friendly, formatted, informative output. When called without arguments, actions limited to read-only (always safe to call without arguments). Support options. Action specified as first non-option argument.

## Development loop

No compilation necessary, script should remain a single file and be runnable from it.
