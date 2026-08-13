#!/usr/bin/env bash
# Sourced by run.sh. Observability + distill suite.

dom="e2e"
token="OBS_${E2E_STEM// /_}"
raw_t="${E2E_STEM} ObsRaw"
atom_t="${E2E_STEM} ObsAtom"

e2e_mm new inbox "$raw_t" --kind raw --body "obs-raw $token" >/dev/null 2>&1 || true
dout="$(e2e_mm distill "$raw_t" "$dom" "$atom_t" --kind atom 2>/dev/null || true)"
assert_contains "$dout" "ObsAtom" "distill creates atom path ($E2E_PHASE)"

body="$(e2e_mm read "$atom_t" 2>/dev/null || true)"
assert_contains "$body" "[[$raw_t]]" "distill body links raw ($E2E_PHASE)"
assert_contains "$body" "sources:" "distill has sources frontmatter ($E2E_PHASE)"
assert_contains "$body" "$raw_t" "distill sources mention raw ($E2E_PHASE)"

raw_body="$(e2e_mm read "$raw_t" 2>/dev/null || true)"
assert_contains "$raw_body" "Distilled to [[$atom_t]]" "distill pointer on raw ($E2E_PHASE)"

# recall + cite + health
e2e_mm append "$atom_t" "findable $token" >/dev/null 2>&1 || true
rout="$(e2e_mm recall "$token" --limit 3 2>/dev/null || true)"
assert_contains "$rout" "title=$atom_t" "recall finds distilled atom ($E2E_PHASE)"

cout="$(e2e_mm cite "$atom_t" 2>/dev/null || true)"
assert_contains "$cout" "cited=$atom_t" "cite records title ($E2E_PHASE)"

hout="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hout" "notes_total=" "health prints notes_total ($E2E_PHASE)"
assert_contains "$hout" "cite_rate=" "health prints cite_rate ($E2E_PHASE)"
assert_contains "$hout" "kind_raw=" "health prints kind_raw ($E2E_PHASE)"

# stats alias
sout="$(e2e_mm stats 2>/dev/null || true)"
assert_contains "$sout" "notes_total=" "stats aliases health ($E2E_PHASE)"

# ledger exists after ops
assert_file "$E2E_VAULT/.memovault/ledger.log" "ledger.log created ($E2E_PHASE)"

rot="$(e2e_mm ledger:rotate --keep 5000 2>/dev/null || true)"
assert_contains "$rot" "keep=5000" "ledger:rotate runs ($E2E_PHASE)"

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
