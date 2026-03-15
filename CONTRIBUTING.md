# Contributing to clc

## Welcome

Bug fixes, new commands, and test coverage improvements are all welcome. clc is built with Claude Code and optimized for that workflow — contributions via Claude Code are encouraged.

## Setup

```bash
git clone https://github.com/sargeri/clc
cd clc
bash test/run.sh   # all tests should pass
```

No build step. clc is a single bash file (`clc.sh`).

## Working with Claude Code

The repo ships a `CLAUDE.md` at the root with full project conventions. Claude Code picks it up automatically when opened at the repo root.

If you want to keep local Claude files out of git in your fork, run:

```bash
clc ignore
```

This writes `CLAUDE.md` and `.claude/` to `.git/info/exclude` so they stay untracked without polluting `.gitignore`.

## Implementing a change

Suggested workflow:

1. Read the relevant section of `clc.sh` — sections are delimited by `# ── Section ──` headers.
2. Add or edit the test case in `test/cases/` — see `test/CLAUDE.md` for the test system.
3. Run `bash test/run.sh` and review output visually.
4. If the output looks correct, bless the snapshot:
   ```bash
   bash test/run.sh --update <case>
   ```

## Code conventions

Compartmentalized functions, succinct comments, match the existing style. See `CLAUDE.md` for the full details.

## Submitting a PR

Fork → branch → tests pass → PR against `main`. Fill out the PR template. Keep commits focused.

## Reporting bugs / requesting features

Use GitHub Issues with the provided templates.
