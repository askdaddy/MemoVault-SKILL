# 设计：分词召回 + 诚实的 7 天观测（方案 A）

日期：2026-08-26
版本目标：`0.8.0`（minor：recall 匹配语义变化；health 7 天窗口与 `capture_after_miss` 口径变化）

## 1. 问题

本机 vault 观测结论（见会话画布）：

1. `recall` 用 `rg -- "$query"` 整句匹配。Agent 的 4 词查询是词袋，命中率在 4 词以上为 0。
2. `mm_obs_field ts` 把行首 `ts=` 解析成 `ts=2026-08`，所有 `*_7d` 实际是全历史。
3. `capture_after_miss_7d` 按 UTC 日桶、无时序：当天任意 miss 则当天全部 capture 都算。
4. `eval` 夹具只有 2 条单词语 case，测不到词袋召回。

## 2. 非目标

- 向量 / 语义检索
- 库内卫生（补 kind、MOC、孤儿链）——方案 B
- 改 `search` 匹配语义（仍整句；协议优先 `recall`）
- 改 `cite_rate` / `recapture_dup` 公式

## 3. `mm_obs_field`

先匹配行首 `key=`，再匹配中间 ` key=`。禁止用 `" $line"` 补空格后再 `${line#*" $key="}`（这是 7 天窗口失效的根因）。

解析后 `ts` 值为 `2026-08-11T02:09:12Z`；`ts_day` 仍 `cut -c1-10`。

`suggest` 的 30 天窗口共用此函数，一并修好。

## 4. `recall` 分词

- 按空白切分查询，丢掉空词。`token_n` = 词数。
- 每个词对 `brain/` 做 **固定字符串** 检索（`rg -F` / `grep -F`），候选为词命中的并集（OR）。
- 笔记的 FTS 名次按「命中了几个查询词」降序，再进入现有一跳图 + RRF + heat/kind。
- 单词查询行为与现网等价（固定字符串，不再当正则）。
- 单词语仍可命中；`PERC copyback RAID 换盘` 只要笔记里分别出现这些词即可，不必连续短语。

ledger：`event=recall q=... token_n=N hits=... top=...`（`token_n` 在 `hits` 之前）。旧行缺 `token_n` 时 health 当 0。

`token_n >= 4` 时 `health` 计 `wide_query_7d`。`recall_7d >= 5` 且 `wide_query_7d >= 5` 时输出 `hint=wide_query`。

## 5. `capture_after_miss_7d`（新口径）

只计窗口内 `event=capture`，且存在一次更早的 `event=recall hits=0` 满足：

- 召回时间 `<=` 写入时间（ISO UTC 字符串可比较），且
- **标题与 miss 查询有词重叠**（把 `q` 的下划线还原成空格后分词；大小写不敏感；词长 >= 2），**或** 该 miss 与 capture 间隔 <= 1800 秒。

不再「当天任意 miss 则当天所有 capture 都算」。`op=append` 仍计入（与现网计数对象一致：所有 capture 事件）。

`hint=capture_after_miss` 阈值仍是 `>= 3`。

无 epoch 解析能力时：退化为「同时序 + 同 UTC 日」（不要静默把窗口外事件算进来）。

## 6. `eval` 夹具

在 `scripts/e2e/fixtures/eval-memory/` 增加一篇词分散的 SOP 笔记（不要从本机真实 vault 拷贝）。`cases.tsv` 增加词袋查询，期望该 title 进入 top 5。现有 c1/c2 不得回归。`hit_at_k` 门槛仍 80%。

## 7. 协议

- 默认 1–3 个词。`hint=wide_query` / `low_recall_hit_rate`：先收窄再召。
- 未命中：用最短辨识词重试一次，再 `search`，再考虑 capture。
- `capture_after_miss`：miss 后先 `search` / `dedupe`；不要把「每轮开头的仪式性 miss」当成必须新建笔记。

## 8. 验收

1. 手工：`ts=2026-08-11T...` 的 `mm_obs_field ts` 得到完整时间戳；health 的 `recall_7d` 小于 ledger 全量 recall。
2. e2e：孤立 vault 写入 8 天前的 `event=recall`，`recall_7d` 不计它。
3. e2e：笔记正文里四个词不连续出现，`recall "PERC copyback RAID 换盘"` 命中该笔记。
4. e2e：ledger `event=recall` 含 `token_n=`。
5. e2e：同日、无词重叠、间隔 > 30 分钟的 miss+capture 不增加 `capture_after_miss_7d`；有词重叠或 30 分钟内的仍增加。
6. `eval` 含词袋 case 且 `hit_at_k>=80`。
7. 现有 suites 不回归。
