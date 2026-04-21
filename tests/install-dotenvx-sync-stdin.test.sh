#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT_DIR/scripts/install-dotenvx-sync.sh"
SOURCE_SCRIPT="$ROOT_DIR/scripts/dotenvx-env-sync.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

project_dir="$tmpdir/project"
mkdir -p "$project_dir"
cat > "$project_dir/package.json" <<'JSON'
{
  "name": "stdin-install-test",
  "version": "1.0.0"
}
JSON

fake_bin="$tmpdir/fake-bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/curl" <<'SH'
#!/usr/bin/env bash
echo "unexpected curl invocation" >&2
exit 99
SH
chmod +x "$fake_bin/curl"

PATH="$fake_bin:$PATH" bash -s -- "$project_dir" < "$INSTALLER"

cmp -s "$SOURCE_SCRIPT" "$project_dir/scripts/dotenvx-env-sync.sh"

node -e '
const fs = require("fs");
const pkg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const requiredScripts = {
  "env:check": "bash scripts/dotenvx-env-sync.sh check",
  "env:seal": "bash scripts/dotenvx-env-sync.sh seal",
  "env:unseal": "bash scripts/dotenvx-env-sync.sh unseal"
};
for (const [name, command] of Object.entries(requiredScripts)) {
  if (pkg.scripts?.[name] !== command) {
    throw new Error(`missing script: ${name}`);
  }
}
' "$project_dir/package.json"

grep -Fq "# >>> dotenvx encrypted env sync >>>" "$project_dir/.gitignore"
grep -Fq "!.env.development.encrypted" "$project_dir/.gitignore"
grep -Fq "!.env.production.encrypted" "$project_dir/.gitignore"
