#!/usr/bin/env bash
# Sourced by run.sh. Uses e2e_mm, E2E_STEM, E2E_VAULT, E2E_PHASE, assert_*.
# Top-level asserts; must not call exit (run.sh sources this file).

dom="e2e"
t="${E2E_STEM} Promo"
# Resolve the note path from `new` stdout so asserts survive any title sanitizing.
rel="$(e2e_mm new "$dom" "$t" --kind atom --body "promo" 2>/dev/null || true)"
f="$E2E_VAULT/$rel"

e2e_mm promote "$t" >/dev/null 2>&1 || true
assert_grep '^heat: growing$' "$f" "promote to growing ($E2E_PHASE)"
e2e_mm promote "$t" >/dev/null 2>&1 || true
assert_grep '^heat: evergreen$' "$f" "promote to evergreen ($E2E_PHASE)"
# third promote: helper logs already evergreen and returns 0
e2e_mm promote "$t" >/dev/null 2>&1
rc=$?
assert_eq 0 "$rc" "promote past evergreen no-ops ($E2E_PHASE)"
assert_grep '^heat: evergreen$' "$f" "still evergreen ($E2E_PHASE)"

moc_out="$(e2e_mm moc "$dom" 2>/dev/null || true)"
assert_file "$E2E_VAULT/brain/$dom/_${dom}-MOC.md" "moc file ($E2E_PHASE)"
assert_grep "$t" "$E2E_VAULT/brain/$dom/_${dom}-MOC.md" "moc lists note ($E2E_PHASE)"

# rename
old="${E2E_STEM} RenameMe"
new="${E2E_STEM} Renamed"
e2e_mm new "$dom" "$old" --kind atom --body "x" >/dev/null 2>&1 || true
e2e_mm rename "$old" "$new" >/dev/null 2>&1 || true
assert_file "$E2E_VAULT/brain/$dom/${new}.md" "rename dest ($E2E_PHASE)"
if [ ! -f "$E2E_VAULT/brain/$dom/${old}.md" ]; then
  e2e_pass "rename removed old ($E2E_PHASE)"
else
  e2e_fail "rename removed old ($E2E_PHASE)" "old still present"
fi

# move into subfolder path under vault
moved="${E2E_STEM} MoveMe"
e2e_mm new "$dom" "$moved" --kind atom --body "m" >/dev/null 2>&1 || true
e2e_mm move "$moved" "brain/${dom}/sub/" >/dev/null 2>&1 || true
assert_file "$E2E_VAULT/brain/${dom}/sub/${moved}.md" "move dest ($E2E_PHASE)"

# path escape: helper must refuse a destination containing a parent reference.
assert_exit_nonzero "refuse move with .. ($E2E_PHASE)" \
  env AGENT_MEMO_VAULT="$E2E_VAULT" \
  "$E2E_MM" move "$new" "../escape/"

# link-safe rename: the shell/fs rename path rewrites [[wikilinks]] across the
# vault via lib/rewrite.sh. This is the official green condition (formerly the
# cli-only red condition). After renaming the target, the source note's body
# must contain the new title (wikilink updated), not the old one.
tgt="${E2E_STEM} Link Target"
src="${E2E_STEM} Link Source"
tgt2="${E2E_STEM} Link Target Renamed"
e2e_mm new "$dom" "$tgt" --kind atom --body "T" >/dev/null 2>&1 || true
e2e_mm new "$dom" "$src" --kind atom --body "See [[$tgt]]" >/dev/null 2>&1 || true
rename_err="$(mktemp)"
e2e_mm rename "$tgt" "$tgt2" >"$rename_err" 2>&1 || true
if grep -q 'links will NOT update' "$rename_err" 2>/dev/null; then
  e2e_fail "rename link-safe ($E2E_PHASE)" "helper reported links NOT updated"
else
  e2e_pass "rename link-safe did not skip rewrite ($E2E_PHASE)"
fi
src_body="$(e2e_mm read "$src" 2>/dev/null || true)"
assert_contains "$src_body" "$tgt2" "rename updated wikilink ($E2E_PHASE)"
case "$src_body" in
  *"[[$tgt]]"*) e2e_fail "rename removed old wikilink ($E2E_PHASE)" "old [[$tgt]] still present" ;;
  *) e2e_pass "rename removed old wikilink ($E2E_PHASE)" ;;
esac
rm -f "$rename_err"
