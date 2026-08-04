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
# MM_FORCE_FS mirrors the active phase so the spawned helper lands in the same
# mode the suite is running under (1 in fs phase, 0 in cli phase).
assert_exit_nonzero "refuse move with .. ($E2E_PHASE)" \
  env AGENT_MEMO_VAULT="$E2E_VAULT" MM_FORCE_FS="${MM_FORCE_FS:-0}" \
  "$E2E_MM" move "$new" "../escape/"

# CLI-only link-safe rename: in cli mode the helper must go through the
# Obsidian CLI (which rewrites wikilinks), not fall back to fs.
if [ "$E2E_PHASE" = cli ]; then
  tgt="${E2E_STEM} Link Target"
  src="${E2E_STEM} Link Source"
  tgt2="${E2E_STEM} Link Target Renamed"
  e2e_mm new "$dom" "$tgt" --kind atom --body "T" >/dev/null 2>&1 || true
  e2e_mm new "$dom" "$src" --kind atom --body "See [[$tgt]]" >/dev/null 2>&1 || true
  # Fail CLI phase if helper falls back to fs.
  rename_err="$(mktemp)"
  e2e_mm rename "$tgt" "$tgt2" >"$rename_err" 2>&1 || true
  if grep -q 'using fs (links will NOT update)' "$rename_err" 2>/dev/null; then
    e2e_fail "cli rename link-safe" "fell back to fs"
  else
    e2e_pass "cli rename did not fs-fallback"
  fi
  src_body="$(e2e_mm read "$src" 2>/dev/null || true)"
  assert_contains "$src_body" "$tgt2" "cli rename updated wikilink"
  rm -f "$rename_err"
fi
