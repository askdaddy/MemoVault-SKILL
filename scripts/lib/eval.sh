#!/usr/bin/env bash
# scripts/lib/eval.sh - recall eval harness. Sourced by memovault.sh. Bash 3.2.

# cases.tsv: id<TAB>query<TAB>expected title, path:<relative path>, or -.
mm_eval_run() {
  local fixture="" limit=5
  local graph_flag=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --fixture|--limit)
        [ $# -ge 2 ] || mm_die "eval: $1 requires a value"
        if [ "$1" = --fixture ]; then fixture="$2"; else limit="$2"; fi
        shift 2
        ;;
      --no-graph) graph_flag=--no-graph; shift ;;
      *) shift ;;
    esac
  done
  case "$limit" in
    ''|*[!0-9]*) mm_die "eval: limit must be a nonnegative integer" ;;
  esac
  if [ -z "$fixture" ]; then
    fixture="$MM_SOURCE/scripts/e2e/fixtures/eval-memory"
  fi
  local cases="$fixture/cases.tsv"
  [ -f "$cases" ] || mm_die "eval: cases.tsv not found in $fixture"
  [ -d "$fixture/brain" ] || mm_die "eval: brain/ missing in $fixture"

  local MM_VAULT="${fixture%/}" ranked_limit="$limit"
  [ "$ranked_limit" -ge 5 ] || ranked_limit=5
  local id q expect out path title rank position hit
  local total=0 positives=0 hits=0 top1=0 top5=0 negatives=0 false_returns=0
  while IFS=$'\t' read -r id q expect || [ -n "$id" ]; do
    case "$id" in ''|'#'*) continue ;; esac
    [ -n "$q" ] && [ -n "$expect" ] || continue
    total=$((total + 1))
    out="$(mmfs_recall_ranked 1 "$q" --limit "$ranked_limit" ${graph_flag:+"$graph_flag"})" || return 1
    rank=0
    position=0
    hit=0
    if [ "$expect" = - ]; then
      negatives=$((negatives + 1))
      hit=1
      if [ -n "$out" ] && [ "$limit" -gt 0 ]; then
        false_returns=$((false_returns + 1))
        hit=0
      fi
    else
      positives=$((positives + 1))
      while IFS=$'\t' read -r path title; do
        [ -n "$path" ] || continue
        position=$((position + 1))
        case "$expect" in
          path:*) [ "$path" = "${expect#path:}" ] || continue ;;
          *) [ "$title" = "$expect" ] || continue ;;
        esac
        if [ "$position" -le "$limit" ]; then
          hit=1
          rank="$position"
          hits=$((hits + 1))
        fi
        [ "$position" -ne 1 ] || top1=$((top1 + 1))
        [ "$position" -gt 5 ] || top5=$((top5 + 1))
        break
      done <<< "$out"
    fi
    printf 'case=%s hit=%s rank=%s expect=%s\n' "$id" "$hit" "$rank" "$expect"
  done < "$cases"

  local pct=0 pct1=0 pct5=0
  if [ "$positives" -gt 0 ]; then
    pct=$((hits * 100 / positives))
    pct1=$((top1 * 100 / positives))
    pct5=$((top5 * 100 / positives))
  fi
  printf 'hit_at_k=%s cases=%s hits=%s\n' "$pct" "$total" "$hits"
  printf 'top1=%s top5=%s positives=%s no_answer=%s false_returns=%s\n' \
    "$pct1" "$pct5" "$positives" "$negatives" "$false_returns"
  if [ "$positives" -gt 0 ] && [ "$pct" -lt 80 ]; then
    return 1
  fi
  return 0
}
