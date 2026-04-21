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
  "name": "source-url-install-test",
  "version": "1.0.0"
}
JSON

override_script="$tmpdir/custom-dotenvx-env-sync.sh"
cat > "$override_script" <<'SH'
#!/usr/bin/env bash
echo custom-source-url
SH
chmod +x "$override_script"

bash "$INSTALLER" "$project_dir" --source-url "file://$override_script"

cmp -s "$override_script" "$project_dir/scripts/dotenvx-env-sync.sh"
