#!/usr/bin/env bash
# Sourced by run.sh. Uses e2e_mm, E2E_STEM, E2E_VAULT, E2E_PHASE, assert_*.
# Top-level asserts; must not call exit (run.sh sources this file).

dom="e2e"
t_atom="${E2E_STEM} Atom"
t_skill="${E2E_STEM} Skill SOP"
token="TOKEN_${E2E_STEM// /_}"

# Create atom note; locate via stdout relative path (sanitize_title may alter name).
rel="$(e2e_mm new "$dom" "$t_atom" --kind atom --tags e2e,alpha --body "body $token" 2>/dev/null || true)"
f="$E2E_VAULT/$rel"
assert_file "$f" "new atom file ($E2E_PHASE)"
assert_grep '^kind: atom$' "$f" "atom kind ($E2E_PHASE)"
assert_grep '^heat: seedling$' "$f" "atom heat seedling ($E2E_PHASE)"
assert_grep 'e2e' "$f" "atom tags ($E2E_PHASE)"
assert_grep "$token" "$f" "atom body token ($E2E_PHASE)"

e2e_mm append "$t_atom" "APPEND_MARK" >/dev/null 2>&1 || true
assert_grep 'APPEND_MARK' "$f" "append ($E2E_PHASE)"

e2e_mm prepend "$t_atom" "PREPEND_MARK" >/dev/null 2>&1 || true
# prepend inserts after frontmatter; file should contain mark
assert_grep 'PREPEND_MARK' "$f" "prepend ($E2E_PHASE)"

read_out="$(e2e_mm read "$t_atom" 2>/dev/null || true)"
assert_contains "$read_out" "$t_atom" "read title ($E2E_PHASE)"
assert_contains "$read_out" "$token" "read body ($E2E_PHASE)"

# Skill SOP note; default heat should be growing.
srel="$(e2e_mm new skills "$t_skill" --kind skill --body "Trigger
Steps
Verify
Related" 2>/dev/null || true)"
sf="$E2E_VAULT/$srel"
assert_file "$sf" "skill file ($E2E_PHASE)"
assert_grep '^heat: growing$' "$sf" "skill default heat growing ($E2E_PHASE)"

# Daily note + daily:append.
e2e_mm daily >/dev/null 2>&1 || true
today="$(date +%Y-%m-%d)"
assert_file "$E2E_VAULT/daily/${today}.md" "daily note ($E2E_PHASE)"
e2e_mm daily:append "- e2e line $token" >/dev/null 2>&1 || true
assert_grep "e2e line $token" "$E2E_VAULT/daily/${today}.md" "daily:append ($E2E_PHASE)"
