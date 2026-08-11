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
