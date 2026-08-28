# 设计：health 功效块 + 对照（方案 A）

日期：2026-08-27
版本目标：折进未发布的 `0.8.0`

## 1. 覆盖结论（现网不够）

现有 `health` **不能**体现技能的全部状态。它偏 **库内卫生（L0）**，功效（检索是否命中、命中后是否被用）只有薄代理。

| 层 | 现有字段 | 能说明什么 | 缺口 |
|---|---|---|---|
| 库存 | notes / kind_* / heat_* / domain_* / inbox / daily / orphan / provenance / superseded | 库长什么样 | `heat_evergreen` 含 MOC，成熟度被抬高；无 `moc_count` |
| 流量 | recall_7d search_7d capture_7d cite_7d | 做了多少次 | `read` / `feedback` / `distill` 已记 ledger，health 不打印 |
| 检索功效 | recall_hit_rate wide_query capture_after_miss | 能否找到 | 无词数桶（A 的核心证据）；无上一窗 |
| 使用功效 | cite_rate（deprecated）skill_reuse promote_rate | 北极星的一半 | 无 `read_7d`；无「命中却不 cite」；`cite_rate` 分母是 hits 不是 recall 次数 |
| 对照 | 无 | 看不出优化前后 | 无 prev7d、无快照 delta、无 `summary=` |

ledger 已有、health 没用：`event=read`、`feedback`、`distill`。

不宣称能测的：回答质量、向量、eval 夹具命中率（那是 CI，不是这座库）。

## 2. 方案 A（锁定）

不新开子命令。`health`/`stats` 仍 `key=value`。新键接在现有 `wide_query_7d=` 之后，以免打乱 0.7.2 字段顺序门禁。

### 2.1 库存诚实

- `moc_count`：`mmfs_is_moc` 为真的笔记数。
- `heat_evergreen` 公式不变；`summary=` 里带上 moc，避免把索引当成内容晋升。

### 2.2 功效（7 天）

从现有 ledger 聚合，不改写入路径。

| 键 | 定义 |
|---|---|
| `read_7d` | `event=read` |
| `feedback_7d` | `event=feedback` |
| `distill_7d` | `event=distill` |
| `use_rate` | `cite_7d * 100 / recall_7d`，无 recall 则为 `-1`（「召了有没有用」） |
| `hit_unused_7d` | `max(0, recall_hits_7d - cite_7d)`（粗：命中次数多于 cite） |
| `read_uncited_7d` | 窗口内 `read` 事件中，title 在同窗无任何 `cite` 的次数（无谓 read 代理） |
| `recall_n1_7d` / `_hits_7d` / `_hit_rate` | `token_n=1` |
| `recall_n23_7d` / `_hits_7d` / `_hit_rate` | `token_n` 为 2 或 3 |
| `recall_n4_7d` / `_hits_7d` / `_hit_rate` | `token_n>=4` |
| `recall_nunk_7d` | 缺 `token_n` 或为 0（升级前旧行） |
| 桶 `*_hit_rate` | 该桶无次数则为 `-1` |

### 2.3 上一窗（days 8–14 vs 近 7 天，边界与现网 `since` 一致）

`since7` = 现网 `mm_obs_days_ago 7`；`since14` = `mm_obs_days_ago 14`。
近 7 天：`ts_day >= since7`。上一窗：`since14 <= ts_day < since7`。

打印：`recall_7d_prev` `recall_hits_7d_prev` `recall_hit_rate_prev7d` `cite_7d_prev` `wide_query_7d_prev`。无上一窗 recall 时 hit_rate 为 `-1`。

不把 `capture_after_miss` 做上一窗（成本高，收益低）。

### 2.4 快照差

路径：`$AGENT_MEMO_VAULT/.memovault/health-snap.log`（vault 内）。
每次 `health` 成功打印后追加一行（与 ledger 相同 `ts= key=` 风格），最多保留 200 行。
键：`ts notes_total recall_hit_rate recall_7d cite_7d read_7d use_rate orphan_pct kind_other_pct wide_query_7d capture_after_miss_7d skill_reuse moc_count`。
若存在上一行，打印 `delta_<key>=`（现值减旧值；缺旧键则该 delta 为 `-`）。
不可写时 stderr 一句，health 仍退出 0。

### 2.5 `summary=`

一行英文，给人扫：

`hit_rate=% n1=% n4=% use_rate=% cite=% read=% uncited_read=% orphan_pct=% moc=%`

百分号字段为 `-` 当值为 `-1`。

### 2.6 hint

`hint=low_use`：`recall_hits_7d>=5` 且 `cite_7d=0`（找得到但协议没 cite）。放在现有 hint 之后。
不删 `low_cite_rate`（仍 deprecated）。

## 3. 协议

用户问效果 / 对比 / 观测 / health 时：跑 `health`，先读 `summary=`、`use_rate`、`recall_n*_hit_rate`、`delta_*`、`hint=low_use`。

## 4. 非目标

向量；改 `cite_rate` / `recapture_dup` 公式；`event=health` 进 ledger；新子命令；eval 夹具命中率并进 production health。

## 5. 验收

1. e2e：上述新键出现；词数桶与上一窗用孤立 ledger；快照 delta；`hint=low_use`；旧字段顺序门禁不破。
2. 本机 `health` 的 `summary=` 能读出 hit_rate / n 桶 / use_rate / moc。
3. 全量 e2e 绿。
