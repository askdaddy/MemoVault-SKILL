# Health Efficacy Block Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fold spec `docs/superpowers/specs/2026-08-27-health-efficacy-design.md` into unreleased `0.8.0`. Extend `health`/`stats` so the skill reports inventory, retrieval efficacy, use efficacy, and before/after contrast — still one subcommand, `key=value` lines.

**Architecture:** Keep aggregation in `mm_obs_health` (`scripts/lib/obs.sh`). New keys print after `wide_query_7d=` so 0.7.2 field-order e2e stays valid. Snapshot file lives in the vault (`.memovault/health-snap.log`), never outside `$AGENT_MEMO_VAULT`. No new subcommand. Do not change `cite_rate` / `recapture_dup` formulas.

**Tech stack:** bash 3.2, `set -uo pipefail`, no `set -e`. e2e via `scripts/e2e/suites/06-obs.sh` then `./scripts/e2e/run.sh`.

---

## File map

| File | Role |
|---|---|
| `scripts/e2e/suites/06-obs.sh` | Isolated ledger: token buckets, prev window, snap delta, `hint=low_use` |
| `scripts/lib/obs.sh` | `mm_obs_health` aggregation + snap |
| `SKILL.md` | Health: read `summary=` / `use_rate` / token buckets / `delta_*` / `low_use` |
| `install/adapters/_protocol.md` | Same protocol text |
| `docs/ARCHITECTURE.md` | 0.8.0 health efficacy keys |
| `AGENTS.md` | Prefer new efficacy fields |
| `docs/CLASSIFICATION.md` | `low_use` hint |
| `README.md` / `README_CN.md` | Health / efficacy one-liners |
| `CHANGELOG.md` | `[0.8.0]` Added |
| `docs/RIPER.md` | Entry 22 |

---

### Task 1: RED — e2e for new health keys

**Files:** `scripts/e2e/suites/06-obs.sh`

- [x] **Step 1: Assert new keys on the wide_query isolated vault, plus iso4 for buckets / prev / delta / low_use**

Already added: `read_7d` `use_rate` `moc_count` `summary=` `recall_hit_rate_prev7d` on `hwq`; iso4 ledger with prev-window `token_n=4` misses, five current `token_n=1` hits, one uncited `read`, seeded `health-snap.log`.

- [x] **Step 2: Run 06-obs and confirm FAIL on the new asserts**

Implemented in the same session after RED asserts; 01-06 then passed.

---

### Task 2: GREEN — `mm_obs_health`

**Files:** `scripts/lib/obs.sh`

- [x] **Step 1: Count `moc_count` with `mmfs_is_moc` during the existing brain scan. Do not change `heat_evergreen`.**

- [x] **Step 2: 14-day ledger pass**

`since7` = existing `mm_obs_days_ago 7`. `since14` = `mm_obs_days_ago 14`.
Skip `ts_day < since14`. Current window: `ts_day >= since7` (unchanged). Prev: `since14 <= ts_day < since7`.
Keep `capture_after_miss` / `recapture_*` / `skill_reuse` on the current 7d window only.

- [x] **Step 3: 7d efficacy counters**

`read_7d` `feedback_7d` `distill_7d`; `use_rate` = `cite_7d * 100 / recall_7d` or `-1`; `hit_unused_7d` = `max(0, recall_hits_7d - cite_7d)`; `read_uncited_7d` = current-window `read` events whose title has no `cite` in the same window.
Token buckets: `n1` (`token_n=1`), `n23` (2 or 3), `n4` (`>=4`), `nunk` (missing or 0). Bucket `*_hit_rate` is `-1` when count is 0.

- [x] **Step 4: Prev-window keys**

`recall_7d_prev` `recall_hits_7d_prev` `recall_hit_rate_prev7d` `cite_7d_prev` `wide_query_7d_prev`. Hit rate `-1` when prev recall count is 0.

- [x] **Step 5: Snap + delta + summary + hint**

Path: `$AGENT_MEMO_VAULT/.memovault/health-snap.log`. Read last line first; print `delta_<key>=` (or `-` if old key missing); append one ledger-style line; keep 200 lines. Write failure: stderr via `mm_log`, exit 0.
`summary=` English one-liner per spec. `hint=low_use` after existing hints when `recall_hits_7d>=5` and `cite_7d=0`.
Print all new keys after `wide_query_7d=`.

- [x] **Step 6: Re-run 06-obs; expect PASS**

---

### Task 3: Docs + RIPER

- [x] **Step 1: SKILL.md Health + out-of-scope line; `_protocol.md`; AGENTS.md; ARCHITECTURE.md; CLASSIFICATION.md; README*; CHANGELOG `[0.8.0]` Added; RIPER entry 22**

Protocol trigger: user asks 效果 / 对比 / 观测 / health → read `summary=` `use_rate` `recall_n*_hit_rate` `delta_*` `hint=low_use`.

- [x] **Step 2: Full gate `./scripts/e2e/run.sh`**

- [x] **Step 3: Live vault `health` once; confirm `summary=` is readable (not a gate)**

---

### Task 4: Commit (only if the user asks)

Do not commit unless the user explicitly requests it.
