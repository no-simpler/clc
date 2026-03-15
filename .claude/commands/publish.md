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

### 2. Bump version

Decide the new version (semver: patch for fixes, minor for new commands, major for breaking changes).

Edit `CLC_VERSION` in `clc.sh` line 10:

```bash
CLC_VERSION="X.Y.Z"
```

Update `version` and `url` in `Formula/clc.rb` (leave `sha256` as a placeholder — it gets filled after the release upload):

```ruby
version "X.Y.Z"
url "https://github.com/no-simpler/clc/releases/download/vX.Y.Z/clc.sh"
sha256 "<sha256>"
```

### 3. Commit

Stage and commit the version bump:

```bash
git add clc.sh Formula/clc.rb
git -c commit.gpgsign=false commit -m "Release vX.Y.Z"
```

### 4. Tag

```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z"
```

### 5. Push

```bash
git push && git push --tags
```

### 6. Create GitHub release

Upload `clc.sh` and `install.sh` as release assets:

```bash
gh release create vX.Y.Z clc.sh install.sh \
    --title "clc vX.Y.Z" \
    --generate-notes
```

### 7. Get SHA256

Compute the sha256 of the uploaded `clc.sh`:

```bash
curl -fsSL https://github.com/no-simpler/clc/releases/download/vX.Y.Z/clc.sh \
    | shasum -a 256
```

### 8. Update formula

Patch the `sha256` value in `Formula/clc.rb` with the hash from step 7:

```ruby
sha256 "<actual-hash-from-step-7>"
```

Commit and push:

```bash
git add Formula/clc.rb
git -c commit.gpgsign=false commit -m "Update formula sha256 for vX.Y.Z"
git push
```

### 9. Verify

Test the Homebrew installation end-to-end:

```bash
brew tap no-simpler/clc
brew install clc
clc --version
```

Confirm the version printed matches vX.Y.Z.
