# [中文](README.md) | [English](README.en.md)

# shipenv

`shipenv` 提供一套可复用脚本，用于在任意项目中快速启用 `dotenvx` 的「明文本地保存、密文入库同步」工作流。

## 仓库内容

- `scripts/install-dotenvx-sync.sh`：一键安装器（复制脚本、改 `package.json`、改 `.gitignore`）
- `scripts/dotenvx-env-sync.sh`：执行加密/还原/状态检查

## 一键安装（新项目中执行）

```bash
curl -fsSL https://raw.githubusercontent.com/JLucky/shipenv/main/scripts/install-dotenvx-sync.sh | bash -s -- .
```

可选：安装时同时把 `@dotenvx/dotenvx` 加到当前项目 devDependencies：

```bash
curl -fsSL https://raw.githubusercontent.com/JLucky/shipenv/main/scripts/install-dotenvx-sync.sh | bash -s -- . --install-dotenvx
```

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
# 1) 本机更新本地 env 明文

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

## 选择要处理的 env 文件

`dotenvx-env-sync.sh` 支持 5 级优先级：

1. `--all-env`（处理当前目录全部 `.env` / `.env.*`，会自动跳过 `*.encrypted`、`*.example`、`.env.keys`）
2. `--files`
3. 环境变量 `DOTENVX_SYNC_FILES`
4. 项目根 `.dotenvx-sync-files`
5. 默认：`.env.development`, `.env.production`

### 示例：显式指定文件名

```bash
bun run env:seal -- --files ".env,.env.dev,.env.prod"
bun run env:unseal -- --files ".env,.env.dev,.env.prod"
```

### 示例：团队固定文件配置

创建 `.dotenvx-sync-files`：

```txt
.env
.env.dev
.env.prod
```

然后团队直接执行：

```bash
bun run env:seal
bun run env:unseal
```

## 安全建议

- 提交：`*.encrypted`
- 不提交：`.env.keys`、任何明文 `.env*`
- 建议把 `.env.keys` 保存在 1Password/Bitwarden 等密码管理器中
- 也可使用环境变量注入私钥（如 `DOTENV_PRIVATE_KEY`, `DOTENV_PRIVATE_KEY_PROD`）

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
