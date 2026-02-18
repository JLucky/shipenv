#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# install-dotenvx-sync: one-command bootstrap for dotenvx encrypted env sync
# Usage:
#   ./scripts/install-dotenvx-sync.sh [target_dir] [options]
#
# Options:
#   --install-dotenvx            Also install @dotenvx/dotenvx
#   --source-url <url>           Remote URL for dotenvx-env-sync.sh
#   -h, --help                   Show help
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/dotenvx-env-sync.sh"
REMOTE_SOURCE_URL="${DOTENVX_SYNC_SCRIPT_URL:-https://raw.githubusercontent.com/JLucky/shipenv/main/scripts/dotenvx-env-sync.sh}"
TEMP_SOURCE_SCRIPT=""

TARGET_DIR="."
INSTALL_DOTENVX=false
TARGET_DIR_SET=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}!${NC} $1"; }
err()   { echo -e "  ${RED}✗${NC} $1" >&2; }
title() { echo -e "\n${BOLD}${CYAN}$1${NC}\n"; }

print_help() {
  echo ""
  echo -e "${BOLD}install-dotenvx-sync${NC} — one-command bootstrap for encrypted env sync"
  echo ""
  echo "Usage: $0 [target_dir] [options]"
  echo ""
  echo "Options:"
  echo "  --install-dotenvx      install @dotenvx/dotenvx dev dependency"
  echo "  --source-url <url>     remote URL for dotenvx-env-sync.sh"
  echo "  -h, --help             show this help"
  echo ""
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --install-dotenvx)
        INSTALL_DOTENVX=true
        shift
        ;;
      --source-url)
        if [ "$#" -lt 2 ]; then
          err "--source-url requires a value"
          exit 1
        fi
        REMOTE_SOURCE_URL="$2"
        shift 2
        ;;
      -h|--help)
        print_help
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -* )
        err "Unknown option: $1"
        print_help
        exit 1
        ;;
      *)
        if [ "$TARGET_DIR_SET" = false ]; then
          TARGET_DIR="$1"
          TARGET_DIR_SET=true
          shift
        else
          err "Unexpected argument: $1"
          print_help
          exit 1
        fi
        ;;
    esac
  done
}

ensure_source_script() {
  if [ -f "$SOURCE_SCRIPT" ]; then
    return
  fi

  if ! command -v curl >/dev/null 2>&1; then
    err "Source script not found and curl is unavailable"
    echo ""
    echo "  Missing local file: $SOURCE_SCRIPT"
    echo ""
    exit 1
  fi

  TEMP_SOURCE_SCRIPT="$(mktemp)"
  if ! curl -fsSL "$REMOTE_SOURCE_URL" -o "$TEMP_SOURCE_SCRIPT"; then
    err "Failed to download source script from: $REMOTE_SOURCE_URL"
    rm -f "$TEMP_SOURCE_SCRIPT"
    TEMP_SOURCE_SCRIPT=""
    exit 1
  fi

  SOURCE_SCRIPT="$TEMP_SOURCE_SCRIPT"
  info "Downloaded source script from remote"
}

ensure_target_project() {
  if [ ! -d "$TARGET_DIR" ]; then
    err "Target directory not found: $TARGET_DIR"
    exit 1
  fi

  if [ ! -f "$TARGET_DIR/package.json" ]; then
    err "No package.json in target directory: $TARGET_DIR"
    echo ""
    echo "  Run this inside your Node/Bun project root, or pass target dir:"
    echo "    ./scripts/install-dotenvx-sync.sh /path/to/project"
    echo ""
    exit 1
  fi
}

copy_sync_script() {
  mkdir -p "$TARGET_DIR/scripts"
  cp "$SOURCE_SCRIPT" "$TARGET_DIR/scripts/dotenvx-env-sync.sh"
  chmod +x "$TARGET_DIR/scripts/dotenvx-env-sync.sh"
  info "Installed scripts/dotenvx-env-sync.sh"
}

run_js() {
  local code="$1"
  shift || true
  if command -v node >/dev/null 2>&1; then
    node -e "$code" -- "$@"
    return
  fi

  if command -v bun >/dev/null 2>&1; then
    bun -e "$code" -- "$@"
    return
  fi

  err "Need node or bun to modify package.json"
  exit 1
}

update_package_json() {
  local package_json="$TARGET_DIR/package.json"
  local js
  js="const fs=require('fs');
const p=process.argv[1];
const pkg=JSON.parse(fs.readFileSync(p,'utf8'));
pkg.scripts=pkg.scripts||{};
const desired={
  'env:check':'bash scripts/dotenvx-env-sync.sh check',
  'env:check:all':'bash scripts/dotenvx-env-sync.sh check --all-env',
  'env:seal':'bash scripts/dotenvx-env-sync.sh seal',
  'env:seal:all':'bash scripts/dotenvx-env-sync.sh seal --all-env',
  'env:unseal':'bash scripts/dotenvx-env-sync.sh unseal',
  'env:unseal:force':'bash scripts/dotenvx-env-sync.sh unseal --force',
  'env:unseal:all':'bash scripts/dotenvx-env-sync.sh unseal --all-env',
  'env:unseal:all:force':'bash scripts/dotenvx-env-sync.sh unseal --all-env --force'
};
let changed=false;
for (const [k,v] of Object.entries(desired)) {
  if (pkg.scripts[k]!==v) { pkg.scripts[k]=v; changed=true; }
}
if (changed) {
  fs.writeFileSync(p, JSON.stringify(pkg,null,2)+'\\n');
  console.log('updated');
} else {
  console.log('unchanged');
}"

  local result
  result=$(run_js "$js" "$package_json")

  if [ "$result" = "updated" ]; then
    info "Updated package.json scripts"
  else
    info "package.json scripts already up to date"
  fi
}

update_gitignore() {
  local gitignore="$TARGET_DIR/.gitignore"

  if [ ! -f "$gitignore" ]; then
    touch "$gitignore"
  fi

  if rg -q "# >>> dotenvx encrypted env sync >>>|!\.env\.development\.encrypted|!\.env\.production\.encrypted" "$gitignore" 2>/dev/null; then
    info ".gitignore already contains dotenvx block"
    return
  fi

  cat >> "$gitignore" <<'EOF'

# >>> dotenvx encrypted env sync >>>
.env*
!.env.development.encrypted
!.env.production.encrypted
!.env.example
!.env.production.example
.env.keys
# <<< dotenvx encrypted env sync <<<
EOF

  info "Updated .gitignore"
}

install_dotenvx_dependency() {
  if [ "$INSTALL_DOTENVX" != true ]; then
    return
  fi

  title "Installing @dotenvx/dotenvx"
  (
    cd "$TARGET_DIR"
    if [ -f "bun.lock" ] || [ -f "bun.lockb" ]; then
      bun add -d @dotenvx/dotenvx
      info "Installed via bun"
      return
    fi

    if [ -f "pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1; then
      pnpm add -D @dotenvx/dotenvx
      info "Installed via pnpm"
      return
    fi

    if [ -f "yarn.lock" ] && command -v yarn >/dev/null 2>&1; then
      yarn add -D @dotenvx/dotenvx
      info "Installed via yarn"
      return
    fi

    npm install -D @dotenvx/dotenvx
    info "Installed via npm"
  )
}

print_next_steps() {
  echo ""
  echo -e "${BOLD}Next steps in $TARGET_DIR:${NC}"
  echo "  1) Create/update local env files (your naming convention)"
  echo "  2) Encrypt: npm run env:seal   (or env:seal:all / --files)"
  echo "  3) Commit generated *.encrypted files"
  echo "  4) On other machines: add .env.keys then run env:unseal"
  echo ""
}

main() {
  trap 'rm -f "$TEMP_SOURCE_SCRIPT"' EXIT
  parse_args "$@"
  title "Bootstrap dotenvx env sync"
  ensure_source_script
  ensure_target_project
  copy_sync_script
  update_package_json
  update_gitignore
  install_dotenvx_dependency
  print_next_steps
}

main "$@"
