#!/usr/bin/env bash
# scripts/lib/eval.sh - recall eval harness. Sourced by memovault.sh. Bash 3.2.

# Run recall cases against a fixture vault.
# Usage: mm_eval_run [--fixture dir] [--limit N] [--no-graph]
# cases.tsv columns: id<TAB>query<TAB>expect_title
mm_eval_run() {
  local fixture="" limit=5 no_graph=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --fixture) fixture="${2:-}"; shift 2 ;;
      --limit) limit="${2:-5}"; shift 2 ;;
      --no-graph) no_graph=1; shift ;;
      *) shift ;;
    esac
  done
  if [ -z "$fixture" ]; then
    fixture="$MM_SOURCE/scripts/e2e/fixtures/eval-memory"
  fi
  local cases="$fixture/cases.tsv"
  [ -f "$cases" ] || mm_die "eval: cases.tsv not found in $fixture"
  [ -d "$fixture/brain" ] || mm_die "eval: brain/ missing in $fixture"

  local old_vault="$MM_VAULT"
  MM_VAULT="$fixture"
  export AGENT_MEMO_VAULT="$fixture"

  local id q expect hit rank total=0 hits=0 line out first
  while IFS='	' read -r id q expect || [ -n "$id" ]; do
    case "$id" in ''|'#'*) continue ;; esac
    [ -n "$q" ] && [ -n "$expect" ] || continue
    total=$((total + 1))
    if [ "$no_graph" = 1 ]; then
      out="$(mmfs_recall "$q" --limit "$limit" --no-graph 2>/dev/null || true)"
    else
      out="$(mmfs_recall "$q" --limit "$limit" 2>/dev/null || true)"
    fi
    hit=0
    rank=0
    first="$(printf '%s\n' "$out" | awk -v e="$expect" '
      BEGIN { r=0 }
      {
        r++
        if ($0 ~ ("title=" e) || $0 ~ ("title=" e " ")) { print r; exit }
      }')"
    if [ -n "$first" ]; then
      hit=1
      rank="$first"
      hits=$((hits + 1))
    fi
    printf 'case=%s hit=%s rank=%s expect=%s\n' "$id" "$hit" "${rank:-0}" "$expect"
  done < "$cases"

  MM_VAULT="$old_vault"
  export AGENT_MEMO_VAULT="$old_vault"

  local pct=0
  if [ "$total" -gt 0 ]; then
    pct=$((hits * 100 / total))
  fi
  printf 'hit_at_k=%s cases=%s hits=%s\n' "$pct" "$total" "$hits"
  if [ "$total" -gt 0 ] && [ "$pct" -lt 80 ]; then
    return 1
  fi
  return 0
}
