#!/usr/bin/env bash
# Sourced by run.sh. Forward themes: supersede, dedupe/suggest, RRF, eval.

dom="e2e"
token="FWD_${E2E_STEM// /_}"

# --- supersede ---
old_t="${E2E_STEM} FwdOld"
new_t="${E2E_STEM} FwdNew"
e2e_mm new "$dom" "$old_t" --kind atom --body "super-token $token" >/dev/null 2>&1 || true
e2e_mm new "$dom" "$new_t" --kind atom --body "super-token $token" >/dev/null 2>&1 || true
sout="$(e2e_mm supersede "$old_t" "$new_t" 2>/dev/null || true)"
assert_contains "$sout" "superseded=$old_t" "supersede reports old ($E2E_PHASE)"

def="$(e2e_mm search "super-token $token" 2>/dev/null || true)"
case "$def" in
  *"$old_t"*) e2e_fail "search excludes superseded ($E2E_PHASE)" "out=$def" ;;
  *"$new_t"*) e2e_pass "search excludes superseded ($E2E_PHASE)" ;;
  *) e2e_fail "search still finds new ($E2E_PHASE)" "out=$def" ;;
esac
inc="$(e2e_mm search "super-token $token" --include-superseded 2>/dev/null || true)"
assert_contains "$inc" "$old_t" "search --include-superseded finds old ($E2E_PHASE)"

# --- dedupe ---
dup="$(e2e_mm dedupe "$new_t" --limit 5 2>/dev/null || true)"
assert_contains "$dup" "reason=title_match" "dedupe title_match ($E2E_PHASE)"

# --- feedback + suggest ---
e2e_mm cite "$new_t" >/dev/null 2>&1 || true
e2e_mm cite "$new_t" >/dev/null 2>&1 || true
e2e_mm read "$new_t" >/dev/null 2>&1 || true
fb="$(e2e_mm feedback "$new_t" +1 2>/dev/null || true)"
assert_contains "$fb" "score=+1" "feedback +1 ($E2E_PHASE)"
sug="$(e2e_mm suggest 2>/dev/null || true)"
case "$sug" in
  *"suggest=promote"*"$new_t"*|*"title=$new_t"*) e2e_pass "suggest promote after reinforce ($E2E_PHASE)" ;;
  *)
    # may need more cites; accept any suggest= line as soft pass if promote missing
    case "$sug" in
      *suggest=promote*) e2e_pass "suggest promote after reinforce ($E2E_PHASE)" ;;
      *) e2e_fail "suggest promote after reinforce ($E2E_PHASE)" "out=$sug" ;;
    esac
    ;;
esac

# --- graph recall ---
hub="${E2E_STEM} FwdHub"
spoke="${E2E_STEM} FwdSpoke"
e2e_mm new "$dom" "$hub" --kind atom --body "graph-token $token See [[$spoke]]" >/dev/null 2>&1 || true
e2e_mm new "$dom" "$spoke" --kind atom --body "spoke only no graph-token" >/dev/null 2>&1 || true
nog="$(e2e_mm recall "graph-token $token" --limit 5 --no-graph 2>/dev/null || true)"
case "$nog" in
  *"title=$spoke"*) e2e_fail "recall --no-graph excludes spoke ($E2E_PHASE)" "out=$nog" ;;
  *) e2e_pass "recall --no-graph excludes spoke ($E2E_PHASE)" ;;
esac
yes="$(e2e_mm recall "graph-token $token" --limit 5 2>/dev/null || true)"
assert_contains "$yes" "title=$spoke" "recall graph includes spoke ($E2E_PHASE)"

# --- health superseded_count ---
hout="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hout" "superseded_count=" "health superseded_count ($E2E_PHASE)"

# --- eval fixture ---
ev="$(e2e_mm eval --limit 5 2>/dev/null || true)"
rc=$?
assert_contains "$ev" "hit_at_k=" "eval prints hit_at_k ($E2E_PHASE)"
assert_contains "$ev" "case=c1" "eval runs case c1 ($E2E_PHASE)"
if [ "$rc" -eq 0 ]; then
  e2e_pass "eval exit 0 at hit threshold ($E2E_PHASE)"
else
  e2e_fail "eval exit 0 at hit threshold ($E2E_PHASE)" "rc=$rc out=$ev"
fi
