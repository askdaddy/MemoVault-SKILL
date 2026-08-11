# Memory Loop（0.6.0）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans，按任务逐项实现。步骤使用 checkbox（`- [ ]`）跟踪。

**Goal:** 落地 Memory Loop：结构化 `search`/`recall`、代理 L2 可观测（ledger + `health`）、`distill`/inbox 替代 daily 主路径、templates 降级，版本 `0.6.0`。

**Architecture:** 检索与排序仍在 `scripts/lib/fs.sh`；可观测与 ledger 抽到新库 `scripts/lib/obs.sh`；`memovault.sh` 派发新子命令并在写路径旁路记账；协议/`install --verify`/文档对齐规格。

**Tech Stack:** Bash 3.2、awk、rg/grep、mktemp；无 JSON 依赖；无网络。

**规格：** `docs/superpowers/specs/2026-08-10-memory-loop-design.md`

## Global Constraints

- 无 emoji；Bash 3.2；`set -uo pipefail`；不用 `set -e`
- 绝不写入 vault 根之外；测试用临时 `AGENT_MEMO_VAULT`
- 禁止 `sed -i`；改写用 mktemp + mv
- 官方平台：macOS、Linux；Windows = WSL2 only
- 文档（docs/、RIPER 新条目、本计划）默认中文；命令名/路径/标识符英文
- 版本目标 `0.6.0`
- 仅在用户明确要求时 git commit
- ledger 写入失败不得阻断主命令（stderr 提示即可）

---

## 文件结构

| 路径 | 动作 | 职责 |
|---|---|---|
| `scripts/lib/fs.sh` | 修改 | `search` 过滤；`recall`；`distill`；`new`/`read`/`append`/`promote` 钩子调用 obs |
| `scripts/lib/obs.sh` | 新建 | ledger 追加/轮转；`cite`；`health`/`stats`；L1/L2 聚合 |
| `scripts/memovault.sh` | 修改 | source obs；派发 recall/cite/distill/health/stats/ledger:rotate；usage |
| `install/adapters/_protocol.md` | 重写 | 短协议：recall→read→capture→distill→cite→health |
| `install/install.sh` | 修改 | verify 不再要求 templates/ |
| `scripts/e2e/suites/03-retrieve.sh` | 修改 | search 过滤 + recall |
| `scripts/e2e/suites/06-obs.sh` | 新建 | ledger/cite/health/distill |
| `scripts/e2e/run.sh` | 修改 | 注册 suite 06 |
| `SKILL.md` / `AGENTS.md` / `VERSION` | 修改 | 0.6.0 与表面 |
| `docs/CLASSIFICATION.md` / `ARCHITECTURE.md` / `RIPER.md` / README* | 修改 | daily/templates/recall/health |
| `docs/superpowers/specs/2026-08-10-memory-loop-design.md` | 已批准 | 实现时保持一致 |

---

### Task 1: `search` 结构化过滤（默认排除 raw + daily）

**Files:**
- Modify: `scripts/lib/fs.sh`（`mmfs_search`）
- Modify: `scripts/e2e/suites/03-retrieve.sh`
- Modify: `scripts/memovault.sh`（usage 中 search 行）

**Interfaces:**
- Consumes: `mmfs_get_prop`, `MM_VAULT`
- Produces:

```bash
# mmfs_search <query> [--limit N] [--domain D] [--kind K] [--heat H] [--include-raw]
# stdout: vault-relative path:line:text (unchanged shape), filtered
```

- [ ] **Step 1: 写失败用例（改代码前应暴露默认会扫到 daily/raw）**

```bash
cd /Users/seven/Workspace/MemoVault-SKILL
export AGENT_MEMO_VAULT="$(mktemp -d)/vault"
MM=./scripts/memovault.sh
mkdir -p "$AGENT_MEMO_VAULT"
"$MM" new engineering "Atom Hit" --kind atom --body "unique-token-loop" >/dev/null
"$MM" new inbox "Raw Hit" --kind raw --body "unique-token-loop" >/dev/null
"$MM" daily:append "unique-token-loop in daily" >/dev/null
out="$("$MM" search "unique-token-loop" 2>/dev/null || true)"
echo "$out" | grep -q 'Raw Hit' && echo HAS_RAW || echo NO_RAW
echo "$out" | grep -q 'daily/' && echo HAS_DAILY || echo NO_DAILY
# 改前预期：HAS_RAW / HAS_DAILY；改后预期：NO_RAW / NO_DAILY，且仍含 Atom Hit
```

- [ ] **Step 2: 实现过滤逻辑**

在 `mmfs_search` 中解析 flags；检索范围改为优先 `$MM_VAULT/brain`（不要整库含 `.memovault`）；对每个命中文件：

1. 路径匹配 `daily/` → 丢弃  
2. 若未 `--include-raw` 且 `mmfs_get_prop kind` = `raw` → 丢弃  
3. 若设了 `--domain`/`--kind`/`--heat`，与 frontmatter 不等则丢弃  
4. 再 `head -n "$limit"`

要点：先收集「唯一文件」的命中行再过滤，避免同一文件多行重复读 prop 过慢时可按文件缓存（awk 一次读三个 prop 亦可）。

最小参考实现骨架（放入 `fs.sh`，按现有风格调整）：

```bash
mmfs_search() {
  local q="$1"; shift
  local limit="" domain="" kind="" heat="" include_raw=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      --domain) domain="$2"; shift 2 ;;
      --kind) kind="$2"; shift 2 ;;
      --heat) heat="$2"; shift 2 ;;
      --include-raw) include_raw=1; shift ;;
      *) shift ;;
    esac
  done
  [ -n "$q" ] || mm_die "usage: search <query> [--limit N] [--domain D] [--kind K] [--heat H] [--include-raw]"
  mmfs_ensure_vault
  local out raw
  if command -v rg >/dev/null 2>&1; then
    raw="$(rg --no-heading -n -- "$q" "$MM_VAULT/brain" 2>/dev/null || true)"
  else
    raw="$(grep -rn -- "$q" "$MM_VAULT/brain" 2>/dev/null || true)"
  fi
  out=""
  # 逐行过滤：见上规则；prefix strip MM_VAULT/
  # ...
  if [ -n "$limit" ]; then
    printf '%s\n' "$out" | head -n "$limit"
  else
    printf '%s\n' "$out"
  fi
}
```

- [ ] **Step 3: 跑 Step 1 脚本，确认 NO_RAW / NO_DAILY，且 Atom Hit 在**

- [ ] **Step 4: 扩展 e2e `03-retrieve.sh`**

追加断言：raw 笔记含 token 时默认 search 不含该文件；`--include-raw` 后含有。

- [ ] **Step 5: 更新 `mm_usage` 中 search 行**

- [ ] **Step 6: Commit（仅当用户要求）**

```bash
git add scripts/lib/fs.sh scripts/memovault.sh scripts/e2e/suites/03-retrieve.sh
git commit -m "$(cat <<'EOF'
feat(search): filter by domain/kind/heat; exclude raw and daily by default

EOF
)"
```

---

### Task 2: `recall` 加权排序摘要

**Files:**
- Modify: `scripts/lib/fs.sh`（新增 `mmfs_recall`）
- Modify: `scripts/memovault.sh`（dispatch + usage）
- Modify: `scripts/e2e/suites/03-retrieve.sh`

**Interfaces:**
- Consumes: 与 search 相同的过滤语义（可内部调用共享 helper）
- Produces:

```bash
# mmfs_recall <query> [--limit N]   default limit 5
# 每行: path=<rel> title=<t> kind=<k|-> heat=<h> snippet=<单行摘录>
# 按 heat 分(evergreen=3,growing=2,seedling=1) + kind 分(persona/skill/scenario/atom=2, 其他=1, raw=0) + updated 新近
```

- [ ] **Step 1: 写排序断言脚本（实现前会失败或缺命令）**

```bash
export AGENT_MEMO_VAULT="$(mktemp -d)/vault"
MM=./scripts/memovault.sh
mkdir -p "$AGENT_MEMO_VAULT"
"$MM" new eng "Low" --kind atom --body "rank-token" >/dev/null
"$MM" new eng "High" --kind skill --body "rank-token" >/dev/null
# manually set heat evergreen on High via promote twice or set_prop if exposed
"$MM" promote "High" >/dev/null  # growing-> if skill starts growing, one promote -> evergreen? skill starts growing; one promote -> evergreen
out="$("$MM" recall "rank-token" --limit 2 2>/dev/null || true)"
# 期望第一行 title=High
```

注意：`kind: skill` 默认 heat=`growing`；再 `promote` 一次到 `evergreen`。atom 保持 seedling。

- [ ] **Step 2: 实现 `mmfs_recall`**

共享过滤：对候选笔记去重（按文件），取 title/kind/heat/updated/snippet（命中行截断至 ~120 字符，去掉换行）。排序用 awk 打分后 `sort -t$'\t' -k1,1nr -k2,2nr -k3,3r`。

```bash
mmfs_recall() {
  local q="$1"; shift
  local limit=5
  while [ $# -gt 0 ]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [ -n "$q" ] || mm_die "usage: recall <query> [--limit N]"
  # build candidate files via same filters as search (no include-raw)
  # print ranked lines
}
```

- [ ] **Step 3: dispatch**

```bash
# memovault.sh main case:
recall) mmfs_recall "$@" ;;
```

- [ ] **Step 4: e2e 断言第一行含 `title=High`（或你构造的 evergreen 标题）**

- [ ] **Step 5: Commit（仅当用户要求）**

---

### Task 3: 协议缩短 + templates verify 降级 + daily 叙事降级（文档 P0）

**Files:**
- Modify: `install/adapters/_protocol.md`
- Modify: `install/install.sh`（`mm_verify` vault 检查）
- Modify: `docs/CLASSIFICATION.md`（§7 Daily → legacy；inbox/raw）
- Modify: `SKILL.md`（§6 协议改为 recall；daily 标 legacy；表面列表）
- Modify: `AGENTS.md`（表面列表含 recall；提及 health 可后补若尚未实现则先写 recall）

**Interfaces:**
- Produces: 注入用短协议文本（仍含 Memory protocol 标题，供 verify 检测）

- [ ] **Step 1: 重写 `_protocol.md`**

保留结构标题 `## Memory protocol (always on)`（verify 依赖此字符串）。正文改为：

1. 每任务一次 `recall "<keywords>"`（`--limit 5`）；失败再用 `search`  
2. 排序已由 helper 完成；`read` ≤3（通常 1）；实质采用则稍后 `cite`（若命令尚无，可先写「实现后调用 cite」——**本任务若在 Task 4 前合并发布，协议可先写 recall/read/capture/distill，cite/health 在 Task 4–5 同步补一句**）  
3. Capture 半自动；显式记住语直写  
4. L0 用 `inbox` + `--kind raw`；`distill` 升格；**不要**默认写 daily  
5. Skill：`new skills ... --kind skill`；体例 Trigger/Steps/Verify/Related  
6. Guardrails 不变  

为避免协议与未实现命令脱节：**本任务可与 Task 4–6 同一 PR 落地**；若分 commit，协议在最后一次注入对齐。

- [ ] **Step 2: `mm_verify` 只要求 `brain/`**

```bash
if [ ! -d "$VAULT/brain" ]; then
  mm_verify_line FAIL vault "scaffold incomplete (need brain/ under $VAULT)"
  fail=1
else
  mm_verify_line OK vault "$VAULT"
fi
```

scaffold 仍可 best-effort 拷贝 templates（保留），但非 FAIL 条件。

- [ ] **Step 3: CLASSIFICATION / SKILL 更新 daily→legacy、inbox 为主路径 L0**

- [ ] **Step 4: 本地 `./install/install.sh --verify` 在临时去掉 templates 的 vault 上应仍 OK（brain 在即可）**

- [ ] **Step 5: Commit（仅当用户要求）**

---

### Task 4: `obs.sh` ledger + `cite` + 写路径埋点

**Files:**
- Create: `scripts/lib/obs.sh`
- Modify: `scripts/memovault.sh`（`. obs.sh`；dispatch `cite` `ledger:rotate`）
- Modify: `scripts/lib/fs.sh`（在 `mmfs_new`/`mmfs_append`/`mmfs_read`/`mmfs_recall`/`mm_promote` 成功路径调用 `mm_obs_log`；失败吞掉）

**Interfaces:**
- Produces:

```bash
mm_obs_dir()           # prints $MM_VAULT/.memovault
mm_obs_ledger_path()   # .../ledger.log
mm_obs_log event=E k=v ...   # append one line; never exit non-zero for IO fail
mm_obs_cite <title>
mm_obs_rotate [--keep N]     # keep last N lines, default 5000
```

事件行示例：

```text
ts=2026-08-10T10:00:00Z event=recall q=foo hits=2 top=High,Low
ts=2026-08-10T10:00:01Z event=cite title=High
```

`ts` 用 `date -u +%Y-%m-%dT%H:%M:%SZ`（macOS/Linux 均可）。

- [ ] **Step 1: 创建 `obs.sh` 骨架 + `bash -n`**

```bash
#!/usr/bin/env bash
# scripts/lib/obs.sh - ledger + health helpers. Sourced by memovault.sh. Bash 3.2.

mm_obs_dir() { printf '%s/.memovault' "$MM_VAULT"; }
mm_obs_ledger_path() { printf '%s/ledger.log' "$(mm_obs_dir)"; }

mm_obs_log() {
  local line="" p dir
  dir="$(mm_obs_dir)"
  p="$(mm_obs_ledger_path)"
  mkdir -p "$dir" 2>/dev/null || { mm_log "obs: cannot mkdir $dir"; return 0; }
  line="ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  while [ $# -gt 0 ]; do
    line="$line $1"
    shift
  done
  printf '%s\n' "$line" >> "$p" 2>/dev/null || mm_log "obs: cannot append ledger"
  return 0
}

mm_obs_cite() {
  local title="$1"
  [ -n "$title" ] || mm_die "usage: cite <title>"
  mm_obs_log "event=cite" "title=$title"
  printf 'cited=%s\n' "$title"
}

mm_obs_rotate() {
  local keep=5000 p tmp
  # parse --keep
  p="$(mm_obs_ledger_path)"
  [ -f "$p" ] || { printf 'rotated=0\n'; return 0; }
  tmp="$(mktemp)"
  tail -n "$keep" "$p" > "$tmp" && mv "$tmp" "$p"
  printf 'rotated=1 keep=%s\n' "$keep"
}
```

- [ ] **Step 2: source + dispatch**

```bash
. "$MM_ROOT/lib/obs.sh"
# case:
cite) mm_obs_cite "${1:-}" ;;
ledger:rotate) mm_obs_rotate "$@" ;;
```

- [ ] **Step 3: 埋点**

- `mmfs_recall` 结束：`mm_obs_log event=recall q=... hits=... top=...`（top 用逗号拼接 title，截断）  
- `mmfs_read`：`event=read title=...`  
- `mmfs_new`：`event=capture title=... kind=... domain=...`  
- `mmfs_append`：`event=capture`（可加 `op=append`）  
- `mm_promote`：`event=promote title=... from=... to=...`  

所有调用形如 `mm_obs_log ... || true` 且函数自身已 return 0。

- [ ] **Step 4: 手动验证 ledger 追加且 chmod 000 目录时主命令仍成功**

- [ ] **Step 5: Commit（仅当用户要求）**

---

### Task 5: `health` / `stats`（L0 + L1）

**Files:**
- Modify: `scripts/lib/obs.sh`（`mm_obs_health`）
- Modify: `scripts/memovault.sh`（dispatch；`stats` 别名）

**Interfaces:**
- Produces: 多行 `key=value`，至少包含：

```text
notes_total=N
kind_atom=N
kind_raw=N
heat_seedling=N
heat_growing=N
heat_evergreen=N
inbox_raw_count=N
legacy_daily_count=N
orphan_pct=N
recall_7d=N
capture_7d=N
capture_without_recall_7d=N
```

L1 窗口固定 7 天：解析 ledger `ts=` 日期部分 ≥ today-7。

- [ ] **Step 1: 实现 L0 扫描**

遍历 `$MM_VAULT/brain/**/*.md`（find）；跳过 `_*MOC*` 可选或计入（与 orphans 行为一致则计入）。`inbox_raw_count`：`kind=raw` 或路径含 `/inbox/`。`legacy_daily_count`：`daily/*.md` 文件数。`orphan_pct`：复用/调用现有 orphans 逻辑或简化为「无任何其他文件包含 `[[title]]`」的比例；若太重，可输出 `orphan_count` + `notes_total` 让协议算，但规格要 `orphan_pct`——用整数百分比。

- [ ] **Step 2: L1 从 ledger 聚合**

- [ ] **Step 3: dispatch `health|stats) mm_obs_health ;;`**

- [ ] **Step 4: 空 vault / 含 inbox 的手工或 e2e 断言 `notes_total`**

- [ ] **Step 5: Commit（仅当用户要求）**

---

### Task 6: L2 代理指标 + `distill` + suite 06

**Files:**
- Modify: `scripts/lib/obs.sh`（L2 字段写入 health）
- Modify: `scripts/lib/fs.sh`（`mmfs_distill`）
- Modify: `scripts/memovault.sh`
- Create: `scripts/e2e/suites/06-obs.sh`
- Modify: `scripts/e2e/run.sh`（加入 `06-obs`）

**Interfaces:**
- L2 keys：`cite_rate`, `skill_reuse`, `promote_rate`, `recapture_dup`（7d）  
  - `cite_rate`：整数 0–100 = cite次数*100 / max(1, recall且hits>0次数)；无数据时输出 `cite_rate=-1`（表示 n/a）  
  - `recapture_dup`：规范化 title（`printf '%s' "$t" | tr '[:upper:]' '[:lower:]'`）在 7d 内 capture 出现 ≥2 的次数  
- Distill：

```bash
# mmfs_distill <raw-ref> <domain> <title> [--kind atom|scenario]
# 创建目标笔记 body 含 See [[Raw Title]]；sources frontmatter 含 raw title 或日期
# 可选 append 一行到 raw：Distilled to [[New Title]]
# mm_obs_log event=distill from=... to=...
```

- [ ] **Step 1: 扩展 `mm_obs_health` 输出 L2**

- [ ] **Step 2: 实现 `mmfs_distill`**

```bash
mmfs_distill() {
  local raw_ref="$1" domain="$2" title="$3"; shift 3
  local kind="atom"
  while [ $# -gt 0 ]; do
    case "$1" in
      --kind) kind="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  case "$kind" in atom|scenario) ;; *) mm_die "distill kind must be atom|scenario" ;; esac
  local raw_file raw_title
  raw_file="$(mmfs_locate "$raw_ref")" || mm_die "raw not found: $raw_ref"
  raw_title="$(mmfs_get_prop "$raw_file" title)"
  [ -n "$raw_title" ] || raw_title="$(basename "$raw_file" .md)"
  mmfs_new "$domain" "$title" "" "See [[$raw_title]]." "$kind"
  # set sources: use mmfs_set_prop to sources: ["$raw_title"] — YAML list string
  local dest; dest="$(mmfs_note_path "$domain" "$title")"
  mmfs_set_prop "$dest" sources "[$raw_title]"
  printf '\nDistilled to [[%s]]\n' "$(mmfs_sanitize_title "$title")" >> "$raw_file"
  mm_obs_log "event=distill" "from=$raw_title" "to=$(mmfs_sanitize_title "$title")"
  printf '%s\n' "${dest#"$MM_VAULT"/}"
}
```

（按现有 `mmfs_set_prop` / sanitize 行为微调；确保 `sources` 格式可读。）

- [ ] **Step 3: `06-obs.sh` 覆盖**

1. new raw → distill → 读 atom 含 `[[Raw]]` 与 sources  
2. recall → cite → health 含 `cite_rate`  
3. ledger:rotate 不炸  

- [ ] **Step 4: `./scripts/e2e/run.sh` 全绿**

- [ ] **Step 5: Commit（仅当用户要求）**

---

### Task 7: 版本、文档、RIPER、协议终态对齐

**Files:**
- Modify: `VERSION` → `0.6.0`
- Modify: `SKILL.md` frontmatter version；§5/§6/§10 表面与 out-of-scope  
- Modify: `AGENTS.md` 表面列表  
- Modify: `docs/ARCHITECTURE.md`  
- Modify: `docs/RIPER.md`（新 Entry：Memory Loop 0.6.0）  
- Modify: `README.md` / `README_CN.md`（daily/templates/recall/health）  
- Modify: `install/adapters/_protocol.md`（确保含 cite + health 自评触发）  
- 可选：跑 `install.sh --upgrade` / `--all --force` 需用户本机确认，计划中作手动步骤

- [ ] **Step 1: bump VERSION 与 SKILL version 字段**

- [ ] **Step 2: RIPER 追加中文条目**，链到规格与本计划

- [ ] **Step 3: README_CN 说明主路径 inbox/distill，daily legacy**

- [ ] **Step 4: `bash -n` 全部 scripts；`./scripts/e2e/run.sh`**

- [ ] **Step 5: Commit（仅当用户要求）**

```bash
git commit -m "$(cat <<'EOF'
feat!: Memory Loop 0.6.0 — recall, health ledger, distill; daily/templates demoted

EOF
)"
```

---

## Spec coverage（自检）

| 规格项 | 任务 |
|---|---|
| search 过滤 / 排除 raw+daily | Task 1 |
| recall 排序摘要 | Task 2 |
| 协议缩短、daily 退出主叙事 | Task 3 (+7) |
| templates verify 可选 | Task 3 |
| ledger + cite + 埋点 | Task 4 |
| health L0+L1 | Task 5 |
| L2 代理 + distill + e2e | Task 6 |
| 文档/版本/RIPER | Task 7 |
| 向量搜索 | 非目标，无任务 |
| ledger 失败不阻断 | Task 4 |

## Placeholder scan

无 TBD/「类似 Task N」占位；§13 已在规格中裁定并反映本计划。

## Type consistency

- 统一子命令：`recall` `cite` `distill` `health`/`stats` `ledger:rotate`  
- 统一函数前缀：`mmfs_*`（fs）/ `mm_obs_*`（obs）  
- ledger 路径：`.memovault/ledger.log`
