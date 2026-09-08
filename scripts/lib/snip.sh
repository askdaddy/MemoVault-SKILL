#!/usr/bin/env bash
# lib/snip.sh - vault-local CLI snippet library (pet semantics, no exec).
# Sourced by memovault.sh. Bash 3.2. Never writes outside $MM_VAULT.

mm_snip_usage() {
  cat <<'USAGE'
snip - local CLI snippet library (kind: snippet).

  snip new "<description>" --command "..." [--tags a,b]
  snip list [--tag t] [--limit N]
  snip search "<query>" [--tag t] [--limit N]
  snip get "<description>" [--set name=value ...]
  snip rm "<description>" --yes

Default recall/search omit snippets. Helper never executes stored commands.
USAGE
}

mm_snip_trim() {
  local t="$1"
  t="${t#"${t%%[![:space:]]*}"}"
  t="${t%"${t##*[![:space:]]}"}"
  printf '%s' "$t"
}

# Extract command text from a snippet note (first fenced block, else body).
mm_snip_extract_command() {
  local file="$1"
  [ -f "$file" ] || return 0
  awk '
    BEGIN { fm = 0; in_fence = 0; got = 0; cmd = ""; fb = ""; stop_fb = 0 }
    /^---[[:space:]]*$/ {
      if (fm == 0) { fm = 1; next }
      if (fm == 1) { fm = 2; next }
    }
    fm < 2 { next }
    /^```/ {
      if (in_fence == 0 && got == 0) { in_fence = 1; next }
      if (in_fence == 1) { in_fence = 0; got = 1; next }
    }
    in_fence == 1 {
      if (cmd != "") cmd = cmd "\n"
      cmd = cmd $0
      next
    }
    got == 1 { next }
    /^#/ { next }
    /^Related:/ { stop_fb = 1; next }
    /^## / { stop_fb = 1; next }
    stop_fb == 1 { next }
    {
      if (fb != "") fb = fb "\n"
      fb = fb $0
    }
    END {
      out = (got == 1) ? cmd : fb
      while (out ~ /^\n/) out = substr(out, 2)
      while (out ~ /\n$/) out = substr(out, 1, length(out) - 1)
      printf "%s", out
    }
  ' "$file"
}

# Flatten command for list/search: newlines -> two chars \n, tabs -> space.
mm_snip_flatten() {
  printf '%s' "$1" | tr '\t' ' ' | awk '{
    if (NR > 1) printf "\\n"
    printf "%s", $0
  }'
}

# YAML tags line -> csv with no spaces: [ssl, openssl] -> ssl,openssl
mm_snip_tags_csv() {
  local file="$1" raw
  raw="$(mmfs_get_prop "$file" tags)"
  raw="$(printf '%s' "$raw" | tr -d '[]')"
  raw="$(printf '%s' "$raw" | tr -d ' ')"
  printf '%s' "$raw"
}

mm_snip_has_tag() {
  local csv="$1" want="$2"
  [ -n "$want" ] || return 0
  [ -n "$csv" ] || return 1
  case ",$csv," in
    *",$want,"*) return 0 ;;
    *) return 1 ;;
  esac
}

# Expand <name> / <name=default>. sets_file: lines of name=value (last wins).
mm_snip_expand() {
  local src="$1" sets_file="$2"
  printf '%s' "$src" | awk -v sf="$sets_file" '
    BEGIN {
      if (sf != "") {
        while ((getline line < sf) > 0) {
          eq = index(line, "=")
          if (eq > 0) {
            k = substr(line, 1, eq - 1)
            v = substr(line, eq + 1)
            map[k] = v
          }
        }
        close(sf)
      }
    }
    {
      s = $0
      result = ""
      while (match(s, /<[^>]*>/)) {
        result = result substr(s, 1, RSTART - 1)
        tok = substr(s, RSTART, RLENGTH)
        inner = substr(tok, 2, length(tok) - 2)
        eq = index(inner, "=")
        if (eq > 0) {
          name = substr(inner, 1, eq - 1)
          def = substr(inner, eq + 1)
        } else {
          name = inner
          def = ""
        }
        if (name in map) result = result map[name]
        else if (eq > 0) result = result def
        else result = result tok
        s = substr(s, RSTART + RLENGTH)
      }
      result = result s
      print result
    }
  '
}

mm_snip_is_snippet_file() {
  local file="$1" k
  [ -f "$file" ] || return 1
  k="$(mmfs_get_prop "$file" kind)"
  [ "$k" = snippet ]
}

mm_snip_is_listed() {
  local file="$1" st
  mm_snip_is_snippet_file "$file" || return 1
  st="$(mmfs_get_prop "$file" status)"
  [ "$st" = superseded ] && return 1
  return 0
}

mm_snip_emit_row() {
  local file="$1" title tags cmd
  title="$(mmfs_get_prop "$file" title)"
  [ -n "$title" ] || title="$(basename "$file" .md)"
  tags="$(mm_snip_tags_csv "$file")"
  cmd="$(mm_snip_extract_command "$file")"
  cmd="$(mm_snip_flatten "$cmd")"
  printf 'title=%s tags=%s command=%s\n' "$title" "$tags" "$cmd"
}

mm_snip_each_listed() {
  local f
  [ -d "$MM_VAULT/brain" ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    mm_snip_is_listed "$f" || continue
    printf '%s\n' "$f"
  done <<EOF
$(find "$MM_VAULT/brain" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)
EOF
}

mm_snip_new() {
  local desc="" cmd="" tags=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --command)
        [ $# -ge 2 ] || mm_die "snip new: --command requires a value"
        cmd="$2"
        shift 2
        ;;
      --tags)
        [ $# -ge 2 ] || mm_die "snip new: --tags requires a value"
        tags="$2"
        shift 2
        ;;
      --*) mm_die "unknown flag: $1" ;;
      *)
        if [ -z "$desc" ]; then
          desc="$1"
          shift
        else
          mm_die "unexpected argument: $1"
        fi
        ;;
    esac
  done
  desc="$(mm_snip_trim "$desc")"
  cmd="$(mm_snip_trim "$cmd")"
  [ -n "$desc" ] || mm_die "usage: snip new \"<description>\" --command \"...\""
  [ -n "$cmd" ] || mm_die "snip new: --command is required and must be non-empty"
  printf '%s' "$cmd" | grep -q '```' && mm_die "snip new: command must not contain a markdown fence"
  mmfs_ensure_vault
  local title_clean hit dest
  title_clean="$(mmfs_sanitize_title "$desc")"
  hit="$(mmfs_find_note "$title_clean")"
  if [ -n "$hit" ] && [ -f "$hit" ]; then
    mm_die "snippet already exists: $title_clean ($hit)"
  fi
  mkdir -p "$MM_VAULT/brain/snippets"
  dest="$(mmfs_note_path snippets "$title_clean")"
  local today
  today="$(mmfs_today)"
  {
    printf -- '---\n'
    printf 'title: %s\n' "$title_clean"
    printf 'domain: snippets\n'
    printf 'kind: snippet\n'
    printf 'tags: %s\n' "$(mmfs_yaml_list "$tags")"
    printf 'heat: growing\n'
    printf 'aliases: []\n'
    printf 'sources: []\n'
    printf 'created: %s\n' "$today"
    printf 'updated: %s\n' "$today"
    printf -- '---\n\n'
    printf '```bash\n'
    printf '%s\n' "$cmd"
    printf '```\n'
  } > "$dest"
  mm_obs_log "event=snip" "op=new" "title=$title_clean"
  printf 'path=%s title=%s\n' "${dest#"$MM_VAULT"/}" "$title_clean"
}

mm_snip_parse_list_flags() {
  SNIP_TAG=""
  SNIP_LIMIT=""
  SNIP_QUERY=""
  local saw_query=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --tag)
        [ $# -ge 2 ] || mm_die "snip: --tag requires a value"
        SNIP_TAG="$2"
        shift 2
        ;;
      --limit)
        [ $# -ge 2 ] || mm_die "snip: --limit requires a value"
        SNIP_LIMIT="$2"
        shift 2
        ;;
      --*) mm_die "unknown flag: $1" ;;
      *)
        if [ "$saw_query" -eq 0 ]; then
          SNIP_QUERY="$1"
          saw_query=1
          shift
        else
          mm_die "unexpected argument: $1"
        fi
        ;;
    esac
  done
}

mm_snip_list() {
  mm_snip_parse_list_flags "$@"
  [ -z "$SNIP_QUERY" ] || mm_die "usage: snip list [--tag t] [--limit N]"
  mmfs_ensure_vault
  local f title kept=0 tmp
  tmp="$(mktemp)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    mm_snip_has_tag "$(mm_snip_tags_csv "$f")" "$SNIP_TAG" || continue
    title="$(mmfs_get_prop "$f" title)"
    [ -n "$title" ] || title="$(basename "$f" .md)"
    printf '%s\t%s\n' "$title" "$f" >> "$tmp"
  done <<EOF
$(mm_snip_each_listed)
EOF
  while IFS='	' read -r title f; do
    [ -n "$f" ] || continue
    if [ -n "$SNIP_LIMIT" ]; then
      [ "$kept" -ge "$SNIP_LIMIT" ] && break
    fi
    mm_snip_emit_row "$f"
    kept=$((kept + 1))
  done <<EOF
$(LC_ALL=C sort -t '	' -k1,1 "$tmp")
EOF
  rm -f "$tmp"
}

mm_snip_search() {
  mm_snip_parse_list_flags "$@"
  [ -n "$SNIP_QUERY" ] || mm_die "usage: snip search \"<query>\" [--tag t] [--limit N]"
  mmfs_ensure_vault
  local f title tags body kept=0 hits=0 q_tok tmp
  tmp="$(mktemp)"
  q_tok="$(printf '%s' "$SNIP_QUERY" | tr ' ' '_')"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    mm_snip_has_tag "$(mm_snip_tags_csv "$f")" "$SNIP_TAG" || continue
    title="$(mmfs_get_prop "$f" title)"
    [ -n "$title" ] || title="$(basename "$f" .md)"
    tags="$(mm_snip_tags_csv "$f")"
    body="$(mm_snip_extract_command "$f")"
    if printf '%s\n%s\n%s\n' "$title" "$tags" "$body" | grep -Fq -- "$SNIP_QUERY"; then
      printf '%s\t%s\n' "$title" "$f" >> "$tmp"
      hits=$((hits + 1))
    fi
  done <<EOF
$(mm_snip_each_listed)
EOF
  while IFS='	' read -r title f; do
    [ -n "$f" ] || continue
    if [ -n "$SNIP_LIMIT" ]; then
      [ "$kept" -ge "$SNIP_LIMIT" ] && break
    fi
    mm_snip_emit_row "$f"
    kept=$((kept + 1))
  done <<EOF
$(LC_ALL=C sort -t '	' -k1,1 "$tmp")
EOF
  rm -f "$tmp"
  mm_obs_log "event=snip" "op=search" "q=$q_tok" "hits=$hits"
}

mm_snip_get() {
  local desc="" sets
  sets="$(mktemp)"
  while [ $# -gt 0 ]; do
    case "$1" in
      --set)
        [ $# -ge 2 ] || { rm -f "$sets"; mm_die "usage: snip get \"<description>\" [--set name=value]"; }
        printf '%s\n' "$2" >> "$sets"
        shift 2
        ;;
      --*) rm -f "$sets"; mm_die "unknown flag: $1" ;;
      *)
        if [ -z "$desc" ]; then
          desc="$1"
          shift
        else
          rm -f "$sets"
          mm_die "unexpected argument: $1"
        fi
        ;;
    esac
  done
  [ -n "$desc" ] || { rm -f "$sets"; mm_die "usage: snip get \"<description>\" [--set name=value]"; }
  local file k cmd expanded
  file="$(mmfs_locate "$desc")"
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    rm -f "$sets"
    mm_die "snippet not found: $desc"
  fi
  k="$(mmfs_get_prop "$file" kind)"
  if [ "$k" != snippet ]; then
    rm -f "$sets"
    mm_die "not a snippet: $desc"
  fi
  cmd="$(mm_snip_extract_command "$file")"
  if [ -z "$cmd" ]; then
    rm -f "$sets"
    mm_die "snippet has empty command: $desc"
  fi
  expanded="$(mm_snip_expand "$cmd" "$sets")"
  rm -f "$sets"
  mm_obs_log "event=snip" "op=get" "title=$(mmfs_get_prop "$file" title)"
  printf '%s\n' "$expanded"
}

mm_snip_rm() {
  local desc="" yes=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --yes) yes=1; shift ;;
      --*) mm_die "unknown flag: $1" ;;
      *)
        if [ -z "$desc" ]; then
          desc="$1"
          shift
        else
          mm_die "unexpected argument: $1"
        fi
        ;;
    esac
  done
  [ -n "$desc" ] || mm_die "usage: snip rm \"<description>\" --yes"
  local file k title rel
  file="$(mmfs_locate "$desc")"
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    mm_die "snippet not found: $desc"
  fi
  k="$(mmfs_get_prop "$file" kind)"
  [ "$k" = snippet ] || mm_die "not a snippet: $desc"
  title="$(mmfs_get_prop "$file" title)"
  [ -n "$title" ] || title="$(basename "$file" .md)"
  rel="${file#"$MM_VAULT"/}"
  if [ "$yes" != 1 ]; then
    printf 'path=%s title=%s\n' "$rel" "$title"
    mm_log "snip rm: pass --yes after user confirmation"
    return 2
  fi
  rm -f "$file"
  mm_obs_log "event=snip" "op=rm" "title=$title"
  printf 'deleted=1 path=%s title=%s\n' "$rel" "$title"
}

mm_snip_main() {
  local sub="${1:-}"
  if [ -z "$sub" ]; then
    mm_snip_usage
    return 0
  fi
  shift
  case "$sub" in
    new) mm_snip_new "$@" ;;
    list) mm_snip_list "$@" ;;
    search) mm_snip_search "$@" ;;
    get) mm_snip_get "$@" ;;
    rm) mm_snip_rm "$@" ;;
    -h|--help|help) mm_snip_usage ;;
    *) mm_die "unknown snip subcommand: $sub (try: memovault snip)" ;;
  esac
}
