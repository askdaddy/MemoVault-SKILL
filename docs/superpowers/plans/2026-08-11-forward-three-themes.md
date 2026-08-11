# 前瞻三主题（0.7.0）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans，按任务逐项实现。步骤使用 checkbox（`- [ ]`）跟踪。

**Goal:** 落地 supersede 时效、reinforce+dedupe 建议、recall 图扩展 RRF 与 eval 门禁，版本 `0.7.0`。

**Architecture:** 过滤与 `supersede`/`dedupe` 在 `fs.sh`；`feedback`/`suggest` 与 ledger 聚合在 `obs.sh`；`recall` 增加一跳邻居 + awk RRF；`eval` 为独立 suite/fixture + 子命令。

**Tech Stack:** Bash 3.2、awk、rg/grep、mktemp；无向量。

**规格：** `docs/superpowers/specs/2026-08-11-forward-three-themes-design.md`  
**调研：** vault `Agent memory 前瞻调研 2026-08`

## Global Constraints

- 无 emoji；Bash 3.2；`set -uo pipefail`；不用 `set -e`
- 不写 vault 外；测试用临时 `AGENT_MEMO_VAULT`
- 禁止 `sed -i`；mktemp + mv
- 文档默认中文；标识符英文
- 版本 `0.7.0`
- 仅在用户明确要求时 git commit
- 不自动 promote / 不自动删笔记

---

## 文件结构

| 路径 | 动作 | 职责 |
|---|---|---|
| `scripts/lib/fs.sh` | 修改 | status 过滤；supersede；dedupe；recall RRF |
| `scripts/lib/obs.sh` | 修改 | feedback；suggest；superseded_count；feedback ledger |
| `scripts/memovault.sh` | 修改 | 派发新命令；usage |
| `scripts/e2e/fixtures/eval-memory/` | 新建 | 小 vault + `cases.tsv` |
| `scripts/e2e/suites/08-forward.sh` | 新建 | 三主题 e2e |
| `install/adapters/_protocol.md` | 修改 | dedupe / supersede / suggest |
| `docs/CLASSIFICATION.md` 等 | 修改 | status 字段；VERSION 0.7.0 |

---

### Task 1: `status` 过滤 + `supersede`

**Files:**
- Modify: `scripts/lib/fs.sh`（`mmfs_search_file_ok`、`mmfs_new` 可选写 status、`mmfs_supersede`）
- Modify: `scripts/memovault.sh`
- Modify: `scripts/e2e/suites/08-forward.sh`（本任务先写断言骨架，Task 4 补全也可在本任务写测）

**Interfaces:**
```bash
# mmfs_search_file_ok ... include_superseded
# mmfs_supersede <old_ref> <new_ref>
# search/recall gain --include-superseded
```

- [ ] **Step 1: 失败用例（改前 superseded 仍可被搜到——若尚无 status 则先造字段）**

```bash
export AGENT_MEMO_VAULT="$(mktemp -d)/vault"
MM=./scripts/memovault.sh
mkdir -p "$AGENT_MEMO_VAULT"
"$MM" new eng "Old Fact" --kind atom --body "token-super" >/dev/null
"$MM" new eng "New Fact" --kind atom --body "token-super" >/dev/null
# 手工写 status 后应被过滤——实现后用 supersede
```

- [ ] **Step 2: 扩展 `mmfs_search_file_ok`**

读 `status`；若值为 `superseded` 且 `include_superseded!=1` → return 1。  
`mmfs_search` / `mmfs_recall` 增加 `--include-superseded`。

- [ ] **Step 3: 实现 `mmfs_supersede`**

```bash
mmfs_supersede() {
  local old_ref="$1" new_ref="$2"
  # locate both; set_prop old status superseded; append pointer lines;
  # update new supersedes list (simple: set_prop supersedes "[Old Title]");
  mm_obs_log "event=supersede" "from=..." "to=..."
}
```

`mmfs_new`：默认不写 status（省略=active），或显式 `status: active`——**省略**以保持兼容。

- [ ] **Step 4: dispatch + usage**

- [ ] **Step 5: 断言默认 search 无 Old；`--include-superseded` 有 Old**

- [ ] **Step 6: Commit（仅用户要求时）**

---

### Task 2: `feedback` + `dedupe` + `suggest`

**Files:**
- Modify: `scripts/lib/obs.sh`（`mm_obs_feedback`、`mm_obs_suggest`）
- Modify: `scripts/lib/fs.sh`（`mmfs_dedupe`）
- Modify: `scripts/memovault.sh`
- Modify: `install/adapters/_protocol.md`

**Interfaces:**
```bash
mm_obs_feedback <title> <+1|-1>
mm_obs_suggest                 # stdout suggest=... lines
mmfs_dedupe <q> [--limit N]    # path= title= reason=
```

- [ ] **Step 1: `mm_obs_feedback`**

校验 score 为 `+1` 或 `-1`；`mm_obs_log event=feedback title=... score=...`。

- [ ] **Step 2: `mmfs_dedupe`**

1. 规范化 query/title。  
2. find `brain/**/*.md`，title 规范化相等或互相包含 → `reason=title_match`。  
3. 再 `mmfs_search "$q" --limit 20`，加入未列候选 `reason=search_hit`。  
4. 去重截断。

- [ ] **Step 3: `mm_obs_suggest`**

扫 ledger 30d（复用 `mm_obs_days_ago 30`）：按 title 累计 cite/read/feedback；对非 evergreen 笔记若 `(cites+reads)>=3` 或 `feedback_net>=2` 或 backlinks≥2 → `suggest=promote ...`。  
可选：对规范化 title 冲突输出 `suggest=dedupe`（轻量：仅当两笔记 title 规范化相等）。

- [ ] **Step 4: health 增加 `superseded_count`**

- [ ] **Step 5: 协议补一段：new 前 dedupe；过期用 supersede；看 suggest**

- [ ] **Step 6: e2e 断言 feedback/dedupe/suggest 至少各一条**

- [ ] **Step 7: Commit（仅用户要求时）**

---

### Task 3: `recall` 图扩展 + 简化 RRF

**Files:**
- Modify: `scripts/lib/fs.sh`（`mmfs_recall`）
- Test: `scripts/e2e/suites/08-forward.sh`

**Interfaces:**
```bash
mmfs_recall <q> [--limit N] [--no-graph] [--include-superseded]
# k_rrf=60；邻居上限 50
```

- [ ] **Step 1: 构造图可达用例**

笔记 Hub 含 token；Spoke 无 token 但 `[[Hub]]` 或 Hub 含 `[[Spoke]]`。  
`--no-graph` 时 Spoke 不应进结果；默认 recall 应能进 top。

- [ ] **Step 2: 实现邻居收集**

对 FTS 有序列表 A 的前 `min(5,n)`：  
- 出链：从文件扫 `[[Title]]`  
- 入链：调用现有 backlinks 逻辑或 rg `[[Title`  

过滤 raw/superseded；映射到文件路径。

- [ ] **Step 3: awk RRF 合并**

临时文件列：`path rank_a rank_b heat_s kind_s updated title kind heat snippet`  
`score = 1/(60+ra) + 1/(60+rb)`；缺席 rank=1000。  
再按 score、heat、kind、updated 排序。

- [ ] **Step 4: e2e 断言 Spoke 出现在默认 recall**

- [ ] **Step 5: Commit（仅用户要求时）**

---

### Task 4: `eval` fixture + suite 08 + 文档 0.7.0

**Files:**
- Create: `scripts/e2e/fixtures/eval-memory/brain/...` 与 `cases.tsv`
- Create: `scripts/lib` 内 `mmfs_eval` 或 `scripts/e2e` 调用的 `mm_obs_eval`——**放 `fs.sh` 旁 `eval.sh` 或 `obs.sh`**：推荐 `scripts/lib/eval.sh` sourced by memovault.sh
- Modify: `scripts/e2e/run.sh` 注册 `08-forward`
- Modify: VERSION、SKILL、CLASSIFICATION、ARCHITECTURE、AGENTS、README*、RIPER、`_protocol.md`

**Interfaces:**
```bash
mm_eval_run [--fixture dir] [--limit 5] [--no-graph]
# prints case= id hit=0|1 rank=N; summary hit_at_k= frac; exit 1 if hit_at_k < 0.8
```

- [ ] **Step 1: 写 fixture**

至少：AtomHit（含 query 词）、Spoke（仅链接）、OldSuperseded、NewActive。  
`cases.tsv`：
```text
c1	unique-eval-token	AtomHit
c2	unique-eval-token	Spoke
```

- [ ] **Step 2: 实现 `mm_eval_run`**

对每个 case：在 fixture vault 上 `mmfs_recall`；看 expect 是否在 top limit。

- [ ] **Step 3: e2e 08 覆盖 supersede/dedupe/suggest/rrf/eval**

- [ ] **Step 4: bump 0.7.0；文档；`./scripts/e2e/run.sh` 全绿**

- [ ] **Step 5: Commit（仅用户要求时）**

---

## Spec coverage

| 规格 | 任务 |
|---|---|
| status + supersede + 过滤 | Task 1 |
| feedback / dedupe / suggest | Task 2 |
| recall RRF | Task 3 |
| eval + 文档版本 | Task 4 |
| 向量 / 自动 promote | 非目标 |

## Placeholder scan

无 TBD；阈值写死在 Task 2/4 可测。
