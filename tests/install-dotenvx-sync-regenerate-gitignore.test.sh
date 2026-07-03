#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT_DIR/scripts/install-dotenvx-sync.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

project_dir="$tmpdir/project"
fake_bin="$tmpdir/bin"
mkdir -p "$project_dir" "$fake_bin"

cat > "$fake_bin/rg" <<'SH'
#!/usr/bin/env bash
exit 127
SH
chmod +x "$fake_bin/rg"

cat > "$project_dir/package.json" <<'JSON'
{
  "name": "regenerate-gitignore-test",
  "version": "1.0.0"
}
JSON

cat > "$project_dir/.gitignore" <<'GITIGNORE'
# existing

# >>> dotenvx encrypted env sync >>>
.env*
!.env.development.encrypted
!.env.production.encrypted
!.env.example
.env.keys
# <<< dotenvx encrypted env sync <<<

# >>> dotenvx encrypted env sync >>>
.env*
!.env.development.encrypted
!.env.production.encrypted
!.env.example
.env.keys
# <<< dotenvx encrypted env sync <<<
GITIGNORE

PATH="$fake_bin:$PATH" bash "$INSTALLER" "$project_dir"
PATH="$fake_bin:$PATH" bash "$INSTALLER" "$project_dir"

grep -Fxq "wrangler.toml" "$project_dir/.gitignore"
grep -Fxq "!wrangler.toml.encrypted" "$project_dir/.gitignore"
grep -Fxq "wrangler.jsonc" "$project_dir/.gitignore"
grep -Fxq "!wrangler.jsonc.encrypted" "$project_dir/.gitignore"

block_count="$(grep -Fc "# >>> dotenvx encrypted env sync >>>" "$project_dir/.gitignore")"
[ "$block_count" -eq 1 ]
