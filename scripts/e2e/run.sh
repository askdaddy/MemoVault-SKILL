#!/usr/bin/env bash
# scripts/e2e/run.sh - MemoVault dual-mode e2e entry.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/assert.sh"
. "$HERE/lib/env.sh"
. "$HERE/lib/register.sh"

E2E_KEEP=0
E2E_FS_ONLY=0
E2E_CLI_ONLY=0
E2E_REPO_OVERRIDE=""

usage() {
  cat <<'U'
Usage: scripts/e2e/run.sh [--keep] [--fs-only] [--cli-only] [--repo <path>]
  --keep       leave E2E_ROOT and print E2E_VAULT (for protocol follow-up)
  --fs-only    escape hatch (not official gate)
  --cli-only   escape hatch (not official gate)
  --repo PATH  override repository root
U
}

while [ $# -gt 0 ]; do
  case "$1" in
    --keep) E2E_KEEP=1; shift ;;
    --fs-only) E2E_FS_ONLY=1; shift ;;
    --cli-only) E2E_CLI_ONLY=1; shift ;;
    --repo) E2E_REPO_OVERRIDE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'e2e: unknown arg: %s\n' "$1" >&2; usage; exit 2 ;;
  esac
done

if [ "$E2E_FS_ONLY" = 1 ] && [ "$E2E_CLI_ONLY" = 1 ]; then
  printf 'e2e: --fs-only and --cli-only are mutually exclusive\n' >&2
  exit 2
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
  local phase="$1" s
  for s in 01-preflight 02-capture 03-retrieve 04-graph 05-organize; do
    if [ -f "$HERE/suites/${s}.sh" ]; then
      # shellcheck disable=SC1090
      E2E_PHASE="$phase" . "$HERE/suites/${s}.sh"
    else
      e2e_fail "suite $s" "missing $HERE/suites/${s}.sh"
    fi
  done
}

FS_FAILS=0
CLI_FAILS=0
CLI_ENTERED=0

if [ "$E2E_CLI_ONLY" != 1 ]; then
  printf '\n--- FS phase ---\n'
  e2e_begin_fs_phase
  fail_at_start=$E2E_FAIL
  run_suites fs
  FS_FAILS=$((E2E_FAIL - fail_at_start))
  printf 'fs_fails=%s\n' "$FS_FAILS"
fi

if [ "$E2E_FS_ONLY" != 1 ]; then
  printf '\n--- CLI phase ---\n'
  if e2e_begin_cli_phase; then
    CLI_ENTERED=1
    out="$(e2e_mm preflight 2>/dev/null || true)"
    case "$out" in
      mode=cli*)
        fail_at_start=$E2E_FAIL
        run_suites cli
        CLI_FAILS=$((E2E_FAIL - fail_at_start))
        printf 'cli_fails=%s\n' "$CLI_FAILS"
        ;;
      *)
        e2e_fail "cli-preflight" "expected mode=cli, got: $out"
        CLI_FAILS=$((CLI_FAILS + 1))
        printf 'cli_fails=%s\n' "$CLI_FAILS"
        ;;
    esac
    e2e_end_cli_phase
  else
    e2e_fail "cli-register" "could not register vault or start cli phase"
    CLI_FAILS=$((CLI_FAILS + 1))
    printf 'cli_fails=%s\n' "$CLI_FAILS"
  fi
fi

e2e_summary

# Official gate: both phases required unless escape hatch used.
rc=0
if [ "$E2E_FS_ONLY" != 1 ] && [ "$E2E_CLI_ONLY" != 1 ]; then
  if [ "$SYNTAX_FAILS" -gt 0 ] || [ "$FS_FAILS" -gt 0 ] || [ "$CLI_FAILS" -gt 0 ] || [ "$CLI_ENTERED" -ne 1 ]; then
    rc=1
  fi
elif [ "$E2E_FS_ONLY" = 1 ]; then
  [ "$SYNTAX_FAILS" -eq 0 ] && [ "$FS_FAILS" -eq 0 ] || rc=1
elif [ "$E2E_CLI_ONLY" = 1 ]; then
  if [ "$SYNTAX_FAILS" -gt 0 ] || [ "$CLI_ENTERED" -ne 1 ] || [ "$CLI_FAILS" -gt 0 ]; then
    rc=1
  fi
fi

exit "$rc"
