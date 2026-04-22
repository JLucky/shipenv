# Wrangler TOML Default Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `wrangler.toml` part of the default encrypt/decrypt workflow while preserving the existing env sync behavior.

**Architecture:** Extend the default managed-file list in both runtime scripts, then lock the behavior in shell tests before updating installer output and public docs. Keep the explicit file-list and `--all-env` precedence model intact, but ensure the default path now includes `wrangler.toml`.

**Tech Stack:** Bash, shell integration tests, `dotenvx`, Git-managed docs

---

### Task 1: Lock default `wrangler.toml` behavior with failing tests

**Files:**
- Create: `tests/dotenvx-env-sync-wrangler-default.test.sh`
- Modify: `tests/install-dotenvx-sync-stdin.test.sh`
- Test: `tests/dotenvx-env-sync-wrangler-default.test.sh`
- Test: `tests/install-dotenvx-sync-stdin.test.sh`

- [ ] **Step 1: Write the failing runtime test**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC_SCRIPT="$ROOT_DIR/scripts/dotenvx-env-sync.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

project_dir="$tmpdir/project"
mkdir -p "$project_dir"
cd "$project_dir"

cat > wrangler.toml <<'TOML'
name = "demo"
main = "dist/index.js"
[vars]
API_BASE = "https://example.com"
TOML

bash "$SYNC_SCRIPT" seal
test -f wrangler.toml.encrypted

rm -f wrangler.toml
bash "$SYNC_SCRIPT" unseal --force
grep -Fq 'name="demo"' wrangler.toml
grep -Fq 'API_BASE="https://example.com"' wrangler.toml
```

- [ ] **Step 2: Run the new test to verify it fails**

Run: `bash tests/dotenvx-env-sync-wrangler-default.test.sh`
Expected: FAIL because `wrangler.toml.encrypted` is not produced by the default workflow yet.

- [ ] **Step 3: Extend the installer test with default gitignore expectations**

```bash
grep -Fq "!wrangler.toml.encrypted" "$project_dir/.gitignore"
grep -Fq "wrangler.toml" "$project_dir/.gitignore"
```

- [ ] **Step 4: Run the installer test to verify it fails**

Run: `bash tests/install-dotenvx-sync-stdin.test.sh`
Expected: FAIL because the installer does not yet include default `wrangler.toml` rules.

- [ ] **Step 5: Commit the red tests**

```bash
git add tests/dotenvx-env-sync-wrangler-default.test.sh tests/install-dotenvx-sync-stdin.test.sh
git commit -m "test: cover default wrangler toml sync"
```

### Task 2: Make the sync scripts include `wrangler.toml` by default

**Files:**
- Modify: `scripts/dotenvx-env-sync.sh`
- Modify: `scripts/install-dotenvx-sync.sh`
- Test: `tests/dotenvx-env-sync-wrangler-default.test.sh`

- [ ] **Step 1: Update the default managed-file list in the main script**

```bash
DEFAULT_PLAIN_ENV_FILES=(
  ".env.development"
  ".env.production"
  "wrangler.toml"
)
```

- [ ] **Step 2: Update user-facing fallback/help text to mention `wrangler.toml`**

```bash
echo "    --files '.env,.env.dev,.env.prod,wrangler.toml'"
echo "    export DOTENVX_SYNC_FILES='.env,.env.dev,.env.prod,wrangler.toml'"
echo "  5) defaults: .env.development, .env.production, wrangler.toml"
```

- [ ] **Step 3: Mirror the same default list inside the bundled installer script**

```bash
DEFAULT_PLAIN_ENV_FILES=(
  ".env.development"
  ".env.production"
  "wrangler.toml"
)
```

- [ ] **Step 4: Run the runtime test to verify it passes**

Run: `bash tests/dotenvx-env-sync-wrangler-default.test.sh`
Expected: PASS, with `wrangler.toml.encrypted` generated and `wrangler.toml` restored.

- [ ] **Step 5: Commit the runtime implementation**

```bash
git add scripts/dotenvx-env-sync.sh scripts/install-dotenvx-sync.sh tests/dotenvx-env-sync-wrangler-default.test.sh
git commit -m "feat: include wrangler toml in default sync"
```

### Task 3: Update installer gitignore defaults and keep rerun behavior correct

**Files:**
- Modify: `scripts/install-dotenvx-sync.sh`
- Test: `tests/install-dotenvx-sync-stdin.test.sh`
- Test: `tests/install-dotenvx-sync-source-url.test.sh`

- [ ] **Step 1: Make default managed files include `wrangler.toml` when `.dotenvx-sync-files` is absent**

```bash
if [ "${#managed_files[@]}" -eq 0 ]; then
  managed_files=(".env.development" ".env.production" "wrangler.toml")
fi
```

- [ ] **Step 2: Emit plaintext ignore rules for non-env managed files**

```bash
for file in "${managed_files[@]}"; do
  case "$file" in
    .env|.env.*) ;;
    *) echo "$file" ;;
  esac
done
for file in "${managed_files[@]}"; do
  echo "!${file}.encrypted"
done
```

- [ ] **Step 3: Ensure block regeneration still preserves unrelated `.gitignore` content**

```bash
# Replace only the managed block between markers, otherwise append it once.
```

- [ ] **Step 4: Run installer tests to verify they pass**

Run: `bash tests/install-dotenvx-sync-stdin.test.sh`
Expected: PASS, with both `wrangler.toml` and `!wrangler.toml.encrypted` in the generated block.

Run: `bash tests/install-dotenvx-sync-source-url.test.sh`
Expected: PASS, showing the source override flow still works after script changes.

- [ ] **Step 5: Commit the installer behavior**

```bash
git add scripts/install-dotenvx-sync.sh tests/install-dotenvx-sync-stdin.test.sh tests/install-dotenvx-sync-source-url.test.sh
git commit -m "feat: add default wrangler gitignore rules"
```

### Task 4: Update docs for the new default

**Files:**
- Modify: `README.md`
- Modify: `README.en.md`

- [ ] **Step 1: Update default precedence examples**

```md
5. 默认：`.env.development`, `.env.production`, `wrangler.toml`
```

- [ ] **Step 2: Add a compatibility note for existing projects**

```md
- 老项目如果没有 `wrangler.toml`，默认流程会把它视为受管文件之一，但在文件不存在时只会跳过，不会破坏现有 `.env*.encrypted`
```

- [ ] **Step 3: Keep the TOML formatting caveat explicit**

```md
- `wrangler.toml` 经过 `seal` / `unseal` 后，内容会恢复，但空格格式可能被 `dotenvx` 规范化
```

- [ ] **Step 4: Run a quick docs search to verify consistency**

Run: `rg -n "wrangler.toml|defaults:" README.md README.en.md scripts/dotenvx-env-sync.sh scripts/install-dotenvx-sync.sh`
Expected: matches show the new default set consistently in docs and help text.

- [ ] **Step 5: Commit the docs**

```bash
git add README.md README.en.md
git commit -m "docs: document default wrangler sync"
```

### Task 5: Run full verification before completion

**Files:**
- Verify: `tests/dotenvx-env-sync-wrangler-default.test.sh`
- Verify: `tests/install-dotenvx-sync-stdin.test.sh`
- Verify: `tests/install-dotenvx-sync-source-url.test.sh`

- [ ] **Step 1: Run the focused test suite**

Run:

```bash
bash tests/dotenvx-env-sync-wrangler-default.test.sh
bash tests/install-dotenvx-sync-stdin.test.sh
bash tests/install-dotenvx-sync-source-url.test.sh
```

Expected: all commands exit `0`.

- [ ] **Step 2: Run the broader regression suite**

Run:

```bash
for test_file in tests/*.test.sh; do
  bash "$test_file"
done
```

Expected: every existing shell test still passes.

- [ ] **Step 3: Review the diff against the user request**

Run:

```bash
git diff --stat HEAD~1..HEAD
git status --short
```

Expected: only the intended scripts, docs, and tests are modified.

- [ ] **Step 4: Summarize actual verification evidence**

```text
Record which commands ran, which tests passed, and whether any caveats remain.
```

- [ ] **Step 5: Prepare branch completion handoff**

```bash
git log --oneline --decorate -5
```
