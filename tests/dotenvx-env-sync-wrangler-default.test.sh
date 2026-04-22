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

grep -Eq '^name *= *"demo"$' wrangler.toml
grep -Eq '^main *= *"dist/index.js"$' wrangler.toml
grep -Eq '^API_BASE *= *"https://example.com"$' wrangler.toml
