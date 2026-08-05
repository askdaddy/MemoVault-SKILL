#!/usr/bin/env bash
# scripts/e2e/lib/env.sh - e2e environment, vault isolation, and phase helpers.
# Bash 3.2. No set -e. No emoji. Source this file; do not execute.
#
# The runtime is always shell/fs now. There is no cli phase and no Obsidian
# vault registration. MM_FORCE_FS is deprecated and ignored by the helper; we
# do not export it from here anymore.

e2e_resolve_repo() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # Layout: scripts/e2e/lib/env.sh -> lib -> e2e -> scripts -> repo root (3 levels up).
  E2E_REPO="$(cd "$here/../../.." && pwd)"
  if [ -n "${E2E_REPO_OVERRIDE:-}" ]; then
    E2E_REPO="$(cd "$E2E_REPO_OVERRIDE" && pwd)"
  fi
  E2E_MM="$E2E_REPO/scripts/memovault.sh"
  [ -x "$E2E_MM" ] || { printf 'e2e: helper not executable: %s\n' "$E2E_MM" >&2; return 1; }
  E2E_STEM="E2E $(date +%s)"
}

e2e_setup_vault() {
  E2E_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/memovault-e2e.XXXXXX")"
  E2E_VAULT="$E2E_ROOT/vault"
  mkdir -p "$E2E_VAULT"
  export AGENT_MEMO_VAULT="$E2E_VAULT"
  # MM_FORCE_FS is deprecated; ensure a caller's export does not leak in.
  unset MM_FORCE_FS 2>/dev/null || true
}

e2e_reset_vault() {
  rm -rf "$E2E_VAULT"
  mkdir -p "$E2E_VAULT/brain" "$E2E_VAULT/daily" "$E2E_VAULT/templates"
}

e2e_mm() {
  # Fresh process so AGENT_MEMO_VAULT from environment applies at helper startup.
  AGENT_MEMO_VAULT="$E2E_VAULT" "$E2E_MM" "$@"
}

e2e_begin_shell_phase() {
  e2e_reset_vault
  export AGENT_MEMO_VAULT="$E2E_VAULT"
}

# Compat alias for older callers; identical to the shell phase.
e2e_begin_fs_phase() { e2e_begin_shell_phase; }

e2e_teardown() {
  if [ "${E2E_KEEP:-0}" = 1 ]; then
    printf 'E2E_ROOT=%s\n' "$E2E_ROOT"
    printf 'E2E_VAULT=%s\n' "$E2E_VAULT"
  else
    [ -n "${E2E_ROOT:-}" ] && rm -rf "$E2E_ROOT"
  fi
}
