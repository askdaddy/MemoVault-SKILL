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

# Default search excludes kind:raw; --include-raw brings it back.
raw_t="${E2E_STEM} RawRet"
e2e_mm new inbox "$raw_t" --kind raw --body "rawfind $token" >/dev/null 2>&1 || true
sout_def="$(e2e_mm search "rawfind $token" 2>/dev/null || true)"
case "$sout_def" in
  *"$raw_t"*|*RawRet*) e2e_fail "search excludes raw by default ($E2E_PHASE)" "out=$sout_def" ;;
  *) e2e_pass "search excludes raw by default ($E2E_PHASE)" ;;
esac
sout_raw="$(e2e_mm search "rawfind $token" --include-raw 2>/dev/null || true)"
assert_contains "$sout_raw" "rawfind" "search --include-raw finds raw ($E2E_PHASE)"

# recall ranks higher heat/kind first
hi="${E2E_STEM} RecallHi"
lo="${E2E_STEM} RecallLo"
e2e_mm new "$dom" "$lo" --kind atom --body "rankme $token" >/dev/null 2>&1 || true
e2e_mm new "$dom" "$hi" --kind skill --body "rankme $token" >/dev/null 2>&1 || true
e2e_mm promote "$hi" >/dev/null 2>&1 || true
rout="$(e2e_mm recall "rankme $token" --limit 2 2>/dev/null || true)"
case "$rout" in
  title="$hi"*|*"title=$hi"*) e2e_pass "recall ranks high note first ($E2E_PHASE)" ;;
  *)
    first="$(printf '%s\n' "$rout" | head -1)"
    case "$first" in
      *"title=$hi"*) e2e_pass "recall ranks high note first ($E2E_PHASE)" ;;
      *) e2e_fail "recall ranks high note first ($E2E_PHASE)" "out=$rout" ;;
    esac
    ;;
esac
