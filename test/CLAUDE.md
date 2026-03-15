# Test system

See also: `test/run.sh` (runner), `test/cases/` (case scripts), `test/expected/` (snapshots), `test/playground/` (gitignored runtime).

## How tests work

Each test has three parts:

1. **Case script** (`test/cases/<case>.sh`) — sets up worktrees under `test/playground/<case>/` and optionally calls `clc --no-color` to produce action output. Stdout is the action output; any debug or setup noise must be suppressed.

2. **Action snapshot** (`test/expected/<case>/output.action.txt`) — if present, asserted against the case script's stdout. Omit the file entirely for pure state-setup tests.

3. **Worktree snapshots** (`test/expected/<case>/output.<worktree>.txt`) — one per worktree to verify. The runner `cd`s into `test/playground/<case>/<worktree>/`, runs `clc --no-color` (no args), and diffs against the file.

## Creating a new test

**State test** (verify `clc` output from one or more worktrees):
1. Copy `test/cases/base.sh` as `test/cases/<case>.sh`; update `CASE_DIR` and adjust the worktree setup.
2. Run `bash test/run.sh --update <case>` — the runner discovers all worktrees and writes `output.<worktree>.txt` for each.
3. Review the generated snapshots, then commit them.

**Action test** (verify output of a specific `clc` command):
1. Same as above, but end the case script with one or more `clc --no-color <command>` calls (capturing their output on stdout).
2. Run `bash test/run.sh --update <case>` — writes `output.action.txt` from stdout, plus `output.<worktree>.txt` for any remaining worktrees.
3. Review, then commit.

## Key conventions

- All `clc` invocations in case scripts must use `--no-color`.
- Silent setup calls (e.g., pre-applying `clc ignore` before testing `clc unignore`) must suppress their output: `clc --no-color ignore > /dev/null`.
- Use `git -c commit.gpgsign=false commit` for any commits in case scripts.
- `test/playground/` is gitignored; never commit anything from there.
