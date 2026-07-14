#!/usr/bin/env bash
# lib/fs.sh - pure filesystem fallback layer for MemoVault.
# All functions operate on $MM_VAULT (set by memovault.sh). They are used in
# fs mode and also for capture operations in cli mode (the on-disk file is the
# same one Obsidian reads). No emoji. Never write outside $MM_VAULT.

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

# Find a note by its title (filename stem) under brain/. Print path or empty.
mmfs_find_note() {
  local title; title="$(mmfs_sanitize_title "$1")"
  [ -d "$MM_VAULT/brain" ] || return 0
  find "$MM_VAULT/brain" -type f -name "$title.md" 2>/dev/null | head -n1
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

# Create a new note. Usage: mmfs_new <domain> <title> [tags_csv] [body]
mmfs_new() {
  local domain="$1" title="$2" tags="${3:-}" body="${4:-}"
  [ -n "$domain" ] && [ -n "$title" ] || { mm_die "usage: new <domain> <title>"; }
  mmfs_ensure_vault
  mkdir -p "$MM_VAULT/brain/$domain"
  local file; file="$(mmfs_note_path "$domain" "$title")"
  [ -f "$file" ] && mm_die "note already exists: $title ($file). Use append instead."
  local today; today="$(mmfs_today)"
  local title_clean; title_clean="$(mmfs_sanitize_title "$title")"
  {
    printf -- '---\n'
    printf 'title: %s\n' "$title_clean"
    printf 'domain: %s\n' "$domain"
    printf 'tags: %s\n' "$(mmfs_yaml_list "$tags")"
    printf 'heat: seedling\n'
    printf 'aliases: []\n'
    printf 'created: %s\n' "$today"
    printf 'updated: %s\n' "$today"
    printf -- '---\n\n'
    printf '# %s\n\n' "$title_clean"
    [ -n "$body" ] && printf '%s\n' "$body"
  } > "$file"
  printf '%s\n' "${file#"$MM_VAULT"/}"
}

mmfs_append() {
  local ref="$1" content="$2"
  local file; file="$(mmfs_locate "$ref")"
  [ -n "$file" ] && [ -f "$file" ] || mm_die "note not found: $ref"
  {
    printf '\n'
    printf '%s\n' "$content"
  } >> "$file"
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
  cat "$file"
}

mmfs_daily_path() {
  printf '%s/daily/%s.md\n' "$MM_VAULT" "$(mmfs_today)"
}

mmfs_daily() {
  local f; f="$(mmfs_daily_path)"
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] || {
    printf -- '---\ncreated: %s\n---\n\n# %s\n\n' "$(mmfs_today)" "$(mmfs_today)" > "$f"
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

mmfs_search() {
  local q="$1"; shift
  local limit=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [ -n "$q" ] || mm_die "usage: search <query>"
  local out
  if command -v rg >/dev/null 2>&1; then
    out="$(rg --no-heading -n -- "$q" "$MM_VAULT" 2>/dev/null)"
  else
    out="$(grep -rn -- "$q" "$MM_VAULT" 2>/dev/null)"
  fi
  if [ -n "$limit" ]; then
    printf '%s\n' "$out" | sed "s#^$(printf '%s' "$MM_VAULT")/##" | head -n "$limit"
  else
    printf '%s\n' "$out" | sed "s#^$(printf '%s' "$MM_VAULT")/##"
  fi
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
mmfs_graph() {
  local f
  [ -d "$MM_VAULT/brain" ] || return 0
  find "$MM_VAULT/brain" -type f -name '*.md' 2>/dev/null | while read -r f; do
    local rel="${f#"$MM_VAULT"/}"
    grep -oE '\[\[[^]]+\]\]' "$f" 2>/dev/null \
      | sed -E 's/^\[\[//; s/\]\]$//; s/\|.*$//' \
      | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
    # re-scan to pair with src (awk is cleaner here)
  done >/dev/null
  find "$MM_VAULT/brain" -type f -name '*.md' 2>/dev/null | while read -r f; do
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

mmfs_unresolved() {
  local tmp; tmp="$(mktemp)"
  mmfs_graph > "$tmp" 2>/dev/null
  cut -f3 "$tmp" 2>/dev/null | sort -u | while read -r target; do
    [ -n "$target" ] || continue
    if ! find "$MM_VAULT/brain" -type f -name "$target.md" 2>/dev/null | grep -q .; then
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
  mm_log "moved (links NOT auto-updated in fs mode): ${file#"$realvault"/} -> ${realdest#"$realvault"/}"
}

mmfs_rename() {
  local ref="$1" newname="$2"
  local file; file="$(mmfs_locate "$ref")"
  [ -n "$file" ] || mm_die "note not found: $ref"
  local clean; clean="$(mmfs_sanitize_title "$newname")"
  local dest; dest="$(dirname "$file")/$clean.md"
  [ "$file" = "$dest" ] && { mm_log "name unchanged"; return 0; }
  mv "$file" "$dest"
  mm_log "renamed (links NOT auto-updated in fs mode): ${file#"$MM_VAULT"/} -> ${dest#"$MM_VAULT"/}"
}
