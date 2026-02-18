#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# dotenvx-env-sync: keep plaintext .env files local and commit encrypted copies
# Usage:
#   ./scripts/dotenvx-env-sync.sh <seal|unseal|check|help> [options]
#
# Options:
#   --files ".env,.env.dev,.env.prod"   Explicit files (comma/space separated)
#   --all-env                            Auto-manage all local .env/.env.* files
#   --force                              Overwrite plaintext when unsealing
#   --keys-file .env.keys                Override dotenvx key file path
#   --config .dotenvx-sync-files         Override file-list config path
# ============================================================================

ENV_KEYS_FILE="${DOTENVX_ENV_KEYS_FILE:-.env.keys}"
SYNC_FILES_CONFIG="${DOTENVX_SYNC_FILES_CONFIG:-.dotenvx-sync-files}"

DEFAULT_PLAIN_ENV_FILES=(
  ".env.development"
  ".env.production"
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

trim_decrypted_meta() {
  awk '
    /^#\// { next }
    /^DOTENV_PUBLIC_KEY_[A-Z0-9_]+=.*$/ { next }
    { print }
  ' | sed '/./,$!d'
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
    err "No env files resolved"
    echo ""
    echo "  Try one of:"
    echo "    --all-env"
    echo "    --files '.env,.env.dev,.env.prod'"
    echo "    export DOTENVX_SYNC_FILES='.env,.env.dev,.env.prod'"
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
  title "Sealing env files with dotenvx"
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
    encrypted_file="$(encrypted_path_for "$plain_file")"
    run_dotenvx encrypt -f "$plain_file" -fk "$ENV_KEYS_FILE" --stdout > "$encrypted_file"
    info "$plain_file  →  $encrypted_file"
    ((count+=1))
  done

  if [ "$count" -eq 0 ]; then
    err "No plaintext .env file found to seal"
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
  title "Unsealing env files from encrypted copies"
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
    tmp_file="$(mktemp)"
    run_dotenvx decrypt -f "$encrypted_file" -fk "$ENV_KEYS_FILE" --stdout | trim_decrypted_meta > "$tmp_file"
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
  title "dotenvx env sync status"
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
  echo -e "${BOLD}dotenvx-env-sync${NC} — commit encrypted env files, keep plaintext local"
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
  echo "  5) defaults: .env.development, .env.production"
  echo ""
  echo "Examples:"
  echo "  $0 seal --files '.env,.env.dev,.env.prod'"
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
