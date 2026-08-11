#!/usr/bin/env bash
# Sourced by run.sh. Install/upgrade hardening (isolated HOME; no network).

e2e_mk_full_tree() {
  local dest="$1" ver="$2"
  mkdir -p "$dest/install/adapters" "$dest/install/lib" "$dest/scripts/lib" \
    "$dest/templates" "$dest/docs"
  printf '%s\n' "$ver" > "$dest/VERSION"
  printf '# skill\n\n## Memory protocol\n' > "$dest/SKILL.md"
  printf '# agents\n' > "$dest/AGENTS.md"
  printf '# claude\n' > "$dest/CLAUDE.md"
  printf '# readme\n' > "$dest/README.md"
  cp "$E2E_REPO/install/targets.sh" "$dest/install/targets.sh"
  cp "$E2E_REPO/install/lib/resolve.sh" "$dest/install/lib/resolve.sh"
  cp "$E2E_REPO/install/install.sh" "$dest/install/install.sh"
  cp -R "$E2E_REPO/install/adapters/." "$dest/install/adapters/"
  cp "$E2E_REPO/scripts/memovault.sh" "$dest/scripts/memovault.sh"
  cp -R "$E2E_REPO/scripts/lib/." "$dest/scripts/lib/"
  for t in note daily moc skill; do
    [ -f "$E2E_REPO/templates/$t.md" ] && cp "$E2E_REPO/templates/$t.md" "$dest/templates/$t.md"
  done
  chmod +x "$dest/install/install.sh" "$dest/scripts/memovault.sh"
}

UP_HOME="$E2E_ROOT/up-home"
UP_SKILL="$UP_HOME/.agents/skills/memovault"
UP_VAULT="$UP_HOME/.agent-memo-vault"
rm -rf "$UP_HOME"
mkdir -p "$UP_HOME"

# --- install copies install/ ---
e2e_mk_full_tree "$E2E_ROOT/tree-a" "0.7.1"
(
  export HOME="$UP_HOME"
  unset AGENT_MEMO_VAULT MEMOVAULT_DEV_REPO MEMOVAULT_CACHE_REPO MEMOVAULT_SOURCE
  "$E2E_ROOT/tree-a/install/install.sh" --source-only --source "$UP_SKILL" --vault "$UP_VAULT"
) >/tmp/mm-up-install.out 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$UP_SKILL/install/install.sh" ]; then
  e2e_pass "install copies install/ ($E2E_PHASE)"
else
  e2e_fail "install copies install/ ($E2E_PHASE)" "rc=$rc out=$(head -c 400 /tmp/mm-up-install.out)"
fi

# --- env preserved under polluted AGENT_MEMO_VAULT ---
CUSTOM_VAULT="$E2E_ROOT/custom-vault"
mkdir -p "$CUSTOM_VAULT/brain"
cat > "$UP_SKILL/env.sh" <<EOF
# Runtime config
export AGENT_MEMO_VAULT="\${AGENT_MEMO_VAULT:-$CUSTOM_VAULT}"
EOF
printf '%s\n' "$E2E_ROOT/tree-a" > "$UP_SKILL/.source-origin"
(
  export HOME="$UP_HOME"
  export AGENT_MEMO_VAULT="$E2E_ROOT/polluted-vault"
  unset MEMOVAULT_CACHE_REPO MEMOVAULT_SOURCE
  export MEMOVAULT_DEV_REPO="$E2E_ROOT/tree-a"
  "$E2E_ROOT/tree-a/install/install.sh" --upgrade --force --no-pull --source "$UP_SKILL"
) >/tmp/mm-up-env.out 2>&1
env_line="$(grep -E '^export AGENT_MEMO_VAULT=' "$UP_SKILL/env.sh" 2>/dev/null || true)"
case "$env_line" in
  *"$CUSTOM_VAULT"*) e2e_pass "upgrade preserves env.sh vault ($E2E_PHASE)" ;;
  *) e2e_fail "upgrade preserves env.sh vault ($E2E_PHASE)" "line=$env_line out=$(head -c 300 /tmp/mm-up-env.out)" ;;
esac
case "$env_line" in
  *polluted*) e2e_fail "upgrade ignores polluted AGENT_MEMO_VAULT ($E2E_PHASE)" "line=$env_line" ;;
  *) e2e_pass "upgrade ignores polluted AGENT_MEMO_VAULT ($E2E_PHASE)" ;;
esac

# --- older gate refuses without --force ---
printf '9.9.9\n' > "$UP_SKILL/VERSION"
e2e_mk_full_tree "$E2E_ROOT/tree-old" "0.1.0"
(
  export HOME="$UP_HOME"
  unset AGENT_MEMO_VAULT MEMOVAULT_CACHE_REPO MEMOVAULT_SOURCE
  export MEMOVAULT_DEV_REPO="$E2E_ROOT/tree-old"
  "$E2E_ROOT/tree-a/install/install.sh" --upgrade --no-pull --source "$UP_SKILL"
) >/tmp/mm-up-older.out 2>&1
orc=$?
if [ "$orc" -ne 0 ]; then
  e2e_pass "upgrade refuses older without --force ($E2E_PHASE)"
else
  e2e_fail "upgrade refuses older without --force ($E2E_PHASE)" "rc=$orc out=$(head -c 300 /tmp/mm-up-older.out)"
fi

# --- pick newest of two candidates ---
e2e_mk_full_tree "$E2E_ROOT/tree-new" "0.8.0"
e2e_mk_full_tree "$E2E_ROOT/tree-mid" "0.7.5"
# shellcheck source=/dev/null
. "$E2E_REPO/install/lib/resolve.sh"
_mm_note_save=""
mm_note() { :; }
export MM_RESOLVE_SOURCE="$UP_SKILL"
export MM_RESOLVE_ROOT="$E2E_ROOT/tree-mid"
export MM_RESOLVE_NO_PULL=1
export MEMOVAULT_CACHE_REPO="$E2E_ROOT/no-cache"
printf '%s\n' "$E2E_ROOT/tree-new" > "$UP_SKILL/.source-origin"
unset MEMOVAULT_DEV_REPO
picked="$(mm_pick_upgrade_tree)"
unset -f mm_note 2>/dev/null || true
unset MEMOVAULT_CACHE_REPO
case "$picked" in
  *tree-new*) e2e_pass "pick newest full tree ($E2E_PHASE)" ;;
  *) e2e_fail "pick newest full tree ($E2E_PHASE)" "picked=$picked" ;;
esac

# --- helper upgrade finds installer ---
printf '0.7.1\n' > "$UP_SKILL/VERSION"
# Ensure install/ still present after prior upgrades
if [ ! -f "$UP_SKILL/install/install.sh" ]; then
  (
    export HOME="$UP_HOME"
    unset AGENT_MEMO_VAULT MEMOVAULT_CACHE_REPO
    export MEMOVAULT_DEV_REPO="$E2E_ROOT/tree-a"
    "$E2E_ROOT/tree-a/install/install.sh" --upgrade --force --no-pull --source "$UP_SKILL"
  ) >/dev/null 2>&1
fi
(
  export HOME="$UP_HOME"
  unset AGENT_MEMO_VAULT MEMOVAULT_CACHE_REPO
  export MEMOVAULT_SOURCE="$UP_SKILL"
  export MEMOVAULT_DEV_REPO="$E2E_ROOT/tree-a"
  "$UP_SKILL/scripts/memovault.sh" upgrade --force --no-pull
) >/tmp/mm-up-helper.out 2>&1
hrc=$?
if [ "$hrc" -eq 0 ] || grep -qE 'upgrade: done|forcing re-sync|already at' /tmp/mm-up-helper.out 2>/dev/null; then
  e2e_pass "helper upgrade finds installer ($E2E_PHASE)"
else
  e2e_fail "helper upgrade finds installer ($E2E_PHASE)" "rc=$hrc out=$(head -c 400 /tmp/mm-up-helper.out)"
fi
