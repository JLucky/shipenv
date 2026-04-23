# [中文](README.md) | [English](README.en.md)

# shipenv

`shipenv` provides reusable scripts to quickly enable a `dotenvx` workflow in any project: keep plaintext files local and sync encrypted files through Git. By default it manages `.env.development`, `.env.production`, and `wrangler.toml`.

## Repository Contents

- `scripts/install-dotenvx-sync.sh`: one-command installer (copies script, updates `package.json`, updates `.gitignore`)
- `scripts/dotenvx-env-sync.sh`: encrypt / decrypt / status checks

## One-command Install (run in a new project)

```bash
curl --retry 3 --connect-timeout 10 --max-time 60 -fsSL \
  https://raw.githubusercontent.com/JLucky/shipenv/main/scripts/install-dotenvx-sync.sh | bash -s -- .
```

Optional: install `@dotenvx/dotenvx` into your current project as dev dependency during setup:

```bash
curl --retry 3 --connect-timeout 10 --max-time 60 -fsSL \
  https://raw.githubusercontent.com/JLucky/shipenv/main/scripts/install-dotenvx-sync.sh | bash -s -- . --install-dotenvx
```

The installer now bundles `dotenvx-env-sync.sh`, so `curl | bash` only needs this single remote download.

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
# 1) Update local plaintext env / wrangler files on your machine

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

## Choosing Which Files to Manage

`dotenvx-env-sync.sh` supports 5-level precedence:

1. `--all-env` (all local `.env` / `.env.*`, while skipping `*.encrypted`, `*.example`, `.env.keys`)
2. `--files`
3. `DOTENVX_SYNC_FILES` environment variable
4. project-root `.dotenvx-sync-files`
5. defaults: `.env.development`, `.env.production`, `wrangler.toml`

### Example: explicit file names

```bash
bun run env:seal -- --files ".env,.env.dev,.env.prod,wrangler.toml"
bun run env:unseal -- --files ".env,.env.dev,.env.prod,wrangler.toml"
```

### Example: team-wide fixed config

Create `.dotenvx-sync-files`:

```txt
.env
.env.dev
.env.prod
wrangler.toml
```

Then your team can just run:

```bash
bun run env:seal
bun run env:unseal
```

### Compatibility Notes

- Older projects that previously synced only `.env*` files will now also treat `wrangler.toml` as a default managed file
- If a project does not have `wrangler.toml`, `seal` / `unseal` / `check` will just skip it and leave existing `.env*.encrypted` behavior unchanged
- If plaintext `wrangler.toml` exists locally, the next `seal` will generate `wrangler.toml.encrypted` by default
- If `wrangler.toml.encrypted` already exists in Git, the next `unseal` will restore `wrangler.toml` by default

## Security Notes

- Commit: `*.encrypted`
- Do not commit: `.env.keys`, any plaintext `.env*`, or plaintext `wrangler.toml`
- Store `.env.keys` in 1Password / Bitwarden or another password manager
- You can also inject private keys through env vars (for example `DOTENV_PRIVATE_KEY`, `DOTENV_PRIVATE_KEY_PROD`)
- Commented config lines in env style (for example `#API_KEY=xxx` and `# API_KEY = xxx`) are encrypted on `seal` and restored as comments on `unseal`
- `wrangler.toml` content round-trips through `seal` / `unseal`, but `dotenvx` may normalize TOML spacing on restore

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
