#!/usr/bin/env bash
# Sourced by run.sh. Uses e2e_mm, E2E_STEM, E2E_VAULT, E2E_PHASE, assert_*.
# Top-level asserts; must not call exit (run.sh sources this file).

dom="e2e"
t="${E2E_STEM} Retrieve"
token="RET_${E2E_STEM// /_}"
e2e_mm new "$dom" "$t" --kind atom --tags e2e/ret --body "findme $token" >/dev/null 2>&1 || true

sout="$(e2e_mm search "$token" 2>/dev/null || true)"
assert_contains "$sout" "$token" "search finds token ($E2E_PHASE)"

# limit: create a second hit then limit 1 — soft assert if implementation differs
sout1="$(e2e_mm search "findme" --limit 1 2>/dev/null || true)"
# At least non-empty when hits exist
if [ -n "$sout1" ]; then
  e2e_pass "search --limit returns output ($E2E_PHASE)"
else
  e2e_fail "search --limit returns output ($E2E_PHASE)" "empty"
fi

tags_out="$(e2e_mm tags 2>/dev/null || true)"
assert_contains "$tags_out" "e2e" "tags lists e2e ($E2E_PHASE)"

by="$(e2e_mm by-tag "e2e/ret" 2>/dev/null || true)"
# fs tag matching may be substring; accept title or path. Use case/if to avoid
# chaining assert_contains || assert_contains (would corrupt pass/fail counters).
case "$by" in
  *"$t"*|*Retrieve*) e2e_pass "by-tag lists note ($E2E_PHASE)" ;;
  *) e2e_fail "by-tag lists note ($E2E_PHASE)" "out=$by" ;;
esac

# heat seed: by-heat should mention seedling or path.
bh="$(e2e_mm by-heat 2>/dev/null || true)"
assert_contains "$bh" "seedling" "by-heat has seedling ($E2E_PHASE)"
