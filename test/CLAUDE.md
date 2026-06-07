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

## Running against multiple Bash versions

When the current machine has multiple Bash versions available (e.g. `/bin/bash` is 3.2 and a Homebrew-installed `bash` is 5.x), run the test suite against each distinct version:

```bash
/bin/bash test/run.sh
/usr/local/bin/bash test/run.sh   # or wherever the newer version lives
```

`$BASH` is used throughout the runner and case scripts so the same version is used end-to-end for each invocation.

## Key conventions

- All `clc` invocations in case scripts must use `--no-color`.
- All `clc` invocations that trigger commit-creating actions (`pull`, `close`) must also use `--no-gpg`.
- Silent setup calls (e.g., pre-applying `clc ignore` before testing `clc unignore`) must suppress their output: `clc --no-color ignore > /dev/null`.
- Use `git -c commit.gpgsign=false commit` for any commits in case scripts.
- `test/playground/` is gitignored; never commit anything from there.

## Storage isolation

Tests that invoke `clc ls`, `clc save`, `clc compare`, or `clc restore` must isolate storage by exporting `CLC_STORE` before any `clc` call:

```bash
export CLC_STORE="${CASE_DIR}/.clc-store"
```

This prevents tests from reading or writing `~/.clc` and ensures snapshots are deterministic across runs.

## XDG isolation

The runner also isolates the XDG base dirs per case. Before each case runs, `run_case()` exports `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, and `XDG_STATE_HOME` under `test/playground/<case>/.xdg/` (auto-cleaned by the per-case `rm -rf`). This applies to both the case-script subprocess and the direct `clc` invocations in the runner, so clc's v2 config/data/state (`config`, the git-backed store, locks/logs) never touch the real `~/.config`, `~/.local/share`, or `~/.local/state`. Cases that need a stable path in their asserted output may still override `XDG_CONFIG_HOME` to a fixed subpath (see `config-roundtrip.sh`).

## Path placeholders in snapshots

The runner normalizes machine-specific paths before comparing against snapshots:

- `%%PARENT_DIR%%` — the parent directory of the repo's managed worktrees, in `~`-shortened form. Used for **display paths** that `clc` emits via `short_path`. If `clc` fails to shorten a path, the absolute form appears in the output instead and the snapshot will not match (intentional: this is how the test detects the regression).
- `%%PARENT_DIR_ABS%%` — same directory in absolute form, for **raw file content** that is not processed by `short_path` (e.g. `full-path.txt`).
- `%%PARENT_DIR_HOME%%` — the same directory in **HOME-relative** form (no leading `~` or `/`). The v2 git store mirrors each project's second brain under a HOME-relative subtree path, which neither of the two placeholders above matches; this covers store/registry subtree paths.
- `%%SHA%%` — a git object SHA (7–40 hex chars) that history-surfacing output emits, e.g. `commit <sha>`. Applied as a shared scrub in `run.sh`. The scrub deliberately leaves git's `index <sha>..<sha>` diff lines alone (those are content-derived and stable) and avoids `\b` for BSD/macOS-sed portability.

## Storage = the git store mirror

`save`/`restore`/`compare`/`diff` (and the storage-comparison parts of `ls`/`new`) operate on the **git store mirror**: `clc save` is an alias for `clc sync`, and "storage" is the project's HEAD-committed subtree under `$(clc_store_dir)/<HOME-relative main-worktree path>` (the legacy `~/.clc/saved/<name>@<md5>/<timestamp>` snapshots are gone). Routine output is content-derived (in-sync / diff state), so it is snapshot-stable by construction — no timestamp or MD5 normalization is needed.

When a case asserts store contents or store-relative paths directly (file listings, `diff`'s git-diff paths), strip the machine-specific subtree prefix with sed against a `<project>`/`<save>` placeholder, following `sync-basic.sh`, `save-basic.sh`, and `diff-diffs.sh`:

```bash
STORE="${CLC_STORE}/store"          # or "${XDG_DATA_HOME}/clc/store" when CLC_STORE is unset
MAIN_WT="$(cd "${CASE_DIR}/main" && pwd)"
PREFIX="${MAIN_WT#${HOME}/}"
git -C "${STORE}" ls-files | sed "s|^${PREFIX}/|<project>/|"
```

Pin `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE` in the case (as `sync-basic.sh` does) so any leaked store-commit history stays deterministic; only explicit history commands surface SHAs, which `run.sh` scrubs to `%%SHA%%`.

## Backups (P6)

Backup tests (`backup-bundle.sh`, `backup-remote.sh`, `backup-debounce.sh`) exercise the store-push machinery (§4.9/§6.2) through its two determinism seams:

- **`CLC_SYNC_SYNC=1`** — makes the post-sync backup push run **synchronously** (no `& disown`), so the harness can observe its effect and capture `clc backup` output. Every backup test must export this to avoid async races.
- **`CLC_NOW=<epoch>`** — pins **all** wall-clock math: the debounce comparison and the `status` Backups staleness age. Export it (or pass per-invocation, as `backup-debounce.sh` does) so both stay deterministic.

Conventions:

- Configure targets by writing the clc config directly: `mkdir -p "${XDG_CONFIG_HOME}/clc"` then `git config -f "${XDG_CONFIG_HOME}/clc/config" clc.backup.<name>.kind …` (the raw `git config -f` needs the dir to exist first; clc's own `config_set` mkdirs, but tests bypass it). Target `<name>` must not contain dots.
- Do **not** snapshot bundle/remote contents (they carry SHAs/dates). Assert **existence + `git bundle verify`** (bundle) or **`git -C remote.git rev-parse --verify <branch>`** (remote), and `echo` a fixed OK line into the action snapshot instead of the verify output.
- A bare remote created under the case dir would be picked up by the runner's `*/` worktree discovery and produce a spurious (error) snapshot. Place it under a **dot-dir** (`${CASE_DIR}/.remote/remote.git`) so the glob skips it.
- The per-worktree `output.<wt>.txt` status snapshots are **omitted** for backup cases: the runner runs those plain `clc` invocations without `CLC_NOW`, so the staleness age would be wall-clock-relative and drift daily. The deterministic Backups-status coverage lives in the **action** snapshot instead (a `clc status` call made inside the case script with `CLC_NOW` pinned → e.g. "just now"). Compare mode only checks snapshots that exist, so deleting the auto-generated `output.main.txt` after `--update` keeps the case green.
