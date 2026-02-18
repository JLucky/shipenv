# [中文](README.md) | [English](README.en.md)

# shipenv

`shipenv` provides reusable scripts to quickly enable a `dotenvx` workflow in any project: keep plaintext env files local, and sync encrypted env files through Git.

## Repository Contents

- `scripts/install-dotenvx-sync.sh`: one-command installer (copies script, updates `package.json`, updates `.gitignore`)
- `scripts/dotenvx-env-sync.sh`: encrypt / decrypt / status checks

## One-command Install (run in a new project)

```bash
curl -fsSL https://raw.githubusercontent.com/JLucky/shipenv/main/scripts/install-dotenvx-sync.sh | bash -s -- .
```

Optional: install `@dotenvx/dotenvx` into your current project as dev dependency during setup:

```bash
curl -fsSL https://raw.githubusercontent.com/JLucky/shipenv/main/scripts/install-dotenvx-sync.sh | bash -s -- . --install-dotenvx
```

## What gets added automatically

- Script: `scripts/dotenvx-env-sync.sh`
- `package.json` scripts:
  - `env:check`
  - `env:check:all`
  - `env:seal`
  - `env:seal:all`
  - `env:unseal`
  - `env:unseal:force`
  - `env:unseal:all`
  - `env:unseal:all:force`
- `.gitignore` rules for dotenvx sync (allow encrypted files, exclude `.env.keys`)

## Daily Workflow

```bash
# 1) Update local plaintext env files on your machine

# 2) Generate/update encrypted files
bun run env:seal

# 3) Commit encrypted files
git add *.encrypted
git commit -m "chore: update encrypted env files"

# 4) On another machine, restore local plaintext after pulling
bun run env:unseal
```

Overwrite existing local plaintext files if needed:

```bash
bun run env:unseal:force
```

## Choosing Which Env Files to Manage

`dotenvx-env-sync.sh` supports 5-level precedence:

1. `--all-env` (all local `.env` / `.env.*`, while skipping `*.encrypted`, `*.example`, `.env.keys`)
2. `--files`
3. `DOTENVX_SYNC_FILES` environment variable
4. project-root `.dotenvx-sync-files`
5. defaults: `.env.development`, `.env.production`

### Example: explicit file names

```bash
bun run env:seal -- --files ".env,.env.dev,.env.prod"
bun run env:unseal -- --files ".env,.env.dev,.env.prod"
```

### Example: team-wide fixed config

Create `.dotenvx-sync-files`:

```txt
.env
.env.dev
.env.prod
```

Then your team can just run:

```bash
bun run env:seal
bun run env:unseal
```

## Security Notes

- Commit: `*.encrypted`
- Do not commit: `.env.keys`, any plaintext `.env*`
- Store `.env.keys` in 1Password / Bitwarden or another password manager
- You can also inject private keys through env vars (for example `DOTENV_PRIVATE_KEY`, `DOTENV_PRIVATE_KEY_PROD`)

## Troubleshooting

- Check status:

```bash
bun run env:check
bun run env:check:all
```

- Show script help directly:

```bash
bash scripts/dotenvx-env-sync.sh --help
bash scripts/install-dotenvx-sync.sh --help
```
