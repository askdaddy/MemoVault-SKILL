# 设计：MemoVault 端到端测试（混合 harness + agentic skill）

日期：2026-08-03  
状态：已批准  
仓库：MemoVault-SKILL

## 1. 目标

让任意编码 agent 都能用同一套、可发现的方式，对 MemoVault 做完整端到端验收：

1. **机械 harness** — 在隔离 vault 上断言每个 helper 子命令可用；`fs` 与 `cli` 双模式都必须通过。
2. **Agentic skill** — 教 agent 如何调用 harness、跑 memory protocol 检查清单，并输出一份统一的通过/失败报告。

本设计范围外：`install.sh` / `upgrade` 覆盖、向量搜索、以及除「确认删除仍需门控」以外的破坏性删除流程。

## 2. 已锁定决策

| 主题 | 选择 |
|---|---|
| 形态 | 混合：bash harness + 仓库内 agentic skill |
| Vault | 仅隔离 vault；绝不写入 `~/.agent-memo-vault` |
| 模式 | `fs` 与 `cli` 都必须通过，否则整体 FAIL |
| 覆盖面 | Helper 命令面 + memory protocol |
| Skill 位置 | 仅仓库内：`skills/testing-memovault/`（不安装到 `~/.agents/skills`） |
| 实现路径 | 单入口 harness + 薄编排 skill |

## 3. 架构

```
skills/testing-memovault/SKILL.md     agent 入口（何时 / 如何 / 报告）
        |
        v
scripts/e2e/run.sh                    机械层单入口
        |
        +-- lib/env.sh                隔离 vault、解析 MM、切换模式
        +-- lib/assert.sh             计数器与 assert_* 助手
        +-- lib/register.sh           临时注册 Obsidian vault（cli 用）
        +-- suites/01-preflight.sh
        +-- suites/02-capture.sh
        +-- suites/03-retrieve.sh
        +-- suites/04-graph.sh
        +-- suites/05-organize.sh
        |
        v
stdout 汇总 + exit 0|1
        |
        v
agent protocol 检查清单（若 --keep 则同一 vault）
        |
        v
统一 E2E 报告
```

### 3.1 隔离 vault（为何不能只用裸 /tmp）

用户要求：绝不碰真实知识库 vault。

`cli` 模式要求 Obsidian 认识该路径（`obsidian.json`）。未注册的 `/tmp/...` 对 CLI 不可见。

**做法：**

- 每次运行创建 `E2E_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/memovault-e2e.XXXXXX")"`。
- Vault 位于 `$E2E_ROOT/vault`。
- 所有 helper 调用都导出 `AGENT_MEMO_VAULT="$E2E_ROOT/vault"`。
- **FS 阶段：** `MM_FORCE_FS=1`；无需注册 Obsidian。
- **CLI 阶段：** 清空/重建 vault 内容；将 `$E2E_ROOT/vault` 注册进 `obsidian.json`，专用名 `memovault-e2e`（不是 `agent-memo-vault`）；先备份 `obsidian.json`，teardown（或 EXIT trap）时整文件还原。要求 Obsidian 桌面端在跑，且 PATH 上有真正的 `obsidian` CLI。
- 被测 helper 始终是**仓库内**副本：`"$REPO/scripts/memovault.sh"`。不要用已安装的 `~/.agents/skills/memovault`（避免安装目录里的 `env.sh` 强制 FS）。

若注册失败，或 CLI 阶段 `preflight` 未报告 `mode=cli`，则硬失败。

### 3.2 模式阶段

1. **语法 / 冒烟：** 对 `scripts/memovault.sh`、`scripts/lib/*.sh` 以及 e2e 脚本做 `bash -n`（廉价门禁）。
2. **FS 套件：** 强制 FS，跑 suites 01–05。
3. **CLI 套件：** 注册 vault，取消 `MM_FORCE_FS`，要求 `mode=cli`，再跑 suites 01–05（organize 增加 link-safe 断言）。
4. **Teardown：** 还原 `obsidian.json` 备份；除非 `--keep`，否则删除 `$E2E_ROOT`（`--keep` 时打印路径供 protocol 跟测）。

任一断言失败，或 CLI 阶段进不了 `cli` 模式，整体 exit 非零。

## 4. Harness 细节

### 4.1 `scripts/e2e/run.sh` 参数

| 参数 | 含义 |
|---|---|
| （默认） | 完整双模式；结束后删除 vault |
| `--keep` | 保留 `$E2E_ROOT` 并打印 `E2E_VAULT=...`，供 protocol 跟测 |
| `--fs-only` | 开发逃生口；**不是** agentic skill 的默认路径。官方 e2e 禁止使用（双模式强制）。 |
| `--cli-only` | 同上：仅逃生口 |
| `--repo <path>` | 覆盖仓库根（默认按脚本位置推断） |

### 4.2 断言库

`scripts/e2e/lib/assert.sh`：

- `e2e_pass "name"` / `e2e_fail "name" "detail"`
- `assert_eq expected actual msg`
- `assert_contains haystack needle msg`
- `assert_file path msg`
- `assert_grep pattern file msg`
- 全局计数 `E2E_PASS` / `E2E_FAIL`；汇总打印
- 不用 `set -e`；显式检查（与 helper 风格一致）
- 兼容 Bash 3.2；无 emoji

### 4.3 断言矩阵（helper 命令面）

每次运行使用唯一标题前缀：形如 `E2E $(date +%s)`，例如 `E2E Alpha Atom`，避免 `--keep` 复用时撞名。

| Suite | 子命令 | 断言（未注明则双模式都测） |
|---|---|---|
| 01 | `preflight` | 输出含 `mode=`，且 `vault=` 等于 `$AGENT_MEMO_VAULT`。FS 阶段：`mode=fs` 且 `forced=1`。CLI 阶段：`mode=cli` 且 `forced=0`。 |
| 02 | `new` | 创建 `brain/<domain>/<Title>.md`；frontmatter 含 `title`、`domain`、`heat`、`created`；`--kind atom` 与 `--tags` 正确写入；`--kind skill` 默认 heat 为 `growing`。 |
| 02 | `append` / `prepend` | 正文末尾 / frontmatter 后出现追加内容；frontmatter 完好。 |
| 02 | `read` | 输出含标题与正文标记。 |
| 02 | `daily` / `daily:append` | 创建或展示 `daily/YYYY-MM-DD.md`；append 写入对应行。 |
| 03 | `search` | 能搜到唯一正文 token；在命中足够多时 `--limit` 生效。 |
| 03 | `tags` / `by-tag` / `tag` | 种子 tag 出现；`by-tag` 列出种子笔记。 |
| 03 | `by-heat` | 种子 heat 落在正确分层/分组下。 |
| 04 | `links` / `backlinks` | 笔记 A 含 `[[B]]`；`links A` 提到 B；`backlinks B` 提到 A（fs：文本扫描即可）。 |
| 04 | `orphans` | 无入链的新笔记出现在 orphans 列表中。 |
| 04 | `unresolved` | 正文含 `[[E2E Missing NoSuchNote]]` 时出现在 unresolved。 |
| 05 | `promote` | `seedling` -> `growing` -> `evergreen`；`updated` 刷新；对 evergreen 再 promote 的行为按当前 helper 文档断言（失败或 no-op）。 |
| 05 | `moc` | 写出 `brain/<domain>/_<domain>-MOC.md` 并列出种子笔记。 |
| 05 | `rename` | 文件改名；新标题下 `read` 可用。**仅 CLI 额外：** 入链 `[[旧标题]]` 更新为新标题（或 Obsidian 等价行为）。**FS：** 只断言文件移动；链接可能断裂属预期。 |
| 05 | `move` | 文件到新目录。**仅 CLI 额外：** 链接仍可解析。**FS：** 只断言路径变化。 |
| gate | 路径逃逸 | 试图写到 vault 外的操作被拒绝（对齐 `DEVELOPMENT.md` 检查项）。 |

`upgrade` **不在**矩阵内（范围外）。

### 4.4 CLI link-safe 检查

仅在 CLI organize 套件中：

1. 创建 `E2E Link Target` 与 `E2E Link Source`（正文 `See [[E2E Link Target]]`）。
2. `rename "E2E Link Target" "E2E Link Target Renamed"`。
3. 断言 `E2E Link Source` 正文已引用新标题（wikilink 已更新）。
4. 对 `move` 到另一 domain 目录做类似检查；若 Obsidian 只按笔记名更新，则用 `backlinks` / `read` 断言按名仍可解析。

若 rename/move 中途回退到 fs（helper 打出 fallback 日志），视为 CLI 阶段失败（模式虚假或 CLI 操作失败）。

## 5. Agentic skill 合同

### 5.1 位置与发现

```
skills/testing-memovault/SKILL.md
```

YAML frontmatter（`description` 只写触发条件，不概括流程）：

```yaml
---
name: testing-memovault
description: "Use when verifying MemoVault end-to-end, running the memovault e2e suite, checking fs and cli mode parity, or validating the memory protocol against an isolated vault."
---
```

### 5.2 Skill 正文要求 agent 做什么（大纲）

1. **前置条件：** 位于仓库根；官方双模式运行需要 Obsidian 桌面端在跑且 CLI 在 PATH；不要指向真实 vault。
2. **步骤 A — 机械层：** 在仓库根执行 `./scripts/e2e/run.sh --keep`。要求 exit 0。捕获打印的 `E2E_VAULT`。
3. **步骤 B — Protocol 检查清单**（导出 `AGENT_MEMO_VAULT=$E2E_VAULT`；protocol 写入优先 `MM_FORCE_FS=1`，除非专门测 cli 召回）：
   - Recall：用窄关键词 `search`；排序偏好 evergreen/growing，以及 `kind` 为 persona|scenario|skill|atom（在报告中记录排序说明；不必自动化算分）。
   - Propose-then-capture：在 skill 模拟的用户确认之前，**不得**写入持久 atom（自检：先写 propose 文本，报告日志中出现 `user: yes` 后再 `new`）。
   - Explicit remember：遇到 `remember this` 立即 `new`，并在报告中确认路径/标题。
   - Distill：`daily:append` 原始行 -> `new ... --kind atom`，带 `sources` / 正文 `[[YYYY-MM-DD]]`。
   - Skill SOP：`new skills "..." --kind skill`，正文含 Trigger / Steps / Verify / Related。
4. **步骤 C — 报告：** 按下方固定格式输出。若 harness 失败，不得宣称 protocol 通过；整体标 FAIL。
5. **清理：** 非调试时，报告后 `rm -rf "$E2E_ROOT"`（harness 会打印 `E2E_ROOT`）。

### 5.3 报告格式（必填）

```
# MemoVault E2E report
repo: <path>
date: <ISO date>
harness: PASS|FAIL
  fs: PASS|FAIL
  cli: PASS|FAIL
  asserts_pass: <n>
  asserts_fail: <n>
protocol: PASS|FAIL|SKIP
  recall: PASS|FAIL
  propose_capture: PASS|FAIL
  explicit_remember: PASS|FAIL
  distill: PASS|FAIL
  skill_sop: PASS|FAIL
overall: PASS|FAIL
notes: <one line>
```

## 6. 文档 / 流程衔接（Execute 阶段）

- 在 `docs/DEVELOPMENT.md` 第 6 节增加指向本设计、`skills/testing-memovault/SKILL.md` 与 `scripts/e2e/run.sh` 的指针。
- 落地实现时在 `docs/RIPER.md` 追加条目。
- **不要**改命名合同或生产 vault 默认路径。
- 后续可选：FS-only 的 CI **不是**官方门禁；官方门禁仍是双模式（在需要 Obsidian 的环境上可由人工或 agent 驱动）。

**文档语言约定（本仓库后续）：** 面向人与 agent 的说明文档（`docs/`、设计稿、RIPER 新条目等）默认使用中文；命令名、路径、环境变量、代码标识符保持英文。脚本内注释与用户可见的 helper 英文文案是否迁移，另议，不在本次范围。

## 7. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 临时 vault 对 Obsidian CLI 不可见 | 临时注册 + 还原 `obsidian.json` |
| 已安装 `env.sh` 强制 FS | 始终调用仓库内 `scripts/memovault.sh` |
| 主机无 CLI | 整体 FAIL，并明确 `cli: FAIL` 原因（按设计如此） |
| Protocol 检查偏软 | 固定报告字段；任一项 FAIL 则禁止 overall PASS |
| 真实 vault 残留 e2e 笔记 | 永不把 `AGENT_MEMO_VAULT` 指到生产路径 |
| Trap 失败导致注册表脏 | 整文件备份/还原 `obsidian.json`；文档说明手工还原 |

## 8. 成功标准

- 其他 agent 仅凭本仓库，加载 `skills/testing-memovault/SKILL.md` 即可跑完全流程，无需额外口头约定。
- 在 Obsidian+CLI 可用时，单独跑 `./scripts/e2e/run.sh` 足以拦住 helper 回归。
- 无论绿/红跑完，真实 vault `~/.agent-memo-vault` 未被修改。
- 新增文件无 emoji。

## 9. 非目标（重申）

- 不把 testing skill 装进 `~/.agents/skills/`
- 不自动化 install/upgrade e2e
- 不替代人对 skill 文案质量的审阅
- 不做向量搜索测试
