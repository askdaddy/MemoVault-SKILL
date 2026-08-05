# 纯 shell 运行时（0.5.0）— 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans，按任务逐项实现。步骤使用 checkbox（`- [ ]`）跟踪。

**Goal:** 移除 Obsidian CLI 运行时，仅保留 bash/fs；为 rename 增加 wikilink 改写；e2e 改为单阶段 shell 门禁；文档与版本升至 0.5.0；官方平台 macOS/Linux，Windows 用 WSL。

**Architecture:** `memovault.sh` 只派发到 `fs.sh`；新建 `scripts/lib/rewrite.sh` 供 `mmfs_rename` 调用；删除 `cli.sh` 与模式探测；e2e 去掉 register/cli 阶段。

**Tech Stack:** Bash 3.2、awk、find、grep/rg、mktemp；无 Obsidian CLI。

**规格：** `docs/superpowers/specs/2026-08-04-shell-only-runtime-design.md`

## Global Constraints

- 无 emoji；Bash 3.2；`set -uo pipefail`；不用 `set -e`
- 绝不写入 `~/.agent-memo-vault` 之外（测试用临时 vault）
- 禁止 `sed -i`；改写用 mktemp + mv
- 官方平台：macOS、Linux；Windows = WSL2 only
- 不维护原生 PowerShell 业务逻辑
- 版本目标 `0.5.0`
- 仅在用户明确要求时 git commit

---

## 文件结构

| 路径 | 动作 | 职责 |
|---|---|---|
| `scripts/lib/rewrite.sh` | 新建 | wikilink 扫描与改写 |
| `scripts/lib/fs.sh` | 修改 | rename 调 rewrite；日志文案 |
| `scripts/memovault.sh` | 修改 | 去 cli 包装；新 preflight |
| `scripts/lib/cli.sh` | 删除 | — |
| `scripts/lib/classify.sh` | 修改 | promote 仅 fs |
| `scripts/e2e/run.sh` | 修改 | 单阶段 |
| `scripts/e2e/lib/register.sh` | 删除 | — |
| `scripts/e2e/lib/env.sh` | 修改 | 去掉 cli phase helpers 对 register 的依赖 |
| `scripts/e2e/suites/01-preflight.sh` | 修改 | runtime=shell |
| `scripts/e2e/suites/05-organize.sh` | 修改 | rename 后断言入链更新（非仅 cli） |
| `VERSION` / `SKILL.md` / README* / docs/* | 修改 | 0.5.0 与叙述 |
| `install/install.sh` | 修改 | `--force-fs` 废弃提示 |

---

### Task 1: `rewrite.sh` + 挂到 `mmfs_rename`

**Files:**
- Create: `scripts/lib/rewrite.sh`
- Modify: `scripts/lib/fs.sh`（source rewrite；`mmfs_rename` 末尾调用；更新日志）
- Modify: `scripts/memovault.sh`（确保 source rewrite，若由 fs 间接 source 则可只在 fs 里 `.`）

**Interfaces:**
- Produces: `mm_rewrite_wikilinks <old_key1,old_key2,...> <new_title>` 或 `mm_rewrite_wikilinks_from_note <old_file> <new_title> <old_stem>`  
  推荐 API：

```bash
# After file has been moved to $new_file. Keys are newline-separated or pass explicitly.
# mm_wikilink_keys_for_file <file>  -> prints keys one per line (stem, title, aliases)
# mm_rewrite_wikilinks <new_title>   # reads keys from stdin (one per line)
# Returns 0; prints count of files modified to stdout as "files_updated=N" or via mm_log
mm_wikilink_keys_for_file() { ... }
mm_rewrite_wikilinks() {
  local new_title="$1"  # already sanitized stem/title text for [[...]]
  # keys on stdin
}
```

- [ ] **Step 1: 写失败断言（e2e 片段或临时脚本）证明 rename 不改链接**

在隔离 vault 用**当前** helper（改 rewrite 前）应失败的检查：

```bash
cd /Users/seven/Workspace/MemoVault-SKILL
export AGENT_MEMO_VAULT="$(mktemp -d)/vault"
export MM_FORCE_FS=1
MM=./scripts/memovault.sh
mkdir -p "$AGENT_MEMO_VAULT"
"$MM" new e2e "Old Name" --kind atom --body "x" >/dev/null
"$MM" new e2e "Linker" --kind atom --body "See [[Old Name]]" >/dev/null
"$MM" rename "Old Name" "New Name" >/dev/null
"$MM" read "Linker" | grep -F '[[New Name]]' && echo UNEXPECTED_PASS || echo EXPECTED_MISS
```

Expected before fix: `EXPECTED_MISS`.

- [ ] **Step 2: 实现 `scripts/lib/rewrite.sh`**

要求：
- 解析 aliases：简单扫描 frontmatter 块内 `aliases:` 行（`[]` 或 `[a, b]`）
- 遍历 brain+daily；fence 跳过；精确匹配 `|` 前 target
- 每文件：读入 → awk 改写 → 若有变更则 mktemp 写回
- Bash 3.2；无 `sed -i`

- [ ] **Step 3: `mmfs_rename` 在 `mv` 成功后调用 rewrite**

```bash
# 伪代码顺序
old_keys="$(mm_wikilink_keys_for_file "$file")"
mv "$file" "$dest"
# update title in dest frontmatter if helper already does not — keep existing title field update if any; else set title to clean
printf '%s\n' "$old_keys" | mm_rewrite_wikilinks "$clean"
mm_log "renamed: ... (wikilinks updated)"
```

同时更新目标文件 `title:` 为新标题（若尚未更新）。

- [ ] **Step 4: 重跑 Step 1 脚本**

Expected: `[[New Name]]` 出现在 Linker 中。

- [ ] **Step 5:（可选，经用户确认）Commit**

---

### Task 2: 移除 CLI 运行时

**Files:**
- Delete: `scripts/lib/cli.sh`
- Modify: `scripts/memovault.sh`（去掉 `. cli.sh`、`mmcli_detect`、所有 `mm_w_*` cli 分支；`search/tags/...` 直接 `mmfs_*`；新 `mm_preflight`）
- Modify: `scripts/lib/classify.sh`（promote 去掉 cli 分支）

**Interfaces:**
- `preflight` 打印：`runtime=shell mode=fs vault=... search=rg|grep forced=0`（按规格）
- 检测 search 后端：`command -v rg` → `rg` else `grep`

- [ ] **Step 1: 改 `mm_preflight` 与派发**

去掉 `MM_MODE` 依赖处：若其他函数读 `MM_MODE`，改为恒定 fs 或删除分支。

- [ ] **Step 2: 删除 `cli.sh`；修复所有 source**

```bash
rg -n 'cli\.sh|mmcli_|MM_MODE' scripts/
```

Expected: 无运行时引用（文档稍后改）。

- [ ] **Step 3: `MM_FORCE_FS` 忽略**

`memovault.sh` 顶部可：`[ "${MM_FORCE_FS:-0}" = 1 ] && mm_log "MM_FORCE_FS is deprecated and ignored (runtime is always shell)"`（仅一次，或仅 preflight 提示）。

- [ ] **Step 4: 冒烟**

```bash
unset MM_FORCE_FS
AGENT_MEMO_VAULT="$(mktemp -d)/v" ./scripts/memovault.sh preflight
# expect runtime=shell, no bin=, no app=
```

- [ ] **Step 5:（可选）Commit**

---

### Task 3: e2e 单阶段 + link-safe 断言

**Files:**
- Modify: `scripts/e2e/run.sh`
- Modify: `scripts/e2e/lib/env.sh`（删除 `e2e_begin_cli_phase` / register 调用）
- Delete: `scripts/e2e/lib/register.sh`
- Modify: `scripts/e2e/suites/01-preflight.sh`
- Modify: `scripts/e2e/suites/05-organize.sh`（rename link 断言对所有 phase；删除 `E2E_PHASE=cli` 守卫或 phase 恒为 shell）
- Modify: `skills/testing-memovault/SKILL.md`

- [ ] **Step 1: 简化 `run.sh`**

只跑一套 suites；门禁：`SYNTAX_FAILS` + suite fails；删除 `--cli-only` 与 cli 阶段；`--fs-only` 可保留为兼容无操作。

- [ ] **Step 2: 改 suites**

`01-preflight.sh`：

```bash
out="$(e2e_mm preflight 2>/dev/null || true)"
assert_contains "$out" "runtime=shell" "preflight runtime"
assert_contains "$out" "vault=$E2E_VAULT" "preflight vault"
```

`05-organize.sh`：将原 cli-only wikilink 断言移到主路径（rename 后 `read` Linker 含新标题）。

- [ ] **Step 3: 跑门禁**

```bash
./scripts/e2e/run.sh
```

Expected: exit 0；含 wikilink 更新 PASS。

- [ ] **Step 4: 更新 `skills/testing-memovault/SKILL.md`**

去掉 Obsidian/双模式前置；报告里 `cli:` 字段改为 `N/A` 或删除，改为：

```
harness: PASS|FAIL
  shell: PASS|FAIL
```

（同步改报告模板。）

- [ ] **Step 5:（可选）Commit**

---

### Task 4: 安装器与版本号

**Files:**
- Modify: `VERSION` → `0.5.0`
- Modify: `SKILL.md` frontmatter version
- Modify: `install/install.sh`（`--force-fs` 废弃提示；register 帮助文案）

- [ ] **Step 1: bump VERSION / SKILL**

- [ ] **Step 2: `--force-fs`**

若用户传 `--force-fs`：仍可写 `env.sh` 但不设置强制逻辑，或写注释说明 ignored；stderr/`mm_note` 提示 deprecated。

- [ ] **Step 3: `--register-vault` 帮助字符串**

改为可选、仅浏览用途。

- [ ] **Step 4:（可选）Commit**

---

### Task 5: 文档（中文优先处用中文更新）

**Files:**
- Modify: `README.md`, `README_CN.md`
- Modify: `AGENTS.md`, `docs/ARCHITECTURE.md`, `docs/INSTALL.md`, `docs/DEVELOPMENT.md`, `docs/CLI-REFERENCE.md`, `docs/RIPER.md`
- Modify: `install/adapters/_protocol.md`（若提及 cli/fs 模式）
- Modify: `docs/superpowers/specs/2026-08-03-e2e-testing-design.md`（文首加 superseded 说明指向 2026-08-04 规格）
- Modify: 本规格状态 → 已批准（若执行前已批）

- [ ] **Step 1: README / README_CN**

删除「cli when Obsidian running」运行时叙述；改为 shell-only；Windows → WSL；版本 0.5.0。

- [ ] **Step 2: ARCHITECTURE / AGENTS / INSTALL / DEVELOPMENT**

重画分层图；删 cli 映射表或改为历史说明。

- [ ] **Step 3: CLI-REFERENCE**

文首声明：非运行时依赖；可选人用参考。

- [ ] **Step 4: RIPER 追加 2026-08-04 条目**

- [ ] **Step 5: `bash -n` + 完整 e2e**

```bash
bash -n scripts/memovault.sh scripts/lib/*.sh scripts/e2e/*.sh scripts/e2e/lib/*.sh scripts/e2e/suites/*.sh
./scripts/e2e/run.sh
```

Expected: exit 0。

- [ ] **Step 6:（可选）Commit**

---

## 规格覆盖自检

| 规格项 | 任务 |
|---|---|
| rewrite + aliases + fence | Task 1 |
| 删 cli / 新 preflight / 忽略 MM_FORCE_FS | Task 2 |
| e2e 单阶段 + link 断言 | Task 3 |
| 0.5.0 / force-fs / register 文案 | Task 4 |
| 文档 + WSL 说明 | Task 5 |
| move 不强制 rewrite（basename 不变） | Task 1（仅 rename） |

---

## 执行方式

计划已保存到 `docs/superpowers/plans/2026-08-04-shell-only-runtime.md`。

**1. Subagent-Driven（推荐）** — 每任务新 subagent + 复核  
**2. Inline Execution** — 本会话连续执行  

规格草案：`docs/superpowers/specs/2026-08-04-shell-only-runtime-design.md`  

你要先审规格再执行，还是规格+计划都认可后直接选 1 或 2 开干？
