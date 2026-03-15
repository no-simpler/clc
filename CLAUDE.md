**Claude Code Cloak (`clc`)** is a single-file bash utility (`clc.sh`) that manages Git worktrees (for using with Claude Code) and helps obfuscate usage of Claude Code in repositories where Claude-related files cannot be committed.

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
- Manages Claude-related files only in managed worktrees.
  - Allows ignoring these files locally (via `.git/info/exclude`).
  - Allows saving Claude files from a current worktree to `~/.clc/` (saved per current repo).
  - Allows restoring Claude files from `~/.clc/` to current worktree.
  - Allows comparing current worktree against the latest saved state.

## Storage design

- Saves Claude-related files to `~/.clc/saved/<name>@<md5>/`
  - `<name>` = basename
  - `<md5>` = md5 hash of the **resolved absolute path** of the **main worktree** (not the current worktree).
- Saved files are keyed by main worktree path, not current worktree.
  - All worktrees of the same repo share one storage namespace.
  - This is intentional: Claude files are conceptually repo-wide.

Sample layout under the save base:

```
~/.clc/saved/<name>@<md5>/
  full-path.txt          # path used for <md5> (for human browsing)
  <unix-timestamp>/      # one directory per save
    CLAUDE.md            # Claude-related files pulled from repo
    docs/CLAUDE.md
    .claude/settings.json
    ...
```

## Conventions

Compartmentalized code. Short, readable functions. Succinct comments where it aids readability. Aim for extendability. Industry standards for shell scripting. Human-friendly, formatted, informative output. When called without arguments, actions limited to read-only (always safe to call without arguments). Support options. Action specified as first non-option argument.

Output style: section headers via `print_header`; muted secondary info via `CLR_MUTED`; warnings via `print_warning_line` / `CLR_WARN`. `--no-color` (or `NO_COLOR` env, or non-TTY stdout) disables all ANSI codes.

## Development loop

No compilation necessary, script should remain a single file and be runnable from it. Remember to always keep --help output in sync with latest features.

When invoking `git commit` (e.g., publishing a version, verification loop), make sure to disable commig signing to prevent in-terminal “full screen” GPG pop-ups that break the flow.

## Verification loop

`test/run.sh` is the snapshot test runner. See `test/CLAUDE.md` for full details on the test system and how to add new tests.

```bash
bash test/run.sh               # run all cases (exit 1 on any diff)
bash test/run.sh base          # run a single case
bash test/run.sh --update      # regenerate all snapshots
bash test/run.sh --update base # regenerate snapshots for one case
```

When adding a feature, run `--update` after verifying the new output is correct, then commit the updated snapshots alongside the code change.
