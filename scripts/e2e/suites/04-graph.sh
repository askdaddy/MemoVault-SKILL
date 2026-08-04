#!/usr/bin/env bash
# Sourced by run.sh. Uses e2e_mm, E2E_STEM, E2E_VAULT, E2E_PHASE, assert_*.
# Top-level asserts; must not call exit (run.sh sources this file).

dom="e2e"
a="${E2E_STEM} GraphA"
b="${E2E_STEM} GraphB"
orphan="${E2E_STEM} Orphan"
missing="E2E Missing NoSuchNote ${E2E_STEM}"

e2e_mm new "$dom" "$b" --kind atom --body "target" >/dev/null 2>&1 || true
e2e_mm new "$dom" "$a" --kind atom --body "See [[$b]]" >/dev/null 2>&1 || true
e2e_mm new "$dom" "$orphan" --kind atom --body "alone" >/dev/null 2>&1 || true
e2e_mm new "$dom" "${E2E_STEM} Unres" --kind atom --body "See [[$missing]]" >/dev/null 2>&1 || true

links_out="$(e2e_mm links "$a" 2>/dev/null || true)"
assert_contains "$links_out" "$b" "links A->B ($E2E_PHASE)"

bl_out="$(e2e_mm backlinks "$b" 2>/dev/null || true)"
assert_contains "$bl_out" "$a" "backlinks B<-A ($E2E_PHASE)"

orp="$(e2e_mm orphans 2>/dev/null || true)"
assert_contains "$orp" "$orphan" "orphans lists orphan ($E2E_PHASE)"

unr="$(e2e_mm unresolved 2>/dev/null || true)"
assert_contains "$unr" "NoSuchNote" "unresolved lists missing ($E2E_PHASE)"
