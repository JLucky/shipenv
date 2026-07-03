#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# install-dotenvx-sync: one-command bootstrap for dotenvx encrypted file sync
# Usage:
#   ./scripts/install-dotenvx-sync.sh [target_dir] [options]
#
# Options:
#   --install-dotenvx            Also install @dotenvx/dotenvx
#   --source-url <url>           Remote URL for dotenvx-env-sync.sh
#   -h, --help                   Show help
# ============================================================================

SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/dotenvx-env-sync.sh"
DEFAULT_REMOTE_SOURCE_URL="https://raw.githubusercontent.com/JLucky/shipenv/main/scripts/dotenvx-env-sync.sh"
REMOTE_SOURCE_URL="$DEFAULT_REMOTE_SOURCE_URL"
REMOTE_SOURCE_URL_EXPLICIT=false
if [ -n "${DOTENVX_SYNC_SCRIPT_URL:-}" ]; then
  REMOTE_SOURCE_URL="$DOTENVX_SYNC_SCRIPT_URL"
  REMOTE_SOURCE_URL_EXPLICIT=true
fi
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
  echo -e "${BOLD}install-dotenvx-sync${NC} — one-command bootstrap for encrypted file sync"
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
        REMOTE_SOURCE_URL_EXPLICIT=true
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

write_embedded_source_script() {
  local destination="$1"

  # Bundling the sync script keeps `curl ... | bash` installs to a single
  # network request, even when the installer is executed from stdin.
  cat > "$destination" <<'__DOTENVX_SYNC_BUNDLED_SCRIPT__'
#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# dotenvx-env-sync: keep plaintext managed files local and commit encrypted copies
# Usage:
#   ./scripts/dotenvx-env-sync.sh <seal|unseal|check|help> [options]
#
# Options:
#   --files ".env,.env.dev,.env.prod,wrangler.toml,wrangler.jsonc" Explicit files (comma/space separated)
#   --all-env                            Auto-manage all local .env/.env.* files
#   --force                              Overwrite plaintext when unsealing
#   --keys-file .env.keys                Override dotenvx key file path
#   --config .dotenvx-sync-files         Override file-list config path
# ============================================================================

ENV_KEYS_FILE="${DOTENVX_ENV_KEYS_FILE:-.env.keys}"
SYNC_FILES_CONFIG="${DOTENVX_SYNC_FILES_CONFIG:-.dotenvx-sync-files}"
COMMENTED_ENV_PLACEHOLDER_PREFIX="DOTENVX_SYNC_COMMENTED"

DEFAULT_PLAIN_ENV_FILES=(
  ".env.development"
  ".env.production"
  "wrangler.toml"
  "wrangler.jsonc"
)

COMMAND="help"
OPTION_FORCE=false
OPTION_ALL_ENV=false
OPTION_FILES=()
PLAIN_ENV_FILES=()

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

DOTENVX_CMD=()

detect_dotenvx() {
  if command -v dotenvx >/dev/null 2>&1; then
    DOTENVX_CMD=(dotenvx)
    return
  fi

  if [ -x "./node_modules/.bin/dotenvx" ]; then
    DOTENVX_CMD=(./node_modules/.bin/dotenvx)
    return
  fi

  if command -v npx >/dev/null 2>&1; then
    DOTENVX_CMD=(npx -y @dotenvx/dotenvx@latest)
    return
  fi

  if command -v bunx >/dev/null 2>&1; then
    DOTENVX_CMD=(bunx @dotenvx/dotenvx@latest)
    return
  fi

  err "dotenvx not found, and bunx/npx are unavailable"
  echo ""
  echo "  Install one of:"
  echo "    npm i -D @dotenvx/dotenvx"
  echo "    bun add -d @dotenvx/dotenvx"
  echo ""
  exit 1
}

run_dotenvx() {
  "${DOTENVX_CMD[@]}" "$@"
}

env_suffix_for_file() {
  local file="$1"
  if [ "$file" = ".env" ]; then
    echo ""
    return
  fi

  local suffix="${file#.env.}"
  echo "$suffix" | tr '[:lower:]-.' '[:upper:]__'
}

encrypted_path_for() {
  local plain_file="$1"
  echo "${plain_file}.encrypted"
}

dotenvx_work_file_for() {
  local dir="$1"
  local plain_file="$2"
  case "$plain_file" in
    .env|.env.*)
      echo "$dir/$(basename "$plain_file")"
      ;;
    *)
      echo "$dir/.env.$(env_suffix_for_file "$plain_file")"
      ;;
  esac
}

dotenvx_public_key_var_for() {
  local plain_file="$1"
  local suffix
  suffix="$(env_suffix_for_file "$plain_file")"
  if [ -n "$suffix" ]; then
    echo "DOTENV_PUBLIC_KEY_${suffix}"
  else
    echo "DOTENV_PUBLIC_KEY"
  fi
}

copy_existing_dotenvx_public_key() {
  local encrypted_file="$1"
  local plain_file="$2"
  if [ ! -f "$encrypted_file" ]; then
    return
  fi

  local key_var
  key_var="$(dotenvx_public_key_var_for "$plain_file")"
  awk -v key="$key_var" -F= '$1 == key { print; exit }' "$encrypted_file"
}

trim_decrypted_meta() {
  awk '
    /^#\// { next }
    /^DOTENV_PUBLIC_KEY[^=]*=.*$/ { next }
    { print }
  ' | sed '/./,$!d'
}

strip_dotenvx_key_file_comment() {
  sed -E '/^DOTENV_PUBLIC_KEY[^=]*=/ s/[[:space:]]+# -fk .*$//'
}

base64_decode() {
  if printf '' | base64 --decode >/dev/null 2>&1; then
    base64 --decode
  else
    base64 -D
  fi
}

strip_dotenvx_file_header() {
  local plain_file="$1"
  local dotenvx_file
  dotenvx_file="$(dotenvx_work_file_for "" "$plain_file")"
  dotenvx_file="${dotenvx_file#/}"
  awk -v header="# $plain_file" -v dotenvx_header="# $dotenvx_file" '
    BEGIN { skipped = 0 }
    skipped == 0 && ($0 == header || $0 == dotenvx_header) { skipped = 1; next }
    { print }
  '
}

is_full_file_encryption() {
  local file="$1"
  case "$file" in
    *.json|*.jsonc) return 0 ;;
    *) return 1 ;;
  esac
}

prepare_plain_for_encryption() {
  local plain_file="$1"
  local mode="${2:-plain}"
  if is_full_file_encryption "$plain_file"; then
    local key
    key="$(managed_file_payload_key "$plain_file")"
    local encoded
    encoded="$(base64 < "$plain_file" | tr -d '\n')"
    printf '%s=%s\n' "$key" "$encoded"
    return
  fi

  commented_env_to_placeholder "$plain_file" "$mode"
}

prepare_encrypted_for_decryption() {
  local encrypted_file="$1"
  local plain_file="$2"
  if is_full_file_encryption "$plain_file"; then
    cat "$encrypted_file"
    return
  fi

  commented_env_to_placeholder "$encrypted_file" encrypted
}

restore_decrypted_output() {
  local plain_file="$1"
  if is_full_file_encryption "$plain_file"; then
    local key
    key="$(managed_file_payload_key "$plain_file")"
    awk -v key="$key" -F= '
      $1 == key {
        value = substr($0, length(key) + 2)
        print value
        found = 1
        exit
      }
      END {
        if (!found) exit 1
      }
    ' | base64_decode
    return
  fi

  strip_dotenvx_file_header "$plain_file" | placeholder_to_commented_env
}

managed_file_payload_key() {
  local file="$1"
  local key
  key="$(printf '%s' "$file" | tr '[:lower:]./-' '[:upper:]___' | sed 's/[^A-Z0-9_]/_/g')"
  printf 'DOTENVX_SYNC_FILE__%s\n' "$key"
}

commented_env_to_placeholder() {
  local input_file="$1"
  local mode="${2:-plain}"

  awk -v mode="$mode" -v prefix="$COMMENTED_ENV_PLACEHOLDER_PREFIX" '
    BEGIN { idx = 0 }
    {
      if ($0 ~ /^[[:space:]]*#[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=.*/) {
        line = $0
        sub(/^[[:space:]]*#[[:space:]]*/, "", line)

        eq_pos = index(line, "=")
        if (eq_pos == 0) {
          print
          next
        }

        key = substr(line, 1, eq_pos - 1)
        sub(/^[[:space:]]+/, "", key)
        sub(/[[:space:]]+$/, "", key)
        if (key !~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
          print
          next
        }

        value = substr(line, eq_pos + 1)
        value_ltrim = value
        sub(/^[[:space:]]+/, "", value_ltrim)

        encrypted_candidate = value_ltrim
        first_char = substr(encrypted_candidate, 1, 1)
        if (first_char == "\"" || first_char == sprintf("%c", 39)) {
          encrypted_candidate = substr(encrypted_candidate, 2)
        }

        if (mode == "encrypted" && encrypted_candidate !~ /^encrypted:/) {
          print
          next
        }

        idx += 1
        printf "%s_%06d__%s=%s\n", prefix, idx, key, value_ltrim
        next
      }

      print
    }
  ' "$input_file"
}

placeholder_to_commented_env() {
  awk -v prefix="$COMMENTED_ENV_PLACEHOLDER_PREFIX" '
    {
      if ($0 ~ ("^" prefix "_[0-9]+__[A-Za-z_][A-Za-z0-9_]*=.*")) {
        line = $0
        sub("^" prefix "_[0-9]+__", "", line)

        key = line
        sub(/=.*/, "", key)

        value = line
        sub(/^[^=]*=/, "", value)

        printf "#%s=%s\n", key, value
        next
      }
      print
    }
  ' "$@"
}

add_plain_env_file() {
  local candidate="$1"
  if [ -z "$candidate" ]; then
    return
  fi

  local existing
  for existing in "${PLAIN_ENV_FILES[@]:-}"; do
    if [ "$existing" = "$candidate" ]; then
      return
    fi
  done

  PLAIN_ENV_FILES+=("$candidate")
}

add_plain_env_files_from_text() {
  local text="$1"
  local token
  text="${text//,/ }"
  for token in $text; do
    add_plain_env_file "$token"
  done
}

load_plain_env_files_from_config() {
  if [ ! -f "$SYNC_FILES_CONFIG" ]; then
    return
  fi

  local line
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    add_plain_env_file "$line"
  done < "$SYNC_FILES_CONFIG"
}

is_valid_env_name() {
  local file="$1"
  if [ "$file" = ".env" ]; then
    return 0
  fi
  case "$file" in
    .env.*) return 0 ;;
    *) return 1 ;;
  esac
}

discover_all_env_files() {
  local discovered=()
  while IFS= read -r file; do
    file="${file#./}"

    if ! is_valid_env_name "$file"; then
      continue
    fi

    case "$file" in
      *.encrypted|.env.keys|*.example|*.example.*|*.sample|*.sample.*|*.template|*.template.*)
        continue
        ;;
    esac

    discovered+=("$file")
  done < <(find . -maxdepth 1 -type f -name '.env*' | sort)

  local file
  for file in "${discovered[@]}"; do
    add_plain_env_file "$file"
  done
}

resolve_plain_env_files() {
  PLAIN_ENV_FILES=()

  if [ "$OPTION_ALL_ENV" = true ]; then
    discover_all_env_files
  elif [ "${#OPTION_FILES[@]}" -gt 0 ]; then
    local item
    for item in "${OPTION_FILES[@]}"; do
      add_plain_env_files_from_text "$item"
    done
  elif [ -n "${DOTENVX_SYNC_FILES:-}" ]; then
    add_plain_env_files_from_text "$DOTENVX_SYNC_FILES"
  elif [ -f "$SYNC_FILES_CONFIG" ]; then
    load_plain_env_files_from_config
  else
    local file
    for file in "${DEFAULT_PLAIN_ENV_FILES[@]}"; do
      add_plain_env_file "$file"
    done
  fi

  if [ "${#PLAIN_ENV_FILES[@]}" -eq 0 ]; then
    err "No managed files resolved"
    echo ""
    echo "  Try one of:"
    echo "    --all-env"
    echo "    --files '.env,.env.dev,.env.prod,wrangler.toml,wrangler.jsonc'"
    echo "    export DOTENVX_SYNC_FILES='.env,.env.dev,.env.prod,wrangler.toml,wrangler.jsonc'"
    echo "    echo '.env.dev' > $SYNC_FILES_CONFIG"
    echo ""
    exit 1
  fi
}

parse_args() {
  if [ "$#" -eq 0 ]; then
    COMMAND="help"
    return
  fi

  COMMAND="$1"
  shift

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --files)
        if [ "$#" -lt 2 ]; then
          err "--files requires a value"
          exit 1
        fi
        OPTION_FILES+=("$2")
        shift 2
        ;;
      --all-env)
        OPTION_ALL_ENV=true
        shift
        ;;
      --force)
        OPTION_FORCE=true
        shift
        ;;
      --keys-file)
        if [ "$#" -lt 2 ]; then
          err "--keys-file requires a value"
          exit 1
        fi
        ENV_KEYS_FILE="$2"
        shift 2
        ;;
      --config)
        if [ "$#" -lt 2 ]; then
          err "--config requires a value"
          exit 1
        fi
        SYNC_FILES_CONFIG="$2"
        shift 2
        ;;
      -h|--help)
        COMMAND="help"
        return
        ;;
      *)
        err "Unknown option: $1"
        echo ""
        cmd_help
        exit 1
        ;;
    esac
  done
}

print_managed_files() {
  local first=true
  local file
  local output=""
  for file in "${PLAIN_ENV_FILES[@]:-}"; do
    if [ "$first" = true ]; then
      output="$file"
      first=false
    else
      output="$output, $file"
    fi
  done
  echo "$output"
}

cmd_seal() {
  title "Sealing managed files with dotenvx"
  detect_dotenvx
  resolve_plain_env_files
  info "Managed files: $(print_managed_files)"

  local count=0
  local plain_file
  for plain_file in "${PLAIN_ENV_FILES[@]:-}"; do
    if [ ! -f "$plain_file" ]; then
      warn "Skipped $plain_file (file not found)"
      continue
    fi

    local encrypted_file
    local tmp_plain_dir
    local tmp_plain_file
    local tmp_encrypted_file
    encrypted_file="$(encrypted_path_for "$plain_file")"
    tmp_plain_dir="$(mktemp -d)"
    tmp_plain_file="$(dotenvx_work_file_for "$tmp_plain_dir" "$plain_file")"
    tmp_encrypted_file="$(mktemp)"

    {
      copy_existing_dotenvx_public_key "$encrypted_file" "$plain_file"
      prepare_plain_for_encryption "$plain_file" plain
    } > "$tmp_plain_file"
    run_dotenvx encrypt -f "$tmp_plain_file" -fk "$ENV_KEYS_FILE" >/dev/null
    strip_dotenvx_key_file_comment < "$tmp_plain_file" > "$tmp_encrypted_file"
    placeholder_to_commented_env "$tmp_encrypted_file" > "$encrypted_file"

    rm -f "$tmp_encrypted_file"
    rm -rf "$tmp_plain_dir"
    info "$plain_file  →  $encrypted_file"
    ((count+=1))
  done

  if [ "$count" -eq 0 ]; then
    err "No plaintext managed file found to seal"
    exit 1
  fi

  if [ -f "$ENV_KEYS_FILE" ]; then
    info "Updated key file at $ENV_KEYS_FILE"
    warn "Do NOT commit $ENV_KEYS_FILE to git"
  fi

  echo ""
  echo "  Next steps:"
  echo "    git add *.encrypted"
  echo "    git commit -m 'chore: update encrypted env files'"
  echo ""
}

cmd_unseal() {
  title "Unsealing managed files from encrypted copies"
  detect_dotenvx
  resolve_plain_env_files
  info "Managed files: $(print_managed_files)"

  local force="$OPTION_FORCE"
  local count=0
  local skipped_existing=0
  local missing_encrypted=0

  local plain_file
  for plain_file in "${PLAIN_ENV_FILES[@]:-}"; do
    local encrypted_file
    encrypted_file="$(encrypted_path_for "$plain_file")"

    if [ ! -f "$encrypted_file" ]; then
      warn "Skipped $encrypted_file (file not found)"
      ((missing_encrypted+=1))
      continue
    fi

    if [ -f "$plain_file" ] && [ "$force" = false ]; then
      warn "Kept existing $plain_file (use --force to overwrite)"
      ((skipped_existing+=1))
      continue
    fi

    local tmp_file
    local tmp_encrypted_file
    tmp_file="$(mktemp)"
    tmp_encrypted_file="$(mktemp)"

    prepare_encrypted_for_decryption "$encrypted_file" "$plain_file" > "$tmp_encrypted_file"
    run_dotenvx decrypt -f "$tmp_encrypted_file" -fk "$ENV_KEYS_FILE" --stdout | trim_decrypted_meta | restore_decrypted_output "$plain_file" > "$tmp_file"

    rm -f "$tmp_encrypted_file"
    mv "$tmp_file" "$plain_file"
    info "$encrypted_file  →  $plain_file"
    ((count+=1))
  done

  if [ "$count" -eq 0 ]; then
    if [ "$force" = false ] && [ "$skipped_existing" -gt 0 ]; then
      warn "No file was unsealed (all local plaintext files already exist)"
      echo ""
      echo "  Tip: run with --force to overwrite existing plaintext files"
      echo ""
      return
    fi

    err "No file was unsealed"
    if [ "$missing_encrypted" -gt 0 ]; then
      echo ""
      echo "  Tip: run seal first or pull encrypted files from git"
    fi
    exit 1
  fi
  echo ""
}

cmd_check() {
  title "dotenvx managed file sync status"
  resolve_plain_env_files
  info "Managed files: $(print_managed_files)"
  echo ""

  local plain_file
  for plain_file in "${PLAIN_ENV_FILES[@]:-}"; do
    local encrypted_file
    encrypted_file="$(encrypted_path_for "$plain_file")"

    echo -e "  ${BOLD}$plain_file${NC}"

    if [ -f "$plain_file" ]; then
      info "plaintext exists"
    else
      warn "plaintext missing"
    fi

    if [ -f "$encrypted_file" ]; then
      info "encrypted exists ($encrypted_file)"
    else
      warn "encrypted missing ($encrypted_file)"
    fi

    if [ -f "$plain_file" ] && [ -f "$encrypted_file" ] && [ "$plain_file" -nt "$encrypted_file" ]; then
      warn "plaintext newer than encrypted — run seal"
    fi

    local suffix
    suffix="$(env_suffix_for_file "$plain_file")"
    local key_var="DOTENV_PRIVATE_KEY"
    if [ -n "$suffix" ]; then
      key_var="DOTENV_PRIVATE_KEY_${suffix}"
    fi
    if [ -n "${!key_var:-}" ]; then
      info "key env var present: $key_var"
    else
      warn "key env var missing: $key_var"
    fi

    echo ""
  done

  if [ -f "$ENV_KEYS_FILE" ]; then
    info "key file exists: $ENV_KEYS_FILE"
  else
    warn "key file missing: $ENV_KEYS_FILE"
  fi

  echo ""
}

cmd_help() {
  echo ""
  echo -e "${BOLD}dotenvx-env-sync${NC} — commit encrypted managed files, keep plaintext local"
  echo ""
  echo "Usage: $0 <command> [options]"
  echo ""
  echo "Commands:"
  echo "  seal            Encrypt plaintext env files into *.encrypted"
  echo "  unseal          Restore encrypted files to local plaintext (no overwrite)"
  echo "  check           Show sync status and key availability"
  echo ""
  echo "Options:"
  echo "  --files <list>     Explicit files, comma or space separated"
  echo "  --all-env          Auto-detect local .env and .env.* files"
  echo "  --force            Overwrite plaintext files during unseal"
  echo "  --keys-file <path> dotenvx keys file path (default: $ENV_KEYS_FILE)"
  echo "  --config <path>    file-list config path (default: $SYNC_FILES_CONFIG)"
  echo ""
  echo "File selection precedence:"
  echo "  1) --all-env"
  echo "  2) --files"
  echo "  3) DOTENVX_SYNC_FILES env var"
  echo "  4) $SYNC_FILES_CONFIG"
  echo "  5) defaults: .env.development, .env.production, wrangler.toml, wrangler.jsonc"
  echo ""
  echo "Examples:"
  echo "  $0 seal --files '.env,.env.dev,.env.prod,wrangler.toml,wrangler.jsonc'"
  echo "  $0 unseal --all-env"
  echo "  DOTENVX_SYNC_FILES='.env,.env.preview' $0 check"
  echo ""
}

main() {
  parse_args "$@"

  case "$COMMAND" in
    seal|enc|encrypt)
      cmd_seal
      ;;
    unseal|dec|decrypt)
      cmd_unseal
      ;;
    check|status|st)
      cmd_check
      ;;
    help|h|--help)
      cmd_help
      ;;
    *)
      err "Unknown command: $COMMAND"
      cmd_help
      exit 1
      ;;
  esac
}

main "$@"
__DOTENVX_SYNC_BUNDLED_SCRIPT__

  chmod +x "$destination"
}

download_source_script() {
  local destination="$1"

  if ! command -v curl >/dev/null 2>&1; then
    err "Source script not found and curl is unavailable"
    echo ""
    echo "  Missing local file: $SOURCE_SCRIPT"
    echo ""
    exit 1
  fi

  info "Downloading source script from remote"
  if ! curl --retry 3 --connect-timeout 10 --max-time 60 -fsSL "$REMOTE_SOURCE_URL" -o "$destination"; then
    err "Failed to download source script from: $REMOTE_SOURCE_URL"
    rm -f "$destination"
    exit 1
  fi
}

ensure_source_script() {
  if [ "$REMOTE_SOURCE_URL_EXPLICIT" = true ]; then
    TEMP_SOURCE_SCRIPT="$(mktemp)"
    download_source_script "$TEMP_SOURCE_SCRIPT"
    SOURCE_SCRIPT="$TEMP_SOURCE_SCRIPT"
    return
  fi

  if [ -f "$SOURCE_SCRIPT" ]; then
    return
  fi

  TEMP_SOURCE_SCRIPT="$(mktemp)"
  write_embedded_source_script "$TEMP_SOURCE_SCRIPT"
  SOURCE_SCRIPT="$TEMP_SOURCE_SCRIPT"
  info "Installed bundled source script"
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

resolve_managed_env_files() {
  local sync_config="$TARGET_DIR/.dotenvx-sync-files"
  local managed_files=()

  if [ -f "$sync_config" ]; then
    local line
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%%#*}"
      line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      if [ -n "$line" ]; then
        managed_files+=("$line")
      fi
    done < "$sync_config"
  fi

  if [ "${#managed_files[@]}" -eq 0 ]; then
    managed_files=(".env.development" ".env.production" "wrangler.toml" "wrangler.jsonc")
  fi

  printf '%s\n' "${managed_files[@]}"
}

build_gitignore_block() {
  local managed_files=()
  local file
  while IFS= read -r file; do
    managed_files+=("$file")
  done < <(resolve_managed_env_files)

  echo "# >>> dotenvx encrypted env sync >>>"
  echo ".env*"
  for file in "${managed_files[@]}"; do
    case "$file" in
      .env|.env.*) ;;
      *) echo "$file" ;;
    esac
  done
  for file in "${managed_files[@]}"; do
    echo "!${file}.encrypted"
  done
  echo "!.env.example"
  echo ".env.keys"
  echo "# <<< dotenvx encrypted env sync <<<"
}

update_gitignore() {
  local gitignore="$TARGET_DIR/.gitignore"
  local block_start="# >>> dotenvx encrypted env sync >>>"
  local block_end="# <<< dotenvx encrypted env sync <<<"
  local tmp_file
  local block_file

  if [ ! -f "$gitignore" ]; then
    touch "$gitignore"
  fi

  tmp_file="$(mktemp)"
  block_file="$(mktemp)"
  build_gitignore_block > "$block_file"

  if rg -Fq "$block_start" "$gitignore" 2>/dev/null; then
    local in_block=false
    local line
    while IFS= read -r line || [ -n "$line" ]; do
      if [ "$line" = "$block_start" ]; then
        cat "$block_file" >> "$tmp_file"
        in_block=true
        continue
      fi

      if [ "$in_block" = true ]; then
        if [ "$line" = "$block_end" ]; then
          in_block=false
        fi
        continue
      fi

      printf '%s\n' "$line" >> "$tmp_file"
    done < "$gitignore"
  else
    cat "$gitignore" > "$tmp_file"
    if [ -s "$tmp_file" ]; then
      echo "" >> "$tmp_file"
    fi
    cat "$block_file" >> "$tmp_file"
  fi

  mv "$tmp_file" "$gitignore"
  rm -f "$block_file"

  info "Updated .gitignore"
}

resolve_pnpm_allow_builds_placeholders() {
  local workspace_file="${1:-pnpm-workspace.yaml}"

  if [ ! -f "$workspace_file" ]; then
    return 1
  fi

  if ! grep -Fq "set this to true or false" "$workspace_file"; then
    return 1
  fi

  run_js '
const fs = require("fs");
const path = process.argv[1];
const text = fs.readFileSync(path, "utf8");
const approvals = new Map([
  ["core-js", false],
  ["esbuild", true],
  ["sharp", true],
  ["unrs-resolver", true],
  ["workerd", true]
]);
let changed = false;
const next = text.replace(/^([ \t]*)([^:\n]+):[ \t]*set this to true or false[ \t]*$/gm, (line, indent, name) => {
  const decision = approvals.get(name.trim());
  if (typeof decision !== "boolean") {
    return line;
  }
  changed = true;
  return `${indent}${name.trim()}: ${decision ? "true" : "false"}`;
});
if (!changed) {
  process.exit(2);
}
fs.writeFileSync(path, next);
' "$workspace_file"
}

install_with_pnpm() {
  if pnpm add -D @dotenvx/dotenvx; then
    info "Installed via pnpm"
    return
  fi

  if resolve_pnpm_allow_builds_placeholders "pnpm-workspace.yaml"; then
    warn "Resolved pnpm build-script approval placeholders"
    pnpm add -D @dotenvx/dotenvx
    pnpm rebuild
    info "Installed via pnpm"
    return
  fi

  exit 1
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
      install_with_pnpm
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
  echo "  1) Create/update local env / wrangler files"
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
