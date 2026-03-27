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

**CHANGELOG writing guidelines:**
- Write from the user's perspective: describe what they can now do, what changed in their experience, or what was broken and is now fixed — not what the code does internally.
- Good: "Fixed a crash when running `clc save` on a repo with no commits."
- Bad: "Refactored save function to handle empty HEAD ref."
- Strictly internal changes (refactors, code cleanup, test improvements) that have no user-visible impact should be omitted or noted only briefly under an `Internal` or `Maintenance` sub-heading.

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

### 8. Update Homebrew tap

Compute the SHA256 of the release tarball and generate a self-contained shell script for the user to copy-paste and run:

```bash
SHA=$(curl -sL https://github.com/no-simpler/clc/archive/refs/tags/vX.Y.Z.tar.gz \
  | shasum -a 256 | cut -d' ' -f1)
```

Then output the following block with `X.Y.Z` and `$SHA` substituted:

```
Run this to update the Homebrew tap:

  TAPDIR=$(mktemp -d) \
  && git clone git@github.com:no-simpler/homebrew-tap.git "$TAPDIR" \
  && sed -i '' 's|refs/tags/v[0-9.]*\.tar\.gz|refs/tags/vX.Y.Z.tar.gz|' "$TAPDIR/Formula/clc.rb" \
  && sed -i '' 's/sha256 ".*"/sha256 "<SHA256>"/' "$TAPDIR/Formula/clc.rb" \
  && git -C "$TAPDIR" add Formula/clc.rb \
  && git -C "$TAPDIR" commit -m "Update clc to vX.Y.Z" \
  && git -C "$TAPDIR" push \
  && rm -rf "$TAPDIR"
```

### 9. Verify

Download the release asset to a temp location, confirm the version, then clean up:

```bash
TMPFILE=$(mktemp)
curl -fsSL https://github.com/no-simpler/clc/releases/download/vX.Y.Z/clc.sh -o "$TMPFILE"
bash "$TMPFILE" --version
rm "$TMPFILE"
```

Confirm the version printed matches vX.Y.Z.
