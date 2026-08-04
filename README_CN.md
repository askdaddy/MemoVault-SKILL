# MemoVault

[English](README.md)

纯本地文件系统 skill：教编码 agent 用 bash 把知识沉到 Obsidian vault。不需要
Obsidian 插件。

桌面端 Obsidian 在跑时，走官方 [Obsidian CLI](https://obsidian.md/cli)；否则在同一
套 markdown 上退回纯文件系统 + `rg`/`grep`。

| | |
|---|---|
| Skill 名 | `memovault` |
| 版本 | `0.4.1`（见 `VERSION`） |
| 安装后 skill 源 | `~/.agents/skills/memovault/` |
| 知识库 vault | `~/.agent-memo-vault/` |
| Vault 覆盖变量 | `AGENT_MEMO_VAULT` |
| 热度分层 | `seedling` / `growing` / `evergreen` |
| 可选笔记 kind | `raw` / `atom` / `scenario` / `persona` / `skill` |

## 为什么需要它

Agent 跨会话会丢上下文。MemoVault 提供本地、持久的第二大脑：一次写入，用
`[[wikilinks]]` 串联，用搜索 / 标签 / 回链找回，并按成熟度 `promote`。

Agent 遵循 always-on 记忆协议：自动召回、半自动沉淀、把 raw/日记蒸馏成
atom/scenario，以及把可复用 SOP 记到 `brain/skills/`。

## 能力

- **写入 / 编辑：** `new`、`append`、`prepend`、`read`、`daily`、`daily:append`
- **检索：** 全文 `search`、`tags` / `by-tag`、`by-heat`
- **图谱：** `backlinks`、`links`、`orphans`、`unresolved`
- **整理：** `move`、`rename`（`cli` 下链接安全）、`promote`、`moc`
- **分层记忆：** 可选 `kind` + `sources`（蒸馏溯源）
- **双运行时：** Obsidian+CLI 可用时为 `cli`；否则 `fs`（也可用 `MM_FORCE_FS=1` 强制无头）
- **多 Agent 安装：** Claude、Cursor、Codex、Gemini、Cline、Copilot 等

向量 / 语义搜索刻意延后，见 `docs/DEVELOPMENT.md`。

## 环境要求

- Bash（兼容 macOS 自带的 3.2）
- 注册 vault / e2e 的 cli 阶段需要 `jq`；推荐 `rg`（可回退 `grep`）
- 只要 **`cli` 模式** 才需要 Obsidian 安装包 **1.12.7+**
  （设置 -> 通用 -> 启用命令行接口，并注册到 PATH）

没有 Obsidian 也能用 `fs` 模式。

## 快速开始

```bash
# 在本仓库根目录
./install/install.sh --all              # 安装 skill 源 + 注入所有支持的 agent
./install/install.sh --register-vault   # 把 ~/.agent-memo-vault 注册进 Obsidian
./install/install.sh --verify           # 只读健康检查
```

常用变体：

```bash
./install/install.sh --agent cursor
./install/install.sh --force-fs         # 在 env.sh 固定 MM_FORCE_FS=1（无头）
./install/install.sh --upgrade          # 从本仓库再同步并重新注入 agents
```

安装后重启终端与 agent。完整说明：`docs/INSTALL.md`。

## 日常用法（给 agent）

安装后的 helper：

```bash
MM="$HOME/.agents/skills/memovault/scripts/memovault.sh"

"$MM" preflight
"$MM" new travel "Trip Plan" --kind atom --tags trip --body "See [[City Guide]]"
"$MM" search "Trip Plan" --limit 10
"$MM" backlinks "Trip Plan"
"$MM" promote "Trip Plan"
```

开发本仓库时用 `./scripts/memovault.sh`。

Agent 侧契约以 `SKILL.md` 为准。

## Always-on 记忆协议

注入到各 agent 的适配器会要求：

1. **召回**：任务开始时 `search`，优先 evergreen/growing 与更丰富的 kind
2. **先提议再写入**：沉淀可复用知识；用户明确说「记一下 / remember this」则立即写
3. **蒸馏**：把日记/raw 提炼为 `atom` / `scenario`，带 `sources` 与 `[[YYYY-MM-DD]]` 溯源
4. **Skill SOP**：`brain/skills/` + `--kind skill`（见 `templates/skill.md`）

## 测试

端到端 harness（隔离临时 vault，绝不写 `~/.agent-memo-vault`）：

```bash
./scripts/e2e/run.sh            # 官方门禁：fs + cli（需要 Obsidian+CLI）
./scripts/e2e/run.sh --fs-only  # 无头 / CI 逃生口
```

Agent 编排 skill：`skills/testing-memovault/SKILL.md`  
设计规格：`docs/superpowers/specs/2026-08-03-e2e-testing-design.md`

## 文档索引

| 文档 | 用途 |
|---|---|
| `AGENTS.md` | 项目章程与命名合同 |
| `SKILL.md` | 面向 agent 的 skill 定义（唯一真源） |
| `docs/INSTALL.md` | 安装、校验、升级、卸载 |
| `docs/ARCHITECTURE.md` | cli/fs 分层与数据流 |
| `docs/CLASSIFICATION.md` | 领域、热度与 memory kinds |
| `docs/CLI-REFERENCE.md` | Obsidian CLI 精简参考 |
| `docs/DEVELOPMENT.md` | 扩展适配器 / 阶段 / e2e 指针 |
| `docs/RIPER.md` | 规格驱动变更记录 |

## 硬约束

- 文件、注释、文档、脚本、笔记内容均禁止 emoji
- 绝不写入 `$AGENT_MEMO_VAULT` 之外
- 删除或批量移动前必须征得用户确认

## 许可证

[MIT](LICENSE) — Copyright (c) 2026 Seven Chan
