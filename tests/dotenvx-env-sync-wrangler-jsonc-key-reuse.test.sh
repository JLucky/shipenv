#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC_SCRIPT="$ROOT_DIR/scripts/dotenvx-env-sync.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

project_dir="$tmpdir/project"
mkdir -p "$project_dir"
cd "$project_dir"

cat > wrangler.jsonc <<'JSONC'
{
  "name": "key-reuse-one"
}
JSONC

bash "$SYNC_SCRIPT" seal

cat > wrangler.jsonc <<'JSONC'
{
  "name": "key-reuse-two"
}
JSONC

bash "$SYNC_SCRIPT" seal

key_count="$(awk -F= '$1 == "DOTENV_PRIVATE_KEY_WRANGLER_JSONC" { count += 1 } END { print count + 0 }' .env.keys)"
if [ "$key_count" -ne 1 ]; then
  echo "expected one DOTENV_PRIVATE_KEY_WRANGLER_JSONC, got $key_count" >&2
  exit 1
fi

rm -f wrangler.jsonc
bash "$SYNC_SCRIPT" unseal --force
grep -Fq '"name": "key-reuse-two"' wrangler.jsonc
