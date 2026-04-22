# Wrangler TOML Support Design

## Summary

This document defines Scheme B for adding first-class `wrangler.toml` support to `shipenv`.

The project will continue to behave as an env-focused sync tool by default:

- `.env` and `.env.*` remain the only files auto-discovered by `--all-env`
- `wrangler.toml` is supported as an explicitly managed extra file
- existing commands and default workflows remain unchanged

The goal is to make `wrangler.toml` work reliably with the existing `seal`, `unseal`, `check`, installer, documentation, and test flow without turning the project into a fully generic config encryption framework in this change.

## Motivation

Projects that deploy Next.js to Cloudflare often carry both:

- local `.env*` files
- a checked-out `wrangler.toml` containing environment-specific configuration or sensitive values

The current implementation already supports explicit file lists through `.dotenvx-sync-files` and `--files`, which means `wrangler.toml` is functionally close to supported today. However, that support is incomplete:

- the docs do not describe it
- the installer does not clearly manage `.gitignore` for it
- the test suite does not protect the behavior
- existing messages still imply the tool only works with `.env` files

This creates a gap between what works experimentally and what is safe to rely on as a documented feature.

## Goals

- Add documented, tested support for `wrangler.toml`
- Preserve the current default env workflow and command surface
- Keep migration impact on existing projects as close to zero as possible
- Make installer-generated `.gitignore` rules correct for projects that explicitly manage `wrangler.toml`
- Document the exact behavior for old projects before and after opting in

## Non-Goals

- Do not make `--all-env` discover arbitrary config files
- Do not rename commands, scripts, or the project in this change
- Do not generalize the product into a universal encrypted file sync tool
- Do not attempt to preserve TOML whitespace formatting byte-for-byte after round-trip decryption
- Do not add special parsing logic for TOML beyond the current line-based encrypt/decrypt pipeline

## Current Behavior

### Sync file resolution

The main script resolves managed files in this order:

1. `--all-env`
2. `--files`
3. `DOTENVX_SYNC_FILES`
4. `.dotenvx-sync-files`
5. default files: `.env.development`, `.env.production`

Important current behavior:

- `--all-env` only auto-discovers `.env` and `.env.*`
- `.dotenvx-sync-files` and `--files` already accept arbitrary filenames
- `seal`, `unseal`, and `check` loop over the resolved file list without enforcing an `.env` suffix

### Effective behavior for `wrangler.toml` today

Today, a user can already place `wrangler.toml` in `.dotenvx-sync-files` or pass it through `--files`, and the script can encrypt and decrypt it with `dotenvx`.

What is missing is product-level support:

- there is no documented contract
- installer output does not fully communicate or protect the behavior
- tests do not cover it
- some user-facing messages are too env-specific

## Proposed Behavior

### Product model

The project remains env-first, with one additional documented explicit file type:

- auto-managed files: `.env`, `.env.*`
- explicitly managed extra file: `wrangler.toml`

The rule is:

- `.env*` files can be discovered automatically with `--all-env`
- `wrangler.toml` must be explicitly listed in `.dotenvx-sync-files` or passed with `--files`

This keeps the old default path stable while making the Cloudflare case official and supportable.

### Command behavior

#### `seal`

When `wrangler.toml` is part of the resolved managed file list:

- `seal` generates `wrangler.toml.encrypted`
- `seal` updates `.env.keys` with the matching wrangler private key entry
- `seal` does not alter the behavior of any existing `.env*.encrypted` outputs

If `wrangler.toml` is not part of the resolved managed file list:

- `seal` behaves exactly as it does today

#### `unseal`

When `wrangler.toml.encrypted` exists and `wrangler.toml` is part of the resolved managed file list:

- `unseal` restores `wrangler.toml`
- existing `--force` semantics remain unchanged
- if plaintext `wrangler.toml` already exists and `--force` is not used, it is kept

If `wrangler.toml` is not in the managed file list:

- `unseal` does not touch it

#### `check`

When `wrangler.toml` is managed:

- `check` reports plaintext presence
- `check` reports encrypted presence
- `check` reports whether plaintext is newer than encrypted
- `check` reports key availability using the same current key detection model

### Formatting behavior

Round-trip support is defined in terms of configuration content, not byte-for-byte file formatting.

Known and accepted behavior:

- decrypted `wrangler.toml` content remains semantically correct
- spacing may be normalized by the `dotenvx` round-trip
- for example, `name = "demo"` may return as `name="demo"`

This is acceptable for Scheme B and must be explicitly documented.

## Compatibility and Migration

### Existing projects that do not opt in

Projects already using encrypted `.env` sync but not listing `wrangler.toml` remain unchanged:

- `seal` keeps working on the same env files
- `unseal` keeps restoring the same env files
- existing `*.encrypted` env files remain valid
- no migration is required

### Existing projects that opt in later

If a project later adds `wrangler.toml` to `.dotenvx-sync-files` or `--files`:

- the next `seal` creates or updates `wrangler.toml.encrypted`
- `.env.keys` gains the wrangler private key entry
- existing `.env*.encrypted` files continue to work without regeneration
- the next `unseal` can restore `wrangler.toml`

This is an additive change, not a breaking migration.

### Existing plaintext file behavior

If a project already has a local plaintext `wrangler.toml`:

- `seal` reads it and produces `wrangler.toml.encrypted`
- `unseal` follows the same overwrite rules as env files
- without `--force`, existing plaintext stays untouched

### Key injection compatibility

The supported key sources for `wrangler.toml` remain the same as the current toolchain:

- `.env.keys`
- private key injection through environment variables

This change does not require a separate key distribution system for wrangler-managed files.

## Installer and Gitignore Design

### Installer goals

The installer must generate `.gitignore` rules that match the actual managed file set when the project explicitly manages `wrangler.toml`.

### Current installer problem

The current installer appends a dotenvx block once and exits early if the block already exists. That behavior is fine for static env-only defaults, but it does not adapt well when a project later adds `wrangler.toml` to `.dotenvx-sync-files`.

As a result, an already-bootstrapped project may end up with:

- `wrangler.toml.encrypted` intended for Git
- plaintext `wrangler.toml` still tracked or left unmanaged in `.gitignore`

### Proposed installer behavior

The installer will continue to derive managed files from `.dotenvx-sync-files` when present.

The generated `.gitignore` block will be rebuilt from current configuration instead of treated as immutable once created.

Desired block behavior:

- always ignore `.env*`
- always allow `!<managed-file>.encrypted` for each managed file
- always ignore `.env.keys`
- additionally ignore plaintext `wrangler.toml` when it is explicitly managed
- keep `!.env.example`

Example for a project managing `.env.development`, `.env.production`, and `wrangler.toml`:

```gitignore
# >>> dotenvx encrypted env sync >>>
.env*
wrangler.toml
!.env.development.encrypted
!.env.production.encrypted
!wrangler.toml.encrypted
!.env.example
.env.keys
# <<< dotenvx encrypted env sync <<<
```

### Update semantics

When the installer runs:

- if the managed block does not exist, create it
- if the managed block exists, replace only that block with a regenerated version
- do not rewrite unrelated `.gitignore` content

This lets old projects rerun the installer after adding `wrangler.toml` and get the correct ignore behavior without manual cleanup.

## Script-Level Changes

### Main sync script

The encryption and decryption pipeline does not need structural changes for Scheme B.

Required script changes are limited to clarity and messaging:

- update help and status wording where it incorrectly implies only plaintext `.env` files are supported
- preserve the current resolution model and `--all-env` scope
- avoid introducing new implicit discovery for `wrangler.toml`

The pipeline itself should continue to treat resolved files uniformly.

### Installer script

The installer requires real behavior changes:

- compute a regenerated managed block from current managed files
- support plaintext ignore for explicitly managed `wrangler.toml`
- replace the prior block instead of short-circuiting when the block already exists

## Documentation Changes

### README and README.en

Both docs should add a dedicated section describing explicit extra-file management.

Required doc content:

- `wrangler.toml` is supported when listed explicitly
- `--all-env` still only discovers `.env*`
- example `.dotenvx-sync-files` containing env files plus `wrangler.toml`
- explicit note that old projects are unaffected until they opt in
- explicit note that TOML spacing may be normalized after decrypting

Suggested example:

```txt
.env
.env.production
wrangler.toml
```

Suggested workflow note:

- commit `wrangler.toml.encrypted`
- do not commit plaintext `wrangler.toml` when managing it through this flow

## Test Plan

### New tests

#### 1. `wrangler.toml` round-trip test

Add an integration-style shell test that:

- creates a temporary project
- configures `.dotenvx-sync-files` with `wrangler.toml`
- writes a sample `wrangler.toml`
- runs `seal`
- confirms `wrangler.toml.encrypted` is generated
- runs `unseal --force`
- confirms the decrypted content contains the expected values
- does not require byte-identical formatting

This test should assert semantic content, not exact spacing.

#### 2. Installer gitignore regeneration test

Add a test that:

- prepares a project with `.dotenvx-sync-files` listing `wrangler.toml`
- runs the installer
- verifies `.gitignore` includes `wrangler.toml`
- verifies `.gitignore` includes `!wrangler.toml.encrypted`

Add a second pass or dedicated test for rerun behavior:

- modify or preserve an existing dotenvx block
- rerun the installer
- confirm the managed block is replaced rather than duplicated

### Existing test expectations

Existing env-focused tests should keep passing without behavioral changes.

That is part of the compatibility contract for Scheme B.

## Implementation Steps

1. Update installer block generation to support block replacement and plaintext `wrangler.toml` ignore when managed.
2. Adjust help and user-facing wording in the main script where needed to describe explicit extra-file support accurately.
3. Add README and README.en examples and migration notes.
4. Add integration coverage for `wrangler.toml` round-trip behavior.
5. Add installer coverage for `.gitignore` generation and regeneration with `wrangler.toml`.
6. Run the full shell test suite.

## Risks

### Risk: wording drifts into “generic file encryption” claims

Mitigation:

- keep docs explicit that this change officially supports `wrangler.toml`
- avoid broad “any file” promises in user-facing text

### Risk: users expect `--all-env` to include `wrangler.toml`

Mitigation:

- document the distinction repeatedly and clearly
- keep examples centered on `.dotenvx-sync-files`

### Risk: formatting-based test brittleness

Mitigation:

- assert semantic TOML content rather than exact original formatting

### Risk: `.gitignore` block replacement damages unrelated content

Mitigation:

- replace only the managed block delimiters and enclosed lines
- preserve all content before and after the block verbatim

## Acceptance Criteria

- A project can explicitly manage `wrangler.toml` using `.dotenvx-sync-files` or `--files`
- `seal` produces `wrangler.toml.encrypted`
- `unseal` restores `wrangler.toml` using existing overwrite semantics
- Existing projects that do not opt in behave exactly as before
- Installer-generated `.gitignore` correctly ignores plaintext `wrangler.toml` and allows `wrangler.toml.encrypted` when managed
- README and README.en document the opt-in behavior and formatting caveat
- Automated tests cover round-trip and installer behavior

## Open Questions Resolved

- Should `wrangler.toml` be auto-discovered by `--all-env`?
  No. It remains explicit-only.

- Should this change generalize the project into a universal encrypted config sync tool?
  No. That is out of scope for Scheme B.

- Will old encrypted env projects be affected automatically?
  No. They stay unchanged until `wrangler.toml` is explicitly added to the managed file list.
