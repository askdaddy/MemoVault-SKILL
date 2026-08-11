#!/usr/bin/env bash
# scripts/lib/obs.sh - ledger + health (observability). Sourced by memovault.sh.
# Bash 3.2 compatible. No emoji. Never writes outside $MM_VAULT.

mm_obs_dir() { printf '%s/.memovault' "$MM_VAULT"; }

mm_obs_ledger_path() { printf '%s/ledger.log' "$(mm_obs_dir)"; }

# Append one ledger line: mm_obs_log event=E k=v ...
# Never returns non-zero for I/O failure (main commands must not fail).
mm_obs_log() {
  local line="" p dir
  [ -n "${MM_VAULT:-}" ] || return 0
  dir="$(mm_obs_dir)"
  p="$(mm_obs_ledger_path)"
  mkdir -p "$dir" 2>/dev/null || { mm_log "obs: cannot mkdir $dir"; return 0; }
  line="ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  while [ $# -gt 0 ]; do
    line="$line $1"
    shift
  done
  printf '%s\n' "$line" >> "$p" 2>/dev/null || mm_log "obs: cannot append ledger"
  return 0
}

mm_obs_cite() {
  local title="${1:-}"
  [ -n "$title" ] || mm_die "usage: cite <title>"
  mm_obs_log "event=cite" "title=$title"
  printf 'cited=%s\n' "$title"
}

mm_obs_rotate() {
  local keep=5000 p tmp lines
  while [ $# -gt 0 ]; do
    case "$1" in
      --keep) keep="${2:-5000}"; shift 2 ;;
      *) shift ;;
    esac
  done
  p="$(mm_obs_ledger_path)"
  if [ ! -f "$p" ]; then
    printf 'rotated=0 keep=%s\n' "$keep"
    return 0
  fi
  lines="$(wc -l < "$p" | tr -d ' ')"
  if [ "${lines:-0}" -le "$keep" ]; then
    printf 'rotated=0 keep=%s lines=%s\n' "$keep" "$lines"
    return 0
  fi
  tmp="$(mktemp)"
  tail -n "$keep" "$p" > "$tmp" && mv "$tmp" "$p" || { rm -f "$tmp"; mm_log "obs: rotate failed"; printf 'rotated=0\n'; return 0; }
  printf 'rotated=1 keep=%s\n' "$keep"
}

# Normalize title for dup detection.
mm_obs_norm_title() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

# Print YYYY-MM-DD that is N days before today (best-effort; macOS/Linux).
mm_obs_days_ago() {
  local n="$1"
  if date -u -v-"${n}"d +%Y-%m-%d >/dev/null 2>&1; then
    date -u -v-"${n}"d +%Y-%m-%d
    return
  fi
  if date -u -d "${n} days ago" +%Y-%m-%d >/dev/null 2>&1; then
    date -u -d "${n} days ago" +%Y-%m-%d
    return
  fi
  # Fallback: today only window
  date -u +%Y-%m-%d
}

# Extract key=value from a ledger line.
mm_obs_field() {
  local line="$1" key="$2" tok
  for tok in $line; do
    case "$tok" in
      "$key"=*) printf '%s' "${tok#"$key"=}"; return 0 ;;
    esac
  done
  printf ''
}

mm_obs_health() {
  mmfs_ensure_vault
  local notes_total=0 kind_atom=0 kind_raw=0 kind_scenario=0 kind_persona=0 kind_skill=0 kind_other=0
  local heat_seedling=0 heat_growing=0 heat_evergreen=0
  local inbox_raw_count=0 legacy_daily_count=0
  local orphan_count=0 orphan_pct=0
  local f rel k h title

  if [ -d "$MM_VAULT/brain" ]; then
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      notes_total=$((notes_total + 1))
      rel="${f#"$MM_VAULT"/}"
      k="$(mmfs_get_prop "$f" kind)"
      h="$(mmfs_get_prop "$f" heat)"
      [ -n "$h" ] || h="seedling"
      case "$k" in
        atom) kind_atom=$((kind_atom + 1)) ;;
        raw) kind_raw=$((kind_raw + 1)) ;;
        scenario) kind_scenario=$((kind_scenario + 1)) ;;
        persona) kind_persona=$((kind_persona + 1)) ;;
        skill) kind_skill=$((kind_skill + 1)) ;;
        *) kind_other=$((kind_other + 1)) ;;
      esac
      case "$h" in
        evergreen) heat_evergreen=$((heat_evergreen + 1)) ;;
        growing) heat_growing=$((heat_growing + 1)) ;;
        *) heat_seedling=$((heat_seedling + 1)) ;;
      esac
      if [ "$k" = raw ]; then
        inbox_raw_count=$((inbox_raw_count + 1))
      else
        case "$rel" in
          brain/inbox/*) inbox_raw_count=$((inbox_raw_count + 1)) ;;
        esac
      fi
    done <<EOF
$(find "$MM_VAULT/brain" -type f -name '*.md' 2>/dev/null)
EOF
  fi

  if [ -d "$MM_VAULT/daily" ]; then
    legacy_daily_count="$(find "$MM_VAULT/daily" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  fi

  # Orphans: notes with no incoming [[title]] from another note (approximate).
  if [ "$notes_total" -gt 0 ] && [ -d "$MM_VAULT/brain" ]; then
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      title="$(mmfs_get_prop "$f" title)"
      [ -n "$title" ] || title="$(basename "$f" .md)"
      if command -v rg >/dev/null 2>&1; then
        hits="$(rg -l --fixed-strings -- "[[$title" "$MM_VAULT/brain" 2>/dev/null | grep -v "^$f\$" || true)"
      else
        hits="$(grep -rlF -- "[[$title" "$MM_VAULT/brain" 2>/dev/null | grep -v "^$f\$" || true)"
      fi
      [ -z "$hits" ] && orphan_count=$((orphan_count + 1))
    done <<EOF
$(find "$MM_VAULT/brain" -type f -name '*.md' 2>/dev/null)
EOF
    orphan_pct=$((orphan_count * 100 / notes_total))
  fi

  local since recall_7d=0 capture_7d=0 cite_7d=0 promote_7d=0
  local recall_hits_7d=0 capture_without_recall_7d=0
  local skill_reuse=0 recapture_dup=0 cite_rate=-1 promote_rate=-1
  local p line ev ts_day hits title_n titles_seen="" dup_titles=""
  since="$(mm_obs_days_ago 7)"
  p="$(mm_obs_ledger_path)"
  if [ -f "$p" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] || continue
      ts_day="$(mm_obs_field "$line" ts | cut -c1-10)"
      [ -n "$ts_day" ] || continue
      # string compare ISO dates
      [ "$ts_day" \< "$since" ] && continue
      ev="$(mm_obs_field "$line" event)"
      case "$ev" in
        recall)
          recall_7d=$((recall_7d + 1))
          hits="$(mm_obs_field "$line" hits)"
          [ "${hits:-0}" -gt 0 ] 2>/dev/null && recall_hits_7d=$((recall_hits_7d + 1))
          ;;
        capture)
          capture_7d=$((capture_7d + 1))
          title_n="$(mm_obs_norm_title "$(mm_obs_field "$line" title)")"
          if [ -n "$title_n" ]; then
            case "$titles_seen" in
              *"|$title_n|"*)
                case "$dup_titles" in
                  *"|$title_n|"*) ;;
                  *) dup_titles="${dup_titles}|$title_n|"; recapture_dup=$((recapture_dup + 1)) ;;
                esac
                ;;
              *) titles_seen="${titles_seen}|$title_n|" ;;
            esac
          fi
          ;;
        cite) cite_7d=$((cite_7d + 1)) ;;
        promote) promote_7d=$((promote_7d + 1)) ;;
        read)
          k="$(mm_obs_field "$line" kind)"
          # skill_reuse counted below from title frequency of read+cite on skills — simplified:
          ;;
      esac
    done < "$p"
  fi

  # capture_without_recall: if captures in window and zero recalls
  if [ "$capture_7d" -gt 0 ] && [ "$recall_7d" -eq 0 ]; then
    capture_without_recall_7d="$capture_7d"
  fi

  # skill_reuse: count read events whose title appears more than once (proxy)
  if [ -f "$p" ]; then
    skill_reuse="$(awk -v since="$since" '
      {
        for (i=1; i<=NF; i++) {
          if ($i ~ /^ts=/) { t=substr($i,4,10) }
          if ($i ~ /^event=/) { e=substr($i,7) }
          if ($i ~ /^title=/) { title=substr($i,7) }
        }
        if (t < since) next
        if (e == "read" || e == "cite") {
          c[title]++
        }
      }
      END {
        n=0
        for (t in c) if (c[t] >= 2) n++
        print n+0
      }
    ' "$p")"
  fi

  if [ "$recall_hits_7d" -gt 0 ]; then
    cite_rate=$((cite_7d * 100 / recall_hits_7d))
  fi
  if [ "$capture_7d" -gt 0 ]; then
    promote_rate=$((promote_7d * 100 / capture_7d))
  fi

  printf 'notes_total=%s\n' "$notes_total"
  printf 'kind_atom=%s\n' "$kind_atom"
  printf 'kind_raw=%s\n' "$kind_raw"
  printf 'kind_scenario=%s\n' "$kind_scenario"
  printf 'kind_persona=%s\n' "$kind_persona"
  printf 'kind_skill=%s\n' "$kind_skill"
  printf 'kind_other=%s\n' "$kind_other"
  printf 'heat_seedling=%s\n' "$heat_seedling"
  printf 'heat_growing=%s\n' "$heat_growing"
  printf 'heat_evergreen=%s\n' "$heat_evergreen"
  printf 'inbox_raw_count=%s\n' "$inbox_raw_count"
  printf 'legacy_daily_count=%s\n' "$legacy_daily_count"
  printf 'orphan_count=%s\n' "$orphan_count"
  printf 'orphan_pct=%s\n' "$orphan_pct"
  printf 'recall_7d=%s\n' "$recall_7d"
  printf 'capture_7d=%s\n' "$capture_7d"
  printf 'capture_without_recall_7d=%s\n' "$capture_without_recall_7d"
  printf 'cite_rate=%s\n' "$cite_rate"
  printf 'skill_reuse=%s\n' "${skill_reuse:-0}"
  printf 'promote_rate=%s\n' "$promote_rate"
  printf 'recapture_dup=%s\n' "$recapture_dup"
}
