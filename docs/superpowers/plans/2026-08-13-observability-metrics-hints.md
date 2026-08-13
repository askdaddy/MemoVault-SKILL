# Observability metrics + hints (0.7.2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `0.7.2`: ledger `event=search` for the public `search` subcommand, new `health` fields/hints that make recall quality auditable, protocol text that prefers the new signals — without changing old formulas or write-path behavior.

**Architecture:** Keep a single shell runtime. Public `search)` sets `MM_SEARCH_OBS=1` then calls `mmfs_search`; `mm_obs_maybe_log_search` no-ops unless that flag is 1, so `dedupe`'s internal `mmfs_search` cannot pollute `search_7d`. `mm_obs_health` keeps existing keys/formulas and appends new keys plus three hints. Docs/`VERSION` follow.

**Tech Stack:** bash 3.2, existing e2e harness (`scripts/e2e/run.sh`), no new languages.

**Spec:** `docs/superpowers/specs/2026-08-12-observability-metrics-hints-design.md`

## Global Constraints

- Skill name `memovault`; never write outside `$AGENT_MEMO_VAULT`; no emoji.
- Helper: `#!/usr/bin/env bash`, `set -uo pipefail`, never `set -e` inside the helper.
- Bash 3.2: no associative arrays, no `${v,,}`, no `mapfile`.
- Integer division for all rates (same as existing `cite_rate`).
- Do not change `cite_rate` / `recapture_dup` formulas or existing hint conditions (`distill_inbox`, `low_cite_rate`, `high_orphan_pct`, `low_provenance`).
- Do not change `search` stdout format.
- Do not add `top=` on `event=search`.
- Do not modify `docs/CLI-REFERENCE.md`, `AGENTS.md` surface list, or `scripts/e2e/suites/07-acceptance.sh` unless a new assertion is broken (should not happen).
- Do not call `e2e_reset_vault` from suite 06 (shared vault). Hint / `-1` cases use an isolated directory under `$E2E_ROOT`.
- Platforms: macOS / Linux / Windows via WSL2; same bash scripts.

---

## File map

| File | Action |
|---|---|
| `scripts/lib/obs.sh` | Add `mm_obs_maybe_log_search`; extend `mm_obs_health` (new fields + 3 hints) |
| `scripts/lib/fs.sh` | Unique-note `hits` + log on all successful `mmfs_search` returns; `dedupe` forces `MM_SEARCH_OBS=0` |
| `scripts/memovault.sh` | `search) MM_SEARCH_OBS=1 mmfs_search "$@"` |
| `scripts/e2e/suites/06-obs.sh` | Spec §11 assertions (true commands; isolated vault for hints) |
| `install/adapters/_protocol.md` | Health: new hints, deprecated fields, legacy `low_cite_rate` |
| `SKILL.md` | Health + Out of scope; frontmatter `version: 0.7.2` |
| `docs/ARCHITECTURE.md` | Ledger `search` event + health keys |
| `README.md` / `README_CN.md` | Version + one observability line |
| `docs/RIPER.md` | Entry for 0.7.2 |
| `VERSION` | `0.7.1` → `0.7.2` |

---

### Task 1: Public `search` ledger (`event=search`)

**Files:**
- Modify: `scripts/lib/obs.sh` (helper after `mm_obs_log`)
- Modify: `scripts/lib/fs.sh` (`mmfs_search`, `mmfs_dedupe` internal call)
- Modify: `scripts/memovault.sh` (`search)` dispatch)
- Test: `scripts/e2e/suites/06-obs.sh`

**Interfaces:**
- Consumes: existing `mm_obs_log`
- Produces: `mm_obs_maybe_log_search <q> <hits>` — logs `event=search q=<tok> hits=N` iff `MM_SEARCH_OBS=1`; always returns 0
- Dispatch: `search) MM_SEARCH_OBS=1 mmfs_search "$@" ;;`
- `hits` = unique `.md` paths that passed filters in this invocation (not rg line count)

- [ ] **Step 1: Write the failing tests**

Append to `scripts/e2e/suites/06-obs.sh` (after the existing `ledger:rotate` block). Do not implement logging yet.

```bash
# --- 0.7.2 search ledger ---
ledger="$E2E_VAULT/.memovault/ledger.log"
tok_s="SRCH_${E2E_STEM// /_}"
note_two="${E2E_STEM} TwoLine"
e2e_mm new e2e "$note_two" --kind atom --body "$tok_s line-a
$tok_s line-b" >/dev/null 2>&1 || true

before_s="$(grep -c 'event=search' "$ledger" 2>/dev/null || true)"
[ -n "$before_s" ] || before_s=0
e2e_mm search "$tok_s" >/dev/null 2>&1 || true
after_s="$(grep -c 'event=search' "$ledger" 2>/dev/null || true)"
[ -n "$after_s" ] || after_s=0
assert_eq "$((before_s + 1))" "$after_s" "public search logs one event=search ($E2E_PHASE)"

last_s="$(grep 'event=search' "$ledger" | tail -1)"
assert_contains "$last_s" "hits=1" "search hits= unique notes not rg lines ($E2E_PHASE)"
assert_contains "$last_s" "q=" "search ledger has q= ($E2E_PHASE)"
case "$last_s" in
  *top=*) e2e_fail "search ledger has no top= ($E2E_PHASE)" "line=$last_s" ;;
  *) e2e_pass "search ledger has no top= ($E2E_PHASE)" ;;
esac

tok_miss="SRCHMISS_${E2E_STEM// /_}"
before_m="$(grep -c 'event=search' "$ledger" 2>/dev/null || true)"
[ -n "$before_m" ] || before_m=0
e2e_mm search "$tok_miss" >/dev/null 2>&1 || true
after_m="$(grep -c 'event=search' "$ledger" 2>/dev/null || true)"
[ -n "$after_m" ] || after_m=0
assert_eq "$((before_m + 1))" "$after_m" "zero-hit search still logs event=search ($E2E_PHASE)"
last_m="$(grep 'event=search' "$ledger" | tail -1)"
assert_contains "$last_m" "hits=0" "zero-hit search logs hits=0 ($E2E_PHASE)"

before_d="$(grep -c 'event=search' "$ledger" 2>/dev/null || true)"
[ -n "$before_d" ] || before_d=0
e2e_mm dedupe "$note_two" --limit 5 >/dev/null 2>&1 || true
after_d="$(grep -c 'event=search' "$ledger" 2>/dev/null || true)"
[ -n "$after_d" ] || after_d=0
assert_eq "$before_d" "$after_d" "dedupe does not log event=search ($E2E_PHASE)"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/e2e/run.sh`

Expected: FAIL on `public search logs one event=search` (no `event=search` in ledger yet).

- [ ] **Step 3: Add `mm_obs_maybe_log_search` in `scripts/lib/obs.sh`**

Place immediately after `mm_obs_log`:

```bash
# Log event=search only when the public search subcommand set MM_SEARCH_OBS=1.
# hits = unique notes in this invocation. Never returns non-zero.
mm_obs_maybe_log_search() {
  local q="$1" hits="${2:-0}" q_tok
  [ "${MM_SEARCH_OBS:-0}" = 1 ] || return 0
  q_tok="$(printf '%s' "$q" | tr ' ' '_')"
  mm_obs_log "event=search" "q=$q_tok" "hits=$hits"
}
```

- [ ] **Step 4: Log from `mmfs_search` on every successful return; count unique notes**

In `scripts/lib/fs.sh` `mmfs_search`:

1. After `mmfs_ensure_vault`, replace the brain-dir early return:

```bash
  if [ ! -d "$MM_VAULT/brain" ]; then
    mm_obs_maybe_log_search "$q" 0
    return 0
  fi
```

2. Replace `[ -n "$raw" ] || return 0` with:

```bash
  if [ -z "$raw" ]; then
    mm_obs_maybe_log_search "$q" 0
    return 0
  fi
```

3. Next to `local ... kept=0` add `uniq=0 seen_files=""`.

4. Inside the loop, after `[ "$ok" = 1 ] || continue` and **before** `printf` / `kept++`:

```bash
    case "$seen_files" in
      *"|$abs|"*) ;;
      *) seen_files="${seen_files}|$abs|"; uniq=$((uniq + 1)) ;;
    esac
```

Leave `kept` as the line counter that still drives `--limit` (stdout unchanged).

5. After the `done <<EOF` / `$raw` / `EOF` block, before the function's closing `}`:

```bash
  mm_obs_maybe_log_search "$q" "$uniq"
```

Do **not** log on the `mm_die` empty-query path.

- [ ] **Step 5: Gate the public subcommand; silence `dedupe`**

`scripts/memovault.sh` dispatch:

```bash
    search)       MM_SEARCH_OBS=1 mmfs_search "$@" ;;
```

`scripts/lib/fs.sh` inside `mmfs_dedupe`, change the command substitution to:

```bash
$(MM_SEARCH_OBS=0 mmfs_search "$q" --limit "$limit" 2>/dev/null || true)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `./scripts/e2e/run.sh`

Expected: the four new search assertions PASS; other suites still pass (07/08 already call `search`; extra `event=search` lines are allowed).

- [ ] **Step 7: Commit**

```bash
git add scripts/lib/obs.sh scripts/lib/fs.sh scripts/memovault.sh scripts/e2e/suites/06-obs.sh
git commit -m "$(cat <<'EOF'
feat: log event=search for the public search subcommand

EOF
)"
```

---

### Task 2: `health` new fields + new hints

**Files:**
- Modify: `scripts/lib/obs.sh` (`mm_obs_health` only)
- Test: `scripts/e2e/suites/06-obs.sh`

**Interfaces:**
- Consumes: Task 1 `event=search`; existing ledger `recall` / `capture` / `cite`; existing `kind_other` / `notes_total` / `recall_hits_7d`
- Produces: keys in this exact relative layout:
  - after `kind_other=` insert `kind_other_pct=`
  - after `recapture_dup=` append in order: `search_7d=` `recall_hits_7d=` `recall_hit_rate=` `capture_after_miss_7d=` `cite_7d=` `recapture_new_dup=`
  - existing four hints unchanged, then new hints in order: `low_recall_hit_rate` `capture_after_miss` `high_kind_other` (only if triggered)
- `capture_after_miss_7d`: if a UTC day has any `recall` with `hits=0`, count every `capture` on that day (no time order, no title dedupe)
- `recapture_new_dup`: same title-count algorithm as `recapture_dup`, but only `op=new`

- [ ] **Step 1: Write the failing tests**

Append to `scripts/e2e/suites/06-obs.sh` after Task 1 tests.

```bash
# --- 0.7.2 health fields ---
hout="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hout" "kind_other_pct=" "health prints kind_other_pct ($E2E_PHASE)"
assert_contains "$hout" "search_7d=" "health prints search_7d ($E2E_PHASE)"
assert_contains "$hout" "recall_hits_7d=" "health prints recall_hits_7d ($E2E_PHASE)"
assert_contains "$hout" "recall_hit_rate=" "health prints recall_hit_rate ($E2E_PHASE)"
assert_contains "$hout" "capture_after_miss_7d=" "health prints capture_after_miss_7d ($E2E_PHASE)"
assert_contains "$hout" "cite_7d=" "health prints cite_7d ($E2E_PHASE)"
assert_contains "$hout" "recapture_new_dup=" "health prints recapture_new_dup ($E2E_PHASE)"
assert_contains "$hout" "cite_rate=" "health still prints cite_rate ($E2E_PHASE)"
assert_contains "$hout" "recapture_dup=" "health still prints recapture_dup ($E2E_PHASE)"

# old keys keep relative order; new L1 block comes after recapture_dup
line_of() { printf '%s\n' "$hout" | grep -n "^${1}=" | head -1 | cut -d: -f1; }
ko="$(line_of kind_other)"
kop="$(line_of kind_other_pct)"
cr="$(line_of cite_rate)"
rd="$(line_of recapture_dup)"
s7="$(line_of search_7d)"
if [ -n "$ko" ] && [ -n "$kop" ] && [ "$ko" -lt "$kop" ]; then
  e2e_pass "kind_other_pct follows kind_other ($E2E_PHASE)"
else
  e2e_fail "kind_other_pct follows kind_other ($E2E_PHASE)" "kind_other=$ko kind_other_pct=$kop"
fi
if [ -n "$cr" ] && [ -n "$rd" ] && [ -n "$s7" ] && [ "$cr" -lt "$rd" ] && [ "$rd" -lt "$s7" ]; then
  e2e_pass "cite_rate then recapture_dup then search_7d ($E2E_PHASE)"
else
  e2e_fail "cite_rate then recapture_dup then search_7d ($E2E_PHASE)" "cite_rate=$cr recapture_dup=$rd search_7d=$s7"
fi

tok_miss_r="RECMISS_${E2E_STEM// /_}"
e2e_mm recall "$tok_miss_r" --limit 3 >/dev/null 2>&1 || true
e2e_mm new e2e "${E2E_STEM} AfterMiss" --kind atom --body "after miss" >/dev/null 2>&1 || true
hout2="$(e2e_mm health 2>/dev/null || true)"
case "$hout2" in
  *capture_after_miss_7d=0*|*capture_after_miss_7d=-*) e2e_fail "capture_after_miss_7d >= 1 after miss+capture ($E2E_PHASE)" "out=$hout2" ;;
  *capture_after_miss_7d=*) e2e_pass "capture_after_miss_7d >= 1 after miss+capture ($E2E_PHASE)" ;;
  *) e2e_fail "capture_after_miss_7d present ($E2E_PHASE)" "out=$hout2" ;;
esac

dup_t="${E2E_STEM} DupNew"
e2e_mm new e2e-a "$dup_t" --kind atom --body "dup-a" >/dev/null 2>&1 || true
e2e_mm new e2e-b "$dup_t" --kind atom --body "dup-b" >/dev/null 2>&1 || true
hout3="$(e2e_mm health 2>/dev/null || true)"
case "$hout3" in
  *recapture_new_dup=0*) e2e_fail "recapture_new_dup >= 1 after two-domain new ($E2E_PHASE)" "out=$hout3" ;;
  *recapture_new_dup=*) e2e_pass "recapture_new_dup >= 1 after two-domain new ($E2E_PHASE)" ;;
  *) e2e_fail "recapture_new_dup present ($E2E_PHASE)" "out=$hout3" ;;
esac

snap_new="$(printf '%s\n' "$hout3" | awk -F= '/^recapture_new_dup=/{print $2; exit}')"
app_t="${E2E_STEM} AppendOnly"
e2e_mm new e2e "$app_t" --kind atom --body "once" >/dev/null 2>&1 || true
e2e_mm append "$app_t" "twice" >/dev/null 2>&1 || true
e2e_mm append "$app_t" "thrice" >/dev/null 2>&1 || true
hout4="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hout4" "recapture_dup=" "recapture_dup still present after appends ($E2E_PHASE)"
snap_new2="$(printf '%s\n' "$hout4" | awk -F= '/^recapture_new_dup=/{print $2; exit}')"
# two-domain new already counted; append-only title must not bump recapture_new_dup
assert_eq "$snap_new" "$snap_new2" "append-only repeats do not bump recapture_new_dup ($E2E_PHASE)"
case "$hout4" in
  *recapture_dup=0*) e2e_fail "recapture_dup >= 1 after append repeats ($E2E_PHASE)" "out=$hout4" ;;
  *recapture_dup=*) e2e_pass "recapture_dup >= 1 after append repeats ($E2E_PHASE)" ;;
  *) e2e_fail "recapture_dup present ($E2E_PHASE)" "out=$hout4" ;;
esac

# isolated vault: recall_hit_rate=-1 and new hints (do not reset E2E_VAULT)
iso="$E2E_ROOT/iso-obs"
mkdir -p "$iso"
old_vault="$E2E_VAULT"
E2E_VAULT="$iso"

e2e_mm new iso "Only Note" --kind atom --body "solo" >/dev/null 2>&1 || true
hiso0="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hiso0" "recall_hit_rate=-1" "recall_hit_rate=-1 when no recall ($E2E_PHASE)"

i=1
while [ "$i" -le 5 ]; do
  e2e_mm recall "ISOMISS${i}_${E2E_STEM}" --limit 3 >/dev/null 2>&1 || true
  i=$((i + 1))
done
hiso1="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hiso1" "hint=low_recall_hit_rate" "hint low_recall_hit_rate after 5 misses ($E2E_PHASE)"

e2e_mm new iso "MissCap A" --kind atom --body "a" >/dev/null 2>&1 || true
e2e_mm new iso "MissCap B" --kind atom --body "b" >/dev/null 2>&1 || true
e2e_mm new iso "MissCap C" --kind atom --body "c" >/dev/null 2>&1 || true
hiso2="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hiso2" "hint=capture_after_miss" "hint capture_after_miss after miss day + 3 captures ($E2E_PHASE)"

j=1
while [ "$j" -le 10 ]; do
  e2e_mm new iso "NoKind $j" --body "nk" >/dev/null 2>&1 || true
  j=$((j + 1))
done
hiso3="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hiso3" "hint=high_kind_other" "hint high_kind_other with 10+ unkinded notes ($E2E_PHASE)"

E2E_VAULT="$old_vault"
```

Note on isolated vault: the 5 miss recalls already make that UTC day a miss day; the three `MissCap *` captures are enough for `capture_after_miss_7d >= 3`. The earlier `Only Note` capture on the same UTC day also counts (spec-accepted bias). Do not treat extra counts as failure.

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/e2e/run.sh`

Expected: FAIL on `health prints kind_other_pct`.

- [ ] **Step 3: Extend `mm_obs_health` aggregation**

Near the existing `local recall_hits_7d=0 ... recapture_dup=0` block, add (do not rename existing locals):

```bash
  local search_7d=0 capture_after_miss_7d=0 recapture_new_dup=0
  local recall_hit_rate=-1 kind_other_pct=-1
  local miss_days="" cap_days="" op
  local titles_new_seen="" dup_new_titles=""
```

Inside the ledger `case "$ev"`:

- `recall)`: keep existing `recall_7d` / `recall_hits_7d`. After the hits>0 increment, also:

```bash
          if [ "${hits:-0}" -eq 0 ] 2>/dev/null; then
            miss_days="${miss_days}|$ts_day|"
          fi
```

- `capture)`: keep the existing `recapture_dup` block unchanged. After it, add:

```bash
          cap_days="${cap_days}${ts_day} "
          op="$(mm_obs_field "$line" op)"
          if [ "$op" = new ] && [ -n "$title_n" ]; then
            case "$titles_new_seen" in
              *"|$title_n|"*)
                case "$dup_new_titles" in
                  *"|$title_n|"*) ;;
                  *) dup_new_titles="${dup_new_titles}|$title_n|"; recapture_new_dup=$((recapture_new_dup + 1)) ;;
                esac
                ;;
              *) titles_new_seen="${titles_new_seen}|$title_n|" ;;
            esac
          fi
```

- Add:

```bash
        search) search_7d=$((search_7d + 1)) ;;
```

After the ledger `while` loop (still inside `if ledger readable`), before `skill_reuse` awk is fine, or immediately after the while:

```bash
    for d in $cap_days; do
      [ -n "$d" ] || continue
      case "$miss_days" in
        *"|$d|"*) capture_after_miss_7d=$((capture_after_miss_7d + 1)) ;;
      esac
    done
```

This second walk is required: a capture earlier the same UTC day as a later miss must still count (spec: no time order).

After existing `cite_rate` / `promote_rate` math, add:

```bash
  if [ "$notes_total" -gt 0 ]; then
    kind_other_pct=$((kind_other * 100 / notes_total))
  fi
  if [ "$recall_7d" -gt 0 ]; then
    recall_hit_rate=$((recall_hits_7d * 100 / recall_7d))
  fi
```

Do not change the `cite_rate` formula.

- [ ] **Step 4: Print new keys; append new hints**

After `printf 'kind_other=%s\n' "$kind_other"` insert:

```bash
  printf 'kind_other_pct=%s\n' "$kind_other_pct"
```

After `printf 'recapture_dup=%s\n' "$recapture_dup"` and **before** the existing hint block:

```bash
  printf 'search_7d=%s\n' "$search_7d"
  printf 'recall_hits_7d=%s\n' "$recall_hits_7d"
  printf 'recall_hit_rate=%s\n' "$recall_hit_rate"
  printf 'capture_after_miss_7d=%s\n' "$capture_after_miss_7d"
  printf 'cite_7d=%s\n' "$cite_7d"
  printf 'recapture_new_dup=%s\n' "$recapture_new_dup"
```

Leave the four existing hint `if` blocks byte-for-byte. After them append:

```bash
  if [ "$recall_7d" -ge 5 ] && [ "$recall_hit_rate" -ge 0 ] 2>/dev/null && [ "$recall_hit_rate" -lt 40 ]; then
    printf 'hint=low_recall_hit_rate\n'
  fi
  if [ "$capture_after_miss_7d" -ge 3 ]; then
    printf 'hint=capture_after_miss\n'
  fi
  if [ "$notes_total" -ge 10 ] && [ "$kind_other_pct" -ge 40 ]; then
    printf 'hint=high_kind_other\n'
  fi
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `./scripts/e2e/run.sh`

Expected: all new 06 assertions PASS; `eval` / 08-forward still PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/obs.sh scripts/e2e/suites/06-obs.sh
git commit -m "$(cat <<'EOF'
feat: add health metrics and hints for recall quality

EOF
)"
```

---

### Task 3: Docs, protocol, version `0.7.2`

**Files:**
- Modify: `install/adapters/_protocol.md`, `SKILL.md`, `docs/ARCHITECTURE.md`, `README.md`, `README_CN.md`, `docs/RIPER.md`, `VERSION`
- Do not modify: adapter stub skeletons, `docs/CLI-REFERENCE.md`, `AGENTS.md`

**Interfaces:**
- Consumes: Task 1–2 field names and hint names (exact spellings above)
- Produces: installed agents see new protocol text only after `upgrade`

- [ ] **Step 1: `VERSION` + `SKILL.md` frontmatter**

`VERSION` contents:

```
0.7.2
```

`SKILL.md` YAML: `version: 0.7.2`

Replace Health (self-check) with:

```markdown
### Health (self-check)

When the user asks about memory health, or inbox/raw is piling up, run `health`
and/or `suggest` and act on `hint=` / `suggest=` lines. Prefer new hints when
present (confirm with the user before any vault rewrite):

- `low_recall_hit_rate`: narrow the recall query and retry.
- `capture_after_miss`: after a miss, run `search` / `dedupe` before capture.
- `high_kind_other`: add `kind` when missing; if invalid, set a legal kind.

Treat `hint=low_cite_rate` as legacy: ignore it when a new hint is present, and
do not use it as the sole action driver. Prefer `recall_hit_rate`,
`recall_hits_7d`, `cite_7d`, `recapture_new_dup`, `kind_other_pct`. `search_7d`
is informational (compare with `recall_7d`). `cite_rate` and `recapture_dup`
are deprecated. Confirm before `promote`. Do not silently rewrite the vault.
```

Replace Out of scope proxy sentence:

```markdown
- Human-rated answer quality scores: `health` uses proxy metrics only
  (`recall_hit_rate`, `cite_7d`, `recapture_new_dup`, `kind_other_pct`;
  `cite_rate` / `recapture_dup` are deprecated).
```

- [ ] **Step 2: `_protocol.md` Health bullet**

Replace the last bullet of section 5 with:

```markdown
- When the user asks about memory health, or inbox/raw is piling up, run
  `__MEMOVAULT_HELPER__ health` / `suggest` and act on `hint=` / `suggest=`
  lines. Prefer new hints when present (confirm before any rewrite):
  `low_recall_hit_rate` (narrow recall), `capture_after_miss` (search/dedupe
  before capture), `high_kind_other` (add or fix `kind`). Treat
  `hint=low_cite_rate` as legacy. Prefer `recall_hit_rate`, `recall_hits_7d`,
  `cite_7d`, `recapture_new_dup`, `kind_other_pct`; `search_7d` is
  informational. `cite_rate` and `recapture_dup` are deprecated. Do not
  silently rewrite the vault.
```

- [ ] **Step 3: `docs/ARCHITECTURE.md`**

After the subcommand table in section 5, add:

```markdown
Ledger file: `$AGENT_MEMO_VAULT/.memovault/ledger.log` (not searchable).
Events include `recall`, `search` (public `search` subcommand only; `dedupe`
internal retrieval is not logged), `read`, `capture`, `cite`, `feedback`,
`promote`, `distill`, `supersede`. `event=search` is independent of
`event=recall` (0.6.0 optionally lumped them; 0.7.2 does not).

`health` / `stats` print L0 vault counts plus L1/L2 ledger proxies. Added in
0.7.2: `kind_other_pct`, `search_7d`, `recall_hits_7d`, `recall_hit_rate`,
`capture_after_miss_7d`, `cite_7d`, `recapture_new_dup`, and hints
`low_recall_hit_rate` / `capture_after_miss` / `high_kind_other`.
`cite_rate` and `recapture_dup` remain with their original formulas
(deprecated).
```

Also change the `search` row to mention ledger: `rg`/`grep` under `brain/`; filters; ledger `event=search` on the public subcommand only.

- [ ] **Step 4: README pair + RIPER**

`README.md`: version cell `0.7.2`. Observability bullet:

```markdown
- **Observability:** `cite`, `feedback`, `suggest`, `health`/`stats`, ledger (`search`, `recall_hit_rate` hints)
```

`README_CN.md`: version cell `0.7.2` if present; observability bullet:

```markdown
- **可观测：** `cite`、`feedback`、`suggest`、`health`/`stats`、ledger（含 `search` 与 `recall_hit_rate` hint）
```

Append to `docs/RIPER.md`:

```markdown
## 17. Entry: 可观测指标可信度 + hint 0.7.2（2026-08-13）

### Research
- 现网 `cite_rate` 用 `recall_hits_7d` 作分母，协议「调过 recall」会被读成「召回有用」。
- `recapture_dup` 计入 `op=append`；`mmfs_search` 被 `dedupe` 复用。
- 规格：`docs/superpowers/specs/2026-08-12-observability-metrics-hints-design.md`（2026-08-13 可行性修订）。

### Innovate
- 方案 1 Metrics+Hints；兼容 B 并列新字段；search 用 `MM_SEARCH_OBS` 门控。

### Plan
- `docs/superpowers/plans/2026-08-13-observability-metrics-hints.md`

### Execute
- `event=search` 仅公开 `search` 子命令；`health` 新键与三则 hint；协议 / SKILL / ARCHITECTURE / README* / VERSION `0.7.2`。

### Review
- `./scripts/e2e/run.sh`：记录 pass/fail。
```

Fill the Review line with the actual e2e summary after Step 5.

- [ ] **Step 5: Full regression**

Run: `./scripts/e2e/run.sh`

Expected: `fail=0`. Record `pass=N` into the RIPER Review line.

Optional local smoke (not a gate): `"$HOME/.agents/skills/memovault/scripts/memovault.sh" health` on the developer vault after install/upgrade — confirm new keys print. Skip if the installed helper is still 0.7.1.

- [ ] **Step 6: Commit**

```bash
git add VERSION SKILL.md install/adapters/_protocol.md docs/ARCHITECTURE.md README.md README_CN.md docs/RIPER.md
git commit -m "$(cat <<'EOF'
docs: ship 0.7.2 observability metrics and protocol hints

EOF
)"
```

---

## Self-review (spec coverage)

| Spec | Task |
|---|---|
| §6 public `search` only; `dedupe` silent; `hits=0` on empty; unique notes; no `top=` | Task 1 |
| §5 `kind_other_pct` after `kind_other=` | Task 2 |
| §5.2 new keys after `recapture_dup=` | Task 2 |
| §5 `recall_hits_7d` / `recall_hit_rate` / `search_7d` / `cite_7d` | Task 2 |
| §5.1 `capture_after_miss_7d` UTC day, no time order | Task 2 |
| §5 `recapture_new_dup` `op=new` title count | Task 2 |
| §7 new hints; old hint conditions untouched | Task 2 |
| §4 / §8 deprecated fields; legacy `low_cite_rate` | Task 3 |
| §9 `-1` on missing denominator | Task 2 isolated vault |
| §10 / §11 file list and e2e cases | Tasks 1–3 |
| §3 no `07-acceptance` / CLI-REFERENCE / adapter skeleton churn | Task 3 |
| Integer division | Task 2 formulas |
| `0.7.2` patch + upgrade for protocol | Task 3 |

No placeholders. `suggest` thresholds are not touched (no task). `capture_without_recall_7d` is not given a new hint (no task).
