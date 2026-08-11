# MemoVault

[English](README.md)

纯本地文件系统 skill：教编码 agent 用 bash 把知识沉到 Obsidian vault。不需要
Obsidian 插件，**Obsidian 桌面端 / CLI 也不是运行时依赖**：MemoVault 直接以纯
markdown 读写 vault 目录下同一批文件。人可以另外用 Obsidian 桌面端浏览同一
个 vault。

| | |
|---|---|
| Skill 名 | `memovault` |
| 版本 | `0.7.0`（见 `VERSION`） |
| 安装后 skill 源 | `~/.agents/skills/memovault/` |
| 知识库 vault | `~/.agent-memo-vault/` |
| Vault 覆盖变量 | `AGENT_MEMO_VAULT` |
| 热度分层 | `seedling` / `growing` / `evergreen` |
| 可选笔记 kind | `raw` / `atom` / `scenario` / `persona` / `skill` |

## 为什么需要它

Agent 跨会话会丢上下文。MemoVault 提供本地、持久的第二大脑：一次写入，用
`[[wikilinks]]` 串联，用搜索 / 标签 / 回链找回，并按成熟度 `promote`。

Agent 遵循 always-on 记忆协议：`recall` 自动召回、半自动沉淀、把 inbox/raw
蒸馏成 atom/scenario，并把可复用 SOP 记到 `brain/skills/`。`daily/` 仅为
人用/legacy；vault `templates/` 可选（非 agent 写入真源）。`health` 提供
L0–L2 代理指标用于自评。

## 能力

- **写入 / 编辑：** `new`、`append`、`prepend`、`read`、`distill`；`daily`（legacy）
- **检索：** `recall`（FTS + 一跳图 RRF）、`search`（可过滤）、`dedupe`、`eval`
- **可观测：** `cite`、`feedback`、`suggest`、`health`/`stats`、ledger
- **图谱：** `backlinks`、`links`、`orphans`、`unresolved`
- **整理：** `move`、`rename`（链接安全）、`promote`、`supersede`、`moc`
- **分层记忆：** 可选 `kind` + `status`/`supersedes` + `sources`
- **单一 shell 运行时：** 一套 bash/文件系统实现；无 headless 开关、无 GUI 探测、不依赖 `obsidian` 二进制
- **跨平台：** macOS、Linux 官方支持；Windows 仅通过 WSL2 跑同一套 bash 脚本（不维护原生 PowerShell 业务逻辑）
- **多 Agent 安装：** Claude、Cursor、Codex、Gemini、Cline、Copilot 等

向量 / 语义搜索刻意延后，见 `docs/DEVELOPMENT.md`。
## 环境要求

- Bash（兼容 macOS 自带的 3.2）
- `find`、`awk`、`grep`、`mv`、`mktemp`；推荐 `rg`（可回退 `grep`）
- `jq` 仅在可选的 `--register-vault` 步骤需要；helper 本身不需要

Obsidian 是可选的：仅当你想用桌面端浏览 vault 时才装。helper 永不依赖 Obsidian
CLI，也不要求 Obsidian 在跑。

### Windows

Windows 仅通过 WSL2 支持。装好 WSL2 后，在 WSL shell 里跑同一套 bash 命令
（例如 `wsl ./scripts/memovault.sh ...`）。不提供也不维护原生 `.ps1` 实现。

## 快速开始

```bash
# 一行安装（需要 git）；无参数 = 安装 skill 源并注入全部 agent
curl -fsSL https://raw.githubusercontent.com/askdaddy/MemoVault-SKILL/main/install/install.sh | bash

# 从本仓库安装（默认行为相同）
./install/install.sh
./install/install.sh --register-vault   # 可选：把 vault 注册进 Obsidian 仅供浏览
./install/install.sh --verify           # 只读健康检查
```

常用变体：

```bash
./install/install.sh --agent cursor
# 或: curl .../install/install.sh | bash -s -- --agent cursor
./install/install.sh --upgrade          # 从源仓库再同步并重新注入 agents
```

`--force-fs` 为兼容旧脚本保留，但已是 no-op：运行时永远为 shell，没有可强制
的东西。安装后重启终端与 agent。完整说明：`docs/INSTALL.md`。

## 日常用法（给 agent）

安装后的 helper：

```bash
MM="$HOME/.agents/skills/memovault/scripts/memovault.sh"

"$MM" preflight
"$MM" new travel "Trip Plan" --kind atom --tags trip --body "See [[City Guide]]"
"$MM" search "Trip Plan" --limit 10
"$MM" backlinks "Trip Plan"
"$MM" rename "Trip Plan" "Trip Plan 2026"   # 跨 vault 的 [[wikilinks]] 会被改写
"$MM" promote "Trip Plan 2026"
```

开发本仓库时用 `./scripts/memovault.sh`。

Agent 侧契约以 `SKILL.md` 为准。

## Always-on 记忆协议

注入到各 agent 的适配器会要求：

1. **召回**：任务开始时 `recall`（失败再用 `search`）；helper 已按 heat/kind 排序
2. **先提议再写入**：沉淀可复用知识；用户明确说「记一下 / remember this」则立即写
3. **蒸馏**：`distill` 或手写把 inbox/raw 提炼为 `atom` / `scenario`，带 `sources` 与 `[[raw-title]]`
4. **Skill SOP**：`brain/skills/` + `--kind skill`（体例见协议；vault templates 可选）
5. **健康度**：适时 `health`，按指标建议 distill/promote/补链（不静默改库）

## 测试

端到端 harness（隔离临时 vault，绝不写 `~/.agent-memo-vault`）：

```bash
./scripts/e2e/run.sh            # 官方门禁：单阶段 shell，不需要 Obsidian
```

`--fs-only` 保留为兼容别名（no-op）；`--cli-only` 已移除。
Agent 编排 skill：`skills/testing-memovault/SKILL.md`
设计规格：`docs/superpowers/specs/2026-08-04-shell-only-runtime-design.md`（§8 取代
2026-08-03 的双模式门禁）。

## 文档索引

| 文档 | 用途 |
|---|---|
| `AGENTS.md` | 项目章程与命名合同 |
| `SKILL.md` | 面向 agent 的 skill 定义（唯一真源） |
| `docs/INSTALL.md` | 安装、校验、升级、卸载 |
| `docs/ARCHITECTURE.md` | 单 shell 分层与数据流 |
| `docs/CLASSIFICATION.md` | 领域、热度与 memory kinds |
| `docs/CLI-REFERENCE.md` | 可选的 Obsidian CLI 参考（人用；非运行时依赖） |
| `docs/DEVELOPMENT.md` | 扩展适配器 / 阶段 / e2e 指针 |
| `docs/RIPER.md` | 规格驱动变更记录 |

## 硬约束

- 文件、注释、文档、脚本、笔记内容均禁止 emoji
- 绝不写入 `$AGENT_MEMO_VAULT` 之外
- 删除或批量移动前必须征得用户确认

## 许可证

[MIT](LICENSE) — Copyright (c) 2026 Seven Chan
