# 分词召回 + 诚实 7 天观测 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `0.8.0`: fix ledger `ts` parsing so 7-day health is real, tokenize `recall` as OR-of-tokens, tighten `capture_after_miss`, add a bag-of-words eval case and protocol 1-3 token guidance.

**Architecture:** `mm_obs_field` start-of-line first. `mmfs_recall` splits the query, unions per-token `rg -F` hits, ranks by token-overlap then existing RRF. `capture_after_miss_7d` requires earlier miss plus title overlap or 30-minute window. Eval fixture adds one scattered-token SOP.

**Tech Stack:** bash 3.2, rg/grep -F, awk, existing e2e harness.

## Global Constraints

- No emoji. English comments and user-facing helper strings. Protocol may stay bilingual where SKILL.md already is English.
- Quote all variables. `set -uo pipefail`. No `set -e` in the helper.
- Never write outside `$MM_VAULT` / the repo.
- Keep `cite_rate` / `recapture_dup` formulas unchanged.
- Do not change `search` matching.

---

### Task 1: Failing e2e for 7d window, token_n, capture_after_miss

**Files:**
- Modify: `scripts/e2e/suites/06-obs.sh` (append after isolated-vault block, before restoring E2E_VAULT)
- Modify: `scripts/e2e/suites/03-retrieve.sh` (bag-of-words recall)

**Interfaces:**
- Consumes: `e2e_mm`, `E2E_VAULT`, `E2E_STEM`, `assert_*`
- Produces: failing assertions that Task 2-3 will make pass

- [ ] **Step 1: Add isolated-vault 7d + capture_after_miss + token_n asserts**

At end of `06-obs.sh` isolated block (before `E2E_VAULT="$old_vault"`), add a new iso2 vault so existing iso tests stay valid:

```bash
# --- 0.8.0: 7d window, token_n, capture_after_miss causality ---
iso2="$E2E_ROOT/iso-obs-window"
mkdir -p "$iso2/.memovault" "$iso2/brain/iso"
E2E_VAULT="$iso2"
: > "$iso2/.memovault/ledger.log"
printf '%s\n' "ts=2000-01-01T00:00:00Z event=recall q=ancient hits=1 top=Old" >> "$iso2/.memovault/ledger.log"
e2e_mm recall "NOWMISS_${E2E_STEM}" --limit 3 >/dev/null 2>&1 || true
hw="$($E2E_MM health 2>/dev/null || true)"
# run via e2e_mm
hw="$(e2e_mm health 2>/dev/null || true)"
r7="$(printf '%s\n' "$hw" | awk -F= '/^recall_7d=/{print $2; exit}')"
assert_eq "1" "$r7" "recall_7d ignores 2000-01-01 ledger row ($E2E_PHASE)"
rh="$(printf '%s\n' "$hw" | awk -F= '/^recall_hits_7d=/{print $2; exit}')"
assert_eq "0" "$rh" "ancient hits=1 does not count in 7d ($E2E_PHASE)"

last_r="$(grep 'event=recall' "$iso2/.memovault/ledger.log" | tail -1)"
assert_contains "$last_r" "token_n=" "recall ledger has token_n= ($E2E_PHASE)"

# same-day miss then unrelated capture 4h later, no token overlap -> not counted
today="$(date -u +%Y-%m-%d)"
: > "$iso2/.memovault/ledger.log"
printf '%s\n' "ts=${today}T00:00:00Z event=recall q=unrelated_query hits=0 top= token_n=2" >> "$iso2/.memovault/ledger.log"
printf '%s\n' "ts=${today}T04:00:00Z event=capture title=Completely Different Title kind=atom domain=iso op=new" >> "$iso2/.memovault/ledger.log"
hw2="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hw2" "capture_after_miss_7d=0" "no overlap + 4h gap is not capture_after_miss ($E2E_PHASE)"

: > "$iso2/.memovault/ledger.log"
printf '%s\n' "ts=${today}T00:00:00Z event=recall q=PERC_copyback hits=0 top= token_n=2" >> "$iso2/.memovault/ledger.log"
printf '%s\n' "ts=${today}T04:00:00Z event=capture title=PERC SOP kind=atom domain=iso op=new" >> "$iso2/.memovault/ledger.log"
hw3="$(e2e_mm health 2>/dev/null || true)"
cam="$(printf '%s\n' "$hw3" | awk -F= '/^capture_after_miss_7d=/{print $2; exit}')"
case "$cam" in
  0|-*) e2e_fail "title overlap still counts capture_after_miss ($E2E_PHASE)" "out=$hw3" ;;
  *) e2e_pass "title overlap still counts capture_after_miss ($E2E_PHASE)" ;;
esac
```

Keep the existing sequential miss+3 captures test: it must still pass via the 30-minute window.

- [ ] **Step 2: Add bag-of-words recall in 03-retrieve.sh**

```bash
bag="${E2E_STEM} BagSop"
e2e_mm new "$dom" "$bag" --kind skill --body "Controller PERC handles the array.
Separate sentence with copyback after insert.
RAID10 layout is required.
Chinese token 换盘 in this line." >/dev/null 2>&1 || true
bag_out="$(e2e_mm recall "PERC copyback RAID 换盘" --limit 5 --no-graph 2>/dev/null || true)"
assert_contains "$bag_out" "title=$bag" "recall token-OR hits scattered SOP ($E2E_PHASE)"
```

- [ ] **Step 3: Run e2e and confirm new asserts fail**

Run: `./scripts/e2e/run.sh`

Expected: fail on `recall_7d ignores 2000-01-01` (counts 2) and/or bag-of-words recall (empty). Do not implement yet.

---

### Task 2: Fix `mm_obs_field` and `capture_after_miss`

**Files:**
- Modify: `scripts/lib/obs.sh`

**Interfaces:**
- Consumes: ledger lines `ts=... event=...`
- Produces: correct `ts` values; new capture_after_miss loop; `wide_query_7d` + `hint=wide_query`

- [ ] **Step 1: Replace `mm_obs_field`**

```bash
mm_obs_field() {
  local line="$1" key="$2" rest
  case "$line" in
    "$key="*) rest="${line#"$key="}" ;;
    *" $key="*) rest="${line#*" $key="}" ;;
    *) printf ''; return 0 ;;
  esac
  printf '%s' "$rest" | sed -E 's/ [a-z][a-z0-9_]*=.*//'
}
```

- [ ] **Step 2: Add epoch + token-overlap helpers after `mm_obs_days_ago`**

```bash
mm_obs_ts_epoch() {
  local ts="$1"
  if date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s >/dev/null 2>&1; then
    date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s
    return
  fi
  if date -u -d "$ts" +%s >/dev/null 2>&1; then
    date -u -d "$ts" +%s
    return
  fi
  printf '0'
}

mm_obs_tokens_overlap() {
  local a="$1" b="$2" ta tb
  ta="$(printf '%s' "$a" | tr '[:upper:]_' '[:lower:] ' | tr -s ' ' '\n' | sed '/^$/d')"
  tb="$(printf '%s' "$b" | tr '[:upper:]_' '[:lower:] ' | tr -s ' ' '\n' | sed '/^$/d')"
  printf '%s\n' "$ta" | while IFS= read -r tok; do
    [ "${#tok}" -ge 2 ] || continue
    printf '%s\n' "$tb" | grep -Fx -- "$tok" >/dev/null 2>&1 && return 0
  done
  return 1
}
```

Note: the `while` in a pipeline runs in a subshell so `return 0` may not propagate. Use a for-loop over words instead:

```bash
mm_obs_tokens_overlap() {
  local a="$1" b="$2" tok needle
  needle=" $(printf '%s' "$b" | tr '[:upper:]_' '[:lower:] ') "
  for tok in $(printf '%s' "$a" | tr '[:upper:]_' '[:lower:] '); do
    [ "${#tok}" -ge 2 ] || continue
    case "$needle" in
      *" $tok "*) return 0 ;;
    esac
  done
  return 1
}
```

- [ ] **Step 3: Rewrite capture_after_miss + wide_query in `mm_obs_health`**

Collect miss rows into a temp file `epoch\\tts\\tq` while scanning. After the main loop, for each capture stored as `epoch title`, test against misses.

Simpler single-pass store:

During the ledger loop, append to `miss_tmp` lines `epoch q` for hits=0 recalls, and `cap_tmp` lines `epoch title` for captures.

After the loop:

```bash
capture_after_miss_7d=0
while IFS= read -r cap_line; do
  cap_ep="${cap_line%%	*}"
  cap_title="${cap_line#*	}"
  while IFS= read -r miss_line; do
    miss_ep="${miss_line%%	*}"
    miss_q="${miss_line#*	}"
    [ "$miss_ep" -gt 0 ] 2>/dev/null || continue
    [ "$cap_ep" -ge "$miss_ep" ] 2>/dev/null || continue
    delta=$((cap_ep - miss_ep))
    if [ "$delta" -le 1800 ]; then
      capture_after_miss_7d=$((capture_after_miss_7d + 1))
      break
    fi
    if mm_obs_tokens_overlap "$cap_title" "$miss_q"; then
      capture_after_miss_7d=$((capture_after_miss_7d + 1))
      break
    fi
  done < "$miss_tmp"
done < "$cap_tmp"
```

If epoch is 0 for both, fall back: same UTC day (`cut -c1-10`) and `ts_cap >= ts_miss` string compare, plus overlap OR skip the 30-min branch.

Count `wide_query_7d` from `token_n>=4` on recall events.

Print `wide_query_7d=` after `recapture_new_dup=`.
Hint `wide_query` after `high_kind_other`, when `recall_7d>=5` and `wide_query_7d>=5`.

Delete the old `miss_days` / `cap_days` same-day loop.

- [ ] **Step 4: Re-run 06-obs related asserts** (full e2e later)

---

### Task 3: Tokenize `mmfs_recall` and log `token_n`

**Files:**
- Modify: `scripts/lib/fs.sh` (`mmfs_query_tokens`, `mmfs_recall` FTS block)
- Modify: `scripts/e2e/fixtures/eval-memory/brain/eng/Eval Perc Sop.md` (create)
- Modify: `scripts/e2e/fixtures/eval-memory/cases.tsv`

- [ ] **Step 1: Add `mmfs_query_tokens` before `mmfs_recall`**

```bash
mmfs_query_tokens() {
  printf '%s\n' "$1" | awk '{
    n = split($0, a, /[[:space:]]+/)
    for (i = 1; i <= n; i++) if (a[i] != "") print a[i]
  }'
}
```

- [ ] **Step 2: Replace the single `rg -- "$q"` block in `mmfs_recall`**

Build union of per-token `rg -l -F` (or `grep -rlF`) files. For each file, `tok_hits` = how many tokens match (`rg -F -q -- "$tok" "$file"`). Sort files by `tok_hits` desc, then fill `tmpa` as today (snippet from first matching token line via `rg -n -F`).

`token_n` = token count (0 if none; treat empty q as existing die).

Both miss and hit ledger lines: add `token_n=$token_n` before `hits=`.

Use `-F` so tokens are not regex.

- [ ] **Step 3: Eval fixture**

Create `Eval Perc Sop.md` with four tokens in separate sentences. Add:

```
c3	PERC copyback RAID 换盘	Eval Perc Sop
```

---

### Task 4: Protocol, version, changelog, RIPER

**Files:** `SKILL.md`, `install/adapters/_protocol.md`, `AGENTS.md`, `docs/ARCHITECTURE.md`, `README.md`, `README_CN.md`, `CHANGELOG.md`, `VERSION`, `docs/RIPER.md`

- VERSION / SKILL.md `0.8.0`
- Recall protocol: 1-3 tokens; on miss retry shortest distinctive token then search; `hint=wide_query`
- Health: document `wide_query_7d`, new `capture_after_miss` formula, `token_n` on recall ledger
- CHANGELOG `[0.8.0] - 2026-08-26` Added/Changed/Fixed; move Unreleased charter note into 0.8.0 Changed
- RIPER entry 20

---

### Task 5: Full e2e

Run: `./scripts/e2e/run.sh`

Expected: `pass` with 0 fails. `eval` shows `case=c3 hit=1`.
