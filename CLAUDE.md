**Claude Code Cloak (`clc`)** is a single-file bash utility (`clc.sh`) that helps obfuscate usage of Claude Code in repositories where Claude-related files cannot be committed. The goal is to work with Claude Code effectively and efficiently in any Git repository (and its subordinate worktrees) without leaving any trace of Claude Code usage in committed files.

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
  - Path convention for managed peer worktree: if main worktree is at `/repos/main-repo`, managed peer peer worktree is at `/repos/main-repo-[worktree-name]`.
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

## Storage design (`save` / `compare` / `restore`)

Files are saved to `~/.clc/saved/<name>@<md5>/` where `<name>` is the basename and `<md5>` is the md5 hash of the **resolved absolute path** of the **main worktree** (not the current worktree). This keys storage per repo, not per worktree.

Layout under the save base:
```
~/.clc/saved/<name>@<md5>/
  full-path.txt          # the resolved path used for the hash (for human browsing)
  <unix-timestamp>/      # one directory per save; timestamp = seconds since epoch
    CLAUDE.md
    docs/CLAUDE.md
    .claude/settings.json
    ...
```

Key design decisions:
- **Keyed by main worktree path, not current worktree.** All worktrees of the same repo share one storage namespace. This is intentional: Claude files are conceptually repo-wide.
- **`latest_save_dir` filters to numeric-only dir names** (`grep -E '^[0-9]+$'`) so `full-path.txt` and any other metadata files in the save base are never mistaken for timestamp snapshots.
- **`_compare_claude_files` populates four globals** (`_CMP_SAME`, `_CMP_DIFFERENT`, `_CMP_ONLY_STORAGE`, `_CMP_ONLY_WORKTREE`) so both `compare` and `restore` can share comparison logic without re-running it. Reset at the top of each call.
- **`cmd_restore` does NOT call `cmd_compare`** — it calls `_compare_claude_files` and `_print_compare_output` directly. This avoids `set -e` triggering on `cmd_compare`'s `return 1` exit code before restore can do its work.
- **`clc ls` includes storage comparison** inline after the file list. Uses `_compare_claude_files` directly (not `cmd_compare`) so the exit code doesn't surface as an error.
- **Suggestion line** ("Run 'clc save' to save current state; run 'clc restore' to load saved state.") is printed by both `cmd_compare` and `cmd_ls` when diffs exist, but NOT by `cmd_restore` (user is already in restore context).
- **`CLC_STORE` is overridable via env var** for test isolation. Tests set `export CLC_STORE="${CASE_DIR}/.clc-store"` to avoid touching `~/.clc` and ensure deterministic snapshots.
- **Bash 4+ is required** (checked at startup). `declare -A` / `local -A` for associative arrays is used in `_compare_claude_files`.

## Conventions

Compartmentalized code. Short, readable functions. Succinct comments where it aids readability. Aim for extendability. Industry standards for shell scripting. Human-friendly, formatted, informative output. When called without arguments, actions limited to read-only (always safe to call without arguments). Support options. Action specified as first non-option argument.

Output style: section headers via `print_header`; muted secondary info via `CLR_MUTED`; warnings via `print_warning_line` / `CLR_WARN`. `--no-color` (or `NO_COLOR` env, or non-TTY stdout) disables all ANSI codes.

## Development loop

No compilation necessary, script should remain a single file and be runnable from it. Remember to always keep --help output in sync with latest features.

Do not commit code yourself. When calling `git commit` for other reasons (e.g., verification loop), make sure to disable commig signing to prevent commit pop-ups that break the flow.

## Verification loop

`test/run.sh` is the snapshot test runner. See `test/CLAUDE.md` for full details on the test system and how to add new tests.

```bash
bash test/run.sh               # run all cases (exit 1 on any diff)
bash test/run.sh base          # run a single case
bash test/run.sh --update      # regenerate all snapshots
bash test/run.sh --update base # regenerate snapshots for one case
```

When adding a feature, run `--update` after verifying the new output is correct, then commit the updated snapshots alongside the code change.
