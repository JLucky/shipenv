# [中文](README.md) | [English](README.en.md)

# shipenv

`shipenv` 提供一套可复用脚本，用于在任意项目中快速启用 `dotenvx` 的「明文本地保存、密文入库同步」工作流，默认会处理 `.env.development`、`.env.production`、`wrangler.toml` 和 `wrangler.jsonc`。

## 仓库内容

- `scripts/install-dotenvx-sync.sh`：一键安装器（复制脚本、改 `package.json`、改 `.gitignore`）
- `scripts/dotenvx-env-sync.sh`：执行加密/还原/状态检查

## 一键安装（新项目中执行）

```bash
curl --retry 3 --connect-timeout 10 --max-time 60 -fsSL \
  https://raw.githubusercontent.com/JLucky/shipenv/main/scripts/install-dotenvx-sync.sh | bash -s -- .
```

可选：安装时同时把 `@dotenvx/dotenvx` 加到当前项目 devDependencies：

```bash
curl --retry 3 --connect-timeout 10 --max-time 60 -fsSL \
  https://raw.githubusercontent.com/JLucky/shipenv/main/scripts/install-dotenvx-sync.sh | bash -s -- . --install-dotenvx
```

安装器已内置 `dotenvx-env-sync.sh`，通过 `curl | bash` 执行时只需要下载这一个远程脚本。

## 安装后会自动添加

- 脚本：`scripts/dotenvx-env-sync.sh`
- `package.json` 命令：
  - `env:check`
  - `env:check:all`
  - `env:seal`
  - `env:seal:all`
  - `env:unseal`
  - `env:unseal:force`
  - `env:unseal:all`
  - `env:unseal:all:force`
- `.gitignore` 的 dotenvx 同步规则（包含 `*.encrypted` 允许项，排除 `.env.keys`）

## 日常使用流程

```bash
# 1) 本机更新本地 env / wrangler 明文

# 2) 生成/更新密文文件
bun run env:seal

# 3) 提交密文
git add *.encrypted
git commit -m "chore: update encrypted env files"

# 4) 其他机器拉代码后还原本地明文
bun run env:unseal
```

如需覆盖已有本地明文：

```bash
bun run env:unseal:force
```

## 选择要处理的文件

`dotenvx-env-sync.sh` 支持 5 级优先级：

1. `--all-env`（处理当前目录全部 `.env` / `.env.*`，会自动跳过 `*.encrypted`、`*.example`、`.env.keys`）
2. `--files`
3. 环境变量 `DOTENVX_SYNC_FILES`
4. 项目根 `.dotenvx-sync-files`
5. 默认：`.env.development`, `.env.production`, `wrangler.toml`, `wrangler.jsonc`

### 示例：显式指定文件名

```bash
bun run env:seal -- --files ".env,.env.dev,.env.prod,wrangler.toml,wrangler.jsonc"
bun run env:unseal -- --files ".env,.env.dev,.env.prod,wrangler.toml,wrangler.jsonc"
```

### 示例：团队固定文件配置

创建 `.dotenvx-sync-files`：

```txt
.env
.env.dev
.env.prod
wrangler.toml
wrangler.jsonc
```

然后团队直接执行：

```bash
bun run env:seal
bun run env:unseal
```

### 兼容性说明

- 老项目如果此前只在同步 `.env*`，升级后默认也会把 `wrangler.toml` 和 `wrangler.jsonc` 视为受管文件
- 如果项目里没有 `wrangler.toml` / `wrangler.jsonc`，`seal` / `unseal` / `check` 只会提示 skipped，不会破坏现有 `.env*.encrypted`
- 如果项目里已有本地 `wrangler.toml` 或 `wrangler.jsonc`，下次 `seal` 会默认生成对应的 `*.encrypted`
- 如果仓库里已有 `wrangler.toml.encrypted` 或 `wrangler.jsonc.encrypted`，下次 `unseal` 会默认尝试恢复明文文件

## 安全建议

- 提交：`*.encrypted`
- 不提交：`.env.keys`、任何明文 `.env*`、明文 `wrangler.toml`、明文 `wrangler.jsonc`
- `seal` 会为任何实际存在的受管文件生成/更新 `.env.keys`，包括项目里只有 `wrangler.toml` 或 `wrangler.jsonc` 的情况
- 建议把 `.env.keys` 保存在 1Password/Bitwarden 等密码管理器中
- 也可使用环境变量注入私钥（如 `DOTENV_PRIVATE_KEY`, `DOTENV_PRIVATE_KEY_PROD`）
- 以 `#` 开头且符合注释配置格式的行（如 `#API_KEY=xxx`、`# API_KEY = xxx`）会在 `seal` 时加密，`unseal` 时恢复为注释格式
- `wrangler.toml` 经过 `seal` / `unseal` 后，内容会恢复，但空格格式可能被 `dotenvx` 规范化
- `wrangler.jsonc` 会作为完整文件加密，不会把 JSON 属性值留在密文文件里，解密后也不会插入破坏 JSONC 的 `#` 注释头

## 故障排查

- 查看状态：

```bash
bun run env:check
bun run env:check:all
```

- 直接查看脚本帮助：

```bash
bash scripts/dotenvx-env-sync.sh --help
bash scripts/install-dotenvx-sync.sh --help
```
