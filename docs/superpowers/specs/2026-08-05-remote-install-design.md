# 设计：install.sh 双模式远程安装（curl | bash）

日期：2026-08-05  
状态：已批准  
仓库：MemoVault-SKILL  
版本目标：`0.5.1`（patch：一行远程安装 + 无参默认 `--all`）

## 1. 目标

让用户无需先 `git clone` 再跑安装器，支持一行安装：

```bash
curl -fsSL https://raw.githubusercontent.com/askdaddy/MemoVault-SKILL/main/install/install.sh | bash
```

同时保留开发者从本地仓库直接运行 `./install/install.sh` 的路径（使用当前工作树，便于未提交改动的试装）。

**为何不用 `bash -s -- --all`：** 管道默认无法向脚本传参；要传参必须写成 `bash -s -- <flags>`。为保持一行最简，**无参数时默认等同 `--all`**（安装 skill source + 注入全部支持的 agent）。`-h` / `--help` 仍只显示帮助。需要定制时再用 `... | bash -s -- --agent cursor` 等。

## 2. 已锁定决策

| 主题 | 选择 |
|---|---|
| 入口形态 | 改现有 `install/install.sh`；**不**新增独立 `bootstrap.sh` |
| 模式 | **A：双模式**（本地完整树 vs 远程同步 cache） |
| 无参数默认 | **等同 `--all`**（breaking 相对今日「无参只打 usage」；本地与远程一致） |
| Cache 路径 | 默认 `$HOME/.cache/memovault/repo` |
| 获取方式 | `git clone` / 更新；无 git 则失败并提示 |
| Tarball / 无 git | 本轮不做 |
| 远程 URL | 默认 `https://github.com/askdaddy/MemoVault-SKILL.git` |
| 默认 ref | `main`（可用 env 覆盖为 branch/tag） |

## 3. 非目标

- 独立 `install/bootstrap.sh`
- GitHub archive tarball / 纯 curl+tar 无 git 安装
- 改变 agent 注入、vault scaffold、`--verify`、`--upgrade` 的核心语义（仅改：无参默认从「打 usage」变为「等同 --all」）
- 自动写入 shell rc、`sudo`、原生 Windows 安装器
- 强制把已有 `.source-origin`（指向工作区）迁移到 cache

## 4. 架构

### 4.1 模式判定

脚本启动后尽早计算候选 `ROOT`（现有：`HERE=dirname(BASH_SOURCE)`，`ROOT=HERE/..`）。

**本地完整树**当且仅当以下文件均存在：

- `$ROOT/VERSION`
- `$ROOT/SKILL.md`
- `$ROOT/install/targets.sh`
- `$ROOT/scripts/memovault.sh`

若判定为本地完整树：行为与今日一致，`$ROOT` 为开发仓库。

否则（典型：`curl | bash`，`BASH_SOURCE` 为空或旁路无仓库树）：进入**远程模式**。

管道注意事项：从 stdin 执行时，部分环境 `BASH_SOURCE[0]` 为 `stdin` 或空；判定必须依赖「完整树文件是否存在」，不能仅依赖「是否在 git 仓库内」。

### 4.2 远程模式流程

```
curl | bash -s -- <args>
  -> install.sh (stdin copy): not a full tree
  -> ensure cache repo at MEMOVAULT_CACHE_REPO (default ~/.cache/memovault/repo)
  -> git clone or fetch/checkout/pull
  -> exec "$cache/install/install.sh" "$@"
  -> cache copy: full tree -> local mode -> existing install logic
```

步骤：

1. 解析 cache 路径：`MEMOVAULT_CACHE_REPO` 或 `$HOME/.cache/memovault/repo`。
2. 解析 `MEMOVAULT_REPO_URL`（默认上述 https GitHub URL）与 `MEMOVAULT_REF`（默认 `main`）。
3. 若 `command -v git` 失败：打印明确错误（需 git，或先 clone 后本地安装）并以非零退出。
4. 若 cache 目录不存在或不含 `.git`：
   - `mkdir -p` 父目录；
   - `git clone --depth 1 --branch "$REF" "$URL" "$cache"`（若 `--branch` 对某 tag 失败，实现计划可选用等价的浅克隆写法，但合同是检出 `$REF`）。
5. 若 cache 已是 git 仓库：
   - `git -C "$cache" fetch --depth 1 origin "$REF"`（或等价）；
   - checkout / reset 到该 ref 的 ff 更新；
   - 优先 `git pull --ff-only`；失败则 **警告并继续**使用当前 cache 内容（与现有 upgrade「pull 失败不阻断」一致）。
6. 确认 `$cache` 通过「本地完整树」判定；否则 `mm_die`。
7. `exec "$cache/install/install.sh" "$@"`，透传全部参数与当前环境变量。

`exec` 保证安装逻辑只跑一遍（cache 内脚本走本地模式）。

### 4.3 与 `.source-origin` / upgrade

- 远程安装成功后，`mm_install_source` 写入的 `.source-origin` 为 **cache 路径**。
- 之后 `memovault upgrade` / `install.sh --upgrade` 对 cache 做 `git pull` 再 re-sync，与现有逻辑兼容。
- 本地仓库安装仍把 `.source-origin` 写成该开发路径；**不**自动改写旧 origin。

### 4.4 环境变量合同

| 变量 | 含义 | 默认 |
|---|---|---|
| `MEMOVAULT_CACHE_REPO` | 远程模式下的 clone 目录 | `$HOME/.cache/memovault/repo` |
| `MEMOVAULT_REPO_URL` | git remote URL | `https://github.com/askdaddy/MemoVault-SKILL.git` |
| `MEMOVAULT_REF` | branch 或 tag | `main` |
| 现有 `MEMOVAULT_SOURCE` / `AGENT_MEMO_VAULT` / `MEMOVAULT_DEV_REPO` | 不变 | 见现 INSTALL |

## 5. 用户可见文案

### 5.1 Quick start（README / README_CN）

主路径改为 curl 一行；次要保留「从本仓库」：

```bash
# One-line install (requires git); no flags => --all
curl -fsSL https://raw.githubusercontent.com/askdaddy/MemoVault-SKILL/main/install/install.sh | bash

# From a local checkout (same default)
./install/install.sh
./install/install.sh --agent cursor   # optional: one agent
```

中文 README 同步。定制参数示例可写在 INSTALL（`bash -s -- --agent cursor`），不放进 Quick start 主路径。

### 5.2 `docs/INSTALL.md`

新增一节「One-line / remote install」：curl 示例、**无参默认 --all**、cache 路径、三个 env、与本地安装 / upgrade 的关系；原「从仓库根运行」保留。说明今日「无参只打 usage」已改为默认全量安装。

### 5.3 `install.sh --help`

简短说明：可由 curl 管道调用；无完整旁路树时会同步到 cache 再安装；**无参数时默认 --all**。

### 5.4 `docs/RIPER.md`

追加本决策条目（实现阶段写入）。

### 5.5 `SKILL.md`

若有安装指引则补一句 curl；无则可不改。

## 6. 实现触点（文件）

| 文件 | 动作 |
|---|---|
| `install/install.sh` | 增加完整树检测、远程同步、`exec` 重入；usage 文案 |
| `README.md` | Quick start |
| `README_CN.md` | Quick start |
| `docs/INSTALL.md` | 远程安装节 |
| `docs/RIPER.md` | 过程记录 |
| `SKILL.md` | 仅当有安装段时同步 |

不新增 `install/bootstrap.sh`。

## 7. 错误与幂等

- 无网络 / clone 失败：非零退出，stderr 说明。
- 无 git：非零退出。
- 二次 curl 安装：更新 cache 后再次走完整 install（idempotent；`--force` 等行为不变）。
- Dry-run：远程模式仍应能同步 cache 或明确文档「dry-run 是否跳过 clone」——**本规格选定**：远程模式在 `exec` 之前仍执行 clone/更新（否则 dry-run 无法预览真实 installer）；透传 `--dry-run` 给 cache 内脚本。

## 8. 验收

1. 模拟管道：`bash install/install.sh` 在「伪造无完整 ROOT」或通过 `bash <(cat install/install.sh)` / stdin 方式，最终 skill 装到 `~/.agents/skills/memovault/`（测试可用临时 `HOME`），cache 在 `~/.cache/memovault/repo`，`.source-origin` 指向 cache。
2. 从真实仓库 `./install/install.sh --dry-run --source-only`：不强制写入/覆盖 cache（本地模式不触发远程同步）。
3. `bash -n install/install.sh` 通过。
4. 远程安装后 `--verify`（在注入过 agent 的前提下）与升级路径可用。

## 9. 开放项（实现计划可定，不阻塞本设计）

- 是否 bump `VERSION`：**已定为 `0.5.1`**。
- 浅克隆对「非 branch 的 tag」的精确 git 命令（保持检出 `MEMOVAULT_REF` 即可）。
