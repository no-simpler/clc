# Publish clc

Guide through a complete clc release. Follow each step in order, verifying before proceeding.

## Steps

### 1. Pre-flight

Run all tests and confirm a clean working tree:

```bash
bash test/run.sh
git status
```

Both must be clean before continuing. Fix any failures first.

### 2. Update CHANGELOG

In `CHANGELOG.md`, add a new `## [X.Y.Z] - YYYY-MM-DD` section below `## [Unreleased]`. Move any entries from `[Unreleased]` into it, or write the notable changes manually. Leave an empty `## [Unreleased]` section at the top for future changes. Add a comparison link at the bottom following the existing pattern.

### 3. Bump version

Decide the new version (semver: patch for fixes, minor for new commands, major for breaking changes).

Edit `CLC_VERSION` in `clc.sh` line 10:

```bash
CLC_VERSION="X.Y.Z"
```

### 4. Commit

Stage and commit the version bump:

```bash
git add clc.sh CHANGELOG.md
git -c commit.gpgsign=false commit -m "Release vX.Y.Z"
```

### 5. Tag

```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z"
```

### 6. Push

```bash
git push && git push --tags
```

### 7. Create GitHub release

Upload `clc.sh` and `install.sh` as release assets:

```bash
gh release create vX.Y.Z clc.sh install.sh \
    --title "clc vX.Y.Z" \
    --generate-notes
```

### 8. Verify

Confirm the release is live and the version is correct:

```bash
curl -fsSL https://github.com/no-simpler/clc/releases/latest/download/install.sh | bash
clc --version
```

Confirm the version printed matches vX.Y.Z.
