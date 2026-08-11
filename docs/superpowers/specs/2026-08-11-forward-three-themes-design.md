# 设计：前瞻三主题（supersede / reinforce+dedupe / RRF+eval）

日期：2026-08-11  
状态：已批准（2026-08-11）  
仓库：MemoVault-SKILL  
版本目标：`0.7.0`  
依据：vault 笔记 [[Agent memory 前瞻调研 2026-08]]；Memory Loop 0.6.x 已落地

## 1. 目标

在 **不引入向量 / Neo4j / MCP 硬依赖** 的前提下，落实调研筛选的三条能力：

1. **Supersede（事实时效）**：过期知识可标记失效，默认召回跳过，历史可查。  
2. **Reinforce + Dedupe（强化与去重）**：cite/read 驱动 promote 建议；创建前可发现近似重复。  
3. **第二路检索 + Eval**：FTS 之外用 backlink 邻居扩展候选并融合排序；提供可重复的 `eval` 门禁证明「记忆有用」。

## 2. 已锁定决策

| 主题 | 选择 |
|---|---|
| 时效模型 | frontmatter `status: active\|superseded`（缺省=active）；可选 `supersedes: [Title]` |
| 作废方式 | 新子命令 `supersede <old> <new>`：标记 old=superseded，new 写 supersedes，互链；**不**自动删除 |
| 召回默认 | `search`/`recall` **排除** `status: superseded`；`--include-superseded` 打开 |
| 强化 | 不自动改 heat；`health` / 新 `suggest` 根据 30d cite+read 与 backlinks **建议** promote |
| 去重 | `dedupe <query-or-title>` 输出候选近似笔记（规范化 title + 共享命中）；协议要求 `new` 前先跑 |
| feedback | 一期做 `feedback <title> +1\|-1` 仅写 ledger（为强化提供显式信号）；不直接改 heat |
| 第二路 | `recall` 内：FTS 候选 + 其一跳 backlink/出链邻居，用简化 RRF 合并且仍受 heat/kind 加权 |
| Eval | `eval` 跑内置 fixture（或 `--vault`）；报告 hit@k / 是否召回期望 title；不做人评 |
| 版本 | `0.7.0` |

## 3. 非目标

- 向量 / sqlite-vec / ONNX  
- 完整 bi-temporal（valid_from/valid_to 双时间）——一期只用 superseded 状态  
- 自动无确认 promote / 自动 merge 重复笔记  
- MCP server（可作为后续适配器，本期不做）  
- 云端评测集 LongMemEval 全量复现  

## 4. 主题 A — Supersede

### 4.1 Frontmatter

```yaml
status: active          # active | superseded；省略视为 active
supersedes: []          # 可选；被本笔记取代的旧 title 列表
```

### 4.2 命令

```bash
"$MM" supersede "<Old Title>" "<New Title>"
```

行为：
1. 确认两笔记存在。  
2. Old：`status=superseded`，`updated=today`；正文可选追加一行 `Superseded by [[New]]`。  
3. New：`supersedes` 列表加入 Old；正文可选 `Supersedes [[Old]]`。  
4. ledger：`event=supersede from=Old to=New`。  

### 4.3 过滤

`mmfs_search_file_ok` / `recall`：若 `status=superseded` 且未 `--include-superseded` → 排除。  
`health`：增加 `superseded_count=`。

## 5. 主题 B — Reinforce + Dedupe

### 5.1 `feedback`

```bash
"$MM" feedback "<Title>" +1
"$MM" feedback "<Title>" -1
```

ledger：`event=feedback title=... score=+1|-1`。

### 5.2 Promote 建议（不自动执行）

`"$MM" suggest`（或 `health` 增补）输出例如：

```text
suggest=promote title=Foo cites_30d=4 backlinks=2
suggest=dedupe title=A other=B score=title
```

启发式（可调，写死在代码并测）：
- promote：`cites_30d + reads_30d + feedback_net` 达阈值 **或** backlinks≥2，且 heat≠evergreen。  
- 阈值一期：`(cites+reads) >= 3` 或 `feedback_net >= 2`。

### 5.3 `dedupe`

```bash
"$MM" dedupe "<query-or-title>" [--limit 5]
```

- 规范化 title 相等 / 包含关系 → 高分。  
- 否则对 query 做 `search`，同 domain 下多命中列为候选。  
- 输出：`path=... title=... reason=title_match|search_hit`。  
- **不**自动合并。

协议：`new` 前对拟定 title 跑一次 `dedupe`；有高分命中则 `append` 而非新建。

## 6. 主题 C — RRF 第二路 + Eval

### 6.1 `recall` 增强

1. 现有 FTS → 过滤 → 得列表 A（有序）。  
2. 对 A 的 top min(5,|A|)：收集链出 `[[...]]` 与 backlinks 邻居 → 列表 B（排除 raw/superseded）。  
3. 简化 RRF：`score(d) = 1/(k+rank_A) + 1/(k+rank_B)`（k=60）；无出现的 rank 视为很大。  
4. 再乘/加现有 heat/kind 先验（保持与 0.6 一致的相对顺序偏好）。  
5. 截断 `--limit`；ledger 仍记 `event=recall`。  

可选 flag：`--no-graph` 关闭第二路（便于对比 eval）。

### 6.2 `eval`

```bash
"$MM" eval [--fixture <dir>] [--limit 5]
```

- 默认 fixture：`scripts/e2e/fixtures/eval-memory/`（计划内建一小库：若干 atom + 1 superseded + 链接）。  
- 用例文件：`cases.tsv` 列 `id query expect_title`。  
- 输出：`case=... hit=0|1 rank=N`；汇总 `hit_at_k=...` `cases=N`。  
- 退出码：命中率低于阈值（如 <0.8）→ 非零（门禁）。  

## 7. 协议与文档

- `_protocol.md`：new 前 dedupe；实质采用则 cite；过期知识用 supersede；适时 `suggest`/`health`。  
- CLASSIFICATION：增加 `status` / `supersedes`。  
- SKILL / AGENTS / README* / ARCHITECTURE / RIPER。  
- 版本 `0.7.0`。

## 8. 测试要点

- superseded 默认不进 search/recall；`--include-superseded` 可进。  
- supersede 互链与 ledger。  
- dedupe 命中同名规范化。  
- suggest 在 cite 足够时提出 promote。  
- recall：仅 FTS 漏掉、经一跳出链可达的笔记，在开启 graph 时进入 top-k。  
- eval fixture 稳定绿；`--no-graph` 可对比。  

## 9. 风险与边界

- RRF 邻居爆炸：邻居只取 top-A 的一跳，且全局候选上限（如 50）。  
- suggest 噪声：只输出建议，阈值偏保守。  
- bash 3.2：无关联数组；RRF 用临时文件+awk。  

## 10. 实现分期

| 阶段 | 内容 |
|---|---|
| P0 | status 过滤 + `supersede` + 文档字段 |
| P1 | `feedback` + `dedupe` + `suggest` |
| P2 | recall 图扩展 RRF + `eval` fixture + e2e |

同一版本 `0.7.0` 发布。
