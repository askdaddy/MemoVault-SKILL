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

# Log event=search only when the public search subcommand set MM_SEARCH_OBS=1.
# hits = unique notes in this invocation. Never returns non-zero.
mm_obs_maybe_log_search() {
  local q="$1" hits="${2:-0}" q_tok
  [ "${MM_SEARCH_OBS:-0}" = 1 ] || return 0
  q_tok="$(printf '%s' "$q" | tr ' ' '_')"
  mm_obs_log "event=search" "q=$q_tok" "hits=$hits"
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

# Extract key=value from a ledger line. Value may contain spaces; ends at
# the next " key=" token (key = [a-z][a-z0-9_]*) or EOL.
# Check start-of-line first: padding the line with a space makes *" ts="*
# match the first field, but ${line#*" ts="} then fails to strip it.
mm_obs_field() {
  local line="$1" key="$2" rest
  case "$line" in
    "$key="*) rest="${line#"$key="}" ;;
    *" $key="*) rest="${line#*" $key="}" ;;
    *) printf ''; return 0 ;;
  esac
  printf '%s' "$rest" | sed -E 's/ [a-z][a-z0-9_]*=.*//'
}

# Epoch seconds for ledger ts= (ISO UTC). 0 if unparseable.
mm_obs_ts_epoch() {
  local ts="$1"
  if date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s >/dev/null 2>&1; then
    date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s
    return
  fi
  if date -u -d "$ts" +%s >/dev/null 2>&1; then
    date -u -d "$ts" +%s
    return
  fi
  printf '0'
}

# Return 0 if title and query share a token of length >= 2.
# Underscores in ledger q= count as spaces.
mm_obs_tokens_overlap() {
  local a="$1" b="$2" tok needle
  a="$(printf '%s' "$a" | tr '_' ' ' | tr '[:upper:]' '[:lower:]')"
  b="$(printf '%s' "$b" | tr '_' ' ' | tr '[:upper:]' '[:lower:]')"
  needle=" $b "
  for tok in $a; do
    [ "${#tok}" -ge 2 ] || continue
    case "$needle" in
      *" $tok "*) return 0 ;;
    esac
  done
  return 1
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

mm_obs_snap_path() { printf '%s/health-snap.log' "$(mm_obs_dir)"; }

# Integer percent, or -1 when den is 0.
mm_obs_pct() {
  local num="${1:-0}" den="${2:-0}"
  if [ "$den" -eq 0 ] 2>/dev/null; then
    printf '%s' '-1'
    return
  fi
  printf '%s' $((num * 100 / den))
}

# For summary=: show "-" when a rate is unknown (-1).
mm_obs_dash_neg() {
  local v="$1"
  if [ "$v" = "-1" ]; then
    printf '-'
  else
    printf '%s' "$v"
  fi
}

mm_obs_health() {
  mmfs_ensure_vault
  local notes_total=0 kind_atom=0 kind_raw=0 kind_scenario=0 kind_persona=0 kind_skill=0 kind_snippet=0 kind_other=0
  local heat_seedling=0 heat_growing=0 heat_evergreen=0
  local inbox_raw_count=0 legacy_daily_count=0 superseded_count=0 moc_count=0
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
      mmfs_is_moc "$f" && moc_count=$((moc_count + 1))
      [ -n "$h" ] || h="seedling"
      case "$k" in
        atom) kind_atom=$((kind_atom + 1)) ;;
        raw) kind_raw=$((kind_raw + 1)) ;;
        scenario) kind_scenario=$((kind_scenario + 1)) ;;
        persona) kind_persona=$((kind_persona + 1)) ;;
        skill) kind_skill=$((kind_skill + 1)) ;;
        snippet) kind_snippet=$((kind_snippet + 1)) ;;
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

  local since since7 since14 recall_7d=0 capture_7d=0 cite_7d=0 promote_7d=0
  local recall_hits_7d=0 capture_without_recall_7d=0
  local skill_reuse=0 recapture_dup=0 cite_rate=-1 promote_rate=-1
  local search_7d=0 capture_after_miss_7d=0 recapture_new_dup=0
  local recall_hit_rate=-1 kind_other_pct=-1 wide_query_7d=0
  local read_7d=0 feedback_7d=0 distill_7d=0 use_rate=-1 hit_unused_7d=0 read_uncited_7d=0
  local recall_n1_7d=0 recall_n1_hits_7d=0 recall_n1_hit_rate=-1
  local recall_n23_7d=0 recall_n23_hits_7d=0 recall_n23_hit_rate=-1
  local recall_n4_7d=0 recall_n4_hits_7d=0 recall_n4_hit_rate=-1
  local recall_nunk_7d=0
  local recall_7d_prev=0 recall_hits_7d_prev=0 recall_hit_rate_prev7d=-1
  local cite_7d_prev=0 wide_query_7d_prev=0
  local op ts_full ts_ep token_n cap_ep cap_title miss_ep miss_q delta cap_ts miss_ts
  local titles_new_seen="" dup_new_titles=""
  local p line ev ts_day hits title_n titles_seen="" dup_titles=""
  local ledger_ok=1 miss_tmp="" cap_tmp="" cite_tmp="" read_tmp=""
  local in_cur in_prev ev_title found rt ct snap last_snap oldv snap_tmp snap_n curv
  local hr_s n1_s n4_s ur_s
  since7="$(mm_obs_days_ago 7)"
  since14="$(mm_obs_days_ago 14)"
  since="$since7"
  p="$(mm_obs_ledger_path)"
  if [ -f "$p" ]; then
    if ! [ -r "$p" ]; then
      mm_log "obs: ledger unreadable; L1/L2 omitted"
      ledger_ok=0
    fi
  fi
  if [ "$ledger_ok" = 1 ] && [ -f "$p" ]; then
    miss_tmp="$(mktemp)"
    cap_tmp="$(mktemp)"
    cite_tmp="$(mktemp)"
    read_tmp="$(mktemp)"
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] || continue
      ts_full="$(mm_obs_field "$line" ts)"
      ts_day="$(printf '%s' "$ts_full" | cut -c1-10)"
      [ -n "$ts_day" ] || continue
      [ "$ts_day" \< "$since14" ] && continue
      in_cur=0
      in_prev=0
      if [ ! "$ts_day" \< "$since7" ]; then
        in_cur=1
      else
        in_prev=1
      fi
      ts_ep="$(mm_obs_ts_epoch "$ts_full")"
      ev="$(mm_obs_field "$line" event)"
      case "$ev" in
        recall)
          hits="$(mm_obs_field "$line" hits)"
          token_n="$(mm_obs_field "$line" token_n)"
          if [ "$in_cur" = 1 ]; then
            recall_7d=$((recall_7d + 1))
            [ "${hits:-0}" -gt 0 ] 2>/dev/null && recall_hits_7d=$((recall_hits_7d + 1))
            [ "${token_n:-0}" -ge 4 ] 2>/dev/null && wide_query_7d=$((wide_query_7d + 1))
            if [ "${token_n:-0}" -eq 1 ] 2>/dev/null; then
              recall_n1_7d=$((recall_n1_7d + 1))
              [ "${hits:-0}" -gt 0 ] 2>/dev/null && recall_n1_hits_7d=$((recall_n1_hits_7d + 1))
            elif [ "${token_n:-0}" -eq 2 ] 2>/dev/null || [ "${token_n:-0}" -eq 3 ] 2>/dev/null; then
              recall_n23_7d=$((recall_n23_7d + 1))
              [ "${hits:-0}" -gt 0 ] 2>/dev/null && recall_n23_hits_7d=$((recall_n23_hits_7d + 1))
            elif [ "${token_n:-0}" -ge 4 ] 2>/dev/null; then
              recall_n4_7d=$((recall_n4_7d + 1))
              [ "${hits:-0}" -gt 0 ] 2>/dev/null && recall_n4_hits_7d=$((recall_n4_hits_7d + 1))
            else
              recall_nunk_7d=$((recall_nunk_7d + 1))
            fi
            if [ "${hits:-0}" -eq 0 ] 2>/dev/null; then
              printf '%s\t%s\t%s\n' "$ts_ep" "$ts_full" "$(mm_obs_field "$line" q)" >> "$miss_tmp"
            fi
          else
            recall_7d_prev=$((recall_7d_prev + 1))
            [ "${hits:-0}" -gt 0 ] 2>/dev/null && recall_hits_7d_prev=$((recall_hits_7d_prev + 1))
            [ "${token_n:-0}" -ge 4 ] 2>/dev/null && wide_query_7d_prev=$((wide_query_7d_prev + 1))
          fi
          ;;
        capture)
          [ "$in_cur" = 1 ] || continue
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
          printf '%s\t%s\t%s\n' "$ts_ep" "$ts_full" "$(mm_obs_field "$line" title)" >> "$cap_tmp"
          op="$(mm_obs_field "$line" op)"
          if [ "$op" = new ] && [ -n "$title_n" ]; then
            case "$titles_new_seen" in
              *"|$title_n|"*)
                case "$dup_new_titles" in
                  *"|$title_n|"*) ;;
                  *) dup_new_titles="${dup_new_titles}|$title_n|"; recapture_new_dup=$((recapture_new_dup + 1)) ;;
                esac
                ;;
              *) titles_new_seen="${titles_new_seen}|$title_n|" ;;
            esac
          fi
          ;;
        cite)
          ev_title="$(mm_obs_field "$line" title)"
          if [ "$in_cur" = 1 ]; then
            cite_7d=$((cite_7d + 1))
            [ -n "$ev_title" ] && printf '%s\n' "$ev_title" >> "$cite_tmp"
          else
            cite_7d_prev=$((cite_7d_prev + 1))
          fi
          ;;
        promote)
          [ "$in_cur" = 1 ] && promote_7d=$((promote_7d + 1))
          ;;
        search)
          [ "$in_cur" = 1 ] && search_7d=$((search_7d + 1))
          ;;
        read)
          if [ "$in_cur" = 1 ]; then
            read_7d=$((read_7d + 1))
            ev_title="$(mm_obs_field "$line" title)"
            [ -n "$ev_title" ] && printf '%s\n' "$ev_title" >> "$read_tmp"
          fi
          ;;
        feedback)
          [ "$in_cur" = 1 ] && feedback_7d=$((feedback_7d + 1))
          ;;
        distill)
          [ "$in_cur" = 1 ] && distill_7d=$((distill_7d + 1))
          ;;
      esac
    done < "$p"

    if [ -s "$cap_tmp" ] && [ -s "$miss_tmp" ]; then
      while IFS='	' read -r cap_ep cap_ts cap_title || [ -n "$cap_ep" ]; do
        [ -n "$cap_ts" ] || continue
        while IFS='	' read -r miss_ep miss_ts miss_q || [ -n "$miss_ep" ]; do
          [ -n "$miss_ts" ] || continue
          if [ "${cap_ts}" \< "${miss_ts}" ]; then
            continue
          fi
          if [ "${cap_ep:-0}" -gt 0 ] 2>/dev/null && [ "${miss_ep:-0}" -gt 0 ] 2>/dev/null; then
            delta=$((cap_ep - miss_ep))
            if [ "$delta" -le 1800 ]; then
              capture_after_miss_7d=$((capture_after_miss_7d + 1))
              break
            fi
          fi
          if mm_obs_tokens_overlap "$cap_title" "$miss_q"; then
            if [ "${cap_ep:-0}" -le 0 ] 2>/dev/null || [ "${miss_ep:-0}" -le 0 ] 2>/dev/null; then
              cap_day="$(printf '%s' "$cap_ts" | cut -c1-10)"
              miss_day="$(printf '%s' "$miss_ts" | cut -c1-10)"
              [ "$cap_day" = "$miss_day" ] || continue
            fi
            capture_after_miss_7d=$((capture_after_miss_7d + 1))
            break
          fi
        done < "$miss_tmp"
      done < "$cap_tmp"
    fi
    rm -f "$miss_tmp" "$cap_tmp"

    read_uncited_7d=0
    if [ -s "$read_tmp" ]; then
      while IFS= read -r rt || [ -n "$rt" ]; do
        [ -n "$rt" ] || continue
        found=0
        if [ -s "$cite_tmp" ]; then
          while IFS= read -r ct || [ -n "$ct" ]; do
            [ -n "$ct" ] || continue
            if [ "$rt" = "$ct" ]; then
              found=1
              break
            fi
          done < "$cite_tmp"
        fi
        [ "$found" -eq 0 ] && read_uncited_7d=$((read_uncited_7d + 1))
      done < "$read_tmp"
    fi
    rm -f "$cite_tmp" "$read_tmp"

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
  if [ "$notes_total" -gt 0 ]; then
    kind_other_pct=$((kind_other * 100 / notes_total))
  fi
  if [ "$recall_7d" -gt 0 ]; then
    recall_hit_rate=$((recall_hits_7d * 100 / recall_7d))
    use_rate=$((cite_7d * 100 / recall_7d))
  fi
  if [ "$recall_hits_7d" -gt "$cite_7d" ]; then
    hit_unused_7d=$((recall_hits_7d - cite_7d))
  fi
  recall_n1_hit_rate="$(mm_obs_pct "$recall_n1_hits_7d" "$recall_n1_7d")"
  recall_n23_hit_rate="$(mm_obs_pct "$recall_n23_hits_7d" "$recall_n23_7d")"
  recall_n4_hit_rate="$(mm_obs_pct "$recall_n4_hits_7d" "$recall_n4_7d")"
  if [ "$recall_7d_prev" -gt 0 ]; then
    recall_hit_rate_prev7d=$((recall_hits_7d_prev * 100 / recall_7d_prev))
  fi

  printf 'notes_total=%s\n' "$notes_total"
  printf 'kind_atom=%s\n' "$kind_atom"
  printf 'kind_raw=%s\n' "$kind_raw"
  printf 'kind_scenario=%s\n' "$kind_scenario"
  printf 'kind_persona=%s\n' "$kind_persona"
  printf 'kind_skill=%s\n' "$kind_skill"
  printf 'kind_snippet=%s\n' "$kind_snippet"
  printf 'kind_other=%s\n' "$kind_other"
  printf 'kind_other_pct=%s\n' "$kind_other_pct"
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
  printf 'search_7d=%s\n' "$search_7d"
  printf 'recall_hits_7d=%s\n' "$recall_hits_7d"
  printf 'recall_hit_rate=%s\n' "$recall_hit_rate"
  printf 'capture_after_miss_7d=%s\n' "$capture_after_miss_7d"
  printf 'cite_7d=%s\n' "$cite_7d"
  printf 'recapture_new_dup=%s\n' "$recapture_new_dup"
  printf 'wide_query_7d=%s\n' "$wide_query_7d"
  printf 'moc_count=%s\n' "$moc_count"
  printf 'read_7d=%s\n' "$read_7d"
  printf 'feedback_7d=%s\n' "$feedback_7d"
  printf 'distill_7d=%s\n' "$distill_7d"
  printf 'use_rate=%s\n' "$use_rate"
  printf 'hit_unused_7d=%s\n' "$hit_unused_7d"
  printf 'read_uncited_7d=%s\n' "$read_uncited_7d"
  printf 'recall_n1_7d=%s\n' "$recall_n1_7d"
  printf 'recall_n1_hits_7d=%s\n' "$recall_n1_hits_7d"
  printf 'recall_n1_hit_rate=%s\n' "$recall_n1_hit_rate"
  printf 'recall_n23_7d=%s\n' "$recall_n23_7d"
  printf 'recall_n23_hits_7d=%s\n' "$recall_n23_hits_7d"
  printf 'recall_n23_hit_rate=%s\n' "$recall_n23_hit_rate"
  printf 'recall_n4_7d=%s\n' "$recall_n4_7d"
  printf 'recall_n4_hits_7d=%s\n' "$recall_n4_hits_7d"
  printf 'recall_n4_hit_rate=%s\n' "$recall_n4_hit_rate"
  printf 'recall_nunk_7d=%s\n' "$recall_nunk_7d"
  printf 'recall_7d_prev=%s\n' "$recall_7d_prev"
  printf 'recall_hits_7d_prev=%s\n' "$recall_hits_7d_prev"
  printf 'recall_hit_rate_prev7d=%s\n' "$recall_hit_rate_prev7d"
  printf 'cite_7d_prev=%s\n' "$cite_7d_prev"
  printf 'wide_query_7d_prev=%s\n' "$wide_query_7d_prev"

  last_snap=""
  snap="$(mm_obs_snap_path)"
  if [ -f "$snap" ] && [ -r "$snap" ]; then
    last_snap="$(tail -1 "$snap" 2>/dev/null || true)"
  fi
  if [ -n "$last_snap" ]; then
    for k in notes_total recall_hit_rate recall_7d cite_7d read_7d use_rate orphan_pct kind_other_pct wide_query_7d capture_after_miss_7d skill_reuse moc_count; do
      oldv="$(mm_obs_field "$last_snap" "$k")"
      eval "curv=\$$k"
      if [ -z "$oldv" ]; then
        printf 'delta_%s=-\n' "$k"
      else
        printf 'delta_%s=%s\n' "$k" "$((curv - oldv))"
      fi
    done
  fi

  hr_s="$(mm_obs_dash_neg "$recall_hit_rate")"
  n1_s="$(mm_obs_dash_neg "$recall_n1_hit_rate")"
  n4_s="$(mm_obs_dash_neg "$recall_n4_hit_rate")"
  ur_s="$(mm_obs_dash_neg "$use_rate")"
  printf 'summary=hit_rate=%s n1=%s n4=%s use_rate=%s cite=%s read=%s uncited_read=%s orphan_pct=%s moc=%s\n' \
    "$hr_s" "$n1_s" "$n4_s" "$ur_s" "$cite_7d" "$read_7d" "$read_uncited_7d" "$orphan_pct" "$moc_count"

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
  if [ "$recall_7d" -ge 5 ] && [ "$recall_hit_rate" -ge 0 ] 2>/dev/null && [ "$recall_hit_rate" -lt 40 ]; then
    printf 'hint=low_recall_hit_rate\n'
  fi
  if [ "$capture_after_miss_7d" -ge 3 ]; then
    printf 'hint=capture_after_miss\n'
  fi
  if [ "$notes_total" -ge 10 ] && [ "$kind_other_pct" -ge 40 ]; then
    printf 'hint=high_kind_other\n'
  fi
  if [ "$recall_7d" -ge 5 ] && [ "$wide_query_7d" -ge 5 ]; then
    printf 'hint=wide_query\n'
  fi
  if [ "$recall_hits_7d" -ge 5 ] && [ "$cite_7d" -eq 0 ]; then
    printf 'hint=low_use\n'
  fi

  # Snapshot last (vault-local). Failure must not fail health.
  {
    mkdir -p "$(mm_obs_dir)" 2>/dev/null || { mm_log "obs: cannot mkdir $(mm_obs_dir)"; false; }
  } && {
    snap="$(mm_obs_snap_path)"
    printf 'ts=%s notes_total=%s recall_hit_rate=%s recall_7d=%s cite_7d=%s read_7d=%s use_rate=%s orphan_pct=%s kind_other_pct=%s wide_query_7d=%s capture_after_miss_7d=%s skill_reuse=%s moc_count=%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      "$notes_total" "$recall_hit_rate" "$recall_7d" "$cite_7d" "$read_7d" "$use_rate" \
      "$orphan_pct" "$kind_other_pct" "$wide_query_7d" "$capture_after_miss_7d" \
      "${skill_reuse:-0}" "$moc_count" >> "$snap" 2>/dev/null \
      || mm_log "obs: cannot append health snap"
    if [ -f "$snap" ]; then
      snap_n="$(wc -l < "$snap" | tr -d ' ')"
      if [ "${snap_n:-0}" -gt 200 ] 2>/dev/null; then
        snap_tmp="$(mktemp)"
        if tail -200 "$snap" > "$snap_tmp" 2>/dev/null && mv "$snap_tmp" "$snap" 2>/dev/null; then
          :
        else
          rm -f "$snap_tmp"
          mm_log "obs: cannot rotate health snap"
        fi
      fi
    fi
  }
}
