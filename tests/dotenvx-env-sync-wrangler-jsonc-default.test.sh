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
// Cloudflare Workers config
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "photo-from-emoji",
  "vars": {
    "DATABASE_PROVIDER": "d1",
    "NEXT_PUBLIC_APP_URL": "https://aiphotofromemoji.com"
  },
  "d1_databases": [
    {
      "binding": "DB",
      "database_name": "photo-from-emoji",
      "database_id": "628896d2-91eb-4155-8ac8-481edc94e82d"
    }
  ]
}
JSONC

bash "$SYNC_SCRIPT" seal
test -f wrangler.jsonc.encrypted
test -f .env.keys
grep -Eq '^DOTENV_PRIVATE_KEY_WRANGLER[._]JSONC=' .env.keys
if grep -Fq "$project_dir" wrangler.jsonc.encrypted; then
  echo "wrangler.jsonc.encrypted must not contain local key-file paths" >&2
  exit 1
fi
if grep -Fq '628896d2-91eb-4155-8ac8-481edc94e82d' wrangler.jsonc.encrypted; then
  echo "wrangler.jsonc.encrypted must not contain raw database_id" >&2
  exit 1
fi
if grep -Fq 'https://aiphotofromemoji.com' wrangler.jsonc.encrypted; then
  echo "wrangler.jsonc.encrypted must not contain raw app URL" >&2
  exit 1
fi

rm -f wrangler.jsonc
bash "$SYNC_SCRIPT" unseal --force

grep -Fxq '// Cloudflare Workers config' wrangler.jsonc
grep -Fq '"name": "photo-from-emoji"' wrangler.jsonc
if grep -Eq '^#' wrangler.jsonc; then
  echo "wrangler.jsonc must not be restored with shell-style # comments" >&2
  exit 1
fi
