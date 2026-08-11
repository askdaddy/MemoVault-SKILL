#!/usr/bin/env bash
# scripts/e2e/run.sh - MemoVault single-phase shell e2e entry.
# The runtime is always shell/fs now; the Obsidian CLI is no longer a runtime
# dependency. There is one suite run; --fs-only is kept as a no-op alias for
# older callers, --cli-only is removed.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/lib/env.sh"

E2E_KEEP=0
E2E_FS_ONLY=0
E2E_REPO_OVERRIDE=""

usage() {
  cat <<'U'
Usage: scripts/e2e/run.sh [--keep] [--fs-only] [--repo <path>]
  --keep       leave E2E_ROOT and print E2E_VAULT (for protocol follow-up)
  --fs-only    no-op alias (runtime is always shell); accepted for compat
  --repo PATH  override repository root
U
}

while [ $# -gt 0 ]; do
  case "$1" in
    --keep) E2E_KEEP=1; shift ;;
    --fs-only) E2E_FS_ONLY=1; shift ;;
    --repo) E2E_REPO_OVERRIDE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --cli-only) printf 'e2e: --cli-only is removed (runtime is always shell)\n' >&2; exit 2 ;;
    *) printf 'e2e: unknown arg: %s\n' "$1" >&2; usage; exit 2 ;;
  esac
done

# --fs-only is now a no-op; runtime is always shell. Warn so callers notice.
if [ "$E2E_FS_ONLY" = 1 ]; then
  printf 'e2e: --fs-only is a no-op (runtime is always shell)\n' >&2
fi

e2e_resolve_repo || exit 1
e2e_setup_vault || exit 1
trap 'e2e_teardown' EXIT

# Syntax gate
if ! bash -n "$E2E_MM"; then
  e2e_fail "bash -n memovault.sh" "parse error"
fi
for f in "$E2E_REPO"/scripts/lib/*.sh "$HERE"/lib/*.sh; do
  [ -f "$f" ] || continue
  if ! bash -n "$f"; then
    e2e_fail "bash -n $(basename "$f")" "parse error"
  fi
done
SYNTAX_FAILS=$E2E_FAIL

run_suites() {
  local s
  for s in 01-preflight 02-capture 03-retrieve 04-graph 05-organize 06-obs 07-acceptance; do
    if [ -f "$HERE/suites/${s}.sh" ]; then
      # shellcheck disable=SC1090
      E2E_PHASE=shell . "$HERE/suites/${s}.sh"
    else
      e2e_fail "suite $s" "missing $HERE/suites/${s}.sh"
    fi
  done
}

printf '\n--- shell phase ---\n'
e2e_begin_shell_phase
fail_at_start=$E2E_FAIL
run_suites
SHELL_FAILS=$((E2E_FAIL - fail_at_start))
printf 'shell_fails=%s\n' "$SHELL_FAILS"

e2e_summary

# Official gate: single shell phase must pass with no syntax failures.
rc=0
if [ "$SYNTAX_FAILS" -gt 0 ] || [ "$SHELL_FAILS" -gt 0 ]; then
  rc=1
fi

exit "$rc"
