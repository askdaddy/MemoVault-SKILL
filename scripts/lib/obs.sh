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
  local title="${1:-}" file kind="-"
  [ -n "$title" ] || mm_die "usage: cite <title>"
  file="$(mmfs_locate "$title" 2>/dev/null || true)"
  if [ -n "$file" ] && [ -f "$file" ]; then
    kind="$(mmfs_get_prop "$file" kind)"
    [ -n "$kind" ] || kind="-"
  fi
  mm_obs_log "event=cite" "title=$title" "kind=$kind"
  printf 'cited=%s\n' "$title"
}

mm_obs_feedback() {
  local title="${1:-}" score="${2:-}"
  [ -n "$title" ] && [ -n "$score" ] || mm_die "usage: feedback <title> +1|-1"
  case "$score" in
    +1|-1) ;;
    *) mm_die "feedback score must be +1 or -1" ;;
  esac
  mm_obs_log "event=feedback" "title=$title" "score=$score"
  printf 'feedback=%s score=%s\n' "$title" "$score"
}

# Suggest promote/dedupe based on ledger + light vault scan. No mutations.
mm_obs_suggest() {
  mmfs_ensure_vault
  local since p line ev ts_day title score
  local cites_file reads_file fb_file
  since="$(mm_obs_days_ago 30)"
  p="$(mm_obs_ledger_path)"
  cites_file="$(mktemp)"
  reads_file="$(mktemp)"
  fb_file="$(mktemp)"
  if [ -f "$p" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] || continue
      ts_day="$(mm_obs_field "$line" ts | cut -c1-10)"
      [ -n "$ts_day" ] || continue
      [ "$ts_day" \< "$since" ] && continue
      ev="$(mm_obs_field "$line" event)"
      title="$(mm_obs_field "$line" title)"
      [ -n "$title" ] || continue
      case "$ev" in
        cite) printf '%s\n' "$title" >> "$cites_file" ;;
        read) printf '%s\n' "$title" >> "$reads_file" ;;
        feedback)
          score="$(mm_obs_field "$line" score)"
          printf '%s\t%s\n' "$title" "$score" >> "$fb_file"
          ;;
      esac
    done < "$p"
  fi

  # Aggregate counts per title (titles may contain spaces; avoid uniq -c $2)
  local counts_tmp
  counts_tmp="$(mktemp)"
  if [ -s "$cites_file" ]; then
    sort "$cites_file" | uniq -c | while IFS= read -r line; do
      line="${line#"${line%%[![:space:]]*}"}"
      cite_n="${line%% *}"
      title="${line#* }"
      [ -n "$title" ] || continue
      printf '%s\tcite\t%s\n' "$title" "$cite_n"
    done >> "$counts_tmp"
  fi
  if [ -s "$reads_file" ]; then
    sort "$reads_file" | uniq -c | while IFS= read -r line; do
      line="${line#"${line%%[![:space:]]*}"}"
      read_n="${line%% *}"
      title="${line#* }"
      [ -n "$title" ] || continue
      printf '%s\tread\t%s\n' "$title" "$read_n"
    done >> "$counts_tmp"
  fi

  local titles_seen="" cite_n read_n fb_net heat file bl
  while IFS= read -r title; do
    [ -n "$title" ] || continue
    case "$titles_seen" in *"|$title|"*) continue ;; esac
    titles_seen="${titles_seen}|$title|"
    cite_n="$(awk -F'	' -v t="$title" '$1==t && $2=="cite" {s+=$3} END{print s+0}' "$counts_tmp")"
    read_n="$(awk -F'	' -v t="$title" '$1==t && $2=="read" {s+=$3} END{print s+0}' "$counts_tmp")"
    fb_net="$(awk -F'	' -v t="$title" '$1==t { if ($2=="+1") s+=1; else if ($2=="-1") s-=1 } END{print s+0}' "$fb_file")"
    file="$(mmfs_locate "$title" 2>/dev/null || true)"
    [ -n "$file" ] && [ -f "$file" ] || continue
    heat="$(mmfs_get_prop "$file" heat)"
    [ -n "$heat" ] || heat="seedling"
    [ "$heat" = evergreen ] && continue
    bl=0
    if command -v rg >/dev/null 2>&1; then
      bl="$(rg -l --fixed-strings -- "[[$title" "$MM_VAULT/brain" 2>/dev/null | grep -cv "^$file\$" || true)"
    else
      bl="$(grep -rlF -- "[[$title" "$MM_VAULT/brain" 2>/dev/null | grep -cv "^$file\$" || true)"
    fi
    if [ $((cite_n + read_n)) -ge 3 ] || [ "$fb_net" -ge 2 ] || [ "${bl:-0}" -ge 2 ]; then
      printf 'suggest=promote title=%s cites_30d=%s reads_30d=%s feedback_net=%s backlinks=%s\n' \
        "$title" "$cite_n" "$read_n" "$fb_net" "${bl:-0}"
    fi
  done <<EOF
$(cut -f1 "$counts_tmp" 2>/dev/null; cut -f1 "$fb_file" 2>/dev/null)
EOF

  # Title-normalization collisions
  local norm_tmp f tn
  norm_tmp="$(mktemp)"
  if [ -d "$MM_VAULT/brain" ]; then
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      title="$(mmfs_get_prop "$f" title)"
      [ -n "$title" ] || title="$(basename "$f" .md)"
      tn="$(mmfs_norm_title "$title")"
      printf '%s\t%s\n' "$tn" "$title" >> "$norm_tmp"
    done <<EOF
$(find "$MM_VAULT/brain" -type f -name '*.md' 2>/dev/null)
EOF
    awk -F'	' '
      { c[$1]++; titles[$1]=titles[$1] (titles[$1]?"|":"") $2 }
      END {
        for (n in c) if (c[n] >= 2) {
          split(titles[n], a, "|")
          printf "suggest=dedupe title=%s other=%s score=title\n", a[1], a[2]
        }
      }
    ' "$norm_tmp"
  fi
  rm -f "$cites_file" "$reads_file" "$fb_file" "$counts_tmp" "$norm_tmp"
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

# Sanitize domain for health key domain_<name>=N
mm_obs_domain_key() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]/_/g; s/^_//; s/_$//'
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
  date -u +%Y-%m-%d
}

# Extract key=value from a ledger line.
# Extract key=value from a ledger line. Value may contain spaces; ends at
# the next " key=" token (key = [a-z][a-z0-9_]*) or EOL.
mm_obs_field() {
  local line="$1" key="$2" rest
  case " $line" in
    *" $key="*) rest="${line#*" $key="}" ;;
    "$key="*) rest="${line#"$key="}" ;;
    *) printf ''; return 0 ;;
  esac
  printf '%s' "$rest" | sed -E 's/ [a-z][a-z0-9_]*=.*//'
}

# Return 0 if note has provenance (non-empty sources or body [[wikilink]]).
mm_obs_note_has_provenance() {
  local file="$1" src
  src="$(mmfs_get_prop "$file" sources)"
  case "$src" in
    ''|'[]'|'[ ]') ;;
    *) return 0 ;;
  esac
  if grep -q '\[\[' "$file" 2>/dev/null; then
    return 0
  fi
  return 1
}

mm_obs_health() {
  mmfs_ensure_vault
  local notes_total=0 kind_atom=0 kind_raw=0 kind_scenario=0 kind_persona=0 kind_skill=0 kind_other=0
  local heat_seedling=0 heat_growing=0 heat_evergreen=0
  local inbox_raw_count=0 legacy_daily_count=0 superseded_count=0
  local orphan_count=0 orphan_pct=0
  local structured=0 with_prov=0 provenance_pct=-1
  local f rel k h title dom dom_key st
  local dom_tmp=""

  dom_tmp="$(mktemp)"

  if [ -d "$MM_VAULT/brain" ]; then
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      notes_total=$((notes_total + 1))
      rel="${f#"$MM_VAULT"/}"
      k="$(mmfs_get_prop "$f" kind)"
      h="$(mmfs_get_prop "$f" heat)"
      dom="$(mmfs_get_prop "$f" domain)"
      st="$(mmfs_get_prop "$f" status)"
      [ "$st" = superseded ] && superseded_count=$((superseded_count + 1))
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
      if [ -n "$dom" ]; then
        dom_key="$(mm_obs_domain_key "$dom")"
        [ -n "$dom_key" ] && printf '%s\n' "$dom_key" >> "$dom_tmp"
      fi
      if [ "$k" = raw ]; then
        inbox_raw_count=$((inbox_raw_count + 1))
      else
        case "$rel" in
          brain/inbox/*) inbox_raw_count=$((inbox_raw_count + 1)) ;;
        esac
        structured=$((structured + 1))
        if mm_obs_note_has_provenance "$f"; then
          with_prov=$((with_prov + 1))
        fi
      fi
    done <<EOF
$(find "$MM_VAULT/brain" -type f -name '*.md' 2>/dev/null)
EOF
  fi

  if [ "$structured" -gt 0 ]; then
    provenance_pct=$((with_prov * 100 / structured))
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
  local ledger_ok=1
  since="$(mm_obs_days_ago 7)"
  p="$(mm_obs_ledger_path)"
  if [ -f "$p" ]; then
    if ! [ -r "$p" ]; then
      mm_log "obs: ledger unreadable; L1/L2 omitted"
      ledger_ok=0
    fi
  fi
  if [ "$ledger_ok" = 1 ] && [ -f "$p" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] || continue
      ts_day="$(mm_obs_field "$line" ts | cut -c1-10)"
      [ -n "$ts_day" ] || continue
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
      esac
    done < "$p"

    # skill_reuse: distinct skill titles with read|cite count >= 2 in window
    skill_reuse="$(awk -v since="$since" '
      {
        t=""; e=""; title=""; kind="-"
        for (i=1; i<=NF; i++) {
          if ($i ~ /^ts=/) t=substr($i, 4, 10)
          if ($i ~ /^event=/) e=substr($i, 7)
          if ($i ~ /^title=/) title=substr($i, 7)
          if ($i ~ /^kind=/) kind=substr($i, 6)
        }
        if (t < since) next
        if ((e == "read" || e == "cite") && kind == "skill" && title != "") {
          c[title]++
        }
      }
      END {
        n=0
        for (x in c) if (c[x] >= 2) n++
        print n+0
      }
    ' "$p")"
  fi

  if [ "$capture_7d" -gt 0 ] && [ "$recall_7d" -eq 0 ]; then
    capture_without_recall_7d="$capture_7d"
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
  printf 'superseded_count=%s\n' "$superseded_count"
  if [ -s "$dom_tmp" ]; then
    sort "$dom_tmp" | uniq -c | while read -r cnt dname; do
      [ -n "$dname" ] || continue
      printf 'domain_%s=%s\n' "$dname" "$cnt"
    done
  fi
  rm -f "$dom_tmp"
  printf 'inbox_raw_count=%s\n' "$inbox_raw_count"
  printf 'legacy_daily_count=%s\n' "$legacy_daily_count"
  printf 'orphan_count=%s\n' "$orphan_count"
  printf 'orphan_pct=%s\n' "$orphan_pct"
  printf 'provenance_pct=%s\n' "$provenance_pct"
  printf 'recall_7d=%s\n' "$recall_7d"
  printf 'capture_7d=%s\n' "$capture_7d"
  printf 'capture_without_recall_7d=%s\n' "$capture_without_recall_7d"
  printf 'cite_rate=%s\n' "$cite_rate"
  printf 'skill_reuse=%s\n' "${skill_reuse:-0}"
  printf 'promote_rate=%s\n' "$promote_rate"
  printf 'recapture_dup=%s\n' "$recapture_dup"

  # Soft hints for agent self-check (not automatic vault mutations).
  if [ "$inbox_raw_count" -ge 3 ]; then
    printf 'hint=distill_inbox\n'
  fi
  if [ "$cite_rate" -ge 0 ] 2>/dev/null && [ "$cite_rate" -lt 40 ] 2>/dev/null && [ "$recall_hits_7d" -gt 0 ]; then
    printf 'hint=low_cite_rate\n'
  fi
  if [ "$orphan_pct" -ge 50 ] && [ "$notes_total" -ge 3 ]; then
    printf 'hint=high_orphan_pct\n'
  fi
  if [ "$provenance_pct" -ge 0 ] 2>/dev/null && [ "$provenance_pct" -lt 40 ] 2>/dev/null && [ "$structured" -ge 2 ]; then
    printf 'hint=low_provenance\n'
  fi
}
