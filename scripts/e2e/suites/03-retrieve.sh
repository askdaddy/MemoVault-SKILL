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

# 0.8.0: token-OR recall (words need not be a consecutive phrase)
bag="${E2E_STEM} BagSop"
e2e_mm new "$dom" "$bag" --kind skill --body "Controller PERC handles the array.
Separate sentence with copyback after insert.
RAID10 layout is required.
Chinese token 换盘 in this line." >/dev/null 2>&1 || true
bag_out="$(e2e_mm recall "PERC copyback RAID 换盘" --limit 5 --no-graph 2>/dev/null || true)"
assert_contains "$bag_out" "title=$bag" "recall token-OR hits scattered SOP ($E2E_PHASE)"

# 0.8.0: recall skips domain MOC; search still finds it
moc_leaf="${E2E_STEM} KillMode Leaf"
e2e_mm new "$dom" "$moc_leaf" --kind atom --body "leaf only" >/dev/null 2>&1 || true
e2e_mm moc "$dom" >/dev/null 2>&1 || true
moc_rec="$(e2e_mm recall "KillMode" --limit 5 2>/dev/null || true)"
assert_contains "$moc_rec" "title=$moc_leaf" "recall KillMode hits leaf not crowded out ($E2E_PHASE)"
case "$moc_rec" in
  *_*-MOC.md*|*"title=$dom MOC"*)
    e2e_fail "recall omits domain MOC ($E2E_PHASE)" "out=$moc_rec"
    ;;
  *) e2e_pass "recall omits domain MOC ($E2E_PHASE)" ;;
esac
moc_search="$(e2e_mm search "KillMode" --limit 20 2>/dev/null || true)"
case "$moc_search" in
  *"_${dom}-MOC.md"*|*"title=$dom MOC"*)
    e2e_pass "search still finds domain MOC ($E2E_PHASE)"
    ;;
  *) e2e_fail "search still finds domain MOC ($E2E_PHASE)" "out=$moc_search" ;;
esac

# 0.9.1: flags may precede the query; --limit is never the query
flag_tok="FLAGTOK_${E2E_STEM// /_}"
flag_t="${E2E_STEM} FlagFirst"
e2e_mm new "$dom" "$flag_t" --kind atom --body "unique $flag_tok" >/dev/null 2>&1 || true
rout_flag="$(e2e_mm recall --limit 3 "$flag_tok" --no-graph 2>/dev/null || true)"
assert_contains "$rout_flag" "title=$flag_t" "recall flag-first finds query ($E2E_PHASE)"
last_flag="$(grep 'event=recall' "$E2E_VAULT/.memovault/ledger.log" | tail -1)"
case "$last_flag" in
  *"q=$flag_tok"*) e2e_pass "recall flag-first ledger q is query ($E2E_PHASE)" ;;
  *) e2e_fail "recall flag-first ledger q is query ($E2E_PHASE)" "line=$last_flag" ;;
esac
case "$last_flag" in
  *"q=--limit"*) e2e_fail "recall flag-first ledger q is not --limit ($E2E_PHASE)" "line=$last_flag" ;;
  *) e2e_pass "recall flag-first ledger q is not --limit ($E2E_PHASE)" ;;
esac

if e2e_mm recall --limit 3 >/dev/null 2>&1; then
  e2e_fail "recall --limit without query exits nonzero ($E2E_PHASE)"
else
  e2e_pass "recall --limit without query exits nonzero ($E2E_PHASE)"
fi
