#!/usr/bin/env bash
# lib/fs.sh - filesystem runtime layer for MemoVault.
# All functions operate on $MM_VAULT (set by memovault.sh). This is the only
# runtime layer in the shell-only runtime; the on-disk file is what humans
# browse in Obsidian. No emoji. Never write outside $MM_VAULT.

# Print today's date (ISO). Defined here so this lib is self-describing; the
# entry script also defines it and overrides nothing.
mmfs_today() { date +%Y-%m-%d; }

# Ensure vault + core folders exist.
mmfs_ensure_vault() {
  mkdir -p "$MM_VAULT/brain" "$MM_VAULT/daily" "$MM_VAULT/templates"
}

# Sanitize a title into a filesystem-safe basename (keeps it readable).
mmfs_sanitize_title() {
  local t="$1"
  t="${t//$\// - }"      # no slashes
  t="${t//:/ -}"         # no colons (cross platform)
  # trim leading/trailing whitespace
  t="${t#"${t%%[![:space:]]*}"}"
  t="${t%"${t##*[![:space:]]}"}"
  printf '%s' "$t"
}

# Find a note by its title (filename stem) under brain/, then daily/.
# Prefer brain on name collision. Print path or empty.
mmfs_find_note() {
  local title; title="$(mmfs_sanitize_title "$1")"
  local hit=""
  if [ -d "$MM_VAULT/brain" ]; then
    hit="$(find "$MM_VAULT/brain" -type f -name "$title.md" 2>/dev/null | head -n1)"
  fi
  if [ -n "$hit" ]; then
    printf '%s' "$hit"
    return 0
  fi
  if [ -f "$MM_VAULT/daily/$title.md" ]; then
    printf '%s' "$MM_VAULT/daily/$title.md"
  fi
}

# Resolve a user supplied reference (title or path) to an absolute file path.
# Print path or empty.
mmfs_locate() {
  local arg="$1"
  [ -n "$arg" ] || return 0
  if [[ "$arg" == /* ]]; then
    [ -f "$arg" ] && printf '%s' "$arg"
    return 0
  fi
  if [ -f "$MM_VAULT/$arg" ]; then
    printf '%s' "$MM_VAULT/$arg"
    return 0
  fi
  # Allow vault-relative paths without .md (e.g. daily/2026-08-03).
  if [ -f "$MM_VAULT/$arg.md" ]; then
    printf '%s' "$MM_VAULT/$arg.md"
    return 0
  fi
  mmfs_find_note "$arg"
}

# Build the canonical note path for a domain/title.
mmfs_note_path() {
  local domain="$1" title; title="$(mmfs_sanitize_title "$2")"
  printf '%s/brain/%s/%s.md' "$MM_VAULT" "$domain" "$title"
}

# Format a comma list "a, b, c" as a YAML list line value "[a, b, c]".
mmfs_yaml_list() {
  local raw="$1"
  raw="${raw#,}"; raw="${raw%,}"
  if [ -z "${raw//[[:space:]]/}" ]; then
    printf '[]'
    return
  fi
  printf '['
  local first=1
  IFS=',' read -ra parts <<<"$raw"
  for p in "${parts[@]}"; do
    p="${p#"${p%%[![:space:]]*}"}"; p="${p%"${p##*[![:space:]]}"}"
    [ -n "$p" ] || continue
    [ $first -eq 1 ] || printf ', '
    printf '%s' "$p"
    first=0
  done
  printf ']'
}

# Create a new note. Usage: mmfs_new <domain> <title> [tags_csv] [body] [kind]
mmfs_new() {
  local domain="$1" title="$2" tags="${3:-}" body="${4:-}" kind="${5:-}"
  [ -n "$domain" ] && [ -n "$title" ] || { mm_die "usage: new <domain> <title>"; }
  if [ -n "$kind" ]; then
    case "$kind" in
      raw|atom|scenario|persona|skill) ;;
      *) mm_die "invalid kind: $kind (raw|atom|scenario|persona|skill)" ;;
    esac
  fi
  mmfs_ensure_vault
  mkdir -p "$MM_VAULT/brain/$domain"
  local file; file="$(mmfs_note_path "$domain" "$title")"
  [ -f "$file" ] && mm_die "note already exists: $title ($file). Use append instead."
  local today; today="$(mmfs_today)"
  local title_clean; title_clean="$(mmfs_sanitize_title "$title")"
  local heat="seedling"
  [ "$kind" = skill ] && heat="growing"
  {
    printf -- '---\n'
    printf 'title: %s\n' "$title_clean"
    printf 'domain: %s\n' "$domain"
    [ -n "$kind" ] && printf 'kind: %s\n' "$kind"
    printf 'tags: %s\n' "$(mmfs_yaml_list "$tags")"
    printf 'heat: %s\n' "$heat"
    printf 'aliases: []\n'
    printf 'sources: []\n'
    printf 'created: %s\n' "$today"
    printf 'updated: %s\n' "$today"
    printf -- '---\n\n'
    printf '# %s\n\n' "$title_clean"
    [ -n "$body" ] && printf '%s\n' "$body"
  } > "$file"
  mm_obs_log "event=capture" "title=$title_clean" "kind=${kind:--}" "domain=$domain" "op=new"
  printf '%s\n' "${file#"$MM_VAULT"/}"
}

# Distill a raw note into atom|scenario. Usage:
# mmfs_distill <raw-ref> <domain> <title> [--kind atom|scenario]
mmfs_distill() {
  local raw_ref="${1:-}" domain="${2:-}" title="${3:-}"
  shift 3 2>/dev/null || true
  local kind="atom"
  while [ $# -gt 0 ]; do
    case "$1" in
      --kind) kind="${2:-atom}"; shift 2 ;;
      *) shift ;;
    esac
  done
  [ -n "$raw_ref" ] && [ -n "$domain" ] && [ -n "$title" ] || \
    mm_die "usage: distill <raw-ref> <domain> <title> [--kind atom|scenario]"
  case "$kind" in
    atom|scenario) ;;
    *) mm_die "distill kind must be atom|scenario" ;;
  esac
  local raw_file raw_title title_clean dest
  raw_file="$(mmfs_locate "$raw_ref")"
  [ -n "$raw_file" ] && [ -f "$raw_file" ] || mm_die "raw not found: $raw_ref"
  raw_title="$(mmfs_get_prop "$raw_file" title)"
  [ -n "$raw_title" ] || raw_title="$(basename "$raw_file" .md)"
  title_clean="$(mmfs_sanitize_title "$title")"
  mmfs_new "$domain" "$title_clean" "" "See [[$raw_title]]." "$kind"
  dest="$(mmfs_note_path "$domain" "$title_clean")"
  mmfs_set_prop "$dest" sources "[$raw_title]"
  printf '\nDistilled to [[%s]]\n' "$title_clean" >> "$raw_file"
  mm_obs_log "event=distill" "from=$raw_title" "to=$title_clean"
  printf '%s\n' "${dest#"$MM_VAULT"/}"
}

mmfs_append() {
  local ref="$1" content="$2"
  local file; file="$(mmfs_locate "$ref")"
  [ -n "$file" ] && [ -f "$file" ] || mm_die "note not found: $ref"
  {
    printf '\n'
    printf '%s\n' "$content"
  } >> "$file"
  local t
  t="$(mmfs_get_prop "$file" title)"
  [ -n "$t" ] || t="$(basename "$file" .md)"
  mm_obs_log "event=capture" "title=$t" "kind=$(mmfs_get_prop "$file" kind)" "domain=$(mmfs_get_prop "$file" domain)" "op=append"
  printf '%s\n' "${file#"$MM_VAULT"/}"
}

# Insert content right after the closing frontmatter delimiter.
mmfs_prepend() {
  local ref="$1" content="$2"
  local file; file="$(mmfs_locate "$ref")"
  [ -n "$file" ] && [ -f "$file" ] || mm_die "note not found: $ref"
  local tmp; tmp="$(mktemp)"
  awk -v c="$content" '
    BEGIN { state = 0 }
    /^---[[:space:]]*$/ {
      print
      if (state == 0) { state = 1; next }
      if (state == 1) { printf "\n%s\n", c; state = 2; next }
    }
    { print }
  ' "$file" > "$tmp" || { rm -f "$tmp"; mm_die "prepend failed"; }
  mv "$tmp" "$file"
  printf '%s\n' "${file#"$MM_VAULT"/}"
}

mmfs_read() {
  local ref="$1"
  local file; file="$(mmfs_locate "$ref")"
  [ -n "$file" ] && [ -f "$file" ] || mm_die "note not found: $ref"
  local t k
  t="$(mmfs_get_prop "$file" title)"
  [ -n "$t" ] || t="$(basename "$file" .md)"
  k="$(mmfs_get_prop "$file" kind)"
  [ -n "$k" ] || k="-"
  mm_obs_log "event=read" "title=$t" "kind=$k"
  cat "$file"
}

mmfs_daily_path() {
  printf '%s/daily/%s.md\n' "$MM_VAULT" "$(mmfs_today)"
}

mmfs_daily() {
  local f; f="$(mmfs_daily_path)"
  local today; today="$(mmfs_today)"
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] || {
    printf -- '---\ntitle: %s\ncreated: %s\n---\n\n# %s\n\n' "$today" "$today" "$today" > "$f"
  }
  cat "$f"
}

mmfs_daily_append() {
  local content="$1"
  local f; f="$(mmfs_daily_path)"
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] || mmfs_daily >/dev/null
  { printf '\n%s\n' "$content"; } >> "$f"
  printf '%s\n' "${f#"$MM_VAULT"/}"
}

# Read a single frontmatter property value (first match). Print value.
mmfs_get_prop() {
  local file="$1" name="$2"
  [ -f "$file" ] || return 0
  awk -v n="$name" '
    /^---[[:space:]]*$/ { c++; next }
    c == 1 && $0 ~ "^"n":" {
      sub("^"n":[[:space:]]*", "")
      print
      exit
    }
  ' "$file"
}

# Set or add a frontmatter property. Updates in place.
mmfs_set_prop() {
  local file="$1" name="$2" value="$3"
  [ -f "$file" ] || mm_die "set_prop: file not found: $file"
  local tmp; tmp="$(mktemp)"
  awk -v n="$name" -v v="$value" '
    BEGIN { state = 0; done = 0 }
    /^---[[:space:]]*$/ {
      print
      if (state == 0) { state = 1; next }
      if (state == 1) {
        if (!done) print n ": " v
        state = 2
        next
      }
    }
    state == 1 && $0 ~ "^"n":" { print n ": " v; done = 1; next }
    { print }
  ' "$file" > "$tmp" || { rm -f "$tmp"; mm_die "set_prop failed"; }
  mv "$tmp" "$file"
}

# Return 0 if note file passes search filters. Args: file domain kind heat include_raw
mmfs_search_file_ok() {
  local file="$1" want_domain="$2" want_kind="$3" want_heat="$4" include_raw="$5"
  local rel prop
  rel="${file#"$MM_VAULT"/}"
  case "$rel" in
    daily/*|.memovault/*) return 1 ;;
  esac
  if [ "$include_raw" != 1 ]; then
    prop="$(mmfs_get_prop "$file" kind)"
    [ "$prop" = raw ] && return 1
  fi
  if [ -n "$want_domain" ]; then
    prop="$(mmfs_get_prop "$file" domain)"
    [ "$prop" = "$want_domain" ] || return 1
  fi
  if [ -n "$want_kind" ]; then
    prop="$(mmfs_get_prop "$file" kind)"
    [ "$prop" = "$want_kind" ] || return 1
  fi
  if [ -n "$want_heat" ]; then
    prop="$(mmfs_get_prop "$file" heat)"
    [ -n "$prop" ] || prop="seedling"
    [ "$prop" = "$want_heat" ] || return 1
  fi
  return 0
}

# Full-text search under brain/. Default excludes kind:raw. daily/ is outside
# the search root. Flags: --limit N --domain D --kind K --heat H --include-raw
mmfs_search() {
  local q="${1:-}"; shift 2>/dev/null || true
  local limit="" domain="" kind="" heat="" include_raw=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --limit) limit="${2:-}"; shift 2 ;;
      --domain) domain="${2:-}"; shift 2 ;;
      --kind) kind="${2:-}"; shift 2 ;;
      --heat) heat="${2:-}"; shift 2 ;;
      --include-raw) include_raw=1; shift ;;
      *) shift ;;
    esac
  done
  [ -n "$q" ] || mm_die "usage: search <query> [--limit N] [--domain D] [--kind K] [--heat H] [--include-raw]"
  mmfs_ensure_vault
  [ -d "$MM_VAULT/brain" ] || return 0

  local raw="" line abs rel fpath kept=0
  if command -v rg >/dev/null 2>&1; then
    raw="$(rg --no-heading -n -- "$q" "$MM_VAULT/brain" 2>/dev/null || true)"
  else
    raw="$(grep -rn -- "$q" "$MM_VAULT/brain" 2>/dev/null || true)"
  fi
  [ -n "$raw" ] || return 0

  # Cache ok/fail per absolute file path to avoid re-reading frontmatter.
  # Bash 3.2: encode as newline list "path<TAB>0|1"
  local cache="" cache_hit ok
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    case "$line" in
      "$MM_VAULT"/*)
        rel="${line#"$MM_VAULT"/}"
        ;;
      *)
        rel="$line"
        ;;
    esac
    # rel is path:lineno:text — split on first two colons after .md
    fpath="$(printf '%s\n' "$rel" | awk -F: '
      {
        p=$1
        for (i=2; i<=NF; i++) {
          if (p ~ /\.md$/) { print p; exit }
          p=p ":" $i
        }
        print $1
      }')"
    abs="$MM_VAULT/$fpath"
    [ -f "$abs" ] || continue

    cache_hit="$(printf '%s\n' "$cache" | awk -F'	' -v p="$abs" '$1==p { print $2; exit }')"
    if [ -n "$cache_hit" ]; then
      ok="$cache_hit"
    else
      if mmfs_search_file_ok "$abs" "$domain" "$kind" "$heat" "$include_raw"; then
        ok=1
      else
        ok=0
      fi
      cache="${cache}${abs}	${ok}
"
    fi
    [ "$ok" = 1 ] || continue
    printf '%s\n' "$rel"
    kept=$((kept + 1))
    if [ -n "$limit" ] && [ "$kept" -ge "$limit" ]; then
      break
    fi
  done <<EOF
$raw
EOF
}

# Heat rank: evergreen=3 growing=2 seedling/other=1
mmfs_heat_score() {
  case "$1" in
    evergreen) printf '3' ;;
    growing) printf '2' ;;
    *) printf '1' ;;
  esac
}

# Kind rank: persona|skill|scenario|atom=2, empty/other=1, raw=0
mmfs_kind_score() {
  case "$1" in
    persona|skill|scenario|atom) printf '2' ;;
    raw) printf '0' ;;
    *) printf '1' ;;
  esac
}

# Ranked recall summary. Same default filters as search (no raw). Default limit 5.
# Lines: path=... title=... kind=... heat=... snippet=...
mmfs_recall() {
  local q="${1:-}"; shift 2>/dev/null || true
  local limit=5
  while [ $# -gt 0 ]; do
    case "$1" in
      --limit) limit="${2:-5}"; shift 2 ;;
      *) shift ;;
    esac
  done
  [ -n "$q" ] || mm_die "usage: recall <query> [--limit N]"
  mmfs_ensure_vault
  [ -d "$MM_VAULT/brain" ] || return 0

  local raw="" line abs rel fpath text snippet
  local title kind heat updated hs ks
  local rows="" seen=""
  local q_tok
  q_tok="$(printf '%s' "$q" | tr ' ' '_')"

  if command -v rg >/dev/null 2>&1; then
    raw="$(rg --no-heading -n -- "$q" "$MM_VAULT/brain" 2>/dev/null || true)"
  else
    raw="$(grep -rn -- "$q" "$MM_VAULT/brain" 2>/dev/null || true)"
  fi
  if [ -z "$raw" ]; then
    mm_obs_log "event=recall" "q=$q_tok" "hits=0" "top="
    return 0
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    case "$line" in
      "$MM_VAULT"/*) rel="${line#"$MM_VAULT"/}" ;;
      *) rel="$line" ;;
    esac
    fpath="$(printf '%s\n' "$rel" | awk -F: '
      {
        p=$1
        for (i=2; i<=NF; i++) {
          if (p ~ /\.md$/) { print p; exit }
          p=p ":" $i
        }
        print $1
      }')"
    abs="$MM_VAULT/$fpath"
    [ -f "$abs" ] || continue
    case "$seen" in
      *"|$fpath|"*) continue ;;
    esac
    mmfs_search_file_ok "$abs" "" "" "" 0 || continue
    seen="${seen}|$fpath|"

    text="$(printf '%s\n' "$rel" | awk -F: '
      {
        p=$1
        idx=2
        for (i=2; i<=NF; i++) {
          if (p ~ /\.md$/) { idx=i+1; break }
          p=p ":" $i
          idx=i+1
        }
        out=""
        for (j=idx; j<=NF; j++) {
          if (out != "") out=out ":"
          out=out $j
        }
        print out
      }')"
    snippet="$(printf '%s' "$text" | tr '\n\r\t' ' ' | sed -E 's/  +/ /g; s/^ //; s/ $//' | cut -c1-120)"

    title="$(mmfs_get_prop "$abs" title)"
    [ -n "$title" ] || title="$(basename "$fpath" .md)"
    kind="$(mmfs_get_prop "$abs" kind)"
    [ -n "$kind" ] || kind="-"
    heat="$(mmfs_get_prop "$abs" heat)"
    [ -n "$heat" ] || heat="seedling"
    updated="$(mmfs_get_prop "$abs" updated)"
    [ -n "$updated" ] || updated="1970-01-01"
    hs="$(mmfs_heat_score "$heat")"
    ks="$(mmfs_kind_score "$kind")"
    rows="${rows}${hs}	${ks}	${updated}	${fpath}	${title}	${kind}	${heat}	${snippet}
"
  done <<EOF
$raw
EOF

  if [ -z "$rows" ]; then
    mm_obs_log "event=recall" "q=$q_tok" "hits=0" "top="
    return 0
  fi

  local ranked titles hits=0 top_tok
  ranked="$(printf '%s' "$rows" | sort -t'	' -k1,1nr -k2,2nr -k3,3r | head -n "$limit")"
  hits="$(printf '%s\n' "$ranked" | grep -c . || true)"
  titles="$(printf '%s\n' "$ranked" | awk -F'	' '{ printf "%s%s", (NR>1?",":""), $5 }')"
  top_tok="$(printf '%s' "$titles" | tr ' ' '_')"
  mm_obs_log "event=recall" "q=$q_tok" "hits=$hits" "top=$top_tok"
  printf '%s\n' "$ranked" | while IFS='	' read -r _hs _ks _upd fpath title kind heat snippet; do
    [ -n "$fpath" ] || continue
    printf 'path=%s title=%s kind=%s heat=%s snippet=%s\n' "$fpath" "$title" "$kind" "$heat" "$snippet"
  done
}

# All tags with counts (expects inline "tags: [a, b]" frontmatter).
mmfs_tags() {
  [ -d "$MM_VAULT/brain" ] || return 0
  grep -rh '^tags:' "$MM_VAULT/brain" 2>/dev/null \
    | sed -E 's/^tags:[[:space:]]*//; s/^\[//; s/\][[:space:]]*$//' \
    | tr ',' '\n' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | grep -v '^$' \
    | sort | uniq -c | sort -rn
}

mmfs_tag() {
  local tag="$1"
  [ -n "$tag" ] || mm_die "usage: tag <name>"
  [ -d "$MM_VAULT/brain" ] || return 0
  grep -rl -- "^tags:.*$tag" "$MM_VAULT/brain" 2>/dev/null \
    | sed "s#^$(printf '%s' "$MM_VAULT")/##"
}

# Backlinks: files referencing [[Title. Approximate (aliases not resolved).
mmfs_backlinks() {
  local ref="$1"
  local file; file="$(mmfs_locate "$ref")"
  local title; title="$(mmfs_get_prop "$file" title 2>/dev/null)"
  [ -n "$title" ] || title="$(mmfs_sanitize_title "$ref")"
  local key="[[$title"
  if command -v rg >/dev/null 2>&1; then
    rg -l -F "$key" "$MM_VAULT" 2>/dev/null
  else
    grep -rl -F "$key" "$MM_VAULT" 2>/dev/null
  fi | grep -v "^$(printf '%s' "$file")$" \
    | sed "s#^$(printf '%s' "$MM_VAULT")/##"
}

# Outgoing wikilinks from a note.
mmfs_links() {
  local ref="$1"
  local file; file="$(mmfs_locate "$ref")"
  [ -n "$file" ] || mm_die "note not found: $ref"
  grep -oE '\[\[[^]]+\]\]' "$file" 2>/dev/null \
    | sed -E 's/^\[\[//; s/\]\]$//; s/\|.*$//' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | sort -u
}

# Emit graph edges: "LINK<TAB>src_rel<TAB>target_text"
# Scans brain/ and daily/ so distill pointers from daily notes count.
mmfs_graph() {
  local f
  {
    [ -d "$MM_VAULT/brain" ] && find "$MM_VAULT/brain" -type f -name '*.md' 2>/dev/null
    [ -d "$MM_VAULT/daily" ] && find "$MM_VAULT/daily" -type f -name '*.md' 2>/dev/null
  } | while read -r f; do
    [ -n "$f" ] || continue
    local rel="${f#"$MM_VAULT"/}"
    awk -v src="$rel" '
      {
        s = $0
        while (match(s, /\[\[[^]]+\]\]/)) {
          tgt = substr(s, RSTART+2, RLENGTH-4)
          sub(/\|.*/, "", tgt)
          gsub(/^[ \t]+|[ \t]+$/, "", tgt)
          printf "LINK\t%s\t%s\n", src, tgt
          s = substr(s, RSTART+RLENGTH)
        }
      }
    ' "$f"
  done
}

mmfs_orphans() {
  local tmp; tmp="$(mktemp)"
  mmfs_graph > "$tmp" 2>/dev/null
  local f stem rel
  find "$MM_VAULT/brain" -type f -name '*.md' 2>/dev/null | while read -r f; do
    stem="$(basename "$f" .md)"
    rel="${f#"$MM_VAULT"/}"
    if awk -F'\t' -v t="$stem" '$3 == t { f = 1 } END { exit !f }' "$tmp"; then
      :
    else
      printf '%s\n' "$rel"
    fi
  done
  rm -f "$tmp"
}

# Return 0 if target text resolves to an existing vault note (brain, daily, or path).
mmfs_target_exists() {
  local target="$1"
  [ -n "$target" ] || return 1
  if find "$MM_VAULT/brain" -type f -name "$target.md" 2>/dev/null | grep -q .; then
    return 0
  fi
  if [ -f "$MM_VAULT/daily/$target.md" ]; then
    return 0
  fi
  if [ -f "$MM_VAULT/$target" ] || [ -f "$MM_VAULT/$target.md" ]; then
    return 0
  fi
  return 1
}

mmfs_unresolved() {
  local tmp; tmp="$(mktemp)"
  mmfs_graph > "$tmp" 2>/dev/null
  cut -f3 "$tmp" 2>/dev/null | sort -u | while read -r target; do
    [ -n "$target" ] || continue
    if ! mmfs_target_exists "$target"; then
      printf '%s\n' "$target"
    fi
  done
  rm -f "$tmp"
}

# Return 0 if path contains a '..' segment (potential traversal).
mmfs_has_dotdot() {
  local p="$1" seg oldifs="$IFS"
  IFS='/'
  set -f
  for seg in $p; do
    if [ "$seg" = ".." ]; then IFS="$oldifs"; set +f; return 0; fi
  done
  IFS="$oldifs"; set +f
  return 1
}

mmfs_move() {
  local ref="$1" to="$2"
  local file; file="$(mmfs_locate "$ref")"
  [ -n "$file" ] || mm_die "note not found: $ref"
  local realvault; realvault="$(cd "$MM_VAULT" && pwd)"
  local dest="$realvault/$to"
  if [[ "$to" == */ ]] || [ -d "$dest" ]; then
    dest="$dest/$(basename "$file")"
  fi
  mmfs_has_dotdot "$to" && mm_die "refusing path with parent reference: $to"
  local parent; parent="$(dirname "$dest")"
  mkdir -p "$parent"
  local realdest; realdest="$(cd "$parent" && pwd)/$(basename "$dest")"
  case "$realdest" in
    "$realvault"|"$realvault"/*) : ;;
    *) mm_die "refusing to move outside vault: $to" ;;
  esac
  mv "$file" "$realdest"
  mm_log "moved (basename preserved; links stay valid): ${file#"$realvault"/} -> ${realdest#"$realvault"/}"
}

mmfs_rename() {
  local ref="$1" newname="$2"
  local file; file="$(mmfs_locate "$ref")"
  [ -n "$file" ] || mm_die "note not found: $ref"
  local clean; clean="$(mmfs_sanitize_title "$newname")"
  local dest; dest="$(dirname "$file")/$clean.md"
  [ "$file" = "$dest" ] && { mm_log "name unchanged"; return 0; }
  # Capture old wikilink keys (stem, title, aliases) before the file moves.
  local old_keys; old_keys="$(mm_wikilink_keys_for_file "$file")"
  mv "$file" "$dest"
  # Update the destination's frontmatter title to the new sanitized title.
  mmfs_set_prop "$dest" title "$clean"
  # Rewrite [[Old]] / [[Old|label]] across brain/ and daily/.
  local files_updated=0
  if [ -n "$old_keys" ]; then
    local rewrite_out rewrite_rc
    rewrite_out="$(printf '%s\n' "$old_keys" | mm_rewrite_wikilinks "$clean")"
    rewrite_rc=$?
    if [ "$rewrite_rc" -ne 0 ]; then
      mm_die "rename: wikilink rewrite failed (note already renamed to ${dest#"$MM_VAULT"/})"
    fi
    files_updated="${rewrite_out#files_updated=}"
  fi
  mm_log "renamed: ${file#"$MM_VAULT"/} -> ${dest#"$MM_VAULT"/} (wikilinks updated: ${files_updated} files)"
}
