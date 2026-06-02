#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT_DIR/scripts/install-dotenvx-sync.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

project_dir="$tmpdir/project"
mkdir -p "$project_dir"

cat > "$project_dir/package.json" <<'JSON'
{
  "name": "pnpm-build-approval-test",
  "version": "1.0.0"
}
JSON
touch "$project_dir/pnpm-lock.yaml"

fake_bin="$tmpdir/fake-bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/pnpm" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

echo "$*" >> "$PNPM_CALLS_FILE"

case "$1" in
  add)
    add_count="$(grep -Ec '^add ' "$PNPM_CALLS_FILE")"
    if [ "$add_count" -eq 1 ]; then
      cat > pnpm-workspace.yaml <<'YAML'
allowBuilds:
  core-js: set this to true or false
  esbuild: set this to true or false
  sharp: set this to true or false
  unrs-resolver: set this to true or false
  workerd: set this to true or false
YAML
      echo "[ERR_PNPM_IGNORED_BUILDS] Ignored build scripts" >&2
      exit 1
    fi

    if grep -Fq "set this to true or false" pnpm-workspace.yaml; then
      echo "pnpm build approval placeholders were not resolved" >&2
      exit 44
    fi
    ;;
  rebuild)
    if grep -Fq "set this to true or false" pnpm-workspace.yaml; then
      echo "pnpm rebuild ran before build approval placeholders were resolved" >&2
      exit 45
    fi
    ;;
  *)
    echo "unexpected pnpm invocation: $*" >&2
    exit 99
    ;;
esac
SH
chmod +x "$fake_bin/pnpm"

PNPM_CALLS_FILE="$tmpdir/pnpm-calls"
export PNPM_CALLS_FILE
PATH="$fake_bin:$PATH" bash "$INSTALLER" "$project_dir" --install-dotenvx

grep -Fxq "  core-js: false" "$project_dir/pnpm-workspace.yaml"
grep -Fxq "  esbuild: true" "$project_dir/pnpm-workspace.yaml"
grep -Fxq "  sharp: true" "$project_dir/pnpm-workspace.yaml"
grep -Fxq "  unrs-resolver: true" "$project_dir/pnpm-workspace.yaml"
grep -Fxq "  workerd: true" "$project_dir/pnpm-workspace.yaml"
if grep -Fq "set this to true or false" "$project_dir/pnpm-workspace.yaml"; then
  echo "pnpm-workspace.yaml still contains build approval placeholders" >&2
  exit 1
fi

grep -Fxq "add -D @dotenvx/dotenvx" "$PNPM_CALLS_FILE"
[ "$(grep -Fc "add -D @dotenvx/dotenvx" "$PNPM_CALLS_FILE")" -eq 2 ]
grep -Fxq "rebuild" "$PNPM_CALLS_FILE"
