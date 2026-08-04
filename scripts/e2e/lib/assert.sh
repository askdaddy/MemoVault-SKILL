#!/usr/bin/env bash
# scripts/e2e/lib/assert.sh - e2e assertion helpers.
# Bash 3.2. No set -e. No emoji. Source this file; do not execute.

E2E_PASS="${E2E_PASS:-0}"
E2E_FAIL="${E2E_FAIL:-0}"

e2e_pass() {
  E2E_PASS=$((E2E_PASS + 1))
  printf 'PASS  %s\n' "$1"
}

e2e_fail() {
  E2E_FAIL=$((E2E_FAIL + 1))
  printf 'FAIL  %s — %s\n' "$1" "${2:-}"
}

assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$expected" = "$actual" ]; then
    e2e_pass "$msg"
  else
    e2e_fail "$msg" "expected='$expected' actual='$actual'"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  case "$haystack" in
    *"$needle"*) e2e_pass "$msg" ;;
    *) e2e_fail "$msg" "missing '$needle' in: $haystack" ;;
  esac
}

assert_file() {
  local path="$1" msg="$2"
  if [ -f "$path" ]; then
    e2e_pass "$msg"
  else
    e2e_fail "$msg" "not a file: $path"
  fi
}

assert_grep() {
  local pattern="$1" file="$2" msg="$3"
  if [ -f "$file" ] && grep -Eq -- "$pattern" "$file" 2>/dev/null; then
    e2e_pass "$msg"
  else
    e2e_fail "$msg" "pattern /$pattern/ not in $file"
  fi
}

# Run command; expect non-zero exit. Usage: assert_exit_nonzero "msg" cmd args...
assert_exit_nonzero() {
  local msg="$1"; shift
  local rc=0
  "$@" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    e2e_pass "$msg"
  else
    e2e_fail "$msg" "expected non-zero exit, got 0"
  fi
}

e2e_summary() {
  printf '\n=== e2e summary: pass=%s fail=%s ===\n' "$E2E_PASS" "$E2E_FAIL"
  [ "$E2E_FAIL" -eq 0 ]
}
