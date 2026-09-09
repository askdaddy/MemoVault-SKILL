# MemoVault 自检报告：生成规则与格式

后续 agent 在本仓库写「记忆库 / 技能功效」自检时，必须读本文再落笔。
报告只进 git 文档，不写入 vault（`$AGENT_MEMO_VAULT`）。

实例目录：`docs/health-reports/YYYY-MM-DDTHH-MM-SSZ.md`（采集时刻的 UTC ISO 8601，文件名里用 `-` 代替时间中的 `:`，避免跨平台路径问题）。
文内标题与「采集 UTC」使用带冒号的真 ISO（`YYYY-MM-DDTHH:MM:SSZ`）。文件名按时间排序即可回顾对比，禁止覆盖旧文件。
本文是格式真源；实例必须能对照本文的章节清单逐项打勾。

## 1. 何时生成

满足任一即写一份**新文件**（按采集 UTC 打时间戳；即使同一天也不得覆盖旧报告）：

- 用户问健康、功效、效果、对比、观测、自检、health
- 用户要求例行自检（发版后、月初、或明确说「按规范出一份」）
- 维护者约定的例行节奏（建议：每个自然月至少一份，或每次 minor 发版后一份）

不因为仪式性的开场 `recall` miss 就写报告。

## 2. 硬约束

- 禁止 emoji。文件名、正文、表格、hint 原文均用纯文本。
- 禁止静默改 vault。报告里的改进项只建议；`promote` / 拆域 / 补链 / 填 `kind` 必须用户确认后再做。
- 机器字段名保持 helper 原样（反引号），不要翻译成另一套键名。中文只用于标题、总评和解释。
- `-1` 表示该比率无分母（例如没有 recall）。正文写成「无」或保留 `-1` 并注明无分母。
- `cite_rate` 与 `recapture_dup` 已 deprecated。可在「原始字段」附录列出，不作为总评依据。`hint=low_cite_rate` 视为遗留。
- `heat_evergreen` 含 MOC 索引。判断内容成熟度时用 `moc_count`，并写明「内容 evergreen = heat_evergreen - moc_count」（若 evergreen 全是 MOC，则内容 evergreen 为 0）。
- `kind_other` 若等于 `moc_count` 且抽查均为 `_*-MOC.md`，写明「other 即 MOC，不是内容缺 kind」，不要当成 `high_kind_other`。

## 3. 采集步骤（顺序固定）

Helper：`$HOME/.agents/skills/memovault/scripts/memovault.sh`（若不可执行则用仓库 `./scripts/memovault.sh`）。
先 `preflight`，确认 `runtime=shell` 与 vault 路径。

```bash
MM="$HOME/.agents/skills/memovault/scripts/memovault.sh"
[ -x "$MM" ] || MM="./scripts/memovault.sh"
"$MM" preflight
"$MM" health
"$MM" suggest
"$MM" orphans
"$MM" unresolved
"$MM" by-heat
```

然后：

1. 先读 `summary=`，再读 `use_rate`、`recall_n*_hit_rate`、`delta_*`、`hint=`。
2. 词数桶合计：`labeled_n = recall_n1_7d + recall_n23_7d + recall_n4_7d`；`labeled_hits = recall_n1_hits_7d + recall_n23_hits_7d + recall_n4_hits_7d`。有 `labeled_n` 时 `labeled_hit_rate = labeled_hits * 100 / labeled_n`（整数除法，与 helper 一致）。这是「升级后检索」口径，总评检索时优先于含 `nunk` 的 `recall_hit_rate`。
3. 对照：`recall_hit_rate_prev7d`、`delta_recall_hit_rate`、`delta_use_rate`。可选：`$VAULT/.memovault/health-snap.log` 最近 3 行。
4. `kind_other`：列出缺合法 `kind` 的路径（是否全是 MOC）。
5. orphan：区分 MOC 与内容笔记。MOC 无入链通常正常。
6. 最大 `domain_*` 记为堆积域。
7. 不要把 eval 夹具 hit@k、回答人评、向量检索写进「已测」；那些不在 production `health` 里。

## 4. 文件名与文首

采集时刻优先用本次 `health` 写入 snap 的 `ts=`；若无 snap 则用 `date -u +%Y-%m-%dT%H:%M:%SZ`。

```bash
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"   # or snap ts=
file="$(printf '%s' "$ts" | tr ':' '-')"
# path: docs/health-reports/${file}.md
# example: 2026-09-01T01:56:50Z -> docs/health-reports/2026-09-01T01-56-50Z.md
```

- 路径：`docs/health-reports/YYYY-MM-DDTHH-MM-SSZ.md`（ISO UTC，`:` → `-`）
- 标题：`# MemoVault 自检报告 YYYY-MM-DDTHH:MM:SSZ`（真 ISO，带冒号）
- 文首「采集 UTC」必须与标题时间戳相同，且能由文件名把 `-` 还原为 `:` 得到
- 文首元数据表必须含下表全部行（值用本次采集）：

| 字段 | 含义 |
|---|---|
| 报告日 | `YYYY-MM-DD`（采集 UTC 的日期部分） |
| 技能版本 | 已安装 `VERSION`（如 `0.8.0`） |
| Helper | 实际执行的 `memovault.sh` 路径 |
| Vault | `preflight` 的 `vault=` |
| 窗口 | 近 7 天 vs 上一窗 8–14 天（与 `mm_obs_days_ago` 一致） |
| 采集 UTC | `YYYY-MM-DDTHH:MM:SSZ`，与标题一致 |

## 5. 章节清单（顺序与标题必须一致）

二级标题用中文，如下。不要增删、不要改名。需要补充时加在「附录」。

1. `## 总评`
2. `## 功效摘要`
3. `## 对照`
4. `## 词数桶`
5. `## 库存`
6. `## 流量`
7. `## Hint 与 suggest`
8. `## 改进项`
9. `## 原始 summary`

### 5.1 总评

第一句必须是三选一，加粗：

- **健康**：检索与使用都可接受。建议：`labeled_hit_rate >= 70`（有 labeled 样本时）或 `recall_hit_rate >= 70`（几乎无 nunk），且 `use_rate >= 20` 或 `hint=low_use` 未出现；无 `hint=capture_after_miss` / `wide_query` / `low_recall_hit_rate`（或已解释为误报）。
- **部分健康**：检索已明显好于上一窗或 labeled 命中高，但使用闭环弱（`use_rate` 低、`read_7d` 远小于 `recall_hits_7d`、`skill_reuse=0`），或卫生有可控问题。
- **不健康**：labeled 与总体命中都差，或 inbox/raw 堆积、或 `hint=low_recall_hit_rate` 且宽查询同时成立。

总评段接着用短句说明：运行时是否正常、检索、使用、卫生各一句。点名依据字段。

### 5.2 功效摘要

一张表，列：`指标` | `值` | `读法`。至少含：

`recall_hit_rate`、`labeled_hit_rate`（算出）、`use_rate`、`cite_7d`、`read_7d`、`hit_unused_7d`、`skill_reuse`、`wide_query_7d`、`capture_after_miss_7d`

### 5.3 对照

上一窗 `recall_7d_prev` / `recall_hit_rate_prev7d` / `cite_7d_prev`。
`delta_*` 中至少写 `delta_recall_hit_rate`、`delta_use_rate`、`delta_notes_total`。
用一两句解释变化（例如 0.8.0 token-OR 之后命中上升、use_rate 仍平）。

### 5.4 词数桶

表：桶 | 次数 (`*_7d`) | 命中 | 命中率。行：`n1`、`n23`、`n4`、`nunk`。
说明 `nunk` 是缺 `token_n` 的旧 ledger 行，会随 7 天窗滚出，不要为清 nunk 去改历史 ledger。

### 5.5 库存

`notes_total`、各 `kind_*`、`kind_other_pct`、三档 heat、`moc_count`、内容 evergreen、inbox、legacy daily、orphan（MOC vs 内容）、provenance、unresolved、`superseded_count`、最大 domain。
`kind_other` 与 orphan 各列路径或说明「全是 MOC」。

### 5.6 流量

近 7 天：`recall_7d` `search_7d` `capture_7d` `cite_7d` `read_7d` `feedback_7d` `distill_7d`。
点明是否「recall 远多于 cite/read」。

### 5.7 Hint 与 suggest

- 列出全部 `hint=` 行。对每条：采纳 / 忽略（遗留）/ 需用户确认。
- 粘贴 `suggest=` 行（可截断为 title + 理由）。写明「未确认不得 promote」。

### 5.8 改进项

表：优先级 | 问题 | 建议动作 | 是否改库。

优先级：`P0` 使用闭环（cite）、`P1` miss 后乱建笔记、`P2` 成熟度 / 大域堆积、`P3` 窗口噪音或单一 orphan。
「是否改库」为「否（协议）」或「需确认」。

### 5.9 原始 summary

单独一行，原样粘贴 `summary=...`（不要改字段顺序）。

## 6. 骨架（复制后填）

```markdown
# MemoVault 自检报告 YYYY-MM-DDTHH:MM:SSZ

| 字段 | 值 |
|---|---|
| 报告日 | YYYY-MM-DD |
| 技能版本 | |
| Helper | |
| Vault | |
| 窗口 | 近 7 天 vs 上一窗 8-14 天 |
| 采集 UTC | YYYY-MM-DDTHH:MM:SSZ |

## 总评

**部分健康**。

（运行时 / 检索 / 使用 / 卫生各一句。）

## 功效摘要

| 指标 | 值 | 读法 |
|---|---|---|
| `recall_hit_rate` | | 含 nunk 的 7 天命中率 |
| `labeled_hit_rate` | | n1+n23+n4 |
| `use_rate` | | cite_7d * 100 / recall_7d |
| `cite_7d` | | |
| `read_7d` | | |
| `hit_unused_7d` | | max(0, hits - cite) |
| `skill_reuse` | | |
| `wide_query_7d` | | token_n>=4 |
| `capture_after_miss_7d` | | |

## 对照

## 词数桶

| 桶 | 次数 | 命中 | 命中率 |
|---|---|---|---|
| n1 | | | |
| n23 | | | |
| n4 | | | |
| nunk | | | n/a 或 -1 |

## 库存

## 流量

## Hint 与 suggest

## 改进项

| 优先级 | 问题 | 建议动作 | 是否改库 |
|---|---|---|---|
| P0 | | | 否（协议） |

## 原始 summary

summary=
```

## 7. 回顾对比

文件名按 UTC 时间戳排序。对比两份报告时：

1. `ls docs/health-reports/*.md` 取相邻或指定的两份（不要用 `README.md`）。
2. 先对「原始 summary」和「功效摘要」表，再看「对照」「词数桶」「总评」。
3. `diff -u docs/health-reports/<older>.md docs/health-reports/<newer>.md`。
4. 报告内的 `delta_*` 是相对 vault `health-snap.log` 上一行，不是相对上一份 git 报告；跨报告对比以两份文档的字段值为准。

禁止为了「同一天只留一份」而改名或覆盖旧文件。

## 8. 与 helper / 协议的关系

- 字段定义以 `SKILL.md` Health 节与 `docs/ARCHITECTURE.md` 为准。
- 本目录是**仓库例行文档**，不是 vault 笔记，也不替代 `health` 机器输出。
- 写完报告后：`CHANGELOG.md` 的 `[Unreleased]` 记一条（若本次只新增/更新报告）；不要为写报告而 bump `VERSION`。
- 用户若要求把结论沉进 vault，另走 capture 协议（先提议，确认后再 `new`/`append`）。
